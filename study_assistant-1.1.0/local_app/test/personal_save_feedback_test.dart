import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/daily_plan_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';

import 'review_core_remediation_test.dart' as f;

class _FailingNotifications extends f.Notifications {
  bool failSummary = false;
  bool failManual = false;

  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {
    if (failSummary) throw StateError('summary unavailable');
  }

  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {
    if (failManual) throw StateError('manual unavailable');
  }
}

Future<AssignmentStore> _setup(_FailingNotifications notifications) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = f.makeStore(f.Session(), notifications: notifications);
  await store.restoreSession();
  await store.repository.mergeAndSave([f.sample('shared')]);
  await store.refreshAssignments();
  return store;
}

void main() {
  test('service warnings do not turn a persisted personal save into failure',
      () async {
    final notifications = _FailingNotifications();
    final store = await _setup(notifications);
    addTearDown(store.dispose);

    notifications.failSummary = true;
    expect(
      await store.savePersonal(
        (w) => w.withSummary(true, 20, 0),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(store.personal.summaryEnabled, isTrue);
    expect(store.serviceWarnings, contains(contains('每日摘要未能更新')));

    notifications
      ..failSummary = false
      ..failManual = true;
    expect(
      await store.saveNotebook(
        (n) => n.withEntries(
            [const ManualEntry(id: 'm1', title: '复习', kind: 'todo')]),
        store.accountEpoch,
      ),
      isTrue,
    );
    expect(store.notebook.entries.single.title, '复习');
    expect(store.serviceWarnings, contains(contains('个人日程提醒未能更新')));
  });

  test('save feedback includes repository recovery warning', () async {
    final store = await _setup(_FailingNotifications());
    addTearDown(store.dispose);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal-broken');
    await store.repository.loadPersonalWorkspace();

    final feedback = store.saveFeedback(
      true,
      successMessage: '个人计划已保存',
      failureMessage: '个人计划保存失败',
    );

    expect(feedback, contains('个人计划已保存'));
    expect(feedback, contains('个人计划与记录无法读取'));
  });

  testWidgets('personal screens show an existing data recovery warning',
      (tester) async {
    final store = await _setup(_FailingNotifications());
    addTearDown(store.dispose);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal-broken');
    await prefs.setString('notebook_v1', '{notebook-broken');
    await store.repository.loadPersonalWorkspace();
    await store.repository.loadNotebook();

    await tester.pumpWidget(
      MaterialApp(home: DailyPlanScreen(store: store)),
    );
    expect(find.textContaining('数据恢复警告'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: ManualAgendaScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('数据恢复警告'), findsOneWidget);
  });

  testWidgets('failed recovery copy is shown as a data recovery warning',
      (tester) async {
    final store = await _setup(_FailingNotifications());
    addTearDown(store.dispose);
    final oversized = 'x' * (4 * 1024 * 1024 + 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', oversized);

    await expectLater(
      store.repository.loadPersonalWorkspace(),
      throwsA(isA<StateError>()),
    );
    final feedback = store.saveFeedback(
      false,
      successMessage: '个人计划已保存',
      failureMessage: '个人计划保存失败',
    );
    expect(feedback, contains('个人计划保存失败'));
    expect(feedback, contains('恢复副本未保存'));

    await tester.pumpWidget(
      MaterialApp(home: DailyPlanScreen(store: store)),
    );
    expect(find.textContaining('数据恢复警告'), findsOneWidget);
    expect(find.textContaining('恢复副本未保存'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: ManualAgendaScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('数据恢复警告'), findsOneWidget);
    expect(find.textContaining('恢复副本未保存'), findsOneWidget);
  });

  testWidgets('daily plan reports summary service warning after saving',
      (tester) async {
    final notifications = _FailingNotifications();
    final store = await _setup(notifications);
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.savePersonal(
      (w) => w.withSummary(true, 20, 0),
      store.accountEpoch,
    );
    notifications.failSummary = true;

    await tester.pumpWidget(
      MaterialApp(home: DailyPlanScreen(store: store)),
    );
    await tester.tap(find.text('添加作业到计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shared'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '75');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(store.personal.plans.single.minutes, 75);
    expect(
      find.textContaining('个人计划已保存；每日摘要未能更新'),
      findsOneWidget,
    );
  });

  testWidgets('manual agenda reports reminder warning after editor saves',
      (tester) async {
    final notifications = _FailingNotifications();
    final store = await _setup(notifications);
    addTearDown(store.dispose);
    notifications.failManual = true;

    await tester.pumpWidget(
      MaterialApp(home: ManualAgendaScreen(store: store)),
    );
    await tester.tap(find.text('添加个人安排'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '标题'),
      '合成待办',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存个人安排'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存个人安排'));
    await tester.pumpAndSettle();

    expect(store.notebook.entries.single.title, '合成待办');
    expect(find.byType(ManualEntryEditor), findsNothing);
    expect(
      find.textContaining('个人安排已保存；个人日程提醒未能更新'),
      findsOneWidget,
    );
  });
}
