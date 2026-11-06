import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/daily_plan_screen.dart';
import 'package:study_assistant_mobile/src/features/personal_work_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_health_screen.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'review_core_remediation_test.dart' as f;

class Notifications extends f.Notifications {
  @override
  Future<ReminderHealth> inspectHealth() async => const ReminderHealth(
      notifications: true,
      exact: false,
      channelEnabled: true,
      pending: 3,
      summaryPending: 0);
  @override
  Future<bool> showTestNotification() async => true;
  @override
  Future<void> rescheduleSummary(
      List assignments, PersonalWorkspace personal, DateTime? lastSync) async {}
}

void main() {
  Future<AssignmentStore> setup() async {
    SharedPreferences.setMockInitialValues({});
    final s = f.makeStore(f.Session(), notifications: Notifications());
    await s.restoreSession();
    await s.repository.mergeAndSave([f.sample('shared')]);
    await s.refreshAssignments();
    return s;
  }

  testWidgets('personal save returns once through the refreshed shell router',
      (t) async {
    final s = await setup();
    final router =
        GoRouter(refreshListenable: s, initialLocation: '/home', routes: [
      ShellRoute(
          builder: (_, __, child) => AppShell(assignmentStore: s, child: child),
          routes: [
            GoRoute(
                path: '/home',
                builder: (c, _) => Scaffold(
                    body: TextButton(
                        onPressed: () => c.push('/personal'),
                        child: const Text('编辑个人记录')))),
            GoRoute(
                path: '/personal',
                builder: (_, __) => PersonalWorkScreen(
                    store: s, assignmentId: 'cx:work:1:2:shared')),
          ])
    ]);
    await t.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light, routerConfig: router));
    await t.pumpAndSettle();
    await t.tap(find.text('编辑个人记录'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'shell note');
    await t.scrollUntilVisible(find.text('保存个人记录'), 250,
        scrollable: find.byType(Scrollable).last);
    await t.pumpAndSettle();
    await t.tap(find.text('保存个人记录'));
    await t.pumpAndSettle();
    expect(s.personal.work.values.single.note, 'shell note');
    expect(find.byType(PersonalWorkScreen), findsNothing);
    expect(find.text('编辑个人记录'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    router.dispose();
    s.dispose();
  });

  testWidgets(
      'plan selection and personal completion stay separate from submission',
      (t) async {
    final s = await setup();
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light, home: DailyPlanScreen(store: s)));
    await t.tap(find.text('添加作业到计划'));
    await t.pumpAndSettle();
    await t.tap(find.text('shared'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '75');
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(s.personal.plans.single.minutes, 75);
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    expect(s.personal.plans.single.done, isTrue);
    expect(s.findAssignment('cx:work:1:2:shared')!.status, 'pending');
    expect(find.textContaining('平台：待提交'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
  testWidgets('personal note and checklist save without changing server status',
      (t) async {
    final s = await setup();
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Builder(
            builder: (c) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        c,
                        MaterialPageRoute<void>(
                            builder: (_) => PersonalWorkScreen(
                                store: s, assignmentId: 'cx:work:1:2:shared'))),
                    child: const Text('编辑'))))));
    await t.tap(find.text('编辑'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '样例备注');
    await t.tap(find.text('添加清单项'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '检查附件');
    await t.tap(find.text('添加'));
    await t.pumpAndSettle();
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('保存个人记录'), 250,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('保存个人记录'));
    await t.pumpAndSettle();
    final value = s.personal.work['cx:work:1:2:shared']!;
    expect(value.note, '样例备注');
    expect(value.steps.single.done, isTrue);
    expect(s.findAssignment('cx:work:1:2:shared')!.status, 'pending');
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
  testWidgets('phase2 pages render on narrow and large text screens',
      (t) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final s = await setup();
    await s.savePersonal(
        (w) => w.withWork(
            'cx:work:1:2:shared',
            const PersonalWork(note: '合成备注：先整理思路，再检查附件', steps: [
              PersonalStep('核对实验要求'),
              PersonalStep('整理报告截图', done: true)
            ])),
        s.accountEpoch);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final (width, scale, page) in [
      for (final w in [320.0, 393.0])
        for (final z in [1.0, 2.0])
          for (final p in ['plan', 'personal', 'health']) (w, z, p)
    ]) {
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
                'plan' => DailyPlanScreen(store: s),
                'personal' => PersonalWorkScreen(
                    store: s, assignmentId: 'cx:work:1:2:shared'),
                _ => ReminderHealthScreen(store: s)
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
              '${Directory.current.resolveSymbolicLinksSync()}/../../artifacts/current/phase2/ui');
          await d.create(recursive: true);
          await File('${d.path}/$page-${width.toInt()}-$scale.png')
              .writeAsBytes(bytes);
          picture.dispose();
        });
      }
    }
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
}
