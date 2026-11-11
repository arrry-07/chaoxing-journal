import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

void main() {
  test('finds newer GitHub release apk asset', () async {
    final dio = Dio(
      BaseOptions(validateStatus: (status) => status != null && status < 500),
    )..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'tag_name': 'v1.0.7',
                  'name': 'v1.0.7',
                  'html_url':
                      'https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.0.7',
                  'body': 'bug fixes',
                  'assets': [
                    {
                      'name': 'study-assistant-v1.0.7.apk',
                      'browser_download_url':
                          'https://github.com/arrry-07/chaoxing-journal/releases/download/v1.0.7/study-assistant-v1.0.7.apk',
                      'size': 123456,
                      'digest': 'sha256:${'a' * 64}',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
    final service = AppUpdateService(dio: dio);

    final update = await service.checkForUpdate(
      currentVersionName: '1.0.6',
      currentVersionCode: 17,
    );

    expect(update, isNotNull);
    expect(update!.versionName, '1.0.7');
    expect(update.apkName, 'study-assistant-v1.0.7.apk');
    expect(update.apkDownloadUrl, contains('/study-assistant-v1.0.7.apk'));
    expect(update.releaseNotes, 'bug fixes');
  });

  test('ignores release when remote version is not newer', () async {
    final dio = Dio(
      BaseOptions(validateStatus: (status) => status != null && status < 500),
    )..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'tag_name': 'v1.0.6',
                  'assets': [
                    {
                      'name': 'study-assistant-v1.0.6.apk',
                      'browser_download_url': 'https://example.com/app.apk',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
    final service = AppUpdateService(dio: dio);

    final update = await service.checkForUpdate(
      currentVersionName: '1.0.6',
      currentVersionCode: 17,
    );

    expect(update, isNull);
  });

  test('compares semantic versions numerically', () {
    expect(AppUpdateService.isRemoteVersionNewer('1.0.10', '1.0.6'), isTrue);
    expect(AppUpdateService.isRemoteVersionNewer('1.0.6', '1.0.10'), isFalse);
    expect(AppUpdateService.isRemoteVersionNewer('v2.0.0', '1.9.9'), isTrue);
  });

  test('transient primary failure falls back to a same-digest backup',
      () async {
    final bytes = Uint8List.fromList([0x50, 0x4b, 3, 4, 1, 2, 3]);
    final digest = sha256.convert(bytes).toString();
    final requests = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options.uri.toString());
        if (options.uri.host == 'primary.example.org') {
          handler.reject(DioException.connectionError(
            requestOptions: options,
            reason: 'primary unavailable',
          ));
          return;
        }
        handler.resolve(Response<ResponseBody>(
          requestOptions: options,
          statusCode: 200,
          data: ResponseBody(Stream.value(bytes), 200),
        ));
      }));
    final dir = await Directory.systemTemp.createTemp('journal-backup-');
    addTearDown(() => dir.delete(recursive: true));

    final file = await AppUpdateService(dio: dio).downloadApk(
      AppUpdateInfo(
        versionName: '1.7.3',
        releaseUrl: 'https://example.org/release',
        apkName: 'journal.apk',
        apkDownloadUrl: 'https://primary.example.org/journal.apk',
        backupApkUrls: const ['https://backup.example.org/journal.apk'],
        releaseNotes: '',
        apkSize: bytes.length,
        sha256Hash: digest,
      ),
      targetDirectory: dir.path,
    );

    expect(requests, [
      'https://primary.example.org/journal.apk',
      'https://backup.example.org/journal.apk',
    ]);
    expect(await file.readAsBytes(), bytes);
    expect(file.path, endsWith('-$digest.apk'));
  });

  test('a primary digest mismatch never falls through to the backup', () async {
    final expectedBytes = Uint8List.fromList([0x50, 0x4b, 3, 4, 1]);
    final wrongBytes = Uint8List.fromList([0x50, 0x4b, 3, 4, 2]);
    final requests = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options.uri.host);
        handler.resolve(Response<ResponseBody>(
          requestOptions: options,
          statusCode: 200,
          data: ResponseBody(Stream.value(wrongBytes), 200),
        ));
      }));
    final dir = await Directory.systemTemp.createTemp('journal-no-fallback-');
    addTearDown(() => dir.delete(recursive: true));

    await expectLater(
      AppUpdateService(dio: dio).downloadApk(
        AppUpdateInfo(
          versionName: '1.7.3',
          releaseUrl: 'https://example.org/release',
          apkName: 'journal.apk',
          apkDownloadUrl: 'https://primary.example.org/journal.apk',
          backupApkUrls: const ['https://backup.example.org/journal.apk'],
          releaseNotes: '',
          apkSize: expectedBytes.length,
          sha256Hash: sha256.convert(expectedBytes).toString(),
        ),
        targetDirectory: dir.path,
      ),
      throwsStateError,
    );

    expect(requests, ['primary.example.org']);
    expect(await dir.list().toList(), isEmpty);
  });

  test('an APK redirect chain cannot downgrade from HTTPS', () async {
    final bytes = Uint8List.fromList([0x50, 0x4b, 3, 4, 1]);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response<ResponseBody>(
          requestOptions: options,
          statusCode: 200,
          data: ResponseBody(Stream.value(bytes), 200),
          redirects: [
            RedirectRecord(
              302,
              'GET',
              Uri.parse('http://mirror.example.org/journal.apk'),
            ),
          ],
        ));
      }));
    final dir = await Directory.systemTemp.createTemp('journal-redirect-');
    addTearDown(() => dir.delete(recursive: true));

    await expectLater(
      AppUpdateService(dio: dio).downloadApk(
        AppUpdateInfo(
          versionName: '1.7.3',
          releaseUrl: 'https://example.org/release',
          apkName: 'journal.apk',
          apkDownloadUrl: 'https://primary.example.org/journal.apk',
          releaseNotes: '',
          apkSize: bytes.length,
          sha256Hash: sha256.convert(bytes).toString(),
        ),
        targetDirectory: dir.path,
      ),
      throwsStateError,
    );
    expect(await dir.list().toList(), isEmpty);
  });

  test('backup bytes still have to match the manifest digest', () async {
    final expectedBytes = Uint8List.fromList([0x50, 0x4b, 3, 4, 1]);
    final wrongBytes = Uint8List.fromList([0x50, 0x4b, 3, 4, 2]);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.uri.host == 'primary.example.org') {
          handler.reject(DioException.connectionTimeout(
            timeout: const Duration(seconds: 30),
            requestOptions: options,
          ));
        } else {
          handler.resolve(Response<ResponseBody>(
            requestOptions: options,
            statusCode: 200,
            data: ResponseBody(Stream.value(wrongBytes), 200),
          ));
        }
      }));
    final dir = await Directory.systemTemp.createTemp('journal-bad-backup-');
    addTearDown(() => dir.delete(recursive: true));

    await expectLater(
      AppUpdateService(dio: dio).downloadApk(
        AppUpdateInfo(
          versionName: '1.7.3',
          releaseUrl: 'https://example.org/release',
          apkName: 'journal.apk',
          apkDownloadUrl: 'https://primary.example.org/journal.apk',
          backupApkUrls: const ['https://backup.example.org/journal.apk'],
          releaseNotes: '',
          apkSize: expectedBytes.length,
          sha256Hash: sha256.convert(expectedBytes).toString(),
        ),
        targetDirectory: dir.path,
      ),
      throwsStateError,
    );
    expect(await dir.list().toList(), isEmpty);
  });

  test('downloads GitHub apk asset to a local apk file', () async {
    final tempDir = await Directory.systemTemp.createTemp('study-update-test-');
    addTearDown(() => tempDir.delete(recursive: true));
    final progressEvents = <List<int>>[];
    final dio = Dio(
      BaseOptions(validateStatus: (status) => status != null && status < 500),
    )..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.responseType, ResponseType.stream);
            handler.resolve(
              Response<ResponseBody>(
                requestOptions: options,
                statusCode: 200,
                data: ResponseBody(
                    Stream.fromIterable([
                      Uint8List.fromList([1, 2]),
                      Uint8List.fromList([3, 4])
                    ]),
                    200),
              ),
            );
          },
        ),
      );
    final service = AppUpdateService(dio: dio);

    final downloaded = await service.downloadApk(
      const AppUpdateInfo(
        versionName: '1.0.7',
        releaseUrl:
            'https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.0.7',
        apkName: 'study-assistant-v1.0.7.apk',
        apkDownloadUrl:
            'https://github.com/arrry-07/chaoxing-journal/releases/download/v1.0.7/study-assistant-v1.0.7.apk',
        releaseNotes: '',
      ),
      targetDirectory: tempDir.path,
      onProgress: (received, total) {
        progressEvents.add([received, total]);
      },
    );

    expect(downloaded.path, endsWith('study-assistant-v1.0.7.apk'));
    expect(await File(downloaded.path).readAsBytes(), [1, 2, 3, 4]);
    expect(progressEvents.last, [4, 4]);
  });
}
