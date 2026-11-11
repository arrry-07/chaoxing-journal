import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_version.dart';
import 'package:study_assistant_mobile/src/services/app_update_controller.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

Map<String, dynamic> release(String name,
        {bool draft = false, bool prerelease = false}) =>
    {
      'tag_name': 'v$name',
      'draft': draft,
      'prerelease': prerelease,
      'assets': [
        {
          'name': 'chaoxing-journal-$name.apk',
          'size': 123,
          'browser_download_url':
              '${AppUpdateService.releasesUrl}/download/v$name/chaoxing-journal-$name.apk',
          'digest': 'sha256:${'a' * 64}'
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual intent suppresses a concurrent iteration startup prompt',
      () async {
    final gate = Completer<void>();
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        final startup = o.uri.path.endsWith('/latest');
        if (startup) await gate.future;
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: startup ? release('1.7.0') : [release('1.7.0')]));
      }));
    final task = AppUpdateController(service: AppUpdateService(dio: dio));
    addTearDown(task.dispose);
    final startup = task.checkOnStartup();
    await Future<void>.delayed(Duration.zero);
    final manual = task.check();
    gate.complete();
    expect(await startup, false);
    await manual;
    expect(task.update?.versionName, '1.7.0');
  });

  test('manual click during startup waits then checks the patch list',
      () async {
    final gate = Completer<void>();
    final paths = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        paths.add(o.uri.path);
        final startup = o.uri.path.endsWith('/latest');
        if (startup) await gate.future;
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: startup ? release('1.6.7') : [release('1.6.73')]));
      }));
    final task = AppUpdateController(service: AppUpdateService(dio: dio));
    addTearDown(task.dispose);
    final startup = task.checkOnStartup();
    await Future<void>.delayed(Duration.zero);
    final manual = task.check();
    gate.complete();
    expect(await startup, false);
    await manual;
    expect(task.update?.versionName, '1.6.73');
    expect(paths, [
      '/repos/arrry-07/chaoxing-journal/releases/latest',
      '/repos/arrry-07/chaoxing-journal/releases'
    ]);
  });

  test('late startup check never replaces a manual candidate', () async {
    var calls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        expect(o.uri.path.endsWith('/latest'), false);
        h.resolve(Response(
            requestOptions: o, statusCode: 200, data: [release('1.6.73')]));
      }));
    final task = AppUpdateController(service: AppUpdateService(dio: dio));
    addTearDown(task.dispose);
    await task.check();
    expect(await task.checkOnStartup(), false);
    expect(task.update!.versionName, '1.6.73');
    expect(calls, 1);
  });

  test('startup reads only latest; manual discovers a non-latest patch',
      () async {
    final paths = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        paths.add(o.uri.path);
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: o.uri.path.endsWith('/latest')
                ? release('1.6.7')
                : [release('1.6.73'), release('1.6.7')]));
      }));
    final task = AppUpdateController(service: AppUpdateService(dio: dio));
    addTearDown(task.dispose);
    expect(await task.checkOnStartup(), false);
    expect(task.showBanner, false);
    expect(task.update, isNull);
    await task.check();
    expect(task.update!.versionName, '1.6.73');
    expect(paths, [
      '/repos/arrry-07/chaoxing-journal/releases/latest',
      '/repos/arrry-07/chaoxing-journal/releases'
    ]);
  });

  for (final row in [('1.6.999', false), ('1.7.0', true), ('2.0.0', true)]) {
    test('startup iteration gate for ${row.$1}', () async {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          expect(o.uri.path.endsWith('/latest'), true);
          h.resolve(Response(
              requestOptions: o, statusCode: 200, data: release(row.$1)));
        }));
      final task = AppUpdateController(service: AppUpdateService(dio: dio));
      addTearDown(task.dispose);
      expect(await task.checkOnStartup(), row.$2);
      expect(task.showBanner, false);
      if (!row.$2) expect(task.update, isNull);
    });
  }

  test('ignored iteration remains silent but manual check can offer it',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(
              requestOptions: o,
              statusCode: 200,
              data: o.uri.path.endsWith('/latest')
                  ? release('1.7.0')
                  : [release('1.7.0')]))));
    final service = AppUpdateService(dio: dio);
    final first = AppUpdateController(service: service);
    addTearDown(first.dispose);
    await first.check();
    expect(await first.ignoreCurrentVersion(), true);
    final second = AppUpdateController(service: service);
    addTearDown(second.dispose);
    expect(await second.checkOnStartup(), false);
    await second.check();
    expect(second.update!.versionName, '1.7.0');
  });

  test('manual reads all pages, excludes draft/prerelease and sorts by version',
      () async {
    final pages = <int>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        expect(o.queryParameters['per_page'], 100);
        final page = o.queryParameters['page'] as int;
        pages.add(page);
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: page == 1
                ? List.generate(100, (_) => release('1.0.0'))
                : [
                    release('99.0.0', draft: true),
                    release('98.0.0', prerelease: true),
                    release('1.6.73'),
                    release('1.7.0'),
                    release('1.6.73')
                  ]));
      }));
    final result = await AppUpdateService(dio: dio)
        .checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.update!.versionName, '1.7.0');
    expect(pages, [1, 2]);
  });

  for (final malformed in [true, false]) {
    test(
        'highest version ${malformed ? 'bad digest' : 'missing apk'} does not fall back',
        () async {
      final newest = release('1.7.0');
      if (malformed) {
        (newest['assets'] as List).single['digest'] = 'bad';
      } else {
        newest['assets'] = [];
      }
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (o, h) => h.resolve(Response(
                requestOptions: o,
                statusCode: 200,
                data: [release('1.6.73'), newest]))));
      final result = await AppUpdateService(dio: dio)
          .checkConfigured(currentVersionCode: AppVersion.code);
      expect(result.update, isNull);
      expect(
          result.status,
          malformed
              ? UpdateCheckStatus.invalidManifest
              : UpdateCheckStatus.packageUnavailable);
    });
  }

  test(
      'pagination failure reports failure instead of a candidate from page one',
      () async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(
              requestOptions: o,
              statusCode: o.queryParameters['page'] == 1 ? 200 : 503,
              data: List.generate(100, (_) => release('1.6.73'))))));
    final result = await AppUpdateService(dio: dio)
        .checkConfigured(currentVersionCode: AppVersion.code);
    expect(result.status, UpdateCheckStatus.networkError);
    expect(result.update, isNull);
  });
}
