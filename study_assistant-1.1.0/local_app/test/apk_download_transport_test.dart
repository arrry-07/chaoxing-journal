import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/apk_download_transport.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

void main() {
  late Directory dir;
  final bytes = Uint8List.fromList([80, 75, 3, 4, 1, 2, 3, 4]);
  AppUpdateInfo candidate({String? url}) => AppUpdateInfo(
      versionName: '99',
      releaseUrl: '',
      apkName: 'fixture.apk',
      apkDownloadUrl: url ?? 'https://example.org/a.apk',
      releaseNotes: '',
      apkSize: bytes.length,
      sha256Hash: sha256.convert(bytes).toString());
  setUp(() async =>
      dir = await Directory.systemTemp.createTemp('apk-transport-'));
  tearDown(() async => dir.delete(recursive: true));

  group('APK redirect policy', () {
    final initial = Uri.parse('https://updates.invalid/start.apk');

    test('blocks HTTPS downgrade before sending any loopback request',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var plaintextRequests = 0;
      server.listen((request) async {
        plaintextRequests++;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      final plaintext = Uri.parse('http://127.0.0.1:${server.port}/asset.apk');
      final io = IOHttpClientAdapter();
      final dio = Dio()
        ..httpClientAdapter =
            _ApkFixtureAdapter((options, stream, cancel) async {
          if (options.uri == plaintext) {
            return io.fetch(options, stream, cancel);
          }
          expect(options.uri, initial);
          if (!options.followRedirects) {
            return _redirect(302, plaintext.toString());
          }
          // Only the HTTPS response is synthetic. Model IOHttpClientAdapter's
          // automatic follow with an actual request to the counted listener.
          final followed = await io.fetch(
            options.copyWith(path: plaintext.toString(), baseUrl: ''),
            stream,
            cancel,
          );
          followed.redirects = [RedirectRecord(302, 'GET', plaintext)];
          return followed;
        }, onClose: (force) => io.close(force: force));
      addTearDown(() => dio.close(force: true));

      final outcome = await AppUpdateService(dio: dio)
          .downloadApk(candidate(url: initial.toString()),
              targetDirectory: dir.path)
          .then<Object>((_) => 'download completed',
              onError: (Object error) => error);
      expect([plaintextRequests, outcome], [0, isA<StateError>()]);
      expect(await dir.list().toList(), isEmpty);
    });

    test('rejects the sixth redirect before requesting its target', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requested = <String>[];
      server.listen((request) async {
        requested.add(request.uri.path);
        final hop = int.parse(request.uri.pathSegments.last);
        if (hop < 6) {
          request.response.statusCode = HttpStatus.temporaryRedirect;
          request.response.headers
              .set(HttpHeaders.locationHeader, '/hop/${hop + 1}');
        } else {
          request.response.add(bytes);
        }
        await request.response.close();
      });
      final dio = Dio(BaseOptions(maxRedirects: 20));
      addTearDown(() => dio.close(force: true));

      final result = await _apkStatusOrError(ApkDownloadTransport(dio).open(
        'http://127.0.0.1:${server.port}/hop/0',
        token: CancelToken(),
      ));
      expect(
        [requested, result],
        [List.generate(6, (hop) => '/hop/$hop'), isA<StateError>()],
      );
    });

    for (final (description, location) in [
      ('without Location', null),
      ('with URI user info', 'https://fixture-user@updates.invalid/asset.apk'),
    ]) {
      test('rejects a redirect $description', () async {
        final requested = <Uri>[];
        final dio = Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = _ApkFixtureAdapter((options, _, __) {
            requested.add(options.uri);
            if (options.uri == initial) return _redirect(302, location);
            return ResponseBody.fromBytes(bytes, 200);
          });
        addTearDown(() => dio.close(force: true));

        final result = await _apkStatusOrError(ApkDownloadTransport(dio).open(
          initial.toString(),
          token: CancelToken(),
        ));
        expect([
          requested,
          result
        ], [
          [initial],
          isA<StateError>()
        ]);
      });
    }

    test('legal hops preserve range and final adapter redirect metadata',
        () async {
      final relativeHop = initial.resolve('/delivery/relay.apk');
      final finalHop = Uri.parse('https://cdn.invalid/asset.apk?part=1');
      final adapterDestination = Uri.parse('https://cache.invalid/asset.apk');
      final requested = <RequestOptions>[];
      final headersValidated = <int?>[];
      var redirectBodies = 0;
      var redirectsClosed = 0;
      ResponseBody stalledRedirect(int status, String location) {
        final body = StreamController<Uint8List>(onCancel: () {
          redirectsClosed++;
        });
        redirectBodies++;
        addTearDown(body.close);
        return ResponseBody(body.stream, status, headers: {
          HttpHeaders.locationHeader: [location],
        });
      }

      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = _ApkFixtureAdapter((options, _, __) {
          expect(redirectsClosed, redirectBodies);
          if (requested.isNotEmpty) {
            expect(requested.last.cancelToken!.isCancelled, isTrue);
            expect(
                options.cancelToken, isNot(same(requested.last.cancelToken)));
          }
          requested.add(options);
          if (options.uri == initial) {
            return stalledRedirect(307, '/delivery/relay.apk');
          }
          if (options.uri == relativeHop) {
            return stalledRedirect(308, finalHop.toString());
          }
          expect(options.uri, finalHop);
          return ResponseBody(
            Stream.value(bytes),
            HttpStatus.partialContent,
            redirects: [RedirectRecord(302, 'GET', adapterDestination)],
            headers: {
              'content-range': ['bytes 0-7/8']
            },
          );
        });
      addTearDown(() => dio.close(force: true));

      final parent = CancelToken();
      final response = await ApkDownloadTransport(dio).open(
        initial.toString(),
        headers: {'Range': 'bytes=0-7', 'Authorization': 'Bearer fixture'},
        token: parent,
        validateHeaders: (response) =>
            headersValidated.add(response.statusCode),
      );
      final payload =
          await response.data!.stream.expand((chunk) => chunk).toList();
      expect(requested.map((request) => request.uri),
          [initial, relativeHop, finalHop]);
      for (final request in requested) {
        expect(request.method, 'GET');
        expect(request.headers['Range'], 'bytes=0-7');
        expect(request.headers['Accept'], 'application/octet-stream');
        expect(request.headers['Accept-Encoding'], 'identity');
      }
      expect(headersValidated, [HttpStatus.partialContent]);
      expect(redirectsClosed, 2);
      expect(parent.isCancelled, isFalse);
      expect(requested[1].headers['Authorization'], 'Bearer fixture');
      expect(requested[2].headers['Authorization'], isNull);
      expect(response.redirects.map((hop) => (hop.statusCode, hop.location)),
          [(307, relativeHop), (308, finalHop), (302, adapterDestination)]);
      expect(response.realUri, adapterDestination);
      expect(payload, bytes);
    });

    test('a stalled redirect cancellation is bounded before the next hop',
        () async {
      final release = Completer<void>();
      final body = StreamController<Uint8List>(onCancel: () => release.future);
      final parent = CancelToken();
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
          requests++;
          handler.resolve(Response<ResponseBody>(
            requestOptions: request,
            statusCode: 302,
            headers: Headers.fromMap({
              HttpHeaders.locationHeader: ['/next.apk'],
            }),
            data: ResponseBody(body.stream, 302),
          ));
        }));
      addTearDown(() => dio.close(force: true));
      addTearDown(() async {
        release.complete();
        await body.close();
      });

      final result = await _apkStatusOrError(
        ApkDownloadTransport(dio).open(initial.toString(), token: parent),
      ).timeout(const Duration(seconds: 3));
      expect(result, isA<TimeoutException>());
      expect(requests, 1);
      expect(parent.isCancelled, isFalse);
    });
  });

  test('APK policy does not change metadata timeouts or the injected Dio',
      () async {
    final seen = <RequestOptions>[];
    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12)))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seen.add(o);
        if (o.path.endsWith('.apk')) {
          h.resolve(Response<ResponseBody>(
              requestOptions: o,
              statusCode: 200,
              data: ResponseBody(Stream.value(bytes), 200)));
        } else {
          h.resolve(Response(
              requestOptions: o,
              statusCode: 200,
              data: {'tag_name': 'v0.0.1'}));
        }
      }));
    final service = AppUpdateService(dio: dio);
    await service.checkForUpdate(
        currentVersionName: '1.6.6', currentVersionCode: 51);
    await service.downloadApk(candidate(), targetDirectory: dir.path);
    expect(seen.first.connectTimeout, const Duration(seconds: 8));
    expect(seen.first.receiveTimeout, const Duration(seconds: 12));
    expect(seen.last.connectTimeout, const Duration(seconds: 30));
    expect(seen.last.receiveTimeout, const Duration(seconds: 60));
    expect(dio.options.connectTimeout, const Duration(seconds: 8));
    expect(dio.options.receiveTimeout, const Duration(seconds: 12));
    expect(service.totalDownloadTimeout, const Duration(minutes: 5));
  });

  for (final kind in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout
  ]) {
    test('retries only once for initial ${kind.name}', () async {
      var calls = 0;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          calls++;
          if (calls == 1) {
            h.reject(DioException(requestOptions: o, type: kind));
          } else {
            h.resolve(Response<ResponseBody>(
                requestOptions: o,
                statusCode: 200,
                data: ResponseBody(Stream.value(bytes), 200)));
          }
        }));
      final result = await AppUpdateService(dio: dio)
          .downloadApk(candidate(), targetDirectory: dir.path);
      expect(calls, 2);
      expect(await result.readAsBytes(), bytes);
    });
  }
  test('exhausted initial timeout stops after two attempts and cleans partials',
      () async {
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        h.reject(DioException.receiveTimeout(
            timeout: const Duration(seconds: 60), requestOptions: o));
      }));
    await expectLater(
        AppUpdateService(dio: dio)
            .downloadApk(candidate(), targetDirectory: dir.path),
        throwsA(isA<DioException>()));
    expect(calls, 2);
    expect(await dir.list().toList(), isEmpty);
  });
  for (final code in [403, 404, 429, 500]) {
    test('HTTP $code is not retried', () async {
      var calls = 0;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          calls++;
          h.resolve(Response<ResponseBody>(
              requestOptions: o,
              statusCode: code,
              data: ResponseBody(Stream.value(bytes), code)));
        }));
      await expectLater(
          AppUpdateService(dio: dio)
              .downloadApk(candidate(), targetDirectory: dir.path),
          throwsA(anything));
      expect(calls, 1);
      expect(await dir.list().toList(), isEmpty);
    });
  }
  test('certificate rejection is not retried', () async {
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        h.reject(DioException(
            requestOptions: o, type: DioExceptionType.badCertificate));
      }));
    await expectLater(
        AppUpdateService(dio: dio)
            .downloadApk(candidate(), targetDirectory: dir.path),
        throwsA(isA<DioException>()));
    expect(calls, 1);
  });
  test('a timeout after response bytes is not retried', () async {
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        Stream<Uint8List> body() async* {
          yield bytes.sublist(0, 4);
          throw DioException.receiveTimeout(
              timeout: const Duration(seconds: 60), requestOptions: o);
        }

        h.resolve(Response<ResponseBody>(
            requestOptions: o,
            statusCode: 200,
            data: ResponseBody(body(), 200)));
      }));
    await expectLater(
        AppUpdateService(dio: dio)
            .downloadApk(candidate(), targetDirectory: dir.path),
        throwsA(isA<DioException>()));
    expect(calls, 1);
    expect(await dir.list().toList(), isEmpty);
  });
  test('header rejection closes the prefetched body without publishing a file',
      () async {
    var cancelled = 0;
    final body = StreamController<Uint8List>(onCancel: () {
      cancelled++;
    });
    body.add(bytes);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        h.resolve(Response<ResponseBody>(
            requestOptions: o,
            statusCode: 200,
            headers: Headers.fromMap({
              'content-length': ['999']
            }),
            data: ResponseBody(body.stream, 200)));
      }));
    await expectLater(
        AppUpdateService(dio: dio)
            .downloadApk(candidate(), targetDirectory: dir.path),
        throwsStateError);
    expect(cancelled, 1);
    expect(await dir.list().toList(), isEmpty);
    await body.close();
  });
  for (final parallel in [false, true]) {
    test(
        '${parallel ? 'range' : 'full'} invalid headers with stalled body fail before retry',
        () async {
      var calls = 0, cancelled = 0;
      final body = StreamController<Uint8List>(onCancel: () {
        cancelled++;
      });
      final size = parallel ? 8 * 1024 * 1024 : bytes.length;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          calls++;
          h.resolve(Response<ResponseBody>(
              requestOptions: o,
              statusCode: parallel ? 206 : 200,
              headers: Headers.fromMap(parallel
                  ? {
                      'content-range': ['bytes 1-2/$size']
                    }
                  : {
                      'content-length': ['999']
                    }),
              data: ResponseBody(body.stream, parallel ? 206 : 200)));
        }));
      final parent = CancelToken();
      final info = AppUpdateInfo(
          versionName: '99',
          releaseUrl: '',
          apkName: 'fixture.apk',
          apkDownloadUrl: 'https://example.org/a.apk',
          releaseNotes: '',
          apkSize: size,
          sha256Hash: 'a' * 64);
      await expectLater(
              AppUpdateService(
                      dio: dio,
                      parallelDownloads: parallel,
                      totalDownloadTimeout: const Duration(milliseconds: 500))
                  .downloadApk(info,
                      targetDirectory: dir.path, cancelToken: parent),
              throwsStateError)
          .timeout(const Duration(seconds: 1));
      expect(calls, 1);
      expect(cancelled, 1);
      expect(parent.isCancelled, isFalse);
      expect(await dir.list().toList(), isEmpty);
      await body.close();
    });
  }
  test('user cancellation during retry delay prevents another request',
      () async {
    final first = Completer<void>();
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        h.reject(DioException.receiveTimeout(
            timeout: const Duration(seconds: 60), requestOptions: o));
        if (!first.isCompleted) first.complete();
      }));
    final token = CancelToken();
    final future = AppUpdateService(dio: dio).downloadApk(candidate(),
        targetDirectory: dir.path, cancelToken: token);
    final failure = expectLater(future, throwsA(isA<DioException>()));
    await first.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel('user cancelled');
    await failure.timeout(const Duration(milliseconds: 500));
    expect(calls, 1);
    expect(await dir.list().toList(), isEmpty);
  });
  test('total budget includes preparation and never cancels its caller',
      () async {
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        h.reject(DioException.receiveTimeout(
            timeout: const Duration(seconds: 60), requestOptions: o));
      }));
    final token = CancelToken();
    await expectLater(
        AppUpdateService(
                dio: dio,
                totalDownloadTimeout: const Duration(milliseconds: 80))
            .downloadApk(candidate(),
                targetDirectory: dir.path, cancelToken: token),
        throwsA(isA<DioException>()));
    expect(calls, inInclusiveRange(0, 1));
    expect(token.isCancelled, isFalse);
    expect(await dir.list().toList(), isEmpty);
  });
  test('a started request cannot reset the total budget before retry',
      () async {
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        calls++;
        await Future<void>.delayed(const Duration(seconds: 1));
        h.reject(DioException.receiveTimeout(
            timeout: const Duration(seconds: 60), requestOptions: o));
      }));
    final parent = CancelToken();
    await expectLater(
            AppUpdateService(
                    dio: dio,
                    totalDownloadTimeout: const Duration(milliseconds: 1500))
                .downloadApk(candidate(),
                    targetDirectory: dir.path, cancelToken: parent),
            throwsA(isA<DioException>()))
        .timeout(const Duration(seconds: 3));
    expect(calls, 1);
    expect(parent.isCancelled, isFalse);
    expect(await dir.list().toList(), isEmpty);
  });
  test('a real redirect with 20 second delayed headers downloads and verifies',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var closing = false;
    addTearDown(() async {
      closing = true;
      await server.close(force: true);
    });
    server.listen((request) async {
      try {
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers
              .set(HttpHeaders.locationHeader, '/asset.apk');
        } else {
          await Future<void>.delayed(const Duration(seconds: 20));
          if (closing) return;
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
        }
        await request.response.close();
      } catch (_) {
        if (!closing) rethrow;
      }
    });
    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12)));
    addTearDown(() => dio.close(force: true));
    final result = await AppUpdateService(dio: dio).downloadApk(
        candidate(url: 'http://127.0.0.1:${server.port}/redirect'),
        targetDirectory: dir.path);
    expect(await result.readAsBytes(), bytes);
  }, timeout: const Timeout(Duration(seconds: 45)));
  test('flushed headers with no first body byte time out and retry once',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var calls = 0;
    server.listen((request) async {
      calls++;
      request.response.contentLength = bytes.length;
      if (calls == 1) {
        unawaited(request.response.done
            .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
        await request.response.flush();
        return;
      }
      request.response.add(bytes);
      await request.response.close();
    });
    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12)));
    addTearDown(() => dio.close(force: true));
    final result = await AppUpdateService(dio: dio).downloadApk(
        candidate(url: 'http://127.0.0.1:${server.port}/asset.apk'),
        targetDirectory: dir.path);
    expect(calls, 2);
    expect(await result.readAsBytes(), bytes);
  }, timeout: const Timeout(Duration(seconds: 90)));
  for (final disconnect in [false, true]) {
    test(
        'real body ${disconnect ? 'disconnect' : 'idle timeout'} does not retry or retain partials',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var calls = 0;
      server.listen((request) async {
        calls++;
        request.response.bufferOutput = false;
        request.response.contentLength = bytes.length;
        unawaited(request.response.done
            .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
        request.response.add(bytes.sublist(0, 4));
        await request.response.flush();
        if (disconnect) {
          try {
            await request.response.close();
          } on HttpException {
            // Deliberately close a response before its declared body length.
          }
        }
      });
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final parent = CancelToken();
      addTearDown(() => parent.cancel('test cleanup'));
      var received = 0;
      await expectLater(
          AppUpdateService(dio: dio).downloadApk(
              candidate(url: 'http://127.0.0.1:${server.port}/asset.apk'),
              targetDirectory: dir.path,
              cancelToken: parent,
              onProgress: (n, _) => received = n),
          throwsA(disconnect
              ? isA<HttpException>()
              : isA<DioException>().having(
                  (e) => e.type, 'type', DioExceptionType.receiveTimeout)));
      expect(received, 4);
      expect(calls, 1);
      expect(parent.isCancelled, isFalse);
      expect(await dir.list().toList(), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 90)));
  }
}

ResponseBody _redirect(int status, String? location) =>
    ResponseBody.fromBytes(const [], status,
        isRedirect: true,
        headers: {
          if (location != null) HttpHeaders.locationHeader: [location],
        });

Future<Object> _apkStatusOrError(Future<Response<ResponseBody>> request) async {
  try {
    final response = await request;
    await response.data?.stream.drain<void>();
    return response.statusCode!;
  } catch (error) {
    return error;
  }
}

class _ApkFixtureAdapter implements HttpClientAdapter {
  _ApkFixtureAdapter(this._respond, {this.onClose});

  final FutureOr<ResponseBody> Function(
      RequestOptions, Stream<Uint8List>?, Future<void>?) _respond;
  final void Function(bool)? onClose;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      _respond(options, requestStream, cancelFuture);

  @override
  void close({bool force = false}) => onClose?.call(force);
}
