import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

Map<String, dynamic> release() => {
      'tag_name': 'v99.0.0',
      'html_url': '${AppUpdateService.releasesUrl}/tag/v99.0.0',
      'body': '更新说明',
      'draft': false,
      'prerelease': false,
      'assets': [
        {
          'name': 'chaoxing-journal-99.0.0.apk',
          'browser_download_url':
              '${AppUpdateService.repositoryUrl}/releases/download/v99.0.0/chaoxing-journal-99.0.0.apk',
          'size': 123,
          'digest': 'sha256:${'a' * 64}',
        }
      ],
    };

AppUpdateService serviceFor(dynamic body,
    {int status = 200, Map<String, List<String>>? headers}) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      expect(o.uri.host, 'api.github.com');
      expect(o.uri.path, '/repos/arrry-07/chaoxing-journal/releases');
      h.resolve(Response(
          requestOptions: o,
          statusCode: status,
          data: status == 200 ? [body] : body,
          headers: Headers.fromMap(headers ?? {})));
    }));
  return AppUpdateService(dio: dio);
}

void main() {
  test('default channel reads the public release and keeps its digest',
      () async {
    final result =
        await serviceFor(release()).checkConfigured(currentVersionCode: 37);
    expect(result.status, UpdateCheckStatus.available);
    expect(result.update!.versionName, '99.0.0');
    expect(result.update!.sha256Hash, 'a' * 64);
    expect(result.update!.apkSize, 123);
  });

  test('an older published version reports latest instead of unconfigured',
      () async {
    final data = release()..['tag_name'] = 'v1.0.0';
    final result =
        await serviceFor(data).checkConfigured(currentVersionCode: 37);
    expect(result.status, UpdateCheckStatus.upToDate);
  });

  for (final row in [
    (401, 'authRequired'),
    (404, 'noRelease'),
    (429, 'rateLimited'),
    (500, 'networkError')
  ]) {
    test('GitHub ${row.$1} is distinct from latest', () async {
      final result = await serviceFor({}, status: row.$1)
          .checkConfigured(currentVersionCode: 37);
      expect(result.status.name, row.$2);
    });
  }

  test('GitHub API rate limiting is not an authorization prompt', () async {
    final result = await serviceFor({},
        status: 403,
        headers: {
          'x-ratelimit-remaining': ['0']
        }).checkConfigured(currentVersionCode: 37);
    expect(result.status.name, 'rateLimited');
  });

  for (final kind in [
    'bad tag',
    'draft',
    'prerelease',
    'missing digest',
    'http'
  ]) {
    test('rejects $kind before offering an installer', () async {
      final data = release();
      final asset = (data['assets'] as List).single as Map;
      switch (kind) {
        case 'bad tag':
          data['tag_name'] = 'not-a-version';
        case 'draft':
          data['draft'] = true;
        case 'prerelease':
          data['prerelease'] = true;
        case 'missing digest':
          asset.remove('digest');
        case 'http':
          asset['browser_download_url'] = 'http://example.org/app.apk';
      }
      final result =
          await serviceFor(data).checkConfigured(currentVersionCode: 37);
      expect(
          result.status,
          kind == 'draft' || kind == 'prerelease'
              ? UpdateCheckStatus.noRelease
              : UpdateCheckStatus.invalidManifest);
      expect(result.update, isNull);
    });
  }

  test('a newer release without an APK is not latest', () async {
    final data = release()..['assets'] = [];
    final result =
        await serviceFor(data).checkConfigured(currentVersionCode: 37);
    expect(result.status.name, 'packageUnavailable');
  });
}
