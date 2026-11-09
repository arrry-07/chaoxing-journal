// Test-only entrypoint; never publish this APK as the normal application.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

final status = ValueNotifier<String>('Android transport acceptance starting');
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
      home: Scaffold(
          body: SafeArea(
              child: ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (c, value, _) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('TEST ENTRYPOINT ONLY\n\n$value')))))));
  final root = await Directory(
          '${(await getTemporaryDirectory()).path}/network-acceptance-${DateTime.now().millisecondsSinceEpoch}')
      .create();
  final results = <Map<String, Object?>>[];
  for (var i = 0; i < 3; i++) {
    final parallel = i == 1;
    final caseDir = await Directory('${root.path}/case-${i + 1}').create();
    final trace = <Map<String, Object?>>[];
    final watch = Stopwatch()..start();
    void event(Map<String, Object?> e) =>
        trace.add({'elapsedMs': watch.elapsedMilliseconds, ...e});
    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        validateStatus: (s) => s != null && s < 500,
        headers: {
          'User-Agent': 'StudyAssistant/1.0',
          'Accept': 'application/vnd.github+json'
        }));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      event({
        'phase': 'request',
        'host': o.uri.host,
        'range': o.headers['Range'],
        'connectSeconds': o.connectTimeout?.inSeconds,
        'idleSeconds': o.receiveTimeout?.inSeconds
      });
      h.next(o);
    }, onResponse: (r, h) {
      event(
          {'phase': 'headers', 'host': r.realUri.host, 'status': r.statusCode});
      h.next(r);
    }, onError: (e, h) {
      event({
        'phase': 'error',
        'type': e.type.name,
        'underlyingType': e.error.runtimeType.toString(),
        if (e.error is HttpException)
          'httpMessage': (e.error as HttpException)
              .message
              .replaceAll(RegExp(r'https?://\S+'), '<URL>')
      });
      h.next(e);
    }));
    final service = AppUpdateService(dio: dio, parallelDownloads: parallel);
    try {
      status.value = 'Case ${i + 1}/3: ${parallel ? 'parallel' : 'standard'}';
      final update = await service.checkForUpdate(
          currentVersionName: '0.0.0', currentVersionCode: 0);
      if (update == null) {
        throw StateError('Public APK metadata unavailable');
      }
      var last = 0;
      final file = await service.downloadApk(update,
          targetDirectory: caseDir.path, onProgress: (n, total) {
        if (n - last >= 8 * 1024 * 1024 || n == total) {
          event({'phase': 'body', 'received': n, 'total': total});
          last = n;
        }
        status.value = 'Case ${i + 1}/3: $n / $total bytes';
      });
      final digest = (await sha256.bind(file.openRead()).first).toString();
      if (digest != update.sha256Hash ||
          await file.length() != update.apkSize) {
        throw StateError('Independent verification failed');
      }
      results.add({
        'case': i + 1,
        'parallel': parallel,
        'success': true,
        'platform': Platform.operatingSystem,
        'bytes': await file.length(),
        'sha256': digest,
        'elapsedMs': watch.elapsedMilliseconds
      });
    } catch (e) {
      results.add({
        'case': i + 1,
        'parallel': parallel,
        'success': false,
        'platform': Platform.operatingSystem,
        'errorType': e.runtimeType.toString(),
        'elapsedMs': watch.elapsedMilliseconds
      });
    } finally {
      dio.close(force: true);
      await File('${caseDir.path}/transport.json')
          .writeAsString(jsonEncode(trace));
      await File('${root.path}/results.json')
          .writeAsString(jsonEncode(results));
      stdout.writeln('ANDROID_DOWNLOAD_ACCEPTANCE ${jsonEncode(results.last)}');
    }
  }
  final ok = results.every((r) => r['success'] == true);
  status.value =
      '${ok ? 'PASS' : 'FAIL'}\n${jsonEncode(results)}\nEvidence: ${root.path}';
  stdout.writeln('ANDROID_DOWNLOAD_ACCEPTANCE_COMPLETE ${jsonEncode({
        'success': ok,
        'directory': root.path
      })}');
}
