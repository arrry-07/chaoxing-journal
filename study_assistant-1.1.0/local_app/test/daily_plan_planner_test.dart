import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/daily_plan_screen.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';

import 'review_core_remediation_test.dart' as f;

Future<AssignmentStore> _setup(f.Session session,
    {f.Notifications? notifications}) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = notifications == null
      ? f.makeStore(session)
      : AssignmentStore(
          sessionStore: session,
          notificationService: notifications,
          widgetSnapshotService: f.WidgetService());
  await store.restoreSession();
  await store.repository.mergeAndSave([f.sample('shared')]);
  await store.restoreSession();
  return store;
}

class _FailingSaveStore extends AssignmentStore {
  _FailingSaveStore()
      : super(
          sessionStore: f.Session(),
          notificationService: f.Notifications(),
          widgetSnapshotService: f.WidgetService(),
        );

  @override
  Future<bool> savePersonal(
          PersonalWorkspace Function(PersonalWorkspace) update,
          int expectedEpoch) async =>
      false;
}

Future<AssignmentStore> _setupFailingSave() async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = _FailingSaveStore();
  await store.restoreSession();
  await store.repository.mergeAndSave([f.sample('shared')]);
  await store.restoreSession();
  return store;
}

Future<void> _scrollPlannerTo(WidgetTester tester, Finder finder) async {
  final plannerList = find.byType(ListView).last;
  final plannerScrollable = find
      .descendant(
        of: plannerList,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    finder,
    180,
    scrollable: plannerScrollable,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bottom action guides selection and generates before saving',
      (tester) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('CAPTURE_UI')) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final out =
            Directory('${Directory.systemTemp.path}/learning-assistant-visual');
        await out.create(recursive: true);
        await File('${out.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: StudyAssistantTheme.light,
            home: DailyPlanScreen(store: store))));
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('planning-save'));
    await capture('generate');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('请先勾选要规划的作业，再填写预计耗时。'), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('planning-estimate-cx:work:1:2:shared')),
        '25');
    await tester.tap(button);
    await tester.pumpAndSettle();
    await capture('save');
    expect(find.text('加入当天计划'), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(store.personal.plans.single.minutes, 25);
  });

  Future<void> openPlanner(WidgetTester tester, AssignmentStore store) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('planning-budget')), '60');
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('planning-estimate-cx:work:1:2:shared')),
        '25');
  }

  testWidgets('planner explains three sections with a fixed example',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    expect(find.text('安排学习时间'), findsOneWidget);
    expect(
      find.text('选作业、填预计耗时，根据可用时间生成安排。'),
      findsOneWidget,
    );
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();

    expect(find.text('选择作业'), findsOneWidget);
    await _scrollPlannerTo(
      tester,
      find.byKey(const ValueKey('planning-budget')),
    );
    expect(find.text('填写可用时间与耗时'), findsOneWidget);
    final budget = tester.widget<TextField>(
      find.byKey(const ValueKey('planning-budget')),
    );
    expect(budget.decoration?.labelText, '当天可用时间（分钟）');
    expect(
      find.text('示例：今天有 60 分钟，两份作业预计各 30 分钟，可生成安排后再确认。'),
      findsOneWidget,
    );

    await _scrollPlannerTo(
      tester,
      find.byKey(const ValueKey('planning-generate')),
    );
    expect(find.text('查看安排'), findsOneWidget);
    expect(find.text('生成安排'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner remains usable at 320dp with double text',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: DailyPlanScreen(store: store),
    ));
    await tester.scrollUntilVisible(
      find.text('安排学习时间'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();

    await _scrollPlannerTo(
      tester,
      find.text('填写可用时间与耗时'),
    );
    expect(find.text('填写可用时间与耗时'), findsOneWidget);
    await _scrollPlannerTo(
      tester,
      find.byKey(const ValueKey('planning-generate')),
    );
    expect(find.text('查看安排'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plannerOperableAt320x640WithKeyboardAndDoubleText',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
          viewInsets: const EdgeInsets.only(bottom: 300),
        ),
        child: child!,
      ),
      home: DailyPlanScreen(store: store),
    ));
    await tester.scrollUntilVisible(
      find.text('安排学习时间'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();

    await _scrollPlannerTo(
      tester,
      find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')),
    );
    await tester.tap(
      find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')),
    );
    await tester.pumpAndSettle();
    await _scrollPlannerTo(
      tester,
      find.byKey(const ValueKey('planning-budget')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('planning-budget')),
      '60',
    );
    await _scrollPlannerTo(
      tester,
      find.byKey(const ValueKey('planning-generate')),
    );
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();

    expect(find.text('查看安排'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner validates available time and estimated duration',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    await openPlanner(tester, store);
    final action = find.byKey(const ValueKey('planning-save'));

    await tester.enterText(
      find.byKey(const ValueKey('planning-budget')),
      '0',
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('当天可用时间应为1至1440分钟'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('planning-budget')),
      '60',
    );
    await tester.enterText(
      find.byKey(const ValueKey('planning-estimate-cx:work:1:2:shared')),
      '0',
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      find.text('预计耗时应为1至1440分钟；未填写的作业不会被自动安排'),
      findsOneWidget,
    );
    expect(store.personal.plans, isEmpty);
  });

  testWidgets('planner shows insufficient available time as manual work',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    await openPlanner(tester, store);
    await tester.enterText(
      find.byKey(const ValueKey('planning-budget')),
      '20',
    );
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('预计耗时超过当天剩余可用时间'),
      findsWidgets,
    );
    expect(find.text('重新生成安排'), findsWidgets);
    expect(store.personal.plans, isEmpty);
  });

  testWidgets('planner displays and preserves existing same-day work',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    final day = PersonalWorkspace.dayKey(DateTime.now());
    await store.savePersonal(
      (workspace) => workspace.withPlans([
        DailyPlanItem('existing', day, 20),
      ]),
      store.accountEpoch,
    );
    await openPlanner(tester, store);
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();

    await _scrollPlannerTo(
      tester,
      find.text('已有未完成计划占用 20 分钟'),
    );
    expect(find.text('预计剩余 15 分钟'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();

    expect(store.personal.plans.length, 2);
    expect(
      store.personal.plans.map((plan) => plan.assignmentId),
      containsAll(['existing', 'cx:work:1:2:shared']),
    );
  });

  Future<void> failDeadlineRead(AssignmentStore store) async {
    final original = store.findAssignment('cx:work:1:2:shared')!;
    await store.repository.mergeAndSave([
      original.copyWith(
          clearDeadlineAt: true,
          deadlineTrusted: false,
          deadlineReadFailed: true,
          lastSyncedAt: DateTime.now())
    ], completeSync: false);
    await store.refreshAssignments();
    expect(store.findAssignment(original.id)!.deadlineAt, original.deadlineAt);
    expect(store.findAssignment(original.id)!.deadlineReadFailed, isTrue);
  }

  testWidgets('planner shows a confirmed deadline in Beijing time',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    await store.repository.mergeAndSave([
      f.sample('shared').copyWith(deadlineAt: DateTime.utc(2030, 11, 6, 16, 30))
    ]);
    await store.refreshAssignments();
    await openPlanner(tester, store);
    expect(find.textContaining('2030年11月7日 00:30'), findsOneWidget);
    expect(find.textContaining('未设置截止时间'), findsNothing);
  });

  testWidgets('regenerating uses a newly failed deadline read', (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    await openPlanner(tester, store);
    await failDeadlineRead(store);
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();
    expect(find.text('自动纳入'), findsNothing);
    expect(find.textContaining('截止时间读取失败'), findsWidgets);
    expect(store.personal.plans, isEmpty);
  });

  testWidgets('planner preserves explicit no-deadline semantics',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    await store.repository.mergeAndSave([
      f.sample('shared').copyWith(clearDeadlineAt: true, deadlineTrusted: true)
    ]);
    // A newly fetched, explicit no-deadline item must actually clear the model.
    store.replaceAssignmentsForTest([
      f.sample('shared').copyWith(clearDeadlineAt: true, deadlineTrusted: true)
    ]);
    await openPlanner(tester, store);
    expect(find.textContaining('未设置截止时间'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();
    expect(find.text('自动纳入'), findsNothing);
    expect(store.personal.plans, isEmpty);
  });

  testWidgets(
      'unrelated refresh still permits save and repeated taps do not duplicate',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    await openPlanner(tester, store);
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();
    await store.repository.mergeAndSave(
        [f.sample('shared').copyWith(lastSyncedAt: DateTime.now())]);
    await store.refreshAssignments();
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();
    expect(store.personal.plans.length, 1);
    expect(store.personal.plans.single.minutes, 25);
  });

  for (final logout in [false, true]) {
    testWidgets(
        'queued planner write rejects ${logout ? 'logout' : 'changed status'} before commit',
        (tester) async {
      final n = f.Notifications();
      final store = await _setup(f.Session(), notifications: n);
      addTearDown(store.dispose);
      await openPlanner(tester, store);
      await tester.tap(find.byKey(const ValueKey('planning-generate')));
      await tester.pumpAndSettle();
      n.gate = Completer<void>();
      final gate = n.gate!;
      n.started = Completer<void>();
      final earlier = store.savePersonal((w) => w, store.accountEpoch);
      await tester.pump();
      expect(n.started!.isCompleted, true);
      await tester.tap(find.byKey(const ValueKey('planning-save')));
      await tester.pump();
      Future<void>? leaving;
      if (logout) {
        leaving =
            store.logout(); // epoch changes immediately, before queued work
      } else {
        store.replaceAssignmentsForTest(
            [f.sample('shared', status: 'submitted')]);
      }
      gate.complete();
      await tester.pumpAndSettle();
      await earlier;
      if (leaving != null) await leaving;
      expect(store.personal.plans, isEmpty);
      expect(
        find.textContaining(
          logout ? '加入当天计划失败' : '重新生成安排',
        ),
        findsWidgets,
      );
    });
  }

  testWidgets('confirmation rejects a newly failed deadline read',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    await openPlanner(tester, store);
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();
    await failDeadlineRead(store);
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();
    expect(store.personal.plans, isEmpty);
    expect(find.textContaining('重新生成安排'), findsWidgets);
  });

  testWidgets('confirmation rechecks budget consumed by new same-day plans',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    await openPlanner(tester, store);
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();
    final day = PersonalWorkspace.dayKey(DateTime.now());
    await store.savePersonal(
        (w) => w.withPlans([DailyPlanItem('another-task', day, 50)]),
        store.accountEpoch);
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();
    expect(store.personal.plans.map((p) => p.assignmentId), ['another-task']);
    expect(find.textContaining('重新生成安排'), findsWidgets);
  });

  testWidgets('rule planner previews and saves only explicitly confirmed work',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();

    expect(find.text('安排学习时间'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('planning-budget')), '60');
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('planning-estimate-cx:work:1:2:shared')),
        '25');
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();

    await _scrollPlannerTo(
      tester,
      find.byKey(
        const ValueKey('planning-suggested-cx:work:1:2:shared'),
      ),
    );
    expect(find.text('自动纳入'), findsOneWidget);
    expect(find.byKey(const ValueKey('planning-suggested-cx:work:1:2:shared')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();

    expect(store.personal.plans.single.assignmentId, 'cx:work:1:2:shared');
    expect(store.personal.plans.single.minutes, 25);
    expect(find.text('已加入当天计划'), findsOneWidget);
  });

  testWidgets('planner never guesses a missing estimate', (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();

    expect(find.textContaining('需要填写预计耗时'), findsWidgets);
    final save = tester
        .widget<FilledButton>(find.byKey(const ValueKey('planning-save')));
    expect(save.onPressed, isNotNull);
    expect(find.text('加入当天计划'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();
    expect(find.text('加入当天计划'), findsNothing);
    expect(store.personal.plans, isEmpty);
  });

  testWidgets('planner invalidates a preview after budget or estimate edits',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('planning-estimate-cx:work:1:2:shared')),
        '25');
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();
    expect(find.text('自动纳入'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('planning-budget')), '20');
    await tester.pump();

    expect(find.text('自动纳入'), findsNothing);
    final save = tester
        .widget<FilledButton>(find.byKey(const ValueKey('planning-save')));
    expect(save.onPressed, isNotNull);
    expect(find.text('加入当天计划'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();
    expect(find.text('加入当天计划'), findsNothing);
    expect(store.personal.plans, isEmpty);
  });

  testWidgets('planner rejects confirmation after the account changes',
      (tester) async {
    final session = f.Session();
    final store = await _setup(session);
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('planning-estimate-cx:work:1:2:shared')),
        '25');
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();

    session.account = 'B';
    await store.restoreSession();
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('账号已变化'), findsOneWidget);
    expect(store.personal.plans, isEmpty);
  });

  testWidgets('planner keeps the sheet open and reports a failed save',
      (tester) async {
    final store = await _setupFailingSave();
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.tap(find.text('安排学习时间'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('planning-estimate-cx:work:1:2:shared')),
        '25');
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();

    expect(find.text('安排学习时间'), findsWidgets);
    expect(find.textContaining('加入当天计划失败'), findsOneWidget);
    expect(store.personal.plans, isEmpty);
  });
}
