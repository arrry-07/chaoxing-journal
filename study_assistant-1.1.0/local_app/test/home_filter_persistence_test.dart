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

Future<void> tapSheetOption(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(
      {'auto_sync_interval_minutes': 0}));

  test('sort and filters survive restart A B A and same-account restore',
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
                deadline: AssignmentDeadlineFilter.notExpired,
                sortOrder: HomeSortOrder.deadlineDesc),
            a.accountEpoch),
        true);
    final restored = makeStore(session);
    addTearDown(restored.dispose);
    await restored.restoreSession();
    expect(restored.homeFilters.query, '数学');
    expect(restored.homeFilters.deadline, AssignmentDeadlineFilter.notExpired);
    expect(restored.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
    final repo = LocalAssignmentRepository();
    expect(
        (await repo.loadHomeFilters()).sortOrder, HomeSortOrder.deadlineDesc);
    await repo.activateAccount('A');
    expect(
        (await repo.loadHomeFilters()).sortOrder, HomeSortOrder.deadlineDesc);
    await repo.activateAccount('B');
    session.account = 'B';
    await restored.restoreSession();
    expect(restored.homeFilters.query, '');
    await restored.saveHomeFilters(
        const HomeFilters(query: '英语', sortOrder: HomeSortOrder.courseName),
        restored.accountEpoch);
    await repo.activateAccount('A');
    session.account = 'A';
    await restored.restoreSession();
    expect(restored.homeFilters.query, '数学');
    expect(restored.homeFilters.deadline, AssignmentDeadlineFilter.notExpired);
    expect(restored.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
    await restored.logout();
    expect(restored.homeFilters.query, '');
    expect(restored.homeFilters.sortOrder, HomeSortOrder.grouped);
    await repo.activateAccount('B');
    expect((await repo.loadHomeFilters()).query, '');
    expect((await repo.loadHomeFilters()).sortOrder, HomeSortOrder.grouped);
  });

  test('legacy noDeadline preference migrates to notExpired', () {
    final legacy = HomeFilters.decode('{"query":"","deadline":"noDeadline"}');
    final newer = HomeFilters.decode(
        const HomeFilters(deadline: AssignmentDeadlineFilter.notExpired)
            .encode());
    expect(legacy.deadline, AssignmentDeadlineFilter.notExpired);
    expect(newer.deadline, AssignmentDeadlineFilter.notExpired);
  });
  test('malformed preferences safely use defaults', () async {
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
      expect(HomeFilters.decode(raw).sortOrder, HomeSortOrder.grouped);
    }
    SharedPreferences.setMockInitialValues({'home_filters_v1': 42});
    expect((await LocalAssignmentRepository().loadHomeFilters()).query, '');
  });

  test('legacy deadline values migrate without discarding other fields', () {
    final legacy = HomeFilters.decode(
        '{"query":" 数学 ","courseKey":"c:k","deadline":"next7Days"}');
    expect(legacy.query, '数学');
    expect(legacy.courseKey, 'c:k');
    expect(legacy.deadline, AssignmentDeadlineFilter.all);
    expect(legacy.sortOrder, HomeSortOrder.grouped);

    final unknown = HomeFilters.decode(
        '{"query":"英语","courseKey":"b:k","deadline":"next30Days","sortOrder":"removed"}');
    expect(unknown.query, '英语');
    expect(unknown.courseKey, 'b:k');
    expect(unknown.deadline, AssignmentDeadlineFilter.all);
    expect(unknown.sortOrder, HomeSortOrder.grouped);

    final uncertain = HomeFilters.decode(
        '{"query":"语文","courseKey":"a:k","deadline":"uncertain","sortOrder":"title"}');
    expect(uncertain.query, '语文');
    expect(uncertain.courseKey, 'a:k');
    expect(uncertain.deadline, AssignmentDeadlineFilter.all);
    expect(uncertain.sortOrder, HomeSortOrder.title);

    final encoded = const HomeFilters(
            query: '语文',
            courseKey: 'a:k',
            deadline: AssignmentDeadlineFilter.overdue,
            sortOrder: HomeSortOrder.title)
        .encode();
    final decoded = HomeFilters.decode(encoded);
    expect(decoded.query, '语文');
    expect(decoded.courseKey, 'a:k');
    expect(decoded.deadline, AssignmentDeadlineFilter.overdue);
    expect(decoded.sortOrder, HomeSortOrder.title);
  });

  test('failed saving preserves last applied filters and reports failure',
      () async {
    final s = makeStore(Session());
    addTearDown(s.dispose);
    await s.restoreSession();
    await s.saveHomeFilters(
        const HomeFilters(query: '原条件', sortOrder: HomeSortOrder.courseName),
        s.accountEpoch);
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = FailingPreferences({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    });
    expect(
        await s.saveHomeFilters(
            const HomeFilters(query: '新条件', sortOrder: HomeSortOrder.title),
            s.accountEpoch),
        false);
    expect(s.homeFilters.query, '原条件');
    expect(s.homeFilters.sortOrder, HomeSortOrder.courseName);
    expect(s.error, isNotNull);
    expect((await LocalAssignmentRepository().loadHomeFilters()).query, '原条件');
    expect((await LocalAssignmentRepository().loadHomeFilters()).sortOrder,
        HomeSortOrder.courseName);
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
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await tapSheetOption(t, '应用');
    expect(find.text('搜索、筛选与排序未能保存，请重试；原偏好已保留'), findsOneWidget);
    expect(s.homeFilters.query, '原条件');
    expect(s.homeFilters.courseKey, 'private:class');
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sort panel actions remain usable at 320dp and 2x text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = makeStore(Session());
    addTearDown(store.dispose);
    await store.restoreSession();
    store.replaceAssignmentsForTest(
        [work(DateTime.now().add(const Duration(days: 1)))]);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(body: AssignmentListScreen(store: store)),
      ),
    ));
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
    expect(find.text('搜索、筛选与排序'), findsOneWidget);
    await tester.ensureVisible(find.text('清空筛选'));
    await tester.pump();
    await tester.ensureVisible(find.text('取消'));
    await tester.pump();
    await tester.ensureVisible(find.text('应用'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('home deadline picker shows only the three current choices',
      (tester) async {
    final store = makeStore(Session());
    addTearDown(store.dispose);
    await store.restoreSession();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))),
    );
    await tester.tap(find.text('搜索与筛选'));
    await tester.pumpAndSettle();

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(chips, ['未逾期', '全部', '已逾期']);
    expect(find.text('7天内'), findsNothing);
    expect(find.text('30天内'), findsNothing);
    expect(find.text('期限待确认'), findsNothing);
    expect(find.text('无截止日期'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'applied sort survives navigation refresh and account cache clearing',
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
    await tapSheetOption(t, '未逾期');
    await tapSheetOption(t, '作业名称');
    await tapSheetOption(t, '应用');
    expect(s.homeFilters.sortOrder, HomeSortOrder.title);
    expect(find.byKey(const ValueKey('current-home-sort')), findsOneWidget);
    expect(find.text('作业名称'), findsOneWidget);
    for (final tab in ['日历', '统计', '我的']) {
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      await t.tap(find.text('作业'));
      await t.pumpAndSettle();
      expect(find.text('已筛选'), findsOneWidget);
      expect(s.homeFilters.query, '数学');
      expect(s.homeFilters.sortOrder, HomeSortOrder.title);
    }
    router.push('/assignments/test');
    await t.pumpAndSettle();
    await t.tap(find.text('返回列表'));
    await t.pumpAndSettle();
    await s.refreshAssignments();
    await t.pumpAndSettle();
    expect(s.homeFilters.deadline, AssignmentDeadlineFilter.notExpired);
    expect(s.homeFilters.sortOrder, HomeSortOrder.title);
    s.replaceAssignmentsForTest([]);
    await t.pump();
    expect(s.homeFilters.query, '数学');
    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '不保存');
    await tapSheetOption(t, '课程名称');
    await tapSheetOption(t, '清空筛选');
    await tapSheetOption(t, '取消');
    expect(s.homeFilters.query, '数学');
    expect(s.homeFilters.deadline, AssignmentDeadlineFilter.notExpired);
    expect(s.homeFilters.sortOrder, HomeSortOrder.title);
    await t.tap(find.text('已筛选'));
    await t.pumpAndSettle();
    await tapSheetOption(t, '清空筛选');
    await tapSheetOption(t, '应用');
    expect(s.homeFilters.query, '');
    expect(s.homeFilters.deadline, AssignmentDeadlineFilter.all);
    expect(s.homeFilters.sortOrder, HomeSortOrder.title);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account change while sort panel is open cannot write old choice',
      (t) async {
    final session = Session();
    final s = makeStore(session);
    addTearDown(s.dispose);
    await s.restoreSession();
    await s.saveHomeFilters(
        const HomeFilters(sortOrder: HomeSortOrder.courseName), s.accountEpoch);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.pumpAndSettle();

    await t.tap(find.text('搜索与筛选'));
    await t.pumpAndSettle();
    expect(find.text('搜索、筛选与排序'), findsOneWidget);
    await tapSheetOption(t, '作业名称');

    session.account = 'B';
    await s.restoreSession();
    await t.pumpAndSettle();
    expect(s.homeFilters.sortOrder, HomeSortOrder.grouped);

    await tapSheetOption(t, '应用');
    expect(s.homeFilters.sortOrder, HomeSortOrder.grouped);

    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    expect((await repo.loadHomeFilters()).sortOrder, HomeSortOrder.courseName);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
