import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/daily_plan_screen.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';

import 'review_core_remediation_test.dart' as f;

Future<AssignmentStore> _setup(f.Session session) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = f.makeStore(session);
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

void main() {
  testWidgets('rule planner previews and saves only explicitly confirmed work',
      (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.tap(find.text('智能规划建议'));
    await tester.pumpAndSettle();

    expect(find.text('规则规划预览'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('planning-budget')), '60');
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('planning-estimate-cx:work:1:2:shared')),
        '25');
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();

    expect(find.text('自动纳入'), findsOneWidget);
    expect(find.byKey(const ValueKey('planning-suggested-cx:work:1:2:shared')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planning-save')));
    await tester.pumpAndSettle();

    expect(store.personal.plans.single.assignmentId, 'cx:work:1:2:shared');
    expect(store.personal.plans.single.minutes, 25);
    expect(find.text('规划建议已保存到个人计划'), findsOneWidget);
  });

  testWidgets('planner never guesses a missing estimate', (tester) async {
    final store = await _setup(f.Session());
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.tap(find.text('智能规划建议'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('planning-candidate-cx:work:1:2:shared')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('planning-generate')));
    await tester.pumpAndSettle();

    expect(find.textContaining('需要填写预计耗时'), findsOneWidget);
    final save = tester
        .widget<FilledButton>(find.byKey(const ValueKey('planning-save')));
    expect(save.onPressed, isNull);
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
    await tester.tap(find.text('智能规划建议'));
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
    expect(save.onPressed, isNull);
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
    await tester.tap(find.text('智能规划建议'));
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
    await tester.tap(find.text('智能规划建议'));
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

    expect(find.text('规则规划预览'), findsOneWidget);
    expect(find.textContaining('规划建议保存失败'), findsOneWidget);
    expect(store.personal.plans, isEmpty);
  });
}
