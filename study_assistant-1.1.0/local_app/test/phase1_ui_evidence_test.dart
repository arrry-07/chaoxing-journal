import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/backup_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_changes_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'review_core_remediation_test.dart' as f;

void main() {
  testWidgets('backup and changes remain readable on narrow large text screens',
      (t) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    SharedPreferences.setMockInitialValues({});
    final store = f.makeStore(f.Session());
    await store.restoreSession();
    store.changes = [
      AssignmentChange(
          assignmentId: 'cx:work:1:2:3',
          title: '合成实验报告',
          courseName: '合成课程',
          kind: AssignmentChangeKind.deadline,
          at: DateTime.utc(2026, 11, 6),
          before: '2026-11-07T08:00:00Z',
          after: '2026-11-08T08:00:00Z')
    ];
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final (width, scale, page) in [
      for (final width in [320.0, 393.0])
        for (final scale in [1.0, 2.0])
          for (final page in ['backup', 'changes']) (width, scale, page)
    ]) {
      t.view.physicalSize = Size(width, 760);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              theme: StudyAssistantTheme.light,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: page == 'backup'
                      ? BackupScreen(store: store)
                      : AssignmentChangesScreen(store: store)))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$page/$width/$scale');
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.png))!
                  .buffer
                  .asUint8List();
          final d = Directory(
              '${Directory.current.resolveSymbolicLinksSync()}/../../artifacts/current/phase1/ui');
          await d.create(recursive: true);
          await File('${d.path}/$page-${width.toInt()}-$scale.png')
              .writeAsBytes(bytes);
          image.dispose();
        });
      }
    }
    await t.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
