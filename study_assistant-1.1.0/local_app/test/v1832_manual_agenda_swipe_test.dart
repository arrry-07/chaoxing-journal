import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _MemorySessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student';

  @override
  Future<String?> readChaoxingPassword() async => 'pw';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;

  @override
  Future<void> removeLegacyAssignmentSchedules() async {}

  @override
  Future<void> migrateLegacyManualChannelIfNeeded(
      List<ManualEntry> entries) async {}

  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> items,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}
}

class _WarningNotificationService extends _NoopNotificationService {
  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {
    throw StateError('模拟提醒重排失败');
  }
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

Future<AssignmentStore> _buildStore({
  List<ManualEntry> initial = const [],
  LocalNotificationService? notifications,
}) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = AssignmentStore(
    sessionStore: _MemorySessionStore(),
    notificationService: notifications ?? _NoopNotificationService(),
    widgetSnapshotService: _NoopWidgetSnapshotService(),
  );
  await store.restoreSession();
  if (initial.isNotEmpty) {
    await store.saveNotebook(
      (n) => n.withEntries(initial),
      store.accountEpoch,
    );
  }
  return store;
}

void main() {
  final fixedNow = DateTime.utc(2026, 11, 20, 4);

  testWidgets(
      'swipe right completes entry into collapsed section, undo restores, and expand allows swipe back to active',
      (tester) async {
    final entry = ManualEntry(
      id: 'm-1',
      title: '完成实验报告',
      kind: ManualEntry.kindTodo,
      course: '操作系统',
      at: fixedNow.add(const Duration(hours: 4)),
    );
    final tomorrowEntry = ManualEntry(
      id: 'm-2',
      title: '准备明天的答辩',
      kind: ManualEntry.kindExam,
      at: fixedNow.add(const Duration(days: 1)),
    );
    final store = await _buildStore(initial: [entry, tomorrowEntry]);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: ManualAgendaScreen(store: store, clock: () => fixedNow),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('agenda-active-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-completed-card')), findsNothing);
    expect(find.text('全部 (2)'), findsOneWidget);
    expect(find.text('待办 (1)'), findsOneWidget);
    expect(find.text('考试 (1)'), findsOneWidget);
    expect(find.textContaining('今天 16:00'), findsOneWidget);
    expect(find.textContaining('明天 12:00'), findsOneWidget);
    expect(find.text('完成实验报告'), findsOneWidget);

    await tester.tap(find.text('待办 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('准备明天的答辩'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('agenda-swipe-m-1')),
      const Offset(240, 0),
    );
    await tester.pumpAndSettle();

    expect(
        store.notebook.entries.firstWhere((e) => e.id == 'm-1').done, isTrue);
    expect(find.byKey(const ValueKey('agenda-active-card')), findsNothing);
    expect(find.text('当前筛选下的个人安排已全部完成'), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-completed-card')), findsOneWidget);
    expect(find.text('已完成（1）'), findsOneWidget);
    expect(find.text('完成实验报告'), findsNothing);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(
      store.notebook.entries.firstWhere((e) => e.id == 'm-1').done,
      isFalse,
    );
    expect(find.byKey(const ValueKey('agenda-active-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('agenda-completed-card')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agenda-toggle-m-1')));
    await tester.pumpAndSettle();
    expect(
        store.notebook.entries.firstWhere((e) => e.id == 'm-1').done, isTrue);

    await tester.tap(find.byKey(const ValueKey('agenda-completed-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('完成实验报告'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('agenda-swipe-m-1')),
      const Offset(240, 0),
    );
    await tester.pumpAndSettle();
    expect(
      store.notebook.entries.firstWhere((e) => e.id == 'm-1').done,
      isFalse,
    );
    expect(find.byKey(const ValueKey('agenda-active-card')), findsOneWidget);
  });

  testWidgets(
      'swipe left opens delete confirmation dialog and appends warnings',
      (tester) async {
    final e1 = ManualEntry(
      id: 'm-del',
      title: '待删除日程',
      kind: ManualEntry.kindTodo,
      at: fixedNow.add(const Duration(hours: 6)),
      remind: true,
    );
    final e2 = ManualEntry(
      id: 'm-keep',
      title: '保留日程',
      kind: ManualEntry.kindTodo,
      at: fixedNow.add(const Duration(hours: 8)),
    );
    final store = await _buildStore(
      initial: [e1, e2],
      notifications: _WarningNotificationService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: ManualAgendaScreen(store: store, clock: () => fixedNow),
    ));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('agenda-swipe-m-del')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('删除这项个人日程？'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('删除'),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.notebook.entries.map((e) => e.id).toList(), ['m-keep']);
    expect(
      find.textContaining('已删除个人安排；个人日程提醒未能更新'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('agenda-toggle-m-keep')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('已完成「保留日程」；个人日程提醒未能更新'),
      findsOneWidget,
    );
  });

  testWidgets(
      'renders empty state and zero overflow at 320dp @ 2x in light and dark',
      (tester) async {
    final emptyStore = await _buildStore();
    addTearDown(emptyStore.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: ManualAgendaScreen(store: emptyStore, clock: () => fixedNow),
    ));
    await tester.pumpAndSettle();
    expect(find.text('还没有个人安排，点击下方按钮添加待办或考试。'), findsOneWidget);

    final store = await _buildStore(initial: [
      ManualEntry(
        id: 'm-long',
        title: '非常长的一个个人待办与考试安排标题用来测试三百二十像素两倍字体不溢出',
        kind: ManualEntry.kindExam,
        course: '编译原理与实践',
        location: '教三 302',
        note: '携带学生证和计算器，提前十分钟入场',
        at: fixedNow.add(const Duration(hours: 2)),
      ),
    ]);
    addTearDown(store.dispose);

    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final theme in [StudyAssistantTheme.light, StudyAssistantTheme.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: ManualAgendaScreen(store: store, clock: () => fixedNow),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
