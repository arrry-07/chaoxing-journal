import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Inject failures at the same preference boundary as the existing repository tests.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class Session extends SecureSessionStore {
  String? account = 'A';
  @override
  Future<String?> readChaoxingAccount() async => account;
  @override
  Future<String?> readChaoxingDisplayName() async => '合成测试';
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
  @override
  Future<void> clear() async {
    account = null;
  }
}

class Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> a) async {}
}

class FailingPreferences extends InMemorySharedPreferencesStore {
  FailingPreferences(super.data) : super.withData();
  @override
  Future<bool> setValue(String type, String key, Object value) =>
      key == 'flutter.home_filters_v1'
          ? Future.value(false)
          : super.setValue(type, key, value);
}

AssignmentStore makeStore(Session session) => AssignmentStore(
    sessionStore: session,
    notificationService: Notifications(),
    widgetSnapshotService: Snapshot());
Assignment work(DateTime due) => Assignment(
    id: 'cx:work:c:k:1',
    courseName: '数学',
    title: '数学练习',
    deadlineAt: due,
    requirementsText: '',
    status: 'pending',
    lastSyncedAt: DateTime.now());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(
      {'auto_sync_interval_minutes': 0}));

  test(
      'relative filters survive process-style restore and A B A; logout clears archives',
      () async {
    final session = Session();
    final a = makeStore(session);
    addTearDown(a.dispose);
    await a.restoreSession();
    expect(
        await a.saveHomeFilters(
            const HomeFilters(
                query: '数学',
                courseKey: 'c:k',
                deadline: AssignmentDeadlineFilter.next7Days),
            a.accountEpoch),
        true);
    final restored = makeStore(session);
    addTearDown(restored.dispose);
    await restored.restoreSession();
    expect(restored.homeFilters.query, '数学');
    expect(restored.homeFilters.deadline, AssignmentDeadlineFilter.next7Days);
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('B');
    session.account = 'B';
    await restored.restoreSession();
    expect(restored.homeFilters.query, '');
    await restored.saveHomeFilters(
        const HomeFilters(query: '英语'), restored.accountEpoch);
    await repo.activateAccount('A');
    session.account = 'A';
    await restored.restoreSession();
    expect(restored.homeFilters.query, '数学');
    await restored.logout();
    expect(restored.homeFilters.query, '');
    await repo.activateAccount('B');
    expect((await repo.loadHomeFilters()).query, '');
  });

  test('absent invalid and unknown preferences safely use defaults', () async {
    for (final raw in [
      null,
      '{bad',
      '[]',
      '{"query":4}',
      '{"query":"x","deadline":"removed"}',
      '{"query":"x","courseKey":2,"deadline":"all"}'
    ]) {
      expect(HomeFilters.decode(raw).query, '');
      expect(HomeFilters.decode(raw).deadline, AssignmentDeadlineFilter.all);
    }
    SharedPreferences.setMockInitialValues({'home_filters_v1': 42});
    expect((await LocalAssignmentRepository().loadHomeFilters()).query, '');
  });

  test('failed saving preserves last applied filters and reports failure',
      () async {
    final s = makeStore(Session());
    addTearDown(s.dispose);
    await s.restoreSession();
    await s.saveHomeFilters(const HomeFilters(query: '原条件'), s.accountEpoch);
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = FailingPreferences({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    });
    expect(
        await s.saveHomeFilters(
            const HomeFilters(query: '新条件'), s.accountEpoch),
        false);
    expect(s.homeFilters.query, '原条件');
    expect(s.error, isNotNull);
    expect((await LocalAssignmentRepository().loadHomeFilters()).query, '原条件');
  });

  test('relative deadline is reevaluated and stale account epoch cannot write',
      () async {
    final s = makeStore(Session());
    addTearDown(s.dispose);
    await s.restoreSession();
    final epoch = s.accountEpoch;
    await s.logout();
    expect(await s.saveHomeFilters(const HomeFilters(query: 'stale'), epoch),
        false);
    final now = DateTime(2026, 11, 10, 12);
    final a = work(now.add(const Duration(days: 8)));
    expect(
        AssignmentQuery.filterHome([a],
            deadline: AssignmentDeadlineFilter.next7Days, now: now),
        isEmpty);
    expect(
        AssignmentQuery.filterHome([a],
            deadline: AssignmentDeadlineFilter.next7Days,
            now: now.add(const Duration(days: 2))),
        hasLength(1));
  });

  testWidgets('missing course stays selected and write failure is visible',
      (t) async {
    final s = makeStore(Session());
    addTearDown(s.dispose);
    await s.restoreSession();
    await s.saveHomeFilters(
        const HomeFilters(query: '原条件', courseKey: 'private:class'),
        s.accountEpoch);
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = FailingPreferences({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    });
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.pumpAndSettle();
    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    expect(find.text('已选课程（当前无可显示作业）'), findsOneWidget);
    expect(find.text('private:class'), findsNothing);
    await t.enterText(find.byType(TextField), '新条件');
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(find.text('筛选条件未能保存，请重试；原条件已保留'), findsOneWidget);
    expect(s.homeFilters.query, '原条件');
    expect(s.homeFilters.courseKey, 'private:class');
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'applied selection survives tabs, detail return, refresh and empty cache; cancel does not save',
      (t) async {
    final s = makeStore(Session());
    addTearDown(s.dispose);
    await s.restoreSession();
    s.replaceAssignmentsForTest(
        [work(DateTime.now().add(const Duration(days: 2)))]);
    final router = GoRouter(initialLocation: '/assignments', routes: [
      ShellRoute(
          builder: (_, __, child) => AppShell(assignmentStore: s, child: child),
          routes: [
            GoRoute(
                path: '/assignments',
                builder: (_, __) => AssignmentListScreen(store: s)),
            for (final path in ['/calendar', '/stats', '/profile'])
              GoRoute(path: path, builder: (_, __) => const SizedBox()),
            GoRoute(
                path: '/assignments/:id',
                builder: (context, _) => Scaffold(
                    body: TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('返回列表')))),
          ])
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light, routerConfig: router));
    await t.pumpAndSettle();
    await t.tap(find.text('搜索与筛选'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '数学');
    await t.tap(find.text('7天内'));
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    for (final tab in ['日历', '统计', '我的']) {
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      await t.tap(find.text('作业'));
      await t.pumpAndSettle();
      expect(find.text('已筛选'), findsOneWidget);
      expect(s.homeFilters.query, '数学');
    }
    router.push('/assignments/test');
    await t.pumpAndSettle();
    await t.tap(find.text('返回列表'));
    await t.pumpAndSettle();
    await s.refreshAssignments();
    await t.pumpAndSettle();
    expect(s.homeFilters.deadline, AssignmentDeadlineFilter.next7Days);
    s.replaceAssignmentsForTest([]);
    await t.pump();
    expect(s.homeFilters.query, '数学');
    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '不保存');
    await t.tap(find.text('重置'));
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(s.homeFilters.query, '数学');
    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await t.tap(find.text('重置'));
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(s.homeFilters.query, '');
    expect(s.homeFilters.deadline, AssignmentDeadlineFilter.all);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
