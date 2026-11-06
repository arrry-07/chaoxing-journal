import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

void main() {
  late Directory dir;
  final bytes = Uint8List(8 * 1024 * 1024)..setAll(0, [80, 75, 3, 4]);
  AppUpdateInfo candidate({String? hash}) => AppUpdateInfo(
      versionName: '99',
      releaseUrl: '',
      apkName: 'fixture.apk',
      apkDownloadUrl: 'https://example.org/a.apk',
      releaseNotes: '',
      apkSize: bytes.length,
      sha256Hash: hash ?? sha256.convert(bytes).toString());
  setUp(
      () async => dir = await Directory.systemTemp.createTemp('parallel-apk-'));
  tearDown(() async => dir.delete(recursive: true));
  for (final corrupt in ['hash', 'truncated']) {
    test('rejects $corrupt parallel transfer without publishing APK', () async {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          final range = RegExp(r'bytes=(\d+)-(\d+)')
              .firstMatch(o.headers['Range'] as String)!;
          final start = int.parse(range[1]!), end = int.parse(range[2]!);
          final body = Uint8List.sublistView(bytes, start,
              end + 1 - (corrupt == 'truncated' && start == 0 ? 1 : 0));
          h.resolve(Response<ResponseBody>(
              requestOptions: o,
              statusCode: 206,
              headers: Headers.fromMap({
                'content-range': ['bytes $start-$end/${bytes.length}']
              }),
              data: ResponseBody(Stream.value(body), 206)));
        }));
      await expectLater(
          AppUpdateService(dio: dio, parallelDownloads: true).downloadApk(
              candidate(hash: corrupt == 'hash' ? 'a' * 64 : null),
              targetDirectory: dir.path),
          throwsA(anything));
      expect(await dir.list().toList(), isEmpty);
    });
  }
  test('downloads four exact ranges and reassembles a verified APK', () async {
    final ranges = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final range = o.headers['Range'] as String?;
        if (range == null) {
          h.resolve(Response<ResponseBody>(
              requestOptions: o,
              statusCode: 200,
              data: ResponseBody(Stream.value(bytes), 200)));
          return;
        }
        ranges.add(range);
        final parts = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final start = int.parse(parts[1]!), end = int.parse(parts[2]!);
        h.resolve(Response<ResponseBody>(
            requestOptions: o,
            statusCode: 206,
            headers: Headers.fromMap({
              'content-range': ['bytes $start-$end/${bytes.length}'],
              'content-length': ['${end - start + 1}']
            }),
            data: ResponseBody(
                Stream.value(Uint8List.sublistView(bytes, start, end + 1)),
                206)));
      }));
    final file = await AppUpdateService(dio: dio, parallelDownloads: true)
        .downloadApk(candidate(), targetDirectory: dir.path);
    expect(ranges.length, 4);
    expect(sha256.convert(await file.readAsBytes()).toString(),
        candidate().sha256Hash);
    expect((await dir.list().toList()).length, 1);
  });
  test(
      'a server ignoring Range reuses the full response without a second request',
      () async {
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        h.resolve(Response<ResponseBody>(
            requestOptions: o,
            statusCode: 200,
            data: ResponseBody(Stream.value(bytes), 200)));
      }));
    final file = await AppUpdateService(dio: dio, parallelDownloads: true)
        .downloadApk(candidate(), targetDirectory: dir.path);
    expect(calls, 1);
    expect(await file.length(), bytes.length);
  });
  test('invalid Content-Range fails closed and leaves no partial APK',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        h.resolve(Response<ResponseBody>(
            requestOptions: o,
            statusCode: 206,
            headers: Headers.fromMap({
              'content-range': ['bytes 1-2/${bytes.length}']
            }),
            data: ResponseBody(Stream.value(Uint8List.fromList([1, 2])), 206)));
      }));
    await expectLater(
        AppUpdateService(dio: dio, parallelDownloads: true)
            .downloadApk(candidate(), targetDirectory: dir.path),
        throwsA(isA<StateError>()));
    expect(await dir.list().toList(), isEmpty);
  });
  test('cancelling all active ranges releases streams and removes partials',
      () async {
    final streams = <StreamController<Uint8List>>[];
    final started = Completer<void>();
    var released = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final match = RegExp(r'bytes=(\d+)-(\d+)')
            .firstMatch(o.headers['Range'] as String)!;
        final begin = int.parse(match[1]!), end = int.parse(match[2]!);
        final stream = StreamController<Uint8List>(onCancel: () {
          released++;
        });
        streams.add(stream);
        h.resolve(Response<ResponseBody>(
            requestOptions: o,
            statusCode: 206,
            headers: Headers.fromMap({
              'content-range': ['bytes $begin-$end/${bytes.length}']
            }),
            data: ResponseBody(stream.stream, 206)));
        if (streams.length == 4) started.complete();
      }));
    final token = CancelToken();
    final future = AppUpdateService(dio: dio, parallelDownloads: true)
        .downloadApk(candidate(),
            targetDirectory: dir.path, cancelToken: token);
    final checked = expectLater(future, throwsA(isA<DioException>()));
    await started.future;
    token.cancel();
    await checked.timeout(const Duration(seconds: 2));
    expect(released, 4);
    expect(await dir.list().toList(), isEmpty);
    for (final stream in streams) {
      await stream.close();
    }
  });
}
