import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
