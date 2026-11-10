import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_dialog.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_scope.dart';
import 'package:study_assistant_mobile/src/services/app_update_controller.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

const candidate = AppUpdateInfo(
    versionName: '1.6.7',
    versionCode: 52,
    releaseUrl: 'https://example.org/release',
    apkName: 'sample.apk',
    apkDownloadUrl: 'https://example.org/sample.apk',
    apkSize: 57297264,
    releaseNotes: '首页筛选会记住上次选择，切换页面后无需重新设置。\n更新提示和下载操作布局更清晰。\n保留既有课程、作业与提醒功能。');

void main() {
  testWidgets(
      'state actions remain reachable and aligned at narrow widths and large text',
      (t) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final output = Directory('../../artifacts/2026-11-10/home-update-ui');
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await t.runAsync(() => output.create(recursive: true));
    }
    for (final width in [320.0, 360.0, 393.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final phase in [
          UpdatePhase.available,
          UpdatePhase.downloading,
          UpdatePhase.verifying,
          UpdatePhase.ready,
          UpdatePhase.failed,
          UpdatePhase.cancelled,
          UpdatePhase.installing
        ]) {
          final task = AppUpdateController()
            ..result = const UpdateCheckResult(UpdateCheckStatus.available,
                update: candidate)
            ..phase = phase
            ..message = switch (phase) {
              UpdatePhase.downloading => '正在下载安装包…',
              UpdatePhase.failed => '网络连接中断，请检查网络后重试',
              UpdatePhase.ready => '安装包已校验完成，可继续安装。',
              UpdatePhase.cancelled => '已取消下载，可重新开始',
              _ => '下载完成后由 Android 确认安装',
            }
            ..receivedBytes = 26000000
            ..totalBytes = 57297264
            ..bytesPerSecond = 1400000;
          if (phase == UpdatePhase.ready) {
            task.downloadedPath = '/test-only/sample.apk';
          }
          final boundary = GlobalKey();
          t.view.physicalSize = Size(width, 760);
          await t.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: StudyAssistantTheme.light,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(body: UpdateDialog(controller: task)),
              )));
          await t.pump(const Duration(milliseconds: 100));
          expect(t.takeException(), isNull, reason: '$width/$scale/$phase');
          final primary = switch (phase) {
            UpdatePhase.available => '下载并安装',
            UpdatePhase.downloading => '后台下载',
            UpdatePhase.verifying => '收起，继续使用',
            UpdatePhase.ready => '安装更新',
            UpdatePhase.failed || UpdatePhase.cancelled => '重新下载',
            _ => null,
          };
          if (primary != null) {
            final button = find.widgetWithText(FilledButton, primary);
            await t.ensureVisible(button);
            await t.pump();
            final rect = t.getRect(button);
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.width, closeTo(width - 88, 1));
            expect(rect.left, greaterThanOrEqualTo(20));
            expect(rect.right, lessThanOrEqualTo(width - 20));
          }
          if (phase == UpdatePhase.downloading) {
            expect(find.text('取消下载'), findsOneWidget);
          }
          if (phase == UpdatePhase.verifying) {
            expect(find.text('取消下载'), findsNothing);
          }
          if (const bool.fromEnvironment('CAPTURE_UI')) {
            if (width == 393 &&
                scale == 1 &&
                [
                  UpdatePhase.available,
                  UpdatePhase.downloading,
                  UpdatePhase.failed,
                  UpdatePhase.ready
                ].contains(phase)) {
              await t.runAsync(() async {
                final image = await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final data =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File('${output.path}/${phase.name}.png')
                    .writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
          await t.pumpWidget(const SizedBox.shrink());
          task.dispose();
        }
      }
    }
  });

  testWidgets('short landscape with long content keeps actions accessible',
      (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(360, 420);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final task = AppUpdateController()
      ..phase = UpdatePhase.available
      ..result = UpdateCheckResult(UpdateCheckStatus.available,
          update: AppUpdateInfo(
              versionName: '2026.11.10-preview.1234567890',
              releaseUrl: '',
              apkName: 'x.apk',
              apkDownloadUrl: 'https://example.org/x.apk',
              releaseNotes: '很长的更新内容，需要滚动查看。' * 100));
    addTearDown(task.dispose);
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(body: UpdateDialog(controller: task))));
    await t.pump();
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('下载并安装'));
    await t.pump();
    expect(find.text('下载并安装').hitTestable(), findsOneWidget);
    await t.ensureVisible(find.text('忽略此版本'));
    await t.pump();
    expect(find.text('忽略此版本').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'unknown-length progress and banner use a readable separate action row',
      (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 640);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final task = AppUpdateController()
      ..phase = UpdatePhase.downloading
      ..result = const UpdateCheckResult(UpdateCheckStatus.available,
          update: candidate)
      ..message = '正在下载安装包，请稍候…'
      ..totalBytes = -1;
    addTearDown(task.dispose);
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: Column(children: [UpdateDownloadBanner(controller: task)]))));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('查看进度'), findsOneWidget);
    expect(t.getRect(find.text('查看进度')).top,
        greaterThan(t.getRect(find.text(task.message)).bottom));
    expect(
        t
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
