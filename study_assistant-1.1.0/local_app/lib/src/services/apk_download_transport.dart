import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// APK-only request policy. The caller owns the whole-transfer deadline,
/// response-header validation and verified-file publication boundary.
class ApkDownloadTransport {
  const ApkDownloadTransport(this._dio,
      {Duration receiveIdleTimeout = const Duration(seconds: 60)})
      : _receiveIdleTimeout = receiveIdleTimeout;

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
    for (var attempt = 0;; attempt++) {
      if (token.isCancelled) throw token.cancelError!;
      final requestToken = CancelToken();
      var requestActive = true;
      token.whenCancel.then((error) {
        if (requestActive && !requestToken.isCancelled) {
          requestToken.cancel(error.message);
        }
      });
      final request = Options(
        responseType: ResponseType.stream,
        headers: {
          'Accept': 'application/octet-stream',
          'Accept-Encoding': 'identity',
          ...headers,
        },
      ).compose(_dio.options, url, cancelToken: requestToken).copyWith(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: _receiveIdleTimeout,
          );
      if (attempt != 0 && retryWithoutRange) {
        request.headers.removeWhere((name, _) => name.toLowerCase() == 'range');
      }
      Stream<Uint8List>? source;
      StreamIterator<Uint8List>? chunks;
      Future<void>? cleanup;
      Future<void> closeRequest() => cleanup ??= () async {
            requestActive = false;
            // Cancelling only a Dio response subscription does not abort its
            // underlying HTTP source. Retire this attempt, not its caller.
            if (!requestToken.isCancelled) {
              requestToken.cancel('APK request closed');
            }
            if (chunks != null) {
              await chunks.cancel();
            } else {
              await source?.listen((_) {}, onError: (Object _) {}).cancel();
            }
          }();
      try {
        final response = await _dio.fetch<ResponseBody>(request);
        final body = response.data;
        source = body?.stream;
        // Reject known status/size/range errors before any idle wait or retry.
        validateHeaders?.call(response);
        if (body == null) {
          await closeRequest();
          return response;
        }
        chunks = StreamIterator<Uint8List>(source!);
        if (response.statusCode != 200 && response.statusCode != 206) {
          body.stream = _replay(chunks, null, closeRequest);
          return response;
        }
        Future<Uint8List?> firstBytes() async {
          while (await chunks!.moveNext()) {
            if (chunks.current.isNotEmpty) return chunks.current;
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
        body.stream = _replay(chunks, first, closeRequest);
        return response;
      } catch (error, stack) {
        await closeRequest();
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
