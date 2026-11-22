import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_assignment_parser.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/reminder_history.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_statistics.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/local_record_query.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

import 'review_core_remediation_test.dart' as f;

class _MigratedNotifications extends f.Notifications {
  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;
}

class _CapturingGateway extends BackgroundReminderGateway {
  final List<AssignmentReminderPlan> appliedPlans = [];
  int _mutationVersion = 1;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<int> ensureActiveAccount(String accountHash) async => 1;

  @override
  Future<bool> isSessionCurrent(String accountHash, int sessionEpoch) async =>
      true;

  @override
  Future<void> markPendingUpdate({
    required String accountHash,
    required int sessionEpoch,
  }) async {
    _mutationVersion++;
  }

  @override
  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
    bool reconcileSchedules = true,
  }) async {}

  @override
  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
  }) async {}

  @override
  Future<ReminderHistoryControl> getReminderHistoryControl({
    String? accountHash,
    int? sessionEpoch,
  }) async =>
      const ReminderHistoryControl(
        historyGeneration: 1,
        recordingEnabled: true,
        ownerMatches: true,
        purgePending: false,
        purgeToken: null,
      );

  @override
  Future<int> enableReminderHistorySession({
    required String accountHash,
    required int sessionEpoch,
    required int expectedHistoryGeneration,
  }) async =>
      1;

  @override
  Future<ReminderObservationContext> acquireReminderObservationContext({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      ReminderObservationContext(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
        historyGeneration: 1,
        operationSequence: 1,
      );

  @override
  Future<ReminderScheduleOutcomeResult> recordReminderScheduleOutcome({
    required ReminderObservationContext context,
    required List<ReminderScheduleOutcome> outcomes,
  }) async =>
      const ReminderScheduleOutcomeResult(
        evidenceUpdated: 1,
        evidenceIgnored: 0,
        inserted: 1,
        duplicate: 0,
        expired: 0,
        warning: null,
      );

  @override
  Future<ReminderPlanState> loadPlanState({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      ReminderPlanState(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
        baselineCompleted: true,
        baselinedSources: const {'courseWork', 'exam'},
        knownAssignmentIds: const {},
        sentNewAssignmentIds: const {},
        lastAttemptAt: null,
        lastFullSuccessAt: null,
        pendingUpdate: false,
        mutationVersion: _mutationVersion,
      );

  @override
  Future<ReminderPlanApplyResult> applyPlan({
    required String accountHash,
    required int sessionEpoch,
    required AssignmentReminderPlan plan,
    required DateTime completedAt,
    required String? failure,
    required bool syncCompleted,
    required int expectedMutationVersion,
  }) async {
    appliedPlans.add(plan);
    return const ReminderPlanApplyResult(
      scheduledDeadlineCount: 0,
      pendingNewCount: 0,
      warning: null,
    );
  }

  @override
  Future<void> cancelAssignmentDeliveryKeepEvents(String accountHash) async {}

  @override
  Future<bool> acquireWriteLease(String owner) async => true;

  @override
  Future<void> releaseWriteLease(String owner) async {}
}

void main() {
  final now = DateTime.utc(2026, 11, 22, 10, 0);

  Assignment makeExam({
    required String id,
    required String title,
    String courseName = '2026全国大学生AI答题实践竞赛',
    String? courseId,
    String? clazzId,
    String status = 'unknown',
    String lifecycle = 'ended',
    bool noticeOnly = false,
    DateTime? startAt,
    DateTime? endAt,
    bool startTrusted = false,
    bool endTrusted = false,
    String? relatedExamId,
  }) =>
      Assignment(
        id: id,
        source: AssignmentSource.exam,
        courseName: courseName,
        title: title,
        deadlineAt: startAt,
        deadlineTrusted: startTrusted,
        requirementsText: '',
        status: status,
        lastSyncedAt: now,
        exam: ExamInfo(
          examId: id.split(':').last,
          relatedExamId: relatedExamId,
          courseId: courseId,
          clazzId: clazzId,
          startAt: startAt,
          endAt: endAt,
          startTrusted: startTrusted,
          endTrusted: endTrusted,
          lifecycle: lifecycle,
          noticeOnly: noticeOnly,
        ),
      );

  group('P1-19 + FB-007: AssignmentStatistics exam & course attention', () {
    test('cancelled and ended exams are never classified as pending or expired',
        () {
      final cancelledPending = makeExam(
        id: 'cx:exam:10:20:c1',
        title: '已取消期中考试',
        courseName: '大学物理',
        courseId: '10',
        clazzId: '20',
        status: 'pending',
        lifecycle: 'cancelled',
        startAt: now.add(const Duration(days: 2)),
        startTrusted: true,
      );
      final endedPendingPast = makeExam(
        id: 'cx:exam:10:20:e1',
        title: '已结束未交卷考试',
        courseName: '大学物理',
        courseId: '10',
        clazzId: '20',
        status: 'pending',
        lifecycle: 'ended',
        startAt: now.subtract(const Duration(days: 3)),
        endAt: now.subtract(const Duration(days: 2)),
        startTrusted: true,
        endTrusted: true,
      );
      final endedByClock = makeExam(
        id: 'cx:exam:10:20:e2',
        title: '按结束时间已结束考试',
        courseName: '大学物理',
        courseId: '10',
        clazzId: '20',
        status: 'pending',
        lifecycle: 'inProgress',
        startAt: now.subtract(const Duration(hours: 3)),
        endAt: now.subtract(const Duration(minutes: 5)),
        startTrusted: true,
        endTrusted: true,
      );
      final submittedEnded = makeExam(
        id: 'cx:exam:10:20:s1',
        title: '已交卷期末考',
        courseName: '大学物理',
        courseId: '10',
        clazzId: '20',
        status: 'submitted',
        lifecycle: 'ended',
        startAt: now.subtract(const Duration(days: 5)),
        endAt: now.subtract(const Duration(days: 5)),
        startTrusted: true,
        endTrusted: true,
      );
      final inProgressExam = makeExam(
        id: 'cx:exam:10:20:p1',
        title: '进行中正式考试',
        courseName: '大学物理',
        courseId: '10',
        clazzId: '20',
        status: 'pending',
        lifecycle: 'inProgress',
        startAt: now.subtract(const Duration(minutes: 20)),
        endAt: now.add(const Duration(minutes: 70)),
        startTrusted: true,
        endTrusted: true,
      );

      expect(AssignmentStatistics.classify(cancelledPending, now),
          AssignmentStatBucket.unknown);
      expect(AssignmentStatistics.classify(endedPendingPast, now),
          AssignmentStatBucket.unknown);
      expect(AssignmentStatistics.classify(endedByClock, now),
          AssignmentStatBucket.unknown);
      expect(AssignmentStatistics.classify(submittedEnded, now),
          AssignmentStatBucket.completed);
      expect(AssignmentStatistics.classify(inProgressExam, now),
          AssignmentStatBucket.pending);
    });

    testWidgets(
        'StatsScreen excludes ended competition & noticeOnly account exam from pending courses and labels active unknown as 待核对',
        (tester) async {
      final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService(),
      );
      addTearDown(store.dispose);

      final endedCompetition = makeExam(
        id: 'cx:exam:77:88:comp1',
        title: 'AI 实践决赛',
        courseName: '2026全国大学生AI答题实践竞赛',
        courseId: '77',
        clazzId: '88',
        status: 'unknown',
        lifecycle: 'ended',
      );
      final accountNotice = makeExam(
        id: 'cx:examNotice:account:n1',
        title: '校级竞赛通知',
        courseName: '账号考试',
        status: 'unknown',
        lifecycle: 'unknown',
        noticeOnly: true,
      );
      final activeUnknownWork = Assignment(
        id: 'cx:work:10:20:u1',
        courseName: '信息安全基础',
        title: '状态待确认作业',
        deadlineAt: now.add(const Duration(days: 2)),
        requirementsText: '',
        status: 'unknown',
        lastSyncedAt: now,
      );

      store.replaceAssignmentsForTest([
        endedCompetition,
        accountNotice,
        activeUnknownWork,
      ]);

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store, clock: () => now)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('2026全国大学生AI答题实践竞赛'), findsNothing);
      expect(find.text('账号考试'), findsNothing);
      expect(find.text('信息安全基础'), findsOneWidget);
      expect(find.text('待核对 1'), findsOneWidget);
      expect(find.text('未知 1'), findsNothing);
    });

    testWidgets(
        'LocalRecordsScreen renders AssignmentCard.examStateLabel for ended and cancelled exams',
        (tester) async {
      final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService(),
      );
      addTearDown(store.dispose);

      final endedExam = makeExam(
        id: 'cx:exam:77:88:comp1',
        title: 'AI 实践决赛',
        courseName: '2026全国大学生AI答题实践竞赛',
        courseId: '77',
        clazzId: '88',
        status: 'unknown',
        lifecycle: 'ended',
      );
      final cancelledExam = makeExam(
        id: 'cx:exam:10:20:c1',
        title: '已取消测验',
        courseName: '高等数学',
        courseId: '10',
        clazzId: '20',
        status: 'pending',
        lifecycle: 'cancelled',
        startAt: now.subtract(const Duration(days: 1)),
        startTrusted: true,
      );
      store.replaceAssignmentsForTest([endedExam, cancelledExam]);

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: LocalRecordsScreen(
          store: store,
          initialFilter: const LocalRecordFilterSpec(
            scope: LocalRecordScopeFilter.allLocal,
          ),
          clock: () => now,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('考试 · 已结束'), findsOneWidget);
      expect(find.text('考试 · 已取消 · 待完成'), findsOneWidget);
      // Only the top status filter chip says "已逾期", never a cancelled exam badge.
      expect(find.text('已逾期'), findsOneWidget);
    });
  });

  group('FB-008: StatsScreen quick unfollow / hide with undo', () {
    testWidgets(
        'long-press course row offers unfollow with undo and restores on undo',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final store = f.makeStore(f.Session());
      addTearDown(store.dispose);
      await store.restoreSession();
      final overdueWork = Assignment(
        id: 'cx:work:55:66:old1',
        courseName: '线性代数',
        title: '第一章习题',
        deadlineAt: now.subtract(const Duration(days: 3)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      await store.repository.mergeAndSave([overdueWork]);
      await store.refreshAssignments();

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store, clock: () => now)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('线性代数'), findsOneWidget);
      expect(store.follows('55:66'), isTrue);

      await tester.longPress(find.byKey(const ValueKey('stats-course-55:66')));
      await tester.pumpAndSettle();

      expect(find.text('查看该课全部记录'), findsOneWidget);
      expect(find.text('取消关注（移出统计）'), findsOneWidget);

      await tester.tap(find.text('取消关注（移出统计）'));
      await tester.pumpAndSettle();

      expect(store.follows('55:66'), isFalse);
      expect(find.text('线性代数'), findsNothing);
      expect(find.text('撤销'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(store.follows('55:66'), isTrue);
      expect(find.text('线性代数'), findsOneWidget);
    });

    testWidgets('left swipe on course row unfollows immediately with undo',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final store = f.makeStore(f.Session());
      addTearDown(store.dispose);
      await store.restoreSession();
      final overdueWork = Assignment(
        id: 'cx:work:55:66:old2',
        courseName: '中国近现代史纲要',
        title: '思考题',
        deadlineAt: now.subtract(const Duration(days: 5)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      await store.repository.mergeAndSave([overdueWork]);
      await store.refreshAssignments();

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store, clock: () => now)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('中国近现代史纲要'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('stats-course-55:66')),
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();

      expect(store.follows('55:66'), isFalse);
      expect(find.text('中国近现代史纲要'), findsNothing);
      expect(find.text('撤销'), findsOneWidget);
    });

    testWidgets(
        'long-press active account exam row offers local hide with undo',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final store = f.makeStore(f.Session());
      addTearDown(store.dispose);
      await store.restoreSession();
      final accExam = makeExam(
        id: 'cx:exam:account:account:991',
        title: '校级测试考试',
        courseName: '账号考试',
        status: 'pending',
        lifecycle: 'scheduled',
        startAt: now.add(const Duration(days: 3)),
        startTrusted: true,
      );
      await store.repository.mergeAndSave([accExam]);
      await store.refreshAssignments();

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store, clock: () => now)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('stats-course-accountExam')),
          findsOneWidget);
      await tester
          .longPress(find.byKey(const ValueKey('stats-course-accountExam')));
      await tester.pumpAndSettle();

      expect(find.text('本机隐藏本组待处理'), findsOneWidget);
      await tester.tap(find.text('本机隐藏本组待处理'));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('stats-course-accountExam')), findsNothing);
      expect(find.text('撤销'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('stats-course-accountExam')),
          findsOneWidget);
    });
  });

  group('P1-20: hidden coursework group suppresses sibling notice reminders',
      () {
    test(
        'hiding formal exam hides all sibling sources in hiddenCourseworkGroups from reminder planner',
        () async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final gateway = _CapturingGateway();
      final store = AssignmentStore(
        sessionStore: f.Session(),
        notificationService: _MigratedNotifications(),
        widgetSnapshotService: f.WidgetService(),
        chaoxingClient: f.Client(),
        backgroundReminderGateway: gateway,
        nativeReminderDeliveryEnabled: true,
      );
      addTearDown(store.dispose);
      await store.restoreSession();

      final formalExam = makeExam(
        id: 'cx:exam:10:20:500',
        title: '期中考试',
        courseName: '软件工程',
        courseId: '10',
        clazzId: '20',
        status: 'pending',
        lifecycle: 'scheduled',
        startAt: now.add(const Duration(hours: 6)),
        startTrusted: true,
      );
      final siblingNotice = makeExam(
        id: 'cx:examNotice:inbox:500',
        relatedExamId: '500',
        title: '期中考试通知',
        courseName: '软件工程',
        courseId: '10',
        clazzId: '20',
        status: 'unknown',
        lifecycle: 'scheduled',
        noticeOnly: true,
        startAt: now.add(const Duration(hours: 6)),
        startTrusted: true,
      );

      await store.repository.mergeAndSave([formalExam, siblingNotice]);
      await store.refreshAssignments();
      // Hide ONLY the formal exam ID (simulating sibling notice remaining
      // unhidden individually while belonging to the same hidden group).
      await store.hideAssignment(formalExam.id);

      expect(store.hiddenCourseworkGroups, hasLength(1));
      expect(store.hiddenCourseworkGroups.single.sources, hasLength(2));

      expect(gateway.appliedPlans, isNotEmpty);
      final lastSnapshots = gateway.appliedPlans.last.snapshots;
      final noticeSnap = lastSnapshots
          .where((s) => s.assignment.id == siblingNotice.id)
          .firstOrNull;
      expect(noticeSnap, isNotNull);
      expect(noticeSnap!.hidden, isTrue);
    });
  });

  group('P1-23: HTML numeric entity out-of-range codePoint guard', () {
    test('malformed hex and decimal HTML entities do not throw RangeError', () {
      const html = '''
        <ul>
          <li class="work-item" data="https://mooc1.chaoxing.com/work/doHomeWorkNew?courseId=10&classId=20&workId=99">
            <a href="https://mooc1.chaoxing.com/work/doHomeWorkNew?courseId=10&classId=20&workId=99">实验&#x110000;与&#0;及&#999999999;合法&#x41;&#66;</a>
            <span class="status">未交</span>
          </li>
        </ul>
      ''';
      final items = ChaoxingAssignmentParser.parseWorkHtml(
        html,
        fallbackCourseName: '编译原理',
        sourcePrefix: 'cx:work:10:20',
        baseUri: Uri.parse('https://mooc1.chaoxing.com/work/list'),
        now: now,
      );
      expect(items, hasLength(1));
      expect(
        items.single.title,
        '实验&#x110000;与&#0;及&#999999999;合法AB',
      );
    });
  });
}
