import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_dialog.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_scope.dart';
import 'package:study_assistant_mobile/src/services/app_update_controller.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';
import 'package:study_assistant_mobile/src/services/external_link_service.dart';

const candidate = AppUpdateInfo(
    versionName: '99.0.0',
    versionCode: 990,
    applicationId: 'com.example.studyassistant.journal',
    releaseUrl:
        'https://github.com/arrry-07/chaoxing-journal/releases/tag/v99.0.0',
    apkName: 'sample.apk',
    apkDownloadUrl: 'https://example.org/sample.apk',
    releaseNotes: '更新说明',
    apkSize: 100);

class DownloadService extends AppUpdateService {
  DownloadService(this.file);
  final File file;
  int downloads = 0;
  Completer<File>? pending;
  CancelToken? token;
  void Function(int, int)? progress;
  @override
  Future<UpdateCheckResult> checkConfigured(
          {required int currentVersionCode, CancelToken? cancelToken}) async =>
      const UpdateCheckResult(UpdateCheckStatus.available, update: candidate);
  @override
  Future<File> downloadApk(AppUpdateInfo update,
      {String? targetDirectory,
      CancelToken? cancelToken,
      void Function(int, int)? onProgress}) {
    downloads++;
    token = cancelToken;
    progress = onProgress;
    pending = Completer<File>();
    return pending!.future;
  }
}

class Installer extends ExternalLinkService {
  bool compatible = true;
  bool permitted = true;
  int launches = 0;
  @override
  Future<Map<String, dynamic>> inspectApk(String filePath) async => {
        if (!File(filePath).existsSync()) ...{
          'compatible': false,
          'reason': '安装包不存在',
        } else ...{
          'compatible': compatible,
          'reason': '安装签名不一致，无法覆盖升级',
          'versionCode': 990,
          'versionName': '99.0.0',
          'applicationId': 'com.example.studyassistant.journal'
        }
      };
  @override
  Future<bool> installApk(String filePath) async {
    launches++;
    return permitted;
  }
}

void main() {
  late Directory dir;
  late DownloadService service;
  late Installer installer;
  late AppUpdateController task;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('update-background-');
    final file =
        await File('${dir.path}/sample.apk').writeAsBytes([80, 75, 3, 4]);
    service = DownloadService(file);
    installer = Installer();
    task = AppUpdateController(service: service, links: installer);
  });
  tearDown(() async {
    task.dispose();
    await dir.delete(recursive: true);
  });

  test('cancelling at stream completion leaves a retryable state', () async {
    await task.check();
    final downloading = task.download();
    task.cancelDownload();
    service.pending!.complete(service.file);
    await downloading;
    expect(task.phase, UpdatePhase.cancelled);
    expect(installer.launches, 0);
    expect(await service.file.exists(), isFalse);
  });

  test(
      'duplicate download taps join one task and signature failure blocks install',
      () async {
    await task.check();
    installer.compatible = false;
    final downloading = task.download();
    await task.download();
    expect(service.downloads, 1);
    service.pending!.complete(service.file);
    await downloading;
    expect(task.phase, UpdatePhase.failed);
    expect(task.message, contains('签名'));
    expect(await service.file.exists(), isFalse);
    await task.install();
    expect(installer.launches, 0);
  });

  test('permission retry reuses the verified download', () async {
    await task.check();
    final downloading = task.download();
    service.pending!.complete(service.file);
    await downloading;
    installer.permitted = false;
    await task.install();
    expect(task.phase, UpdatePhase.ready);
    expect(task.message, contains('允许安装'));
    installer.permitted = true;
    await task.install();
    expect(installer.launches, 2);
    expect(service.downloads, 1);
  });

  test('a removed cached APK can be downloaded again without restarting',
      () async {
    await task.check();
    var downloading = task.download();
    service.pending!.complete(service.file);
    await downloading;
    await service.file.delete();
    await task.install();
    expect(task.downloadedPath, isNull);
    expect(task.phase, UpdatePhase.failed);
    await service.file.writeAsBytes([80, 75, 3, 4]);
    downloading = task.download();
    service.pending!.complete(service.file);
    await downloading;
    expect(service.downloads, 2);
    expect(task.phase, UpdatePhase.ready);
  });

  for (final method in ['button', 'back', 'barrier']) {
    testWidgets('closing by $method prevents install during the exit animation',
        (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => UpdateDialog(controller: task)),
                      child: const Text('检查更新'))))));
      await t.tap(find.text('检查更新'));
      await t.pumpAndSettle();
      await t.tap(find.text('下载并安装'));
      await t.pump();
      if (method == 'button') {
        await t.tap(find.text('后台下载'));
      } else if (method == 'back') {
        await t.binding.handlePopRoute();
      } else {
        await t.tapAt(const Offset(5, 5));
      }
      service.pending!.complete(service.file);
      await t.pumpAndSettle();
      expect(installer.launches, 0);
      expect(task.phase, UpdatePhase.ready);
    });
  }

  testWidgets(
      'background download survives closing dialog and other app content remains usable',
      (t) async {
    var changedPage = false;
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
                  body: Column(children: [
                    Text(changedPage ? '日历内容' : '作业内容'),
                    TextButton(
                        onPressed: () => setState(() => changedPage = true),
                        child: const Text('切换到日历')),
                    TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => UpdateDialog(controller: task)),
                        child: const Text('检查更新')),
                  ]),
                  bottomNavigationBar: UpdateDownloadBanner(controller: task),
                ))));
    await t.tap(find.text('检查更新'));
    await t.pumpAndSettle();
    await t.tap(find.text('下载并安装'));
    await t.pump();
    service.progress!(50, 100);
    await t.pump();
    await t.tap(find.text('后台下载'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.token!.isCancelled, isFalse);
    await t.tap(find.text('切换到日历'));
    await t.pump();
    expect(find.text('日历内容'), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
    service.pending!.complete(service.file);
    await t.pumpAndSettle();
    expect(task.phase, UpdatePhase.ready);
    expect(installer.launches, 0);
    await t.tap(find.text('安装更新'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '安装更新'));
    await t.pumpAndSettle();
    expect(installer.launches, 1);
    expect(service.downloads, 1);
  });
}
