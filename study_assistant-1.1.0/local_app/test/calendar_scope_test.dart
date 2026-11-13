import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Session extends SecureSessionStore {
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

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _AuthenticatedStore extends AssignmentStore {
  _AuthenticatedStore()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
        );

  @override
  bool get isAuthenticated => true;

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

AssignmentStore _makeStore(_Session session) => AssignmentStore(
      sessionStore: session,
      notificationService: _Notifications(),
      widgetSnapshotService: _Snapshot(),
    );

Assignment _assignment(
  String workId, {
  required String title,
  DateTime? deadlineAt,
  bool trusted = true,
  bool failed = false,
  String courseId = 'c',
  String classId = 'k',
  String courseName = '课程',
  String status = 'pending',
}) =>
    Assignment(
      id: 'cx:work:$courseId:$classId:$workId',
      courseName: courseName,
      title: title,
      deadlineAt: deadlineAt,
      deadlineTrusted: trusted,
      deadlineReadFailed: failed,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(
      {'auto_sync_interval_minutes': 0}));

  test('recoveryScopeClassificationSeparatesNoDeadlineAndUntrustedDates', () {
    final now = DateTime.now();
    final untrusted = _assignment('untrusted',
        title: 'untrusted',
        deadlineAt: now.add(const Duration(days: 1)),
        trusted: false);
    final readFailed = _assignment('read-failed',
        title: 'read-failed',
        deadlineAt: now.add(const Duration(days: 1)),
        failed: true);
    final trusted = _assignment('trusted',
        title: 'trusted', deadlineAt: now.add(const Duration(days: 1)));
    final clear = _assignment('clear', title: 'clear');
    final failedWithoutDate =
        _assignment('failed-no-date', title: 'failed-no-date', failed: true);

    expect(AssignmentRecoveryScope.fromQueryValue('noDeadline'),
        AssignmentRecoveryScope.noDeadline);
    expect(AssignmentRecoveryScope.fromQueryValue('deadlinePending'),
        AssignmentRecoveryScope.deadlinePending);
    expect(AssignmentRecoveryScope.fromQueryValue('unknown'), isNull);

    expect(AssignmentRecoveryScope.noDeadline.matches(clear), isTrue);
    expect(
        AssignmentRecoveryScope.noDeadline.matches(failedWithoutDate), isFalse);
    expect(AssignmentRecoveryScope.noDeadline.matches(trusted), isFalse);
    expect(AssignmentRecoveryScope.deadlinePending.matches(failedWithoutDate),
        isTrue);
    expect(AssignmentRecoveryScope.deadlinePending.matches(untrusted), isTrue);
    expect(AssignmentRecoveryScope.deadlinePending.matches(readFailed), isTrue);
    expect(AssignmentRecoveryScope.deadlinePending.matches(trusted), isFalse);
    expect(AssignmentRecoveryScope.deadlinePending.matches(clear), isFalse);
  });

  testWidgets('calendarExposesRetainedUntrustedDeadlines', (tester) async {
    await initializeDateFormatting('zh_CN');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = _makeStore(_Session());
    addTearDown(store.dispose);
    final now = DateTime.now();
    store.replaceAssignmentsForTest([
      _assignment('retained',
          title: '保留但不可信的日期',
          deadlineAt: now.add(const Duration(days: 2)),
          trusted: false),
      _assignment('read-failed',
          title: '读取失败后保留的日期',
          deadlineAt: now.add(const Duration(days: 3)),
          failed: true),
      _assignment('undated', title: '明确无截止'),
      _assignment('failed-undated', title: '读取失败且无日期', failed: true),
    ]);

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CalendarScreen(store: store))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('截止待确认（3）'), 200,
        scrollable: find.byType(Scrollable).first);

    expect(find.text('待核对作业'), findsOneWidget);
    expect(find.text('无截止日期（1）'), findsOneWidget);
    expect(find.text('截止待确认（3）'), findsOneWidget);
    expect(find.text('保留但不可信的日期'), findsNothing);
    expect(find.text('读取失败后保留的日期'), findsNothing);
  });

  testWidgets('calendarRecoveryEntryIgnoresConflictingHomeFilters',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/calendar';
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    final store = _AuthenticatedStore();
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([
      _assignment('retained',
          title: '被首页筛选隐藏的待确认作业',
          deadlineAt: DateTime.now().add(const Duration(days: 5)),
          failed: true),
    ]);
    store.homeFilters = const HomeFilters(
      query: '完全不匹配',
      courseKey: 'other:key',
      deadline: AssignmentDeadlineFilter.next7Days,
      sortOrder: HomeSortOrder.title,
    );

    await tester.pumpWidget(StudyAssistantApp(
        assignmentStore: store, notificationService: _Notifications()));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('截止待确认（1）'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('截止待确认（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('截止待确认（1）'));
    await tester.pumpAndSettle();

    expect(find.byType(AssignmentListScreen), findsOneWidget);
    expect(find.text('临时范围 · 截止待确认'), findsOneWidget);
    expect(find.textContaining('共 1 项'), findsOneWidget);
    expect(find.text('被首页筛选隐藏的待确认作业'), findsOneWidget);
    expect(find.text('退出临时范围'), findsOneWidget);
    expect(store.homeFilters.query, '完全不匹配');
    expect(store.homeFilters.courseKey, 'other:key');
    expect(store.homeFilters.deadline, AssignmentDeadlineFilter.next7Days);
    expect(store.homeFilters.sortOrder, HomeSortOrder.title);

    await tester.tap(find.text('退出临时范围'));
    await tester.pumpAndSettle();
    expect(find.text('临时范围 · 截止待确认'), findsNothing);
    expect(find.text('没有符合搜索或期限条件的作业'), findsOneWidget);
    expect(store.homeFilters.query, '完全不匹配');
    expect(store.homeFilters.sortOrder, HomeSortOrder.title);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('temporaryScopeDoesNotOverwriteSavedPreferences', (tester) async {
    await initializeDateFormatting('zh_CN');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final session = _Session();
    final store = _makeStore(session);
    addTearDown(store.dispose);
    await store.restoreSession();
    const saved = HomeFilters(
      query: '首页搜索',
      courseKey: 'c:k',
      deadline: AssignmentDeadlineFilter.next7Days,
      sortOrder: HomeSortOrder.deadlineDesc,
    );
    expect(await store.saveHomeFilters(saved, store.accountEpoch), isTrue);
    store.replaceAssignmentsForTest([
      _assignment('retained',
          title: '待确认作业',
          deadlineAt: DateTime.now().add(const Duration(days: 2)),
          trusted: false),
    ]);

    final router = GoRouter(
      initialLocation:
          '/assignments?${AssignmentRecoveryScope.queryParameter}=${AssignmentRecoveryScope.deadlinePending.queryValue}',
      routes: [
        GoRoute(
            path: '/assignments',
            builder: (_, __) =>
                Scaffold(body: AssignmentListScreen(store: store))),
        GoRoute(
            path: '/calendar',
            builder: (_, __) => Scaffold(body: CalendarScreen(store: store))),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('临时范围 · 截止待确认'), findsOneWidget);
    expect(find.textContaining('共 1 项'), findsOneWidget);
    expect(find.text('待确认作业'), findsOneWidget);
    expect(find.text('已筛选'), findsNothing);
    expect(store.homeFilters.query, '首页搜索');
    expect(store.homeFilters.courseKey, 'c:k');
    expect(store.homeFilters.deadline, AssignmentDeadlineFilter.next7Days);
    expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);

    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    final persisted = await repo.loadHomeFilters();
    expect(persisted.query, '首页搜索');
    expect(persisted.courseKey, 'c:k');
    expect(persisted.deadline, AssignmentDeadlineFilter.next7Days);
    expect(persisted.sortOrder, HomeSortOrder.deadlineDesc);

    await tester.tap(find.text('退出临时范围'));
    await tester.pumpAndSettle();
    expect(find.text('临时范围 · 截止待确认'), findsNothing);
    expect(find.text('没有符合搜索或期限条件的作业'), findsOneWidget);
    expect(store.homeFilters.query, '首页搜索');
    expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
