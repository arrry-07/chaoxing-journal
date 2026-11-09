// Explicit network acceptance; run separately from the offline test suite.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

void main() {
  final output = Platform.environment['XXT_ACCEPTANCE_OUTPUT'];
  if (output == null) {
    throw StateError('Set XXT_ACCEPTANCE_OUTPUT to a local evidence directory');
  }
  for (var i = 0; i < 3; i++) {
    final parallel = i == 1;
    test(
        'public APK full download ${i + 1} ${parallel ? 'parallel' : 'standard'}',
        () async {
      final root = await Directory(
              '$output/download-${i + 1}-${DateTime.now().millisecondsSinceEpoch}')
          .create(recursive: true);
      final watch = Stopwatch()..start();
      final events = <Map<String, Object?>>[];
      void event(Map<String, Object?> e) {
        events.add({'elapsedMs': watch.elapsedMilliseconds, ...e});
      }

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
        event({
          'phase': 'headers',
          'host': r.realUri.host,
          'status': r.statusCode,
          'redirectHosts': r.redirects.map((v) => v.location.host).toList()
        });
        h.next(r);
      }, onError: (e, h) {
        event({
          'phase': 'failure',
          'host': e.requestOptions.uri.host,
          'type': e.type.name,
          'underlyingType': e.error.runtimeType.toString(),
          if (e.error is HttpException)
            'httpMessage': (e.error as HttpException)
                .message
                .replaceAll(RegExp(r'https?://\S+'), '<URL>'),
          if (e.error is SocketException)
            'socketCode': (e.error as SocketException).osError?.errorCode,
          if (e.error is TlsException)
            'certificateFailure': (e.error as TlsException)
                .message
                .contains('CERTIFICATE_VERIFY_FAILED'),
        });
        h.next(e);
      }));
      final service = AppUpdateService(dio: dio, parallelDownloads: parallel);
      try {
        final update = await service.checkForUpdate(
            currentVersionName: '0.0.0', currentVersionCode: 0);
        expect(update, isNotNull);
        var first = true, lastReport = 0;
        final file = await service.downloadApk(update!,
            targetDirectory: root.path, onProgress: (received, total) {
          if (first ||
              received - lastReport >= 8 * 1024 * 1024 ||
              received == total) {
            event({
              'phase': first ? 'first-bytes' : 'body',
              'received': received,
              'total': total
            });
            first = false;
            lastReport = received;
          }
        });
        final verify = Stopwatch()..start();
        final digest = (await sha256.bind(file.openRead()).first).toString();
        expect(digest, update.sha256Hash);
        expect(await file.length(), update.apkSize);
        event({
          'phase': 'independent-verification',
          'sha256': digest,
          'bytes': await file.length(),
          'verificationMs': verify.elapsedMilliseconds,
          'version': update.versionName,
          'parallel': parallel
        });
        stdout.writeln(jsonEncode({
          'case': i + 1,
          'success': true,
          'parallel': parallel,
          'elapsedMs': watch.elapsedMilliseconds,
          'sha256': digest
        }));
      } catch (e) {
        event({'phase': 'case-failed', 'type': e.runtimeType.toString()});
        fail(
            'Real download acceptance failed; inspect redacted transport trace');
      } finally {
        dio.close(force: true);
        await File('${root.path}/transport.json')
            .writeAsString(jsonEncode(events));
      }
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
