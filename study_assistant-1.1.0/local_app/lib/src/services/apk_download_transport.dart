import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// APK-only request policy. The caller owns the whole-transfer deadline,
/// response-header validation and verified-file publication boundary.
class ApkDownloadTransport {
  const ApkDownloadTransport(this._dio,
      {Duration receiveIdleTimeout = const Duration(seconds: 60)})
      : _receiveIdleTimeout = receiveIdleTimeout;

  static const _maxRedirects = 5;
  static const _redirectStatuses = {301, 302, 303, 307, 308};
  static const _loopbackHosts = {'127.0.0.1', 'localhost', '::1'};
  static const _streamCleanupTimeout = Duration(seconds: 1);

  final Dio _dio;
  // Production uses sixty seconds; short timers exercise the real stream and
  // cancellation seam in tests without relying on framework HTTP overrides.
  final Duration _receiveIdleTimeout;

  Future<Response<ResponseBody>> open(
    String url, {
    required CancelToken token,
    Map<String, dynamic> headers = const {},
    bool retryInitialRequest = true,
    bool retryWithoutRange = false,
    void Function(Response<ResponseBody>)? validateHeaders,
  }) async {
    if (token.isCancelled) throw token.cancelError!;
    final initial = Uri.tryParse(url);
    if (initial == null) _unsafeRedirect();
    _validateUri(initial, httpsOnly: false);
    for (var attempt = 0;; attempt++) {
      try {
        return await _openAttempt(
          initial,
          token,
          headers,
          withoutRange: attempt != 0 && retryWithoutRange,
          validateHeaders: validateHeaders,
        );
      } catch (error, stack) {
        final transient = error is DioException &&
            (error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout);
        if (!retryInitialRequest ||
            attempt != 0 ||
            !transient ||
            token.isCancelled) {
          Error.throwWithStackTrace(error, stack);
        }
        await Future.any<void>([
          Future<void>.delayed(const Duration(seconds: 1)),
          token.whenCancel.then<void>((error) => throw error),
        ]);
      }
    }
  }

  Future<Response<ResponseBody>> _openAttempt(
    Uri initial,
    CancelToken token,
    Map<String, dynamic> headers, {
    required bool withoutRange,
    required void Function(Response<ResponseBody>)? validateHeaders,
  }) async {
    final template = Options(
      method: 'GET',
      responseType: ResponseType.stream,
      followRedirects: false,
      validateStatus: (status) => status != null && status < 500,
      headers: {
        'Accept': 'application/octet-stream',
        'Accept-Encoding': 'identity',
        ...headers,
      },
    ).compose(_dio.options, initial.toString()).copyWith(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: _receiveIdleTimeout,
        );
    final requestHeaders = template.headers;
    if (withoutRange) {
      requestHeaders.removeWhere((name, _) => name.toLowerCase() == 'range');
    }
    final httpsOnly = initial.scheme == 'https';
    var current = template.uri;
    _validateUri(current, httpsOnly: httpsOnly);
    final hops = <RedirectRecord>[];

    while (true) {
      if (token.isCancelled) throw token.cancelError!;
      final requestToken = CancelToken();
      var requestActive = true;
      token.whenCancel.then((error) {
        if (requestActive && !requestToken.isCancelled) {
          requestToken.cancel(error.message);
        }
      });
      final request = template.copyWith(
        path: current.toString(),
        baseUrl: '',
        // Current already includes the first request's query options, or the
        // query from Location. Dio must not append the initial options again.
        queryParameters: {},
        headers: Map.of(requestHeaders),
        cancelToken: requestToken,
      );
      requestToken.requestOptions = request;
      Stream<Uint8List>? source;
      StreamIterator<Uint8List>? chunks;
      Future<void>? cleanup;
      Future<void> closeRequest() => cleanup ??= () async {
            requestActive = false;
            // Dio's child token closes the adapter source for this hop.
            if (!requestToken.isCancelled) {
              requestToken.cancel('APK request closed');
            }
            final cancellation = chunks?.cancel() ??
                source?.listen((_) {}, onError: (Object _) {}).cancel();
            await cancellation?.timeout(_streamCleanupTimeout);
          }();
      try {
        final Response<ResponseBody> response;
        try {
          response = await _dio.fetch<ResponseBody>(request);
        } on DioException catch (error) {
          final failedResponse = error.response;
          final failedBody = failedResponse?.data;
          if (failedBody is ResponseBody) source = failedBody.stream;
          if (failedResponse != null) {
            _mergeReportedRedirects(failedResponse, current, hops, httpsOnly);
          }
          rethrow;
        }
        final body = response.data;
        source = body?.stream;
        if (token.isCancelled) throw token.cancelError!;
        final responseUri =
            _mergeReportedRedirects(response, current, hops, httpsOnly);
        final status = response.statusCode;
        if (status != null && _redirectStatuses.contains(status)) {
          final locations = response.headers['location'];
          if (locations == null || locations.length != 1) _unsafeRedirect();
          final location = locations.single.trim();
          if (location.isEmpty || hops.length >= _maxRedirects) {
            _unsafeRedirect();
          }
          final relativeOrAbsolute = Uri.tryParse(location);
          if (relativeOrAbsolute == null) _unsafeRedirect();
          final next = responseUri.resolveUri(relativeOrAbsolute);
          _validateUri(next, httpsOnly: httpsOnly);
          await closeRequest();
          _removeSensitiveHeaders(requestHeaders, responseUri, next);
          hops.add(RedirectRecord(status, 'GET', next));
          current = next;
          continue;
        }

        // Reject known status/size/range errors before any idle wait or retry.
        validateHeaders?.call(response);
        if (body == null) {
          await closeRequest();
          return response;
        }
        final iterator = StreamIterator<Uint8List>(body.stream);
        chunks = iterator;
        if (status != 200 && status != 206) {
          body.stream = _replay(iterator, null, closeRequest);
          return response;
        }
        Future<Uint8List?> firstBytes() async {
          while (await iterator.moveNext()) {
            if (iterator.current.isNotEmpty) return iterator.current;
          }
          return null;
        }

        // Dio's normal idle timer starts at the first body chunk. Cover the
        // headers-to-first-byte gap, then replay that first chunk exactly once.
        final first = await Future.any<Uint8List?>([
          firstBytes().timeout(_receiveIdleTimeout,
              onTimeout: () => throw DioException.receiveTimeout(
                  timeout: _receiveIdleTimeout, requestOptions: request)),
          token.whenCancel.then<Uint8List?>((error) => throw error),
        ]);
        body.stream = _replay(iterator, first, closeRequest);
        return response;
      } catch (_) {
        try {
          await closeRequest();
        } catch (_) {
          // Preserve the request's failure if its cancelled body also fails.
        }
        rethrow;
      }
    }
  }

  static Never _unsafeRedirect() => throw StateError('安装包下载重定向不安全');

  static void _validateUri(Uri uri, {required bool httpsOnly}) {
    final allowedScheme = uri.scheme == 'https' ||
        (!httpsOnly &&
            uri.scheme == 'http' &&
            _loopbackHosts.contains(uri.host));
    if (!allowedScheme || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      _unsafeRedirect();
    }
  }

  static Uri _mergeReportedRedirects(
    Response<dynamic> response,
    Uri current,
    List<RedirectRecord> hops,
    bool httpsOnly,
  ) {
    var terminal = current;
    for (final redirect in response.redirects) {
      if (hops.length >= _maxRedirects) _unsafeRedirect();
      terminal = terminal.resolveUri(redirect.location);
      _validateUri(terminal, httpsOnly: httpsOnly);
      hops.add(redirect);
    }
    if (hops.isNotEmpty) {
      response.redirects = List.of(hops);
      response.isRedirect = true;
    }
    return terminal;
  }

  static void _removeSensitiveHeaders(
      Map<String, dynamic> headers, Uri current, Uri next) {
    final sameEndpoint =
        next.scheme == current.scheme && next.port == current.port;
    if (sameEndpoint && next.host == current.host) return;
    // Match the IO client's credential forwarding to same-site subdomains.
    final sameCredentialDomain =
        sameEndpoint && next.host.endsWith('.${current.host}');
    const sensitive = {
      'authorization',
      'www-authenticate',
      'cookie',
      'cookie2',
      'proxy-authorization',
    };
    headers.removeWhere((name, _) {
      final key = name.toLowerCase();
      return key == 'host' ||
          (!sameCredentialDomain && sensitive.contains(key));
    });
  }

  static Stream<Uint8List> _replay(StreamIterator<Uint8List> chunks,
      Uint8List? first, Future<void> Function() closeRequest) {
    Stream<Uint8List> remaining() async* {
      try {
        if (first != null) yield first;
        while (await chunks.moveNext()) {
          yield chunks.current;
        }
      } finally {
        await closeRequest();
      }
    }

    StreamSubscription<Uint8List>? subscription;
    late final StreamController<Uint8List> output;
    output = StreamController<Uint8List>(
      onListen: () {
        subscription = remaining()
            .listen(output.add, onError: output.addError, onDone: output.close);
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        await closeRequest();
        await subscription?.cancel();
      },
    );
    return output.stream;
  }
}
