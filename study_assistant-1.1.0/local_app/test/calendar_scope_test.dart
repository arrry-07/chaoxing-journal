import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/interaction_feedback_service.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/calendar_day_workload.dart';
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

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}
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

class _CalendarPreviewStore extends _AuthenticatedStore {
  _CalendarPreviewStore(this.homeCatalogAssignments);

  @override
  final List<Assignment> homeCatalogAssignments;
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

class _CalendarRefreshStore extends AssignmentStore {
  _CalendarRefreshStore(this._onSync)
      : super(
          sessionStore: _Session(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
          manageBackgroundSchedule: false,
        );

  final Future<void> Function() _onSync;
  SyncReport nextReport = const SyncReport(phase: SyncPhase.success);
  List<String> nextServiceWarnings = const [];
  String? nextError;
  DateTime? nextLastSync;
  int nextEpoch = 0;

  @override
  bool get isAuthenticated => true;

  @override
  int get accountEpoch => nextEpoch;

  @override
  SyncReport get syncReport => nextReport;

  @override
  List<String> get serviceWarnings => nextServiceWarnings;

  @override
  String? get operationError => nextError;

  @override
  String? get error =>
      nextError ??
      (nextServiceWarnings.isEmpty ? null : nextServiceWarnings.join('；'));

  @override
  DateTime? get lastSyncAt => nextLastSync;

  @override
  Future<void> syncAssignments({bool complete = false}) => _onSync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(
      {'auto_sync_interval_minutes': 0}));

  test('calendar grouping matches forDay for 30 cross-month days', () {
    final now = DateTime.utc(2026, 11, 30, 15, 58);
    final days = [
      for (var i = 0; i < 30; i++) DateTime(2026, 11, 20 + i),
    ];
    final beforeMidnight = DateTime.utc(2026, 11, 30, 15, 59);
    final midnight = DateTime.utc(2026, 11, 30, 16);
    final displayRecords = AssignmentQuery.projectDisplay([
      for (var i = 0; i < days.length; i++)
        if (i % 5 != 4) ...[
          _assignment('late-$i',
              title: 'First by title only',
              deadlineAt: DateTime.utc(2026, 11, 20 + i, 12)),
          _assignment('tie-z-$i',
              title: 'Same title',
              deadlineAt: DateTime.utc(2026, 11, 20 + i, 1)),
          _assignment('tie-a-$i',
              title: 'Same title',
              deadlineAt: DateTime.utc(2026, 11, 20 + i, 1)),
        ],
      _assignment('before-midnight',
          title: 'Before Beijing midnight', deadlineAt: beforeMidnight),
      _assignment('midnight', title: 'Beijing midnight', deadlineAt: midnight),
      _assignment('untrusted',
          title: 'Untrusted deadline', deadlineAt: midnight, trusted: false),
      _assignment('read-failed',
          title: 'Retained deadline', deadlineAt: midnight, failed: true),
      _assignment('submitted',
          title: 'Submitted', deadlineAt: midnight, status: 'submitted'),
      _assignment('undated', title: 'No deadline'),
      Assignment(
        id: 'manual:out-of-scope',
        source: AssignmentSource.manual,
        courseName: 'Personal',
        title: 'Out of assignment scope',
        deadlineAt: midnight,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
      Assignment(
        id: 'cx:exam:c:k:101',
        courseName: 'Course',
        title: 'Cross-midnight exam',
        deadlineAt: DateTime.utc(2026, 12, 1, 17),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
        exam: ExamInfo(
          examId: '101',
          courseId: 'c',
          clazzId: 'k',
          startAt: midnight,
          endAt: DateTime.utc(2026, 12, 1, 17),
          startTrusted: true,
          endTrusted: true,
          lifecycle: 'scheduled',
        ),
      ),
    ]);

    final grouped = AssignmentQuery.groupCalendarByDay(displayRecords, now);
    final nonemptyDays = <DateTime>[];
    for (final day in days) {
      final expected =
          AssignmentQuery.forDay(displayRecords, day, {}, now: now);
      if (expected.isNotEmpty) nonemptyDays.add(day);
      expect(
        (grouped[day] ?? const <Assignment>[]).map((a) => a.toJson()).toList(),
        equals(expected.map((a) => a.toJson()).toList()),
        reason: 'Beijing date ${day.toIso8601String()}',
      );
    }
    expect(grouped.keys, unorderedEquals(nonemptyDays));
    expect(grouped[DateTime(2026, 11, 30)]!.map((a) => a.id), [
      'cx:work:c:k:tie-a-10',
      'cx:work:c:k:tie-z-10',
      'cx:work:c:k:late-10',
      'cx:work:c:k:before-midnight',
    ]);
    expect(grouped[DateTime(2026, 12, 1)]!.map((a) => a.id), [
      'cx:work:c:k:midnight',
      'cx:exam:c:k:101',
      'cx:work:c:k:tie-a-11',
      'cx:work:c:k:tie-z-11',
      'cx:work:c:k:late-11',
    ]);
    expect(grouped, isNot(contains(DateTime(2026, 12, 19))));
  });

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

    expect(AssignmentRecoveryScope.noDeadline.matches(clear, now), isTrue);
    expect(AssignmentRecoveryScope.noDeadline.matches(failedWithoutDate, now),
        isFalse);
    expect(AssignmentRecoveryScope.noDeadline.matches(trusted, now), isFalse);
    expect(
        AssignmentRecoveryScope.deadlinePending.matches(failedWithoutDate, now),
        isTrue);
    expect(AssignmentRecoveryScope.deadlinePending.matches(untrusted, now),
        isTrue);
    expect(AssignmentRecoveryScope.deadlinePending.matches(readFailed, now),
        isTrue);
    expect(
        AssignmentRecoveryScope.deadlinePending.matches(trusted, now), isFalse);
    expect(
        AssignmentRecoveryScope.deadlinePending.matches(clear, now), isFalse);
  });

  testWidgets('calendar keeps Beijing month-boundary selection and agenda',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = _makeStore(_Session());
    addTearDown(store.dispose);
    final now = DateTime.utc(2026, 11, 30, 15, 58);
    final beforeMidnight = DateTime.utc(2026, 11, 30, 15, 59);
    final midnight = DateTime.utc(2026, 11, 30, 16);
    store.replaceAssignmentsForTest([
      _assignment('november', title: '十一月作业', deadlineAt: beforeMidnight),
      _assignment('december', title: '十二月作业', deadlineAt: midnight),
      _assignment('december-later',
          title: '十二月后续作业', deadlineAt: DateTime.utc(2026, 12, 3)),
    ]);
    store.notebook = StudyNotebook(entries: [
      ManualEntry(
        id: 'december-later',
        title: '十二月稍后安排',
        kind: 'todo',
        at: midnight.add(const Duration(minutes: 1)),
      ),
      ManualEntry(
        id: 'november',
        title: '十一月安排',
        kind: 'todo',
        at: beforeMidnight,
      ),
      ManualEntry(
        id: 'december-first',
        title: '十二月跨月安排',
        kind: 'todo',
        at: midnight,
      ),
      ManualEntry(
        id: 'december-done',
        title: '十二月已完成安排',
        kind: 'todo',
        at: DateTime.utc(2026, 12, 3),
        done: true,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('11月30日 · 议程'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-dots-30')), findsOneWidget);
    expect(find.text('十一月作业'), findsOneWidget);
    expect(find.text('个人待办 · 十一月安排'), findsOneWidget);
    expect(find.text('十二月作业'), findsNothing);

    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();

    expect(find.text('12月1日 · 议程'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-dots-1')), findsOneWidget);
    expect(find.text('十二月作业'), findsOneWidget);
    expect(find.text('十一月作业'), findsNothing);
    expect(find.text('个人待办 · 十一月安排'), findsNothing);
    final firstManual = find.text('个人待办 · 十二月跨月安排');
    final laterManual = find.text('个人待办 · 十二月稍后安排');
    for (final row in [firstManual, laterManual]) {
      await tester.scrollUntilVisible(row, 180,
          scrollable: find.byType(Scrollable).first);
    }
    expect(tester.getTopLeft(firstManual).dy,
        lessThan(tester.getTopLeft(laterManual).dy));

    final emptyDay = find.descendant(
      of: find.byKey(const ValueKey('calendar-grid-viewport')),
      matching: find.text('2'),
    );
    await tester.ensureVisible(emptyDay);
    await tester.pumpAndSettle();
    await tester.tap(emptyDay);
    await tester.pumpAndSettle();

    expect(find.text('12月2日 · 议程'), findsOneWidget);
    expect(find.text('所选范围没有已知日期的课业'), findsOneWidget);
    expect(find.text('十二月作业'), findsNothing);
    expect(firstManual, findsNothing);

    final monthPill = find.text('本月');
    await tester.ensureVisible(monthPill);
    await tester.pumpAndSettle();
    await tester.tap(monthPill);
    await tester.pumpAndSettle();

    expect(find.text('本月议程'), findsOneWidget);
    final firstAssignment = find.text('十二月作业');
    final laterAssignment = find.text('十二月后续作业');
    await tester.scrollUntilVisible(laterAssignment, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.getTopLeft(firstAssignment).dy,
        lessThan(tester.getTopLeft(laterAssignment).dy));
    await tester.scrollUntilVisible(laterManual, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.getTopLeft(firstManual).dy,
        lessThan(tester.getTopLeft(laterManual).dy));
    expect(find.text('十一月作业'), findsNothing);
    expect(find.text('个人待办 · 十一月安排'), findsNothing);
    expect(find.text('个人待办 · 十二月已完成安排'), findsNothing);
  });

  testWidgets('calendar cells reuse the display projection for their month',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    final now = DateTime.utc(2026, 11, 30, 15, 58);
    final store = _makeStore(_Session());
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([
      _assignment('month-end',
          title: '月底作业', deadlineAt: DateTime.utc(2026, 11, 30, 15, 59)),
    ]);
    AssignmentQuery.debugResetDisplayCaches();
    addTearDown(AssignmentQuery.debugResetDisplayCaches);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-dots-30')), findsOneWidget);
    expect(
      AssignmentQuery.debugProjectionBuildCount,
      0,
      reason: 'Persisted calendar rows should use the matching home index.',
    );
  });

  testWidgets('calendar keeps persisted dates during a home sync preview',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final now = DateTime.utc(2026, 11, 30, 15, 58);
    final dueToday = DateTime.utc(2026, 11, 30, 15, 59);
    final store = _CalendarPreviewStore([
      _assignment('persisted',
          title: '预览中的改期作业', deadlineAt: DateTime.utc(2026, 11, 30, 16)),
      _assignment('preview-only', title: '预览独有作业', deadlineAt: dueToday),
    ])
      ..replaceAssignmentsForTest([
        _assignment('persisted', title: '持久化作业', deadlineAt: dueToday),
      ]);
    addTearDown(store.dispose);
    AssignmentQuery.debugResetDisplayCaches();
    addTearDown(AssignmentQuery.debugResetDisplayCaches);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-dots-30')), findsOneWidget);
    expect(find.text('持久化作业'), findsOneWidget);
    expect(find.text('预览独有作业'), findsNothing);
    expect(AssignmentQuery.debugProjectionBuildCount, 1);

    await tester.tap(find.text('本月'));
    await tester.pumpAndSettle();
    expect(find.text('持久化作业'), findsOneWidget);
    expect(find.text('预览独有作业'), findsNothing);
    expect(AssignmentQuery.debugProjectionBuildCount, 1);

    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-dots-1')), findsNothing);
    expect(find.text('预览中的改期作业'), findsNothing);
    expect(AssignmentQuery.debugProjectionBuildCount, 1);
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
      _assignment('unknown-date',
          title: '状态未知但有日期',
          deadlineAt: now.add(const Duration(days: 4)),
          status: 'unknown'),
      _assignment('overdue-future',
          title: '状态冲突的未来日期',
          deadlineAt: now.add(const Duration(days: 5)),
          status: 'overdue'),
      _assignment(
        'overdue-undated',
        title: '已逾期状态但没有日期',
        status: 'overdue',
      ),
    ]);

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CalendarScreen(store: store))));
    await tester.pumpAndSettle();
    final noDeadlineRow =
        find.byKey(const ValueKey('calendar-no-deadline-scope'));
    final pendingRow =
        find.byKey(const ValueKey('calendar-deadline-pending-scope'));
    await tester.scrollUntilVisible(pendingRow, 200,
        scrollable: find.byType(Scrollable).first);

    expect(find.text('待核对课业'), findsOneWidget);
    expect(noDeadlineRow, findsOneWidget);
    expect(find.descendant(of: noDeadlineRow, matching: find.text('无截止日期')),
        findsOneWidget);
    expect(find.descendant(of: noDeadlineRow, matching: find.text('1 项')),
        findsOneWidget);
    expect(pendingRow, findsOneWidget);
    expect(find.descendant(of: pendingRow, matching: find.text('截止时间未知')),
        findsOneWidget);
    expect(find.descendant(of: pendingRow, matching: find.text('6 项')),
        findsOneWidget);
    expect(find.ancestor(of: pendingRow, matching: find.byType(Card)),
        findsNothing);
    expect(find.text('保留但不可信的日期'), findsNothing);
    expect(find.text('读取失败后保留的日期'), findsNothing);
    expect(find.text('状态未知但有日期'), findsNothing);
    expect(find.text('状态冲突的未来日期'), findsNothing);
    expect(find.text('已逾期状态但没有日期'), findsNothing);
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
      deadline: AssignmentDeadlineFilter.notExpired,
      sortOrder: HomeSortOrder.title,
    );

    await tester.pumpWidget(StudyAssistantApp(
        assignmentStore: store, notificationService: _Notifications()));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarScreen), findsOneWidget);
    final pendingRow =
        find.byKey(const ValueKey('calendar-deadline-pending-scope'));
    await tester.scrollUntilVisible(pendingRow, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(pendingRow);
    await tester.pumpAndSettle();
    await tester.tap(pendingRow);
    await tester.pumpAndSettle();

    expect(find.byType(AssignmentListScreen), findsOneWidget);
    expect(find.text('截止时间未知'), findsOneWidget);
    expect(find.textContaining('共 1 项'), findsOneWidget);
    expect(find.text('被首页筛选隐藏的待确认作业'), findsOneWidget);
    expect(find.text('返回全部'), findsOneWidget);
    expect(store.homeFilters.query, '完全不匹配');
    expect(store.homeFilters.courseKey, 'other:key');
    expect(store.homeFilters.deadline, AssignmentDeadlineFilter.notExpired);
    expect(store.homeFilters.sortOrder, HomeSortOrder.title);

    await tester.tap(find.text('返回全部'));
    await tester.pumpAndSettle();
    expect(find.text('截止时间未知'), findsNothing);
    expect(find.text('没有符合搜索、类型或期限条件的记录'), findsOneWidget);
    expect(store.homeFilters.query, '完全不匹配');
    expect(store.homeFilters.sortOrder, HomeSortOrder.title);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('calendar keeps counts muted and category color in the agenda',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = _makeStore(_Session());
    addTearDown(store.dispose);
    final now = DateTime.utc(2026, 11, 18, 2);
    store.replaceAssignmentsForTest([
      _assignment('today',
          title: '今日课业', deadlineAt: DateTime.utc(2026, 11, 18, 15, 59)),
      _assignment('pending',
          title: '时间待确认',
          deadlineAt: DateTime.utc(2026, 11, 19, 15, 59),
          trusted: false),
    ]);
    store.notebook = StudyNotebook(entries: [
      ManualEntry(
        id: 'exam',
        title: '高数考试',
        kind: 'exam',
        at: DateTime.utc(2026, 11, 18, 1),
      ),
      ManualEntry(
        id: 'todo',
        title: '交材料',
        kind: 'todo',
        at: DateTime.utc(2026, 11, 18, 3),
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('课业日历'));
    final agendaEntry = tester.getRect(find.text('个人待办与考试'));
    expect(agendaEntry.left, greaterThan(title.right));
    final agendaHeading = find.text('11月18日 · 议程');
    expect(agendaHeading.hitTestable(), findsOneWidget);
    expect(
      find.text('日期下方数字为当天合计。考试按开考日，其余按截止日，均为北京时间。'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('calendar-dots-18')), findsOneWidget);

    await tester.tap(find.byTooltip('查看说明'));
    await tester.pumpAndSettle();
    expect(find.text('日历统计与圆点说明'), findsOneWidget);
    expect(find.text('考试按开考日展示，作业与课堂任务按截止日展示，均使用北京时间。'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('手动考试 · 高数考试'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final examTitle = tester.widget<Text>(find.text('手动考试 · 高数考试'));
    final todoTitle = tester.widget<Text>(find.text('个人待办 · 交材料'));
    expect(examTitle.style?.color, Journal.slate);
    expect(todoTitle.style?.color, Journal.ink);
    final examTile = find.ancestor(
      of: find.text('手动考试 · 高数考试'),
      matching: find.byType(ListTile),
    );
    final todoTile = find.ancestor(
      of: find.text('个人待办 · 交材料'),
      matching: find.byType(ListTile),
    );
    expect(
      tester
          .widget<Icon>(find.descendant(
            of: examTile,
            matching: find.byIcon(Icons.school_outlined),
          ))
          .color,
      Journal.slate,
    );
    expect(
      tester
          .widget<Icon>(find.descendant(
            of: todoTile,
            matching: find.byIcon(Icons.event_note_outlined),
          ))
          .color,
      Journal.ink,
    );

    final pendingRow =
        find.byKey(const ValueKey('calendar-deadline-pending-scope'));
    await tester.scrollUntilVisible(
      pendingRow,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final pendingLabel = tester.widget<Text>(
      find.descendant(
        of: pendingRow,
        matching: find.text('截止时间未知'),
      ),
    );
    expect(pendingLabel.style?.color, Journal.ochre);
    final pendingIcon = tester.widget<Icon>(
      find.descendant(
        of: pendingRow,
        matching: find.byIcon(Icons.help_outline_rounded),
      ),
    );
    expect(pendingIcon.color, Journal.ochre);
    final pendingCount = tester.widget<Text>(
      find.descendant(
        of: pendingRow,
        matching: find.text('1 项'),
      ),
    );
    expect(pendingCount.style?.color, Journal.muted);
    expect(find.ancestor(of: pendingRow, matching: find.byType(Card)),
        findsNothing);
  });

  testWidgets('calendar month heading stays on one line at 320dp and 2x text',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = _makeStore(_Session());
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: CalendarScreen(
          store: store,
          clock: () => DateTime.utc(2026, 11, 18, 2),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final month = tester.widget<Text>(find.text('2026年11月'));
    expect(month.maxLines, 1);
    expect(month.softWrap, isFalse);
    expect(tester.takeException(), isNull);
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
      deadline: AssignmentDeadlineFilter.notExpired,
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

    expect(find.text('截止时间未知'), findsOneWidget);
    expect(find.textContaining('共 1 项'), findsOneWidget);
    expect(find.text('待确认作业'), findsOneWidget);
    expect(find.text('已筛选'), findsNothing);
    expect(store.homeFilters.query, '首页搜索');
    expect(store.homeFilters.courseKey, 'c:k');
    expect(store.homeFilters.deadline, AssignmentDeadlineFilter.notExpired);
    expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);

    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    final persisted = await repo.loadHomeFilters();
    expect(persisted.query, '首页搜索');
    expect(persisted.courseKey, 'c:k');
    expect(persisted.deadline, AssignmentDeadlineFilter.notExpired);
    expect(persisted.sortOrder, HomeSortOrder.deadlineDesc);

    await tester.tap(find.text('返回全部'));
    await tester.pumpAndSettle();
    expect(find.text('截止时间未知'), findsNothing);
    expect(find.text('没有符合搜索、类型或期限条件的记录'), findsOneWidget);
    expect(store.homeFilters.query, '首页搜索');
    expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'calendar refresh uses completion time and distinguishes partial/warning',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    var now = DateTime(2026, 11, 18, 10, 0, 0);
    late _CalendarRefreshStore store;
    var mode = 0;
    store = _CalendarRefreshStore(() async {
      now = DateTime(2026, 11, 18, 10, 0, 5);
      if (mode == 0) {
        store.nextReport = const SyncReport(phase: SyncPhase.success);
        store.nextServiceWarnings = const [];
        store.nextError = null;
        store.nextLastSync = now;
      } else if (mode == 1) {
        store.nextReport = const SyncReport(phase: SyncPhase.partial);
        store.nextServiceWarnings = const [];
        store.nextError = '部分课程读取失败';
        store.nextLastSync = now;
      } else {
        store.nextReport = const SyncReport(phase: SyncPhase.success);
        store.nextServiceWarnings = const ['小组件更新失败'];
        store.nextError = null;
        store.nextLastSync = now;
      }
    });
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CalendarScreen(store: store, clock: () => now),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('本次刷新已完成（10:00:05）'), findsOneWidget);

    mode = 1;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('部分完成'), findsOneWidget);

    mode = 2;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('本机提醒或小组件需处理'), findsOneWidget);
  });

  testWidgets(
      'calendar refresh triggers syncDone feedback only on fresh same-epoch success without operationError',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    InteractionFeedback.debugReset();
    addTearDown(InteractionFeedback.debugReset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const channel = MethodChannel('study_assistant/interaction_sound');
      final kinds = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'feedback') {
          kinds.add((call.arguments as Map)['kind'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      late _CalendarRefreshStore store;
      var mode = 0;
      store = _CalendarRefreshStore(() async {
        switch (mode) {
          case 0:
            // Fresh SyncPhase.success in same epoch without operationError.
            store.nextReport = SyncReport(
                phase: SyncPhase.success,
                attemptedAt: DateTime(2026, 11, 22, 10, 0, 1));
            store.nextError = null;
          case 1:
            // Partial must not emit syncDone.
            store.nextReport = SyncReport(
                phase: SyncPhase.partial,
                attemptedAt: DateTime(2026, 11, 22, 10, 0, 2));
            store.nextError = null;
          case 2:
            // Success with operationError must not emit syncDone.
            store.nextReport = SyncReport(
                phase: SyncPhase.success,
                attemptedAt: DateTime(2026, 11, 22, 10, 0, 3));
            store.nextError = '保存失败';
          case 3:
            // Epoch switched mid-sync must not emit syncDone.
            store.nextEpoch++;
            store.nextReport = SyncReport(
                phase: SyncPhase.success,
                attemptedAt: DateTime(2026, 11, 22, 10, 0, 4));
            store.nextError = null;
        }
      });
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CalendarScreen(store: store)),
      ));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        kinds.clear();
        mode = i;
        await tester.tap(find.byTooltip('刷新'));
        await tester.pumpAndSettle();
        expect(
          kinds.where((k) => k == 'syncDone').toList(),
          i == 0 ? ['syncDone'] : isEmpty,
          reason: 'mode=$i',
        );
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'Phase 2B calendar places manual deadline on Beijing day and shows manual label',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.utc(2026, 11, 20, 2); // 10:00 Beijing
    // Cross-day UTC instant: 2026-11-24T16:30:00Z == 2026-11-25 00:30 Beijing (Los Angeles still Nov 24 08:30!).
    final beijingNov25 = DateTime.utc(2026, 11, 24, 16, 30);
    final unknownWork = _assignment(
      'manual-cal',
      title: '未确认截止日历实验',
      deadlineAt: null,
      trusted: false,
    );
    final session = _Session();
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    await repo.mergeAndSave([unknownWork], completeSync: true);
    final store = _makeStore(session);
    addTearDown(store.dispose);
    await store.restoreSession();

    expect(
      AssignmentQuery.groupCalendarByDay(
        [unknownWork],
        now,
        coursework: store.courseworkState,
      ),
      isEmpty,
    );

    expect(await store.setManualDeadline(unknownWork, beijingNov25), isTrue);

    final byDay = AssignmentQuery.groupCalendarByDay(
      [unknownWork],
      now,
      coursework: store.courseworkState,
    );
    expect(byDay.keys.single, DateTime(2026, 11, 25));
    expect(byDay[DateTime(2026, 11, 25)]!.single.id, unknownWork.id);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 950);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    // Tap day 25 on calendar grid.
    await tester.tap(find.text('25').first);
    await tester.pumpAndSettle();

    expect(find.text('未确认截止日历实验'), findsOneWidget);
    expect(find.text('手动'), findsOneWidget);
    expect(find.textContaining('官方待确认'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
  });

  test(
      'Phase 5A CalendarDayWorkload dedupes exam identity, includes manual deadlines/entries, and excludes completed/ended',
      () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.utc(2026, 12, 20, 2); // Beijing 10:00
    final day1Start = DateTime.utc(2026, 12, 22, 1); // Beijing Dec 22 09:00

    final w1 = _assignment('w1', title: '作业1', deadlineAt: day1Start);
    final completedWork = _assignment(
      'done',
      title: '已完成作业',
      deadlineAt: day1Start,
      status: 'submitted',
    );
    final untrustedWork = _assignment(
      'manual-work',
      title: '2B 手动期限作业',
      deadlineAt: null,
      trusted: false,
    );
    final endedExam = Assignment(
      id: 'cx:exam:1:2:ended',
      source: AssignmentSource.exam,
      courseName: '课程',
      title: '已结束考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: 'ended',
        courseId: '1',
        clazzId: '2',
        startAt: day1Start,
        endAt: day1Start.add(const Duration(hours: 2)),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'ended',
      ),
    );
    final formalExam = Assignment(
      id: 'cx:exam:1:2:55',
      source: AssignmentSource.exam,
      courseName: '课程',
      title: '正式考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '55',
        courseId: '1',
        clazzId: '2',
        startAt: day1Start,
        endAt: day1Start.add(const Duration(hours: 2)),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    final dupNotice = Assignment(
      id: 'cx:examNotice:inbox:n55',
      source: AssignmentSource.exam,
      courseName: '课程',
      title: '考试通知副本',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: 'n55',
        relatedExamId: '55',
        courseId: '1',
        clazzId: '2',
        noticeOnly: true,
        startAt: day1Start,
        endAt: day1Start.add(const Duration(hours: 2)),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'scheduled',
      ),
    );

    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    await repo.mergeAndSave([untrustedWork], completeSync: true);
    final store = _makeStore(_Session());
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(await store.setManualDeadline(untrustedWork, day1Start), isTrue);

    // 2 items: formalExam (+ dupNotice deduped) + w1 -> not busy
    expect(
      CalendarDayWorkload.countForDay(
        assignments: [w1, completedWork, endedExam, formalExam, dupNotice],
        manualEntries: [
          ManualEntry(
              id: 'done-m',
              title: '已完成手动',
              kind: 'todo',
              at: day1Start,
              done: true),
          const ManualEntry(id: 'nodate-m', title: '无日期手动', kind: 'todo'),
        ],
        now: now,
        coursework: store.courseworkState,
      ),
      2,
    );
    expect(CalendarDayWorkload.isBusyCount(2), isFalse);

    // Adding 2B manual deadline makes 3 items -> busy!
    final count3 = CalendarDayWorkload.countForDay(
      assignments: [w1, untrustedWork, formalExam, dupNotice],
      manualEntries: const [],
      now: now,
      coursework: store.courseworkState,
    );
    expect(count3, 3);
    expect(CalendarDayWorkload.isBusyCount(count3), isTrue);
  });

  testWidgets(
      'Phase 5A calendar + 记一条 creates todo or manual exam on selected Beijing day including blank cross-year day',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime.utc(2026, 12, 20, 2); // Beijing 2026-12-20 10:00
    final store = _makeStore(_Session());
    addTearDown(store.dispose);
    await store.restoreSession();
    store.replaceAssignmentsForTest([
      _assignment(
        'dec-other',
        title: '十二月其他作业',
        deadlineAt: DateTime.utc(2026, 12, 15, 1),
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    // Navigate to Jan 2027 (cross-year) and select blank day Jan 2.
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.text('2027年1月'), findsOneWidget);

    final jan2 = find.descendant(
      of: find.byKey(const ValueKey('calendar-grid-viewport')),
      matching: find.text('2'),
    );
    await tester.tap(jan2);
    await tester.pumpAndSettle();
    expect(find.text('1月2日 · 议程'), findsOneWidget);
    expect(find.text('所选范围没有已知日期的课业'), findsOneWidget);

    // Open + 记一条 and immediately cancel without saving: writes nothing.
    final quickAdd = find.byKey(const ValueKey('calendar-quick-add-entry'));
    expect(quickAdd, findsOneWidget);
    await tester.tap(quickAdd);
    await tester.pumpAndSettle();
    expect(find.text('2027-01-02 09:00 北京时间'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(store.notebook.entries, isEmpty);

    // Open + 记一条 again, save a personal todo on 2027-01-02.
    await tester.tap(quickAdd);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '跨年二日复习');
    await tester.pump();
    final saveBtn = find.text('保存个人安排');
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text('个人待办 · 跨年二日复习'), findsOneWidget);
    expect(store.notebook.entries, hasLength(1));
    expect(
      AssignmentQuery.dayKey(store.notebook.entries.single.at!),
      DateTime(2027, 1, 2),
    );

    // Open + 记一条 and add a manual exam on the same blank day.
    await tester.tap(quickAdd);
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动考试'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '跨年口试');
    await tester.pump();
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(find.text('手动考试 · 跨年口试'), findsOneWidget);
    expect(store.notebook.entries, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
