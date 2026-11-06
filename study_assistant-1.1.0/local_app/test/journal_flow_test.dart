import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_settings_screen.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> a, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _WidgetSnapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> a) async {}
}

void main() {
  late AssignmentStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = AssignmentStore(
      sessionStore: SecureSessionStore(),
      notificationService: _Notifications(),
      widgetSnapshotService: _WidgetSnapshot(),
    );
  });
  tearDown(() => store.dispose());

  testWidgets('profile opens settings, saves changes and returns', (t) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        ShellRoute(
          builder: (_, __, child) =>
              AppShell(assignmentStore: store, child: child),
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, __) => ProfileScreen(store: store),
            ),
            GoRoute(
              path: '/reminders',
              builder: (_, __) =>
                  ReminderSettingsScreen(assignmentStore: store),
            ),
            GoRoute(
              path: '/sync',
              builder: (_, __) => SyncStatusScreen(store: store),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      MaterialApp.router(
        theme: StudyAssistantTheme.light,
        routerConfig: router,
      ),
    );
    await t.tap(find.byTooltip('打开提醒设置'));
    await t.pumpAndSettle();
    final choice = find.text('提前 10 分钟');
    await t.ensureVisible(choice);
    await t.tap(choice);
    final save = find.text('保存提醒规则');
    await t.ensureVisible(save);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(store.reminderOffsetsMinutes, contains(10));
    await t.tap(find.byTooltip('返回我的'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    final row = find.widgetWithText(ListTile, '同步学习通');
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    await t.tap(row);
    await t.pumpAndSettle();
    final interval = find.byKey(const ValueKey('auto-sync-option-60'));
    await t.scrollUntilVisible(interval, 150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(interval);
    await t.pumpAndSettle();
    expect(store.autoSyncIntervalMinutes, 60);
    await t.tap(find.byTooltip('返回我的'));
    await t.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('auto_sync_interval_minutes'), 60);
    expect(await store.reminderRuleStore.loadOffsetsMinutes(), contains(10));
    await t.ensureVisible(find.widgetWithText(ListTile, '提醒设置'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, '提醒设置'));
    await t.pumpAndSettle();
    final persisted = find.widgetWithText(CheckboxListTile, '提前 10 分钟');
    expect(t.widget<CheckboxListTile>(persisted).value, isTrue);
  });

  for (final (hour, minute, label) in [(0, 15, '00:15'), (17, 45, '17:45')]) {
    testWidgets(
        'tomorrow at $label stays under its own date when today has no deadlines',
        (t) async {
      final now = DateTime.now().toUtc();
      final beijingToday = now.add(const Duration(hours: 8));
      final tomorrow = DateTime.utc(
          beijingToday.year, beijingToday.month, beijingToday.day + 1);
      // Beijing midnight can fall on the previous UTC date.
      final due = tomorrow.add(Duration(hours: hour - 8, minutes: minute));
      store.replaceAssignmentsForTest([
        Assignment(
            id: 'cx:work:1:2:tomorrow',
            courseName: '数学',
            title: '下周预习',
            deadlineAt: due,
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now)
      ]);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: AssignmentListScreen(store: store))));
      expect(find.text('今天截止'), findsNothing);
      expect(find.text(label), findsOneWidget);
      expect(find.textContaining('${tomorrow.month}月${tomorrow.day}日  周'),
          findsOneWidget);
    });
  }

  testWidgets(
    'narrow screen with large text shows every same-day assignment in order',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 720);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final now = DateTime.now().toUtc();
      final beijingToday = now.add(const Duration(hours: 8));
      const title = '面向对象程序设计课程综合实验报告与项目复盘';
      store.replaceAssignmentsForTest([
        for (final hour in [22, 14, 10, 19])
          Assignment(
            id: 'cx:work:1:2:a$hour',
            courseName: '程序设计',
            title: '$title $hour',
            deadlineAt: DateTime.utc(beijingToday.year, beijingToday.month,
                beijingToday.day + 1, hour - 8),
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
          ),
      ]);
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: AssignmentListScreen(store: store)),
          ),
        ),
      );
      for (final hour in [10, 14, 19, 22]) {
        final target = find.byKey(ValueKey('assignment-cx:work:1:2:a$hour'));
        await t.scrollUntilVisible(target, 180);
        expect(target, findsOneWidget);
        expect(t.takeException(), isNull);
      }
      expect(find.text('22:00'), findsOneWidget);
    },
  );
}
