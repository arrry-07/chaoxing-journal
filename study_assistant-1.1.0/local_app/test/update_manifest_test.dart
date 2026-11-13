import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_version.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

const manifestHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

String patchVersion() {
  final parts = AppVersion.name.split('.').map(int.parse).toList();
  return '${parts[0]}.${parts[1]}.${parts[2] + 1}';
}

String iterationVersion() {
  final parts = AppVersion.name.split('.').map(int.parse).toList();
  return '${parts[0]}.${parts[1] + 1}.0';
}

Map<String, dynamic> manifest({
  String? versionName,
  int? versionCode,
  String applicationId = AppUpdateService.applicationId,
  String apkUrl = 'https://download.example.org/app.apk',
  String sha256 = manifestHash,
  int size = 1234,
  String? backupApkUrl,
}) =>
    {
      'versionCode': versionCode ?? AppVersion.code + 1,
      'versionName': versionName ?? patchVersion(),
      'applicationId': applicationId,
      'apkUrl': apkUrl,
      'sha256': sha256,
      'size': size,
      if (backupApkUrl != null) 'backupApkUrl': backupApkUrl,
    };

Dio manifestDio(
  dynamic Function(RequestOptions options) body, {
  int Function(RequestOptions options)? status,
  List<String>? paths,
}) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      paths?.add(options.uri.toString());
      handler.resolve(Response(
        requestOptions: options,
        statusCode: status?.call(options) ?? 200,
        data: body(options),
      ));
    }));
  return dio;
}

void main() {
  test('client defaults to fixed Gitee stable and manual manifests', () {
    final service = AppUpdateService.withGiteeDefaults();
    expect(
      service.stableManifestUrl,
      'https://raw.giteeusercontent.com/arrry-07/chaoxing-journal-updates/raw/master/update-stable.json',
    );
    expect(
      service.manualManifestUrl,
      'https://raw.giteeusercontent.com/arrry-07/chaoxing-journal-updates/raw/master/update-manual.json',
    );
  });

  test('explicit update manifest configuration overrides Gitee defaults', () {
    final legacy = AppUpdateService.withGiteeDefaults(
      legacyManifestUrl: 'https://updates.example.org/legacy.json',
    );
    expect(legacy.manifestUrl, 'https://updates.example.org/legacy.json');
    expect(legacy.stableManifestUrl, isEmpty);
    expect(legacy.manualManifestUrl, isEmpty);

    final stableOnly = AppUpdateService.withGiteeDefaults(
      stableManifestUrl: 'https://updates.example.org/stable.json',
    );
    expect(stableOnly.stableManifestUrl,
        'https://updates.example.org/stable.json');
    expect(stableOnly.manualManifestUrl, isEmpty);
  });

  for (final pair in [
    (401, UpdateCheckStatus.authRequired),
    (403, UpdateCheckStatus.authRequired),
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
  test('manifest JSON bytes accept UTF-8 BOM and non-JSON content type',
      () async {
    final manifest =
        '{"applicationId":"${AppUpdateService.applicationId}","versionCode":${AppVersion.code + 1},"versionName":"${patchVersion()}","apkUrl":"https://example.org/app.apk","sha256":"$manifestHash","size":1234}';
    final bytes = Uint8List.fromList([239, 187, 191, ...utf8.encode(manifest)]);
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        expect(o.responseType, ResponseType.stream);
        expect(o.followRedirects, isFalse);
        h.resolve(Response<String>(
          requestOptions: o,
          statusCode: 200,
          data: utf8.decode(bytes),
          headers: Headers.fromMap({
            'content-type': ['application/octet-stream']
          }),
        ));
      }));
    final result = await AppUpdateService(
      dio: dio,
      manifestUrl: 'https://example.org/update.json',
    ).checkConfigured(currentVersionCode: 31);
    expect(result.status, UpdateCheckStatus.available);
    expect(result.update?.versionCode, AppVersion.code + 1);
  });
  test('manifest redirects are rejected instead of followed', () async {
    final dio = manifestDio(
      (_) => manifest(),
      status: (_) => 302,
    );
    final result = await AppUpdateService(
      dio: dio,
      manifestUrl: 'https://updates.example.org/update.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.networkError);
    expect(result.update, isNull);
  });
  test('manifest bodies are capped at 64 KiB', () async {
    final dio = manifestDio((_) => ' ' * (64 * 1024 + 1));
    final result = await AppUpdateService(
      dio: dio,
      manifestUrl: 'https://updates.example.org/update.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.invalidManifest);
    expect(result.update, isNull);
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
          onRequest: (o, h) =>
              h.resolve(Response(requestOptions: o, statusCode: 200, data: [
                {'tag_name': 'v1.0.0'}
              ]))));
    expect(
        (await AppUpdateService(
                    dio: dio, stableManifestUrl: '', manualManifestUrl: '')
                .checkConfigured(currentVersionCode: 31))
            .status,
        UpdateCheckStatus.upToDate);
  });
  test('same display version with higher code is an update', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(
              requestOptions: o,
              statusCode: 200,
              data: manifest(versionName: AppVersion.name)))));
    final result = await AppUpdateService(
            dio: dio, manifestUrl: 'https://example.org/update.json')
        .checkConfigured(currentVersionCode: 31);
    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionCode, AppVersion.code + 1);
  });

  test('startup and manual both discover a patch from the manual manifest',
      () async {
    final paths = <String>[];
    final dio = manifestDio(
      (options) => manifest(),
      paths: paths,
    );
    final service = AppUpdateService(
      dio: dio,
      stableManifestUrl: 'https://updates.example.org/stable.json',
      manualManifestUrl: 'https://updates.example.org/manual.json',
    );

    final startup =
        await service.checkForStartup(currentVersionCode: AppVersion.code);
    expect(startup.status, UpdateCheckStatus.available);
    expect(startup.update!.versionName, patchVersion());

    final manual =
        await service.checkConfigured(currentVersionCode: AppVersion.code);
    expect(manual.status, UpdateCheckStatus.available);
    expect(manual.update!.versionName, patchVersion());
    expect(paths, [
      'https://updates.example.org/manual.json',
      'https://updates.example.org/manual.json',
    ]);
  });

  test('stable startup allows a major/minor iteration', () async {
    final dio = manifestDio(
      (_) => manifest(versionName: iterationVersion()),
    );
    final service = AppUpdateService(
      dio: dio,
      stableManifestUrl: 'https://updates.example.org/stable.json',
    );
    final result =
        await service.checkForStartup(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, iterationVersion());
  });

  test('legacy single manifest offers patches on startup and manual checks',
      () async {
    final paths = <String>[];
    final service = AppUpdateService(
      dio: manifestDio((_) => manifest(), paths: paths),
      manifestUrl: 'https://updates.example.org/legacy.json',
    );
    expect(
        (await service.checkForStartup(currentVersionCode: AppVersion.code))
            .status,
        UpdateCheckStatus.available);
    expect(
        (await service.checkConfigured(currentVersionCode: AppVersion.code))
            .status,
        UpdateCheckStatus.available);
    expect(paths, [
      'https://updates.example.org/legacy.json',
      'https://updates.example.org/legacy.json',
    ]);
  });

  test('valid Gitee manifest succeeds without contacting GitHub', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        calls++;
        if (options.uri.host == 'api.github.com') {
          handler.reject(DioException.connectionError(
            requestOptions: options,
            reason: 'GitHub unreachable',
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: manifest(),
        ));
      }));
    final result = await AppUpdateService(
      dio: dio,
      manualManifestUrl: AppUpdateService.giteeManualManifestUrl,
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.available);
    expect(calls, 1);
  });

  test('HTML with HTTP 200 is an invalid manifest', () async {
    final result = await AppUpdateService(
      dio: manifestDio((_) => '<!doctype html><html>login</html>'),
      manualManifestUrl: 'https://updates.example.org/manual.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.invalidManifest);
  });

  test('non-Gitee configured manifest does not fall back to GitHub', () async {
    final hosts = <String>[];
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        hosts.add(options.uri.host);
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'api.github.com'
              ? [
                  {
                    'tag_name': 'v99.0.0',
                    'draft': false,
                    'prerelease': false,
                    'assets': []
                  }
                ]
              : {'versionCode': AppVersion.code + 1},
        ));
      }));
    final result = await AppUpdateService(
      dio: dio,
      manualManifestUrl: 'https://updates.example.org/manual.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.invalidManifest);
    expect(hosts, ['updates.example.org']);
  });

  test('Gitee manifest network failure falls back to GitHub release', () async {
    final hosts = <String>[];
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        hosts.add(options.uri.host);
        if (options.uri.host == 'raw.giteeusercontent.com') {
          handler.reject(DioException.connectionError(
            requestOptions: options,
            reason: 'Gitee unavailable',
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: [
            {
              'tag_name': 'v9.0.0',
              'draft': false,
              'prerelease': false,
              'body': 'GitHub fallback release',
              'assets': [
                {
                  'name': 'chaoxing-journal-9.0.0.apk',
                  'browser_download_url':
                      'https://github.com/arrry-07/chaoxing-journal/releases/download/v9.0.0/chaoxing-journal-9.0.0.apk',
                  'size': 1234,
                  'digest': 'sha256:${'b' * 64}',
                }
              ],
            }
          ],
        ));
      }));

    final result = await AppUpdateService(
      dio: dio,
      manualManifestUrl: AppUpdateService.giteeManualManifestUrl,
    ).checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, '9.0.0');
    expect(result.update!.sha256Hash, 'b' * 64);
    expect(result.update!.apkDownloadUrl, contains('github.com'));
    expect(hosts, ['raw.giteeusercontent.com', 'api.github.com']);
  });

  test('invalid Gitee JSON falls back to GitHub release', () async {
    final hosts = <String>[];
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        hosts.add(options.uri.host);
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'raw.giteeusercontent.com'
              ? '<!doctype html><html>blocked</html>'
              : [
                  {
                    'tag_name': 'v9.0.0',
                    'draft': false,
                    'prerelease': false,
                    'assets': [
                      {
                        'name': 'chaoxing-journal-9.0.0.apk',
                        'browser_download_url':
                            'https://github.com/arrry-07/chaoxing-journal/releases/download/v9.0.0/chaoxing-journal-9.0.0.apk',
                        'size': 1234,
                        'digest': 'sha256:${'b' * 64}',
                      }
                    ],
                  }
                ],
        ));
      }));

    final result = await AppUpdateService(
      dio: dio,
      manualManifestUrl: AppUpdateService.giteeManualManifestUrl,
    ).checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(hosts, ['raw.giteeusercontent.com', 'api.github.com']);
  });

  test('cancelled Gitee check does not fall back to GitHub', () async {
    final hosts = <String>[];
    final cancel = CancelToken()..cancel('cancelled');
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        hosts.add(options.uri.host);
        handler.reject(DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        ));
      }));

    final result = await AppUpdateService(
      dio: dio,
      manualManifestUrl: AppUpdateService.giteeManualManifestUrl,
    ).checkConfigured(currentVersionCode: AppVersion.code, cancelToken: cancel);

    expect(result.status, UpdateCheckStatus.cancelled);
    expect(hosts, isEmpty);
  });

  test('non-HTTPS manifest URL fails before making a request', () async {
    var calls = 0;
    final dio = manifestDio((_) {
      calls++;
      return manifest();
    });
    final result = await AppUpdateService(
      dio: dio,
      manualManifestUrl: 'http://updates.example.org/manual.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.invalidManifest);
    expect(calls, 0);
  });

  final malformed = <String, Map<String, dynamic>>{
    'wrong applicationId':
        manifest(applicationId: 'com.example.studyassistant'),
    'invalid versionName': manifest(versionName: '1.7'),
    'HTTP APK URL': manifest(apkUrl: 'http://download.example.org/app.apk'),
    'HTTP backup URL':
        manifest(backupApkUrl: 'http://backup.example.org/app.apk'),
    'string versionCode': manifest()
      ..['versionCode'] = '${AppVersion.code + 1}',
    'zero versionCode': manifest(versionCode: 0),
    'invalid SHA-256': manifest(sha256: 'not-a-sha256'),
    'zero size': manifest(size: 0),
    'string size': manifest()..['size'] = '1234',
    'missing size': manifest()..remove('size'),
  };
  for (final entry in malformed.entries) {
    test('${entry.key} is rejected', () async {
      final result = await AppUpdateService(
        dio: manifestDio((_) => entry.value),
        manualManifestUrl: 'https://updates.example.org/manual.json',
      ).checkConfigured(currentVersionCode: AppVersion.code);
      expect(result.status, UpdateCheckStatus.invalidManifest);
      expect(result.update, isNull);
    });
  }

  test('manifest larger than the APK download limit is rejected', () async {
    final result = await AppUpdateService(
      dio: manifestDio((_) => manifest(size: 1025)),
      maxDownloadBytes: 1024,
      manualManifestUrl: 'https://updates.example.org/manual.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.invalidManifest);
  });

  test('backup APK URL is retained under the same manifest metadata', () async {
    final result = await AppUpdateService(
      dio: manifestDio((_) => manifest(
            backupApkUrl: 'https://backup.example.org/app.apk',
          )),
      manualManifestUrl: 'https://updates.example.org/manual.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.backupApkUrls, [
      'https://backup.example.org/app.apk',
    ]);
    expect(result.update!.apkSize, 1234);
    expect(result.update!.sha256Hash, manifestHash);
  });

  test('older version with a higher versionCode is rejected', () async {
    final parts = AppVersion.name.split('.').map(int.parse).toList();
    final older = '${parts[0]}.${parts[1]}.${parts[2] - 1}';
    final result = await AppUpdateService(
      dio: manifestDio((_) => manifest(versionName: older)),
      manualManifestUrl: 'https://updates.example.org/manual.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.invalidManifest);
  });

  test('non-increasing versionCode is up to date, not offered', () async {
    final result = await AppUpdateService(
      dio: manifestDio((_) => manifest(versionCode: AppVersion.code)),
      manualManifestUrl: 'https://updates.example.org/manual.json',
    ).checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.upToDate);
    expect(result.update, isNull);
  });
}
