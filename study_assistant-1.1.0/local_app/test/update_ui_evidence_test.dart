import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_dialog.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';

class _ResultService extends AppUpdateService {
  _ResultService(this.result);
  final UpdateCheckResult result;
  @override
  Future<UpdateCheckResult> checkConfigured(
          {required int currentVersionCode, CancelToken? cancelToken}) async =>
      result;
}

void main() {
  testWidgets(
      'update dialog handles narrow screens, large text and long release notes',
      (t) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final output = Directory(
        '${Directory.current.resolveSymbolicLinksSync()}/../../artifacts/current/update-ui');
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await t.runAsync(() => output.create(recursive: true));
    }
    for (final width in [320.0, 393.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final status in [
          UpdateCheckStatus.upToDate,
          UpdateCheckStatus.networkError,
          UpdateCheckStatus.available
        ]) {
          await t.pumpWidget(const SizedBox.shrink());
          final boundary = GlobalKey();
          t.view.physicalSize = Size(width, 760);
          final service = _ResultService(UpdateCheckResult(status,
              update: status == UpdateCheckStatus.available
                  ? AppUpdateInfo(
                      versionName: '99.0.0',
                      versionCode: 990,
                      apkName: 'sample.apk',
                      apkDownloadUrl: 'https://example.org/sample.apk',
                      releaseUrl:
                          'https://github.com/arrry-07/chaoxing-journal/releases',
                      apkSize: 144189702,
                      releaseNotes: '下载完成后由 Android 确认安装。\n' * 35)
                  : null));
          await t.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: StudyAssistantTheme.light,
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: Builder(
                      builder: (context) => Scaffold(
                          body: TextButton(
                              onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (_) =>
                                      UpdateDialog(service: service)),
                              child: const Text('检查更新')))))));
          await t.tap(find.text('检查更新'));
          await t.pumpAndSettle();
          await t.pump();
          expect(t.takeException(), isNull, reason: '$width/$scale/$status');
          expect(find.text('关闭'), findsOneWidget);
          if (const bool.fromEnvironment('CAPTURE_UI')) {
            await t.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
              final bytes =
                  (await image.toByteData(format: ui.ImageByteFormat.png))!
                      .buffer
                      .asUint8List();
              await File(
                      '${output.path}/${status.name}-${width.toInt()}-$scale.png')
                  .writeAsBytes(bytes);
              image.dispose();
            });
          }
          await t.tap(find.text('关闭'));
          await t.pumpAndSettle();
        }
      }
    }
  });
}
