import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_version.dart';
import 'package:study_assistant_mobile/src/services/app_update_controller.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

const giteeApkUrl =
    'https://gitee.com/arrry-07/chaoxing-journal-updates/releases/download/'
    'v9.0.0/chaoxing-journal-9.0.0.apk';
const githubApkUrl =
    'https://github.com/arrry-07/chaoxing-journal/releases/download/'
    'v9.0.0/chaoxing-journal-9.0.0.apk';

String nextPatchVersion() {
  final parts = AppVersion.name.split('.').map(int.parse).toList();
  return '${parts[0]}.${parts[1]}.${parts[2] + 1}';
}

Map<String, dynamic> manifest({
  required String versionName,
  required int versionCode,
  String apkUrl = giteeApkUrl,
  String sha256 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int size = 1234,
  String? backupApkUrl,
}) =>
    {
      'versionCode': versionCode,
      'versionName': versionName,
      'applicationId': AppUpdateService.applicationId,
      'apkUrl': apkUrl,
      'sha256': sha256,
      'size': size,
      if (backupApkUrl != null) 'backupApkUrl': backupApkUrl,
      'notes': 'Gitee notes',
    };

Map<String, dynamic> release({
  required String versionName,
  int? versionCode,
  String sha256 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int size = 1234,
  String notes = 'GitHub notes',
}) {
  final tag = versionCode == null ? versionName : '$versionName+$versionCode';
  return {
    'tag_name': 'v$tag',
    'html_url': '${AppUpdateService.releasesUrl}/tag/v$tag',
    'body': notes,
    'draft': false,
    'prerelease': false,
    'assets': [
      {
        'name': 'chaoxing-journal-$versionName.apk',
        'browser_download_url':
            '${AppUpdateService.repositoryUrl}/releases/download/'
                'v$tag/chaoxing-journal-$versionName.apk',
        'size': size,
        'digest': 'sha256:$sha256',
      }
    ],
  };
}

AppUpdateService dualService(Dio dio) => AppUpdateService.withGiteeDefaults(
      dio: dio,
      legacyManifestUrl: '',
      stableManifestUrl: '',
      manualManifestUrl: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Gitee latest does not hide a newer GitHub release', () async {
    final newer = nextPatchVersion();
    final hosts = <String>[];
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        hosts.add(options.uri.host);
        if (options.uri.host == 'raw.giteeusercontent.com') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: manifest(
              versionName: AppVersion.name,
              versionCode: AppVersion.code,
            ),
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: [release(versionName: newer)],
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, newer);
    expect(result.update!.apkDownloadUrl, contains('github.com'));
    expect(hosts, containsAll(['raw.giteeusercontent.com', 'api.github.com']));
  });

  test('parallel official checks start before either source responds',
      () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final hosts = <String>[];
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) async {
          hosts.add(options.uri.host);
          if (hosts.length == 2 && !started.isCompleted) started.complete();
          await gate.future;
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: options.uri.host == 'raw.giteeusercontent.com'
                ? manifest(
                    versionName: AppVersion.name,
                    versionCode: AppVersion.code,
                  )
                : [release(versionName: AppVersion.name)],
          ));
        },
      ));

    final checking =
        dualService(dio).checkConfigured(currentVersionCode: AppVersion.code);
    await started.future.timeout(const Duration(seconds: 1));
    expect(
      hosts,
      containsAll(['raw.giteeusercontent.com', 'api.github.com']),
    );
    gate.complete();
    expect((await checking).status, UpdateCheckStatus.upToDate);
  });

  test('GitHub outage keeps a valid Gitee update', () async {
    final newer = nextPatchVersion();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.uri.host == 'raw.giteeusercontent.com') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: manifest(
              versionName: newer,
              versionCode: AppVersion.code + 1,
            ),
          ));
          return;
        }
        handler.reject(DioException.connectionError(
          requestOptions: options,
          reason: 'GitHub unavailable',
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, newer);
    expect(result.update!.apkDownloadUrl, giteeApkUrl);
  });

  test('matching metadata merges Gitee primary with GitHub identity', () async {
    final newer = nextPatchVersion();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'raw.giteeusercontent.com'
              ? manifest(
                  versionName: newer,
                  versionCode: AppVersion.code + 1,
                  backupApkUrl: githubApkUrl.replaceAll('9.0.0', newer),
                  apkUrl: giteeApkUrl.replaceAll('9.0.0', newer),
                )
              : [release(versionName: newer)],
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, newer);
    expect(result.update!.versionCode, AppVersion.code + 1);
    expect(result.update!.apkDownloadUrl, contains('gitee.com'));
    expect(result.update!.backupApkUrls.first, contains('github.com'));
    expect(result.update!.releaseNotes, 'GitHub notes');
    expect(result.update!.releaseUrl, contains('/tag/v$newer'));
  });

  test('same-version digest conflict keeps the GitHub asset', () async {
    final newer = nextPatchVersion();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'raw.giteeusercontent.com'
              ? manifest(
                  versionName: newer,
                  versionCode: AppVersion.code + 1,
                  apkUrl: giteeApkUrl.replaceAll('9.0.0', newer),
                  sha256: 'b' * 64,
                )
              : [release(versionName: newer, sha256: 'a' * 64)],
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.apkDownloadUrl, contains('github.com'));
    expect(result.update!.apkDownloadUrl, isNot(contains('gitee.com')));
    expect(result.update!.sha256Hash, 'a' * 64);
  });

  test('same-version size conflict keeps the GitHub asset', () async {
    final newer = nextPatchVersion();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'raw.giteeusercontent.com'
              ? manifest(
                  versionName: newer,
                  versionCode: AppVersion.code + 1,
                  apkUrl: giteeApkUrl.replaceAll('9.0.0', newer),
                  size: 1235,
                )
              : [release(versionName: newer, size: 1234)],
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.apkDownloadUrl, contains('github.com'));
    expect(result.update!.apkDownloadUrl, isNot(contains('gitee.com')));
  });

  test('same-version versionCode conflict uses GitHub identity', () async {
    final newer = nextPatchVersion();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'raw.giteeusercontent.com'
              ? manifest(
                  versionName: newer,
                  versionCode: AppVersion.code + 2,
                  apkUrl: giteeApkUrl.replaceAll('9.0.0', newer),
                )
              : [
                  release(
                    versionName: newer,
                    versionCode: AppVersion.code + 1,
                  )
                ],
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionCode, AppVersion.code + 1);
  });

  test('startup uses the same dual-source selection', () async {
    final newer = nextPatchVersion();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'raw.giteeusercontent.com'
              ? manifest(
                  versionName: AppVersion.name,
                  versionCode: AppVersion.code,
                )
              : [release(versionName: newer)],
        ));
      }));

    final result = await dualService(dio)
        .checkForStartup(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, newer);
  });

  test('ignored dual-source version stays silent until a manual check',
      () async {
    final newer = nextPatchVersion();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'raw.giteeusercontent.com'
              ? manifest(
                  versionName: AppVersion.name,
                  versionCode: AppVersion.code,
                )
              : [release(versionName: newer)],
        ));
      }));
    final service = dualService(dio);
    final first = AppUpdateController(service: service);
    addTearDown(first.dispose);
    await first.check();
    expect(await first.ignoreCurrentVersion(), isTrue);

    final second = AppUpdateController(service: service);
    addTearDown(second.dispose);
    expect(await second.checkOnStartup(), isFalse);
    await second.check();
    expect(second.update!.versionName, newer);
  });

  test('ignore survives a later Gitee metadata sync for the same version',
      () async {
    final newer = nextPatchVersion();
    var giteeAvailable = false;
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.uri.host == 'raw.giteeusercontent.com') {
          if (!giteeAvailable) {
            handler.reject(DioException.connectionError(
              requestOptions: options,
              reason: 'Gitee index not updated yet',
            ));
            return;
          }
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: manifest(
              versionName: newer,
              versionCode: AppVersion.code + 1,
              apkUrl: giteeApkUrl.replaceAll('9.0.0', newer),
            ),
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: [release(versionName: newer)],
        ));
      }));
    final service = dualService(dio);
    final first = AppUpdateController(service: service);
    addTearDown(first.dispose);
    await first.check();
    expect(first.update!.versionCode, isNull);
    expect(await first.ignoreCurrentVersion(), isTrue);

    giteeAvailable = true;
    final second = AppUpdateController(service: service);
    addTearDown(second.dispose);
    expect(await second.checkOnStartup(), isFalse);
    await second.check();
    expect(second.update!.versionName, newer);
    expect(second.update!.versionCode, AppVersion.code + 1);
  });

  test('cancelled dual-source check makes no requests', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        calls++;
        handler.resolve(Response(requestOptions: options, statusCode: 200));
      }));
    final cancel = CancelToken()..cancel('cancelled');

    final result = await dualService(dio).checkConfigured(
      currentVersionCode: AppVersion.code,
      cancelToken: cancel,
    );

    expect(result.status, UpdateCheckStatus.cancelled);
    expect(calls, 0);
  });

  test('valid Gitee update survives GitHub rate limiting', () async {
    final newer = nextPatchVersion();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.uri.host == 'raw.giteeusercontent.com') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: manifest(
              versionName: newer,
              versionCode: AppVersion.code + 1,
            ),
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 429,
          data: {},
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, newer);
    expect(result.update!.apkDownloadUrl, giteeApkUrl);
  });

  test('a newer Gitee version wins over an older GitHub release', () async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.uri.host == 'raw.giteeusercontent.com'
              ? manifest(
                  versionName: '1.8.0',
                  versionCode: AppVersion.code + 5,
                  apkUrl: giteeApkUrl.replaceAll('9.0.0', '1.8.0'),
                )
              : [release(versionName: nextPatchVersion())],
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, '1.8.0');
    expect(result.update!.apkDownloadUrl, contains('gitee.com'));
  });

  test('invalid Gitee and rate-limited GitHub stay explicit errors', () async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.uri.host == 'raw.giteeusercontent.com') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: '<!doctype html><html>login</html>',
          ));
          return;
        }
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 429,
          data: {},
        ));
      }));

    final result = await dualService(dio)
        .checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.rateLimited);
    expect(result.update, isNull);
  });

  test('custom manifests stay single-source', () async {
    final hosts = <String>[];
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        hosts.add(options.uri.host);
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: manifest(
            versionName: AppVersion.name,
            versionCode: AppVersion.code,
          ),
        ));
      }));
    final service = AppUpdateService.withGiteeDefaults(
      dio: dio,
      manualManifestUrl: 'https://updates.example.org/manual.json',
    );

    final result =
        await service.checkConfigured(currentVersionCode: AppVersion.code);

    expect(result.status, UpdateCheckStatus.upToDate);
    expect(hosts, ['updates.example.org']);
  });
}
