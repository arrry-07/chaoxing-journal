import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

const candidate = AppUpdateInfo(
  versionName: '99.0.0',
  releaseUrl: 'https://example.invalid/release',
  apkName: 'fixture.apk',
  apkDownloadUrl: 'https://example.invalid/fixture.apk',
  releaseNotes: '',
);

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bounded-apk-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Dio response(Stream<Uint8List> body, {int? contentLength}) => Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response<ResponseBody>(
          requestOptions: options,
          statusCode: 200,
          headers: Headers.fromMap({
            if (contentLength != null) 'content-length': ['$contentLength'],
          }),
          data: ResponseBody(body, 200)));
    }));

  test(
      'stops a lengthless stream at the cumulative byte limit and removes partials',
      () async {
    var cancelled = false;
    final stream = StreamController<Uint8List>(onCancel: () {
      cancelled = true;
    });
    stream.add(Uint8List.fromList([1, 2, 3]));
    stream.add(Uint8List.fromList([4, 5, 6]));
    final service =
        AppUpdateService(dio: response(stream.stream), maxDownloadBytes: 4);
    await expectLater(service.downloadApk(candidate, targetDirectory: dir.path),
        throwsA(isA<StateError>()));
    expect(cancelled, isTrue);
    expect(await dir.list().toList(), isEmpty);
    await stream.close();
  });

  test('rejects a header that contradicts the release asset size', () async {
    final service = AppUpdateService(
        dio: response(Stream.value(Uint8List(4)), contentLength: 4));
    const sized = AppUpdateInfo(
        versionName: '99',
        releaseUrl: '',
        apkName: 'fixture.apk',
        apkDownloadUrl: 'https://example.invalid/a.apk',
        releaseNotes: '',
        apkSize: 5);
    await expectLater(service.downloadApk(sized, targetDirectory: dir.path),
        throwsA(isA<StateError>()));
    expect(await dir.list().toList(), isEmpty);
  });

  test('total timeout stops a stream even when small chunks keep arriving',
      () async {
    var cancelled = false;
    late Timer timer;
    late StreamController<Uint8List> stream;
    stream = StreamController<Uint8List>(onListen: () {
      timer = Timer.periodic(
          const Duration(milliseconds: 5), (_) => stream.add(Uint8List(1)));
    }, onCancel: () {
      cancelled = true;
      timer.cancel();
    });
    final service = AppUpdateService(
        dio: response(stream.stream),
        totalDownloadTimeout: const Duration(milliseconds: 60));
    await expectLater(service.downloadApk(candidate, targetDirectory: dir.path),
        throwsA(isA<DioException>()));
    expect(cancelled, isTrue);
    expect(await dir.list().toList(), isEmpty);
    await stream.close();
  });

  test(
      'cancelling a stalled stream releases it and leaves an existing APK intact',
      () async {
    final existing =
        await File('${dir.path}/fixture.apk').writeAsBytes([9, 8, 7]);
    var cancelled = false;
    final stream = StreamController<Uint8List>(onCancel: () {
      cancelled = true;
    });
    final token = CancelToken();
    final service = AppUpdateService(dio: response(stream.stream));
    final downloading = service.downloadApk(candidate,
        targetDirectory: dir.path, cancelToken: token);
    final checked = expectLater(downloading, throwsA(isA<DioException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel();
    await checked.timeout(const Duration(seconds: 2));
    expect(cancelled, isTrue);
    expect(await existing.readAsBytes(), [9, 8, 7]);
    expect((await dir.list().toList()).length, 1);
    await stream.close();
  });

  test('a cancelled earlier attempt cannot remove a completed retry', () async {
    final closeOldStream = Completer<void>();
    final oldStarted = Completer<void>();
    final first =
        StreamController<Uint8List>(onCancel: () => closeOldStream.future);
    first.add(Uint8List.fromList([1]));
    var requests = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        final stream = requests++ == 0
            ? first.stream
            : Stream.value(Uint8List.fromList([9, 8, 7]));
        handler.resolve(Response<ResponseBody>(
            requestOptions: options,
            statusCode: 200,
            data: ResponseBody(stream, 200)));
      }));
    final service = AppUpdateService(dio: dio);
    final token = CancelToken();
    final old = service.downloadApk(candidate,
        targetDirectory: dir.path, cancelToken: token, onProgress: (_, __) {
      if (!oldStarted.isCompleted) oldStarted.complete();
    });
    final checked = expectLater(old, throwsA(isA<DioException>()));
    await oldStarted.future;
    token.cancel();
    final retry =
        await service.downloadApk(candidate, targetDirectory: dir.path);
    closeOldStream.complete();
    await checked;
    expect(await retry.readAsBytes(), [9, 8, 7]);
    expect((await dir.list().toList()).length, 1);
    await first.close();
  });

  test('a failing transport cancellation still closes and removes the partial',
      () async {
    final stream = StreamController<Uint8List>(onCancel: () {
      throw StateError('synthetic transport close failure');
    });
    stream.add(Uint8List(8));
    final service =
        AppUpdateService(dio: response(stream.stream), maxDownloadBytes: 4);
    await expectLater(service.downloadApk(candidate, targetDirectory: dir.path),
        throwsA(isA<StateError>()));
    expect(await dir.list().toList(), isEmpty);
    await stream.close();
  });

  test('rejects an HTTP error without draining an unbounded error body',
      () async {
    var cancelled = false;
    final stream = StreamController<Uint8List>(onCancel: () {
      cancelled = true;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response<ResponseBody>(
            requestOptions: options,
            statusCode: 404,
            data: ResponseBody(stream.stream, 404)));
      }));
    final service = AppUpdateService(dio: dio);
    await expectLater(service.downloadApk(candidate, targetDirectory: dir.path),
        throwsA(isA<StateError>()));
    expect(cancelled, isTrue);
    expect(await dir.list().toList(), isEmpty);
    await stream.close();
  });
}
