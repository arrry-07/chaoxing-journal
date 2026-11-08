import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/term_archives_screen.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';

import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'review_core_remediation_test.dart' as f;

class Notifications extends f.Notifications {
  @override
  Future<ReminderHealth> inspectHealth() async => const ReminderHealth(
      notifications: true,
      exact: false,
      assignmentChannel:
          ReminderChannelHealth(ReminderChannelStatus.enabled, importance: 4),
      summaryChannel:
          ReminderChannelHealth(ReminderChannelStatus.enabled, importance: 3),
      manualChannel:
          ReminderChannelHealth(ReminderChannelStatus.enabled, importance: 4),
      pending: 3,
      summaryPending: 0);
  @override
  Future<bool> showTestNotification() async => true;
  @override
  Future<void> rescheduleSummary(
      List assignments, PersonalWorkspace personal, DateTime? lastSync) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  Future<AssignmentStore> setup() async {
    SharedPreferences.setMockInitialValues({});
    final s = f.makeStore(f.Session(), notifications: Notifications());
    await s.restoreSession();
    await s.repository.mergeAndSave([f.sample('shared')]);
    await s.refreshAssignments();
    return s;
  }

  testWidgets(
      'create personal task and toggle without changing platform homework',
      (t) async {
    final s = await setup();
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light, home: ManualAgendaScreen(store: s)));
    await t.tap(find.text('添加个人安排'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, '标题'), '合成待办');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('保存个人安排'), 300,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('保存个人安排'));
    await t.pumpAndSettle();
    expect(s.notebook.entries.single.title, '合成待办');
    expect(find.byType(ManualEntryEditor), findsNothing);
    await t.tap(find.byType(Checkbox));
    await t.pumpAndSettle();
    expect(s.notebook.entries.single.done, isTrue);
    expect(s.assignments.single.status, 'pending');
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
  testWidgets(
      'save named snapshot leaves active data intact and opens read-only',
      (t) async {
    final s = await setup();
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light, home: TermArchivesScreen(store: s)));
    await t.tap(find.text('保存当前学期快照'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '合成秋季学期');
    await t.tap(find.text('保存快照'));
    await t.pumpAndSettle();
    expect(s.notebook.terms.single.rows.length, 1);
    expect(s.assignments.length, 1);
    await t.tap(find.text('合成秋季学期'));
    await t.pumpAndSettle();
    expect(find.textContaining('只读快照'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
  testWidgets('phase3 pages render on narrow large text screens', (t) async {
    final s = await setup();
    final e = ManualEntry(
        id: 'm',
        title: '合成考试 · 长标题与教学楼地点',
        kind: 'exam',
        at: DateTime.utc(2030),
        course: '合成课程',
        location: '实验楼 A-203',
        note: '请带好计算器',
        minutes: 90);
    await s.saveNotebook(
        (n) => StudyNotebook(entries: [
              e
            ], terms: [
              TermArchive.capture(
                  id: 't',
                  label: '合成秋季学期',
                  rows: s.assignments,
                  personal: s.personal,
                  entries: [e])
            ]),
        s.accountEpoch);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final width in [320.0, 393.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final page in ['agenda', 'editor', 'terms', 'detail']) {
          t.view.physicalSize = Size(width, 760);
          final boundary = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: StudyAssistantTheme.light,
                  builder: (c, child) => MediaQuery(
                      data: MediaQuery.of(c)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: switch (page) {
                    'agenda' => ManualAgendaScreen(store: s),
                    'editor' => ManualEntryEditor(store: s, entry: e),
                    'terms' => TermArchivesScreen(store: s),
                    _ => TermArchiveDetail(store: s, id: 't')
                  })));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$page/$width/$scale');
          if (const bool.fromEnvironment('CAPTURE_UI')) {
            await t.runAsync(() async {
              final picture = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
              final bytes =
                  (await picture.toByteData(format: ui.ImageByteFormat.png))!
                      .buffer
                      .asUint8List();
              final d = Directory(
                  '${Directory.current.resolveSymbolicLinksSync()}/../../artifacts/current/phase3/ui');
              await d.create(recursive: true);
              await File('${d.path}/$page-${width.toInt()}-$scale.png')
                  .writeAsBytes(bytes);
              picture.dispose();
            });
          }
        }
      }
    }
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
  testWidgets('editor opened for A cannot first save after switching to B',
      (t) async {
    final s = await setup();
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: ManualEntryEditor(
            store: s,
            entry: const ManualEntry(
                id: 'oldA', title: 'A private note', kind: 'todo'))));
    await t.pumpAndSettle();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('study_assistant/external_links'),
            (_) async => true);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('study_assistant/external_links'), null));
    await s.loginChaoxing(
        account: 'B', password: 'dummy', agreementAccepted: true);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('保存个人安排'), 300,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('保存个人安排'));
    await t.pumpAndSettle();
    expect(s.account, 'B');
    expect(s.notebook.entries, isEmpty);
    expect(find.textContaining('保存失败'), findsOneWidget);
    final feedback = t.widget<Semantics>(
        find.byKey(const ValueKey('manual-editor-feedback')));
    expect(feedback.properties.liveRegion, isTrue);
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
}
