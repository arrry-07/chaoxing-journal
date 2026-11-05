import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
