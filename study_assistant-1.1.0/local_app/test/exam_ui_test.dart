import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

final _now = DateTime.utc(2026, 11, 16, 0);

Assignment _exam(
  String id, {
  DateTime? start,
  DateTime? end,
  bool trusted = true,
  int? durationMinutes = 90,
  bool notice = false,
  bool global = false,
  String lifecycle = 'scheduled',
  String status = 'pending',
  String title = '期末考试',
  String location = '教学楼 A301',
}) =>
    Assignment(
      id: notice
          ? 'cx:examNotice:inbox:$id'
          : 'cx:exam:${global ? 'account:account' : 'c:k'}:$id',
      source: AssignmentSource.exam,
      exam: ExamInfo(
        examId: id,
        durationMinutes: durationMinutes,
        courseId: notice || global ? null : 'c',
        clazzId: notice || global ? null : 'k',
        startAt: start,
        endAt: end,
        startTrusted: trusted && start != null,
        endTrusted: trusted && end != null,
        location: location,
        lifecycle: lifecycle,
        noticeOnly: notice,
      ),
      courseName: notice ? '考试通知' : '高等数学',
      title: title,
      // Deliberately different: UI and queries must use the opening time.
      deadlineAt: end,
      requirementsText: '',
      status: status,
      lastSyncedAt: _now,
    );

Assignment _task(String id, {int? activityType}) => Assignment(
      id: activityType == null ? 'cx:work:c:k:$id' : 'cx:activity:c:k:$id',
      activityType: activityType,
      courseName: '高等数学',
      title: activityType == null ? '课后作业' : '课程任务',
      deadlineAt: _now.add(const Duration(days: 2)),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: _now,
    );

class _Store extends AssignmentStore {
  _Store()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    homeFilters = HomeFilters.decode(next.encode());
    notifyListeners();
    return true;
  }

  void notify() => notifyListeners();
}

Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('zh_CN'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'type preferences persist while old or unknown types preserve other filters',
      () async {
    final repository = LocalAssignmentRepository();
    await repository.activateAccount('exam-ui-test');
    const filters = HomeFilters(
      query: '考试',
      courseKey: 'c:k',
      type: AssignmentTypeFilter.examNotice,
      sortOrder: HomeSortOrder.title,
    );
    await repository.saveHomeFilters(filters, 'exam-ui-test');
    final restored = await repository.loadHomeFilters();
    expect(restored.type, AssignmentTypeFilter.exam);
    expect(restored.query, '考试');
    expect(restored.courseKey, 'c:k');
    expect(restored.sortOrder, HomeSortOrder.deadlineAsc);
    for (final raw in [
      '{"query":"旧搜索","courseKey":"c:k","deadline":"all","sortOrder":"title"}',
      '{"query":"旧搜索","courseKey":"c:k","deadline":"all","sortOrder":"title","type":"futureType"}',
    ]) {
      final decoded = HomeFilters.decode(raw);
      expect(decoded.type, AssignmentTypeFilter.all);
      expect(decoded.query, '旧搜索');
      expect(decoded.courseKey, 'c:k');
      expect(decoded.sortOrder, HomeSortOrder.deadlineAsc);
    }
  });

  test(
      'four visible types group notices as exams and global exams survive followed-course scope',
      () {
    final homework = _task('work');
    final task = _task('task', activityType: 35);
    final quiz = _task('quiz', activityType: 42);
    final ai = _task('ai', activityType: 77);
    final exam = _exam('exam', global: true);
    final notice = _exam('notice', notice: true);
    final records = [homework, task, quiz, ai, exam, notice];
    final expected = {
      AssignmentTypeFilter.all: records,
      AssignmentTypeFilter.homework: [homework, task, quiz, ai],
      AssignmentTypeFilter.task: [task, quiz, ai],
      AssignmentTypeFilter.exam: [exam, notice],
      AssignmentTypeFilter.examNotice: [notice],
    };
    for (final entry in expected.entries) {
      expect(
          AssignmentQuery.filterHome(records,
              type: entry.key, followed: {'c:k'}, now: _now),
          entry.value);
    }
    expect(AssignmentQuery.scope([exam, notice, homework], {'another:class'}),
        [exam, notice]);
    expect(AssignmentQuery.filterHome(records, courseKey: 'c:k', now: _now),
        [homework, task, quiz, ai]);
    expect(AssignmentQuery.filterHome(records, query: '期末', now: _now),
        [exam, notice]);
  });

  test('exam sorting range filters and calendar use Beijing opening date', () {
    final exam = _exam('start-first',
        start: _now.add(const Duration(hours: 1)),
        end: _now.add(const Duration(days: 9)));
    final task = _task('later');
    expect(
        AssignmentQuery.sortHome([task, exam], HomeSortOrder.deadlineAsc,
            now: _now),
        [exam, task]);
    expect(
        AssignmentQuery.filterHome([exam],
            now: _now, deadline: AssignmentDeadlineFilter.next7Days),
        [exam]);
    expect(
        AssignmentQuery.forDay([exam], DateTime(2026, 11, 16), {}, now: _now),
        [exam]);
    expect(
        AssignmentQuery.forDay([exam], DateTime(2026, 11, 25), {}, now: _now),
        isEmpty);
    final midnight =
        _exam('beijing-midnight', start: DateTime.utc(2026, 11, 16, 16, 1));
    expect(
        AssignmentQuery.forDay([midnight], DateTime(2026, 11, 17), {},
            now: _now),
        [midnight]);
  });

  test('ended exits current display while untrusted time remains searchable',
      () {
    final ended = _exam('ended',
        lifecycle: 'ended',
        status: 'unknown',
        start: _now.subtract(const Duration(hours: 2)),
        end: _now.subtract(const Duration(hours: 1)));
    final untrusted = _exam('untrusted',
        trusted: false,
        status: 'unknown',
        start: _now.add(const Duration(hours: 1)));
    final submitted = _exam('submitted', status: 'submitted', start: _now);
    final cancelled = _exam('cancelled',
        lifecycle: 'cancelled', start: _now.add(const Duration(days: 1)));
    expect(AssignmentQuery.filterHome([ended, untrusted, submitted], now: _now),
        [untrusted]);
    expect(AssignmentQuery.home([ended], _now, {}).uncertain, isEmpty);
    expect(AssignmentQuery.home([ended], _now, {}).overdue, isEmpty);
    expect(
        AssignmentQuery.forDay(
            [ended, untrusted, submitted], DateTime(2026, 11, 16), {},
            now: _now),
        isEmpty);
    expect(
        AssignmentRecoveryScope.deadlinePending.matches(ended, _now), isFalse);
    expect(
        AssignmentRecoveryScope.examUnknown.matches(untrusted, _now), isTrue);
    expect(
        AssignmentQuery.filterHome([cancelled],
            now: _now, deadline: AssignmentDeadlineFilter.next7Days),
        isEmpty);
    expect(AssignmentQuery.filterHome([untrusted], now: _now, query: '期末'),
        [untrusted]);
  });

  test('ended exams leave home without changing personal submission', () {
    final records = [
      for (final status in [
        'unknown',
        'completed',
        'reviewing',
        'graded',
        'submitted'
      ])
        _exam('personal-$status',
            lifecycle: 'ended',
            status: status,
            start: _now.subtract(const Duration(hours: 2)),
            end: _now.subtract(const Duration(hours: 1))),
    ];
    for (final record in records) {
      expect(record.hasExamIdentity, isTrue,
          reason: 'Fixture ID must match its ExamInfo identity: ${record.id}');
      expect(record.isInAssignmentScope, isTrue);
    }
    expect(records.where((a) => a.isCompleted).map((a) => a.status),
        ['submitted']);
    expect(AssignmentQuery.filterHome(records, now: _now), isEmpty);
  });

  testWidgets(
      'exam card uses opening rail with location and separate submission at narrow large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final exam = _exam('card',
        title: '期末综合实践与课程项目复盘考试',
        start: _now.add(const Duration(hours: 1)),
        end: _now.add(const Duration(hours: 3)),
        location: '第一教学楼三楼 A301 多媒体教室');
    var details = 0, opens = 0;
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [
        AssignmentCard(
            assignment: exam,
            now: _now,
            showFullDeadline: false,
            countdown: true,
            onTap: () => details++,
            onOpenAssignment: () => opens++),
      ])),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('开考 2026年11月16日 09:00'), findsNothing);
    expect(find.text('结束 2026年11月16日 11:00'), findsNothing);
    expect(find.text('地点 第一教学楼三楼 A301 多媒体教室'), findsOneWidget);
    expect(find.text('考试 · 未开始 · 待参加'), findsOneWidget);
    expect(find.textContaining('今天截止'), findsNothing);
    final openExam = find.byTooltip('在学习通内查看考试');
    await tester.ensureVisible(openExam);
    await tester.tap(openExam);
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(details, 0);
    await _tap(tester, exam.title);
    expect(details, 1);
  });

  testWidgets('a standalone exam card shows both dates for an overnight exam',
      (tester) async {
    final exam = _exam('standalone',
        start: DateTime.utc(2026, 11, 16, 14),
        end: DateTime.utc(2026, 11, 17, 2));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentCard(
          assignment: exam,
          now: _now,
          showFullDeadline: false,
          inPinnedSection: true,
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('开考 2026年11月16日 22:00'), findsOneWidget);
    expect(find.text('结束 2026年11月17日 10:00'), findsOneWidget);
  });

  testWidgets('standalone exam card marks the inferred overnight end',
      (tester) async {
    final exam = _exam('estimated',
        start: DateTime.utc(2026, 11, 30, 15, 30), durationMinutes: 90);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentCard(
          assignment: exam,
          now: _now,
          showFullDeadline: false,
          inPinnedSection: true,
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('开考 2026年11月30日 23:30'), findsOneWidget);
    expect(find.text('结束（按时长推算） 2026年12月1日 01:00'), findsOneWidget);
    expect(exam.exam!.endAt, isNull);
  });

  testWidgets('ended and unconfirmed notice cards keep factual unknown states',
      (tester) async {
    final ended = _exam('ended-card',
        lifecycle: 'ended',
        status: 'unknown',
        start: _now.subtract(const Duration(hours: 2)),
        end: _now.subtract(const Duration(hours: 1)));
    final notice =
        _exam('notice-card', notice: true, status: 'unknown', location: '');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      AssignmentCard(assignment: ended, now: _now, onTap: () {}),
      AssignmentCard(
          assignment: notice, now: _now, onTap: () {}, onOpenAssignment: () {}),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('考试 · 已结束'), findsOneWidget);
    expect(find.text('已完成'), findsNothing);
    expect(find.text('开考时间待确认'), findsNothing);
    expect(find.text('结束时间待确认'), findsNothing);
    expect(find.text('地点 通知未提供实体考场'), findsNothing);
    expect(find.byTooltip('在学习通内查看考试通知'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home type filter edits preserve type until explicitly cleared',
      (tester) async {
    final store = _Store()
      ..replaceAssignmentsForTest([
        _task('home-work'),
        _exam('home-notice', notice: true),
      ]);
    addTearDown(store.dispose);
    expect(store.visibleAssignments.map((a) => a.id),
        contains('cx:examNotice:inbox:home-notice'));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))));
    await _tap(tester, '搜索与筛选');
    for (final type in homeTypeFilterChoices) {
      expect(find.byKey(ValueKey('type-${type.name}')), findsOneWidget);
    }
    final noticeType = find.byKey(const ValueKey('type-exam'));
    await tester.ensureVisible(noticeType);
    await tester.tap(noticeType);
    await tester.pumpAndSettle();
    await _tap(tester, '应用');
    expect(store.homeFilters.type, AssignmentTypeFilter.exam);
    expect(find.textContaining('考试时间未知'), findsNothing);
    expect(find.text('期末考试'), findsOneWidget);
    expect(find.text('课后作业'), findsNothing);
    await _tap(tester, '搜索与筛选 (1)');
    await _tap(tester, '按课程');
    await _tap(tester, '应用');
    expect(store.homeFilters.type, AssignmentTypeFilter.exam);
    expect(store.homeFilters.sortOrder, HomeSortOrder.courseName);
    await _tap(tester, '搜索与筛选 (1)');
    await tester.tap(find.byKey(const ValueKey('home-filter-sheet-clear')));
    await tester.pumpAndSettle();
    await _tap(tester, '应用');
    expect(store.homeFilters.type, AssignmentTypeFilter.all);
    expect(store.homeFilters.sortOrder, HomeSortOrder.courseName);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('calendar places notice at opening rather than ending',
      (tester) async {
    final today = DateTime.now();
    var anchor = DateTime(today.year, today.month, today.day + 2);
    if (anchor.day < today.day ||
        anchor.add(const Duration(days: 1)).month != anchor.month) {
      anchor = DateTime(today.year, today.month + 1, 5);
    }
    final opening = anchor.add(const Duration(hours: 1));
    final ending = anchor.add(const Duration(days: 1));
    final store = _Store()
      ..replaceAssignmentsForTest([
        _exam('calendar-notice',
            notice: true, status: 'unknown', start: opening, end: ending),
      ]);
    addTearDown(store.dispose);
    expect(store.visibleAssignments.single.hasExamIdentity, isTrue);
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: CalendarScreen(store: store, clock: () => anchor))));
    await tester.pumpAndSettle();
    expect(find.text('期末考试'), findsOneWidget);
    expect(
        find.text(DateFormat('HH:mm').format(AssignmentQuery.beijing(opening))),
        findsOneWidget);
    await tester.tap(find.text('${ending.day}'));
    await tester.pumpAndSettle();
    expect(find.text('期末考试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail exposes schedule location and ended unknown separately',
      (tester) async {
    final exam = _exam('detail',
        lifecycle: 'ended',
        status: 'unknown',
        start: _now.subtract(const Duration(hours: 2)),
        end: _now.subtract(const Duration(hours: 1)));
    final store = _Store()..replaceAssignmentsForTest([exam]);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                AssignmentDetailScreen(store: store, assignmentId: exam.id))));
    await tester.pumpAndSettle();
    expect(find.textContaining('开考 2026年11月16日 06:00'), findsOneWidget);
    expect(find.textContaining('地点 教学楼 A301'), findsOneWidget);
    expect(find.text('考试 · 已结束'), findsOneWidget);
    expect(find.text('部分信息尚未核实'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync source names include course account and notice exams',
      (tester) async {
    final store = _Store()
      ..syncReport = const SyncReport(sourceResults: [
        SyncSourceResult(source: 'exam', phase: SyncSourcePhase.success),
        SyncSourceResult(source: 'examAccount', phase: SyncSourcePhase.success),
        SyncSourceResult(source: 'examNotice', phase: SyncSourcePhase.success),
      ]);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
    await _tap(tester, '读取来源');
    expect(find.text('课程考试'), findsOneWidget);
    expect(find.text('账号考试'), findsOneWidget);
    expect(find.text('考试通知'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Phase 5A upcoming exam strip covers 14-day boundaries, exclusions, toggle/return and zero placeholder at 360dp',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime.utc(2026, 11, 16, 2); // Beijing 10:00
    final day14Plus1Min = _exam('too-far',
        start: now.add(const Duration(days: 14, minutes: 1)),
        end: now.add(const Duration(days: 14, hours: 2)),
        title: '第15天超窗考试');
    final pastExam = _exam('past',
        start: now.subtract(const Duration(minutes: 1)),
        end: now.add(const Duration(hours: 2)),
        title: '已开考中考试');
    final endedExam = _exam('ended',
        lifecycle: 'ended',
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 1, hours: 2)),
        title: '已结束考试');
    final cancelledExam = _exam('cancelled',
        lifecycle: 'cancelled',
        start: now.add(const Duration(days: 2)),
        end: now.add(const Duration(days: 2, hours: 2)),
        title: '已取消考试');
    final untrustedExam = _exam('untrusted',
        trusted: false,
        start: now.add(const Duration(days: 2)),
        title: '未核实考试');
    final noticeOnlyExam = _exam('notice-only',
        notice: true,
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 1, hours: 2)),
        title: '纯通知考试');
    final completedExam = _exam('completed',
        status: 'submitted',
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 1, hours: 2)),
        title: '已完成考试');

    final store = _Store()
      ..replaceAssignmentsForTest([
        _task('work-1'),
        day14Plus1Min,
        pastExam,
        endedExam,
        cancelledExam,
        untrustedExam,
        noticeOnlyExam,
        completedExam,
      ]);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home:
          Scaffold(body: AssignmentListScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('home-upcoming-exam-strip')), findsNothing);
    final baselineActionsTop = tester.getTopLeft(find.text('搜索与筛选')).dy;

    final exactDay14 = _exam('boundary-14',
        start: now.add(const Duration(days: 14)),
        end: now.add(const Duration(days: 14, hours: 2)),
        title: '第十四天边界期末综合测评考试');
    store.replaceAssignmentsForTest(
        [_task('work-1'), day14Plus1Min, exactDay14]);
    store.notify();
    await tester.pumpAndSettle();

    final stripFinder = find.byKey(const ValueKey('home-upcoming-exam-strip'));
    expect(stripFinder, findsOneWidget);
    expect(find.text('近期考试 · 《第十四天边界期末综合测评考试》14 天后'), findsOneWidget);
    expect(tester.getTopLeft(find.text('搜索与筛选')).dy,
        greaterThan(baselineActionsTop));
    expect(tester.takeException(), isNull);

    // Same-day and nearer 3-day exams beat day-14 exam.
    final day3Exam = _exam('day3',
        start: now.add(const Duration(days: 3)),
        end: now.add(const Duration(days: 3, hours: 2)),
        title: '离散数学期中测试');
    store.replaceAssignmentsForTest([_task('work-1'), exactDay14, day3Exam]);
    store.notify();
    await tester.pumpAndSettle();
    expect(find.text('近期考试 · 《离散数学期中测试》3 天后'), findsOneWidget);

    final sameDayExam = _exam('today',
        start: now.add(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 3)),
        title: '数据结构上机考试');
    store.replaceAssignmentsForTest([_task('work-1'), day3Exam, sameDayExam]);
    store.notify();
    await tester.pumpAndSettle();
    expect(find.text('近期考试 · 《数据结构上机考试》今天'), findsOneWidget);

    // Tap enters exam filter view; tap again returns to previous filters.
    await tester.tap(stripFinder);
    await tester.pumpAndSettle();
    expect(store.homeFilters.type, AssignmentTypeFilter.exam);
    expect(find.text('返回'), findsOneWidget);
    expect(find.text('课后作业'), findsNothing);
    expect(find.text('数据结构上机考试'), findsOneWidget);

    await tester.tap(stripFinder);
    await tester.pumpAndSettle();
    expect(store.homeFilters.type, AssignmentTypeFilter.all);
    expect(find.text('课后作业'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
