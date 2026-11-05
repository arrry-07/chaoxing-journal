import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

void main() {
  for (final pair in [
    (401, UpdateCheckStatus.authRequired),
    (404, UpdateCheckStatus.networkError),
    (429, UpdateCheckStatus.networkError)
  ]) {
    test('manifest HTTP ${pair.$1} is not upToDate', () async {
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (o, h) => h.resolve(
                Response(requestOptions: o, statusCode: pair.$1, data: {}))));
      expect(
          (await AppUpdateService(
                      dio: dio, manifestUrl: 'https://example.org/update.json')
                  .checkConfigured(currentVersionCode: 31))
              .status,
          pair.$2);
    });
  }
  test('malformed manifest stays an error', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(
              requestOptions: o, statusCode: 200, data: {'versionCode': 32}))));
    expect(
        (await AppUpdateService(
                    dio: dio, manifestUrl: 'https://example.org/update.json')
                .checkConfigured(currentVersionCode: 31))
            .status,
        UpdateCheckStatus.invalidManifest);
  });
  test('hash mismatch removes partial APK and does not publish a final file',
      () async {
    final dir = await Directory.systemTemp.createTemp('journal-hash-');
    addTearDown(() => dir.delete(recursive: true));
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response<ResponseBody>(
              requestOptions: o,
              statusCode: 200,
              data: ResponseBody(
                  Stream.value(Uint8List.fromList([80, 75, 3, 4])), 200)))));
    final service = AppUpdateService(dio: dio);
    await expectLater(
        service.downloadApk(
            AppUpdateInfo(
                versionName: '1',
                releaseUrl: 'https://example.org',
                apkName: 'test.apk',
                apkDownloadUrl: 'https://example.org/test.apk',
                releaseNotes: '',
                sha256Hash: 'a' * 64),
            targetDirectory: dir.path),
        throwsStateError);
    expect(await dir.list().toList(), isEmpty);
  });
  test('cancelled check is distinct from latest', () async {
    final cancel = CancelToken()..cancel();
    expect(
        (await AppUpdateService(manifestUrl: 'https://example.org/update.json')
                .checkConfigured(currentVersionCode: 31, cancelToken: cancel))
            .status,
        UpdateCheckStatus.cancelled);
  });
  test('default GitHub channel reports an older release as up to date',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(
              requestOptions: o,
              statusCode: 200,
              data: {'tag_name': 'v1.0.0'}))));
    expect(
        (await AppUpdateService(dio: dio)
                .checkConfigured(currentVersionCode: 31))
            .status,
        UpdateCheckStatus.upToDate);
  });
  test('same display version with higher code is an update', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) =>
              h.resolve(Response(requestOptions: o, statusCode: 200, data: {
                'applicationId': 'com.example.studyassistant',
                'versionCode': 32,
                'versionName': '1.2.1',
                'apkUrl': 'https://example.org/app.apk',
                'sha256': 'a' * 64
              }))));
    final result = await AppUpdateService(
            dio: dio, manifestUrl: 'https://example.org/update.json')
        .checkConfigured(currentVersionCode: 31);
    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionCode, 32);
  });
}
