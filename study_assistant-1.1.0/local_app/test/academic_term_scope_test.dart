import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/course_term_preferences.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_scope.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

DateTime _beijing(int year, int month, int day,
        [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour - 8, minute);

Assignment _work(
  String id, {
  DateTime? deadlineAt,
  DateTime? publishedAt,
  DateTime? availableFromAt,
  bool deadlineTrusted = true,
  bool deadlineReadFailed = false,
  String status = 'pending',
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: '合成课程',
      title: id,
      deadlineAt: deadlineAt,
      publishedAt: publishedAt,
      availableFromAt: availableFromAt,
      deadlineTrusted: deadlineTrusted,
      deadlineReadFailed: deadlineReadFailed,
      requirementsText: '',
      status: status,
      lastSyncedAt: deadlineAt ?? DateTime.utc(2026),
    );

Assignment _exam(
  String id, {
  DateTime? startAt,
  DateTime? endAt,
  bool startTrusted = true,
  bool endTrusted = true,
  String lifecycle = 'scheduled',
  String status = 'pending',
}) =>
    Assignment(
      id: 'cx:exam:1:2:$id',
      source: AssignmentSource.exam,
      courseName: '合成课程',
      title: id,
      deadlineAt: endAt,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.utc(2026),
      exam: ExamInfo(
        examId: id,
        courseId: '1',
        clazzId: '2',
        startAt: startAt,
        endAt: endAt,
        startTrusted: startTrusted,
        endTrusted: endTrusted,
        lifecycle: lifecycle,
      ),
    );

void main() {
  test('Beijing semester switches exactly at March and September first', () {
    expect(
        AssignmentQuery.semesterStartAt(_beijing(2026, 2, 28, 23, 59)).toUtc(),
        _beijing(2025, 9, 1));
    expect(AssignmentQuery.semesterStartAt(_beijing(2026, 3, 1)).toUtc(),
        _beijing(2026, 3, 1));
    expect(
        AssignmentQuery.semesterStartAt(_beijing(2026, 8, 31, 23, 59)).toUtc(),
        _beijing(2026, 3, 1));
    expect(AssignmentQuery.semesterStartAt(_beijing(2026, 9, 1)).toUtc(),
        _beijing(2026, 9, 1));
  });

  test('newly published work stays current within the inclusive 30 days', () {
    final now = _beijing(2026, 9, 5, 12);
    final edge = _work(
      'edge',
      deadlineAt: _beijing(2026, 7, 1),
      publishedAt: now.subtract(const Duration(days: 30)),
    );
    final tooOld = _work(
      'too-old',
      deadlineAt: _beijing(2026, 7, 1),
      publishedAt: now.subtract(const Duration(days: 30, minutes: 1)),
    );
    expect(AssignmentQuery.isArchivedPastTerm(edge, now), isFalse);
    expect(AssignmentQuery.isArchivedPastTerm(tooOld, now), isTrue);
  });

  test('confirmed no-deadline work follows a trusted current-term start', () {
    final now = _beijing(2026, 10, 5, 12);
    final current = _work(
      'current',
      availableFromAt: _beijing(2026, 9, 2),
    );
    final previous = _work(
      'previous',
      availableFromAt: _beijing(2026, 8, 31),
    );
    expect(AssignmentQuery.isArchivedPastTerm(current, now), isFalse);
    expect(AssignmentQuery.isArchivedPastTerm(previous, now), isTrue);
  });

  test('recent no-deadline publication survives the term switch', () {
    final now = _beijing(2026, 9, 1, 0, 1);
    final recent = _work(
      'recent-no-deadline',
      publishedAt: _beijing(2026, 8, 31, 23, 59),
    );
    expect(AssignmentQuery.isArchivedPastTerm(recent, now), isFalse);
  });

  test('past-term deadlines archive while extensions return to the home term',
      () {
    final now = _beijing(2026, 10, 5, 12);
    final overdue = _work('old', deadlineAt: _beijing(2026, 1, 15));
    final extended = _work('extended', deadlineAt: _beijing(2026, 12, 20));
    expect(AssignmentQuery.isArchivedPastTerm(overdue, now), isTrue);
    expect(AssignmentQuery.isArchivedPastTerm(extended, now), isFalse);
    expect(
      AssignmentQuery.isArchivedPastTerm(
        _work(
          'old-deadline-new-start',
          deadlineAt: _beijing(2026, 1, 15),
          availableFromAt: _beijing(2026, 9, 15),
        ),
        now,
      ),
      isTrue,
    );
    expect(
      AssignmentQuery.isArchivedPastTerm(
        _work(
          'recent-extension',
          deadlineAt: _beijing(2026, 1, 15),
          publishedAt: _beijing(2026, 9, 15),
        ),
        now,
      ),
      isFalse,
    );
  });

  test('insufficient or failed time evidence stays pending', () {
    final now = _beijing(2026, 10, 5, 12);
    expect(
      AssignmentQuery.isArchivedPastTerm(
        _work(
          'untrusted',
          deadlineAt: _beijing(2026, 1, 15),
          deadlineTrusted: false,
        ),
        now,
      ),
      isFalse,
    );
    expect(
      AssignmentQuery.isArchivedPastTerm(
        _work(
          'failed',
          deadlineAt: _beijing(2026, 1, 15),
          deadlineReadFailed: true,
        ),
        now,
      ),
      isFalse,
    );
  });

  test('old exams archive by trusted end or unambiguous start only', () {
    final now = _beijing(2026, 11, 19, 12);
    final ended = _exam(
      'ended',
      startAt: _beijing(2026, 6, 9, 8),
      endAt: _beijing(2026, 6, 9, 10),
      lifecycle: 'ended',
    );
    final startOnly = _exam(
      'start-only',
      startAt: _beijing(2026, 7, 4, 8),
      endAt: null,
      endTrusted: false,
    );
    final futureEnd = _exam(
      'future-end',
      startAt: _beijing(2026, 8, 31, 8),
      endAt: _beijing(2026, 9, 2, 10),
    );
    final yearless = _exam(
      'yearless',
      startAt: null,
      endAt: null,
      startTrusted: false,
      endTrusted: false,
      lifecycle: 'unknown',
    );
    expect(AssignmentQuery.isArchivedPastTerm(ended, now), isTrue);
    expect(AssignmentQuery.isArchivedPastTerm(startOnly, now), isTrue);
    expect(AssignmentQuery.isArchivedPastTerm(futureEnd, now), isFalse);
    expect(AssignmentQuery.isArchivedPastTerm(yearless, now), isFalse);
  });

  test('home calendar recovery and reminders share the archive decision', () {
    final now = _beijing(2026, 11, 19, 12);
    final old = _work('old', deadlineAt: _beijing(2026, 1, 15));
    final current = _work('current', deadlineAt: _beijing(2026, 12, 15));
    final records = [old, current];

    expect(AssignmentQuery.currentDisplay(records, now), [current]);
    expect(AssignmentQuery.filterHome(records, now: now), [current]);
    expect(AssignmentQuery.home(records, now, {}).overdue, isEmpty);
    expect(AssignmentQuery.isCalendarDated(old, now), isFalse);
    expect(
      AssignmentQuery.forDay(records, DateTime(2026, 1, 15), {}, now: now),
      isEmpty,
    );
    expect(AssignmentRecoveryScope.deadlinePending.matches(old, now), isFalse);
    expect(
      AssignmentReminderSnapshot(
        assignment: old,
        hidden: false,
        followed: true,
      ).eligibleAt(now),
      isFalse,
    );
  });

  group('Phase 3C AcademicTerm & CourseTermCatalog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('resolves Beijing Mar 1 and Sep 1 boundaries across UTC midnight', () {
      expect(
        AcademicTerm.fromInstant(DateTime.utc(2026, 2, 28, 15, 59)),
        const AcademicTerm(2025, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.fromInstant(DateTime.utc(2026, 2, 28, 16, 0)),
        const AcademicTerm(2025, AcademicSemester.spring),
      );
      expect(
        AcademicTerm.fromInstant(DateTime.utc(2026, 8, 31, 15, 59)),
        const AcademicTerm(2025, AcademicSemester.spring),
      );
      expect(
        AcademicTerm.fromInstant(DateTime.utc(2026, 8, 31, 16, 0)),
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      final janTerm = AcademicTerm.fromInstant(DateTime.utc(2026, 1, 10, 4));
      expect(janTerm, const AcademicTerm(2025, AcademicSemester.fall));
      expect(janTerm.academicYearLabel, '2025-2026 学年');
    });

    test(
        'parses anchored academic term folder names and rejects custom or relative-grade labels',
        () {
      expect(
        AcademicTerm.tryParseFolderLabel('2025-2026(1)'),
        const AcademicTerm(2025, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseFolderLabel('2025-2026学年第二学期'),
        const AcademicTerm(2025, AcademicSemester.spring),
      );
      expect(
        AcademicTerm.tryParseFolderLabel('2026年秋季学期'),
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseFolderLabel('2026春'),
        const AcademicTerm(2025, AcademicSemester.spring),
      );

      for (final unverified in const [
        '',
        '专业核心课',
        '大二上学期',
        '大一下',
        '收藏夹',
        '2024-2026(1)',
        '期末冲刺文件夹',
      ]) {
        expect(AcademicTerm.tryParseFolderLabel(unverified), isNull);
      }
    });

    test(
        'enforces attribution precedence manual > folder > activity > ungrouped and ignores untrusted/system notices',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const manualCourse = CourseRef(
        courseId: '1',
        clazzId: '10',
        name: '同名课程',
        folderName: '2025-2026(1)',
      );
      const folderCourse = CourseRef(
        courseId: '1',
        clazzId: '11',
        name: '同名课程',
        folderName: '2025-2026(2)',
      );
      const activityCourse = CourseRef(
        courseId: '2',
        clazzId: '20',
        name: '往期活跃推导课',
        folderName: '自定义归类目录',
      );
      const ungroupedCourse = CourseRef(
        courseId: '3',
        clazzId: '30',
        name: '无证据新课',
        folderName: '大二上学期',
      );

      final catalog = CourseTermCatalog.build(
        courses: const [
          manualCourse,
          folderCourse,
          activityCourse,
          ungroupedCourse,
        ],
        assignments: [
          Assignment(
            id: 'cx:work:2:20:1',
            courseName: '往期活跃推导课',
            title: '旧期中论文',
            publishedAt: DateTime.utc(2025, 10, 10, 4),
            deadlineAt: DateTime.utc(2025, 11, 1, 15, 59),
            requirementsText: '',
            status: 'submitted',
            lastSyncedAt: now,
          ),
          Assignment(
            id: 'cx:work:3:30:1',
            courseName: '无证据新课',
            title: '待确认任务',
            deadlineAt: DateTime.utc(2025, 5, 1),
            deadlineTrusted: false,
            requirementsText: '',
            status: 'unknown',
            lastSyncedAt: now,
          ),
        ],
        notices: [
          CourseNotice(
            id: 'cx:notice:${'1' * 64}',
            courseId: '3',
            clazzId: '30',
            courseName: '无证据新课',
            senderName: '学习通知',
            title: '作业结束提醒',
            publishedAt: DateTime.utc(2025, 4, 1),
            publishedTrusted: true,
            lastSyncedAt: now,
          ),
          CourseNotice(
            id: 'cx:notice:${'2' * 64}',
            courseId: '1',
            clazzId: '11',
            courseName: '同名课程',
            senderName: '学习通知',
            title: '作业:《同名课程》自动汇总',
            publishedAt: now.subtract(const Duration(hours: 2)),
            publishedTrusted: true,
            lastSyncedAt: now,
          ),
        ],
        preferences: CourseTermPreferences().withManualTerm(
          manualCourse.key,
          '2026-fall',
        ),
        now: now,
      );

      final m = catalog.entryFor(manualCourse.key)!;
      expect(m.source, CourseTermSource.manual);
      expect(m.term, const AcademicTerm(2026, AcademicSemester.fall));
      expect(m.state, CourseCatalogState.active);

      final f = catalog.entryFor(folderCourse.key)!;
      expect(f.source, CourseTermSource.folder);
      expect(f.term, const AcademicTerm(2025, AcademicSemester.spring));
      expect(f.state, CourseCatalogState.archived);

      final a = catalog.entryFor(activityCourse.key)!;
      expect(a.source, CourseTermSource.activity);
      expect(a.term, const AcademicTerm(2025, AcademicSemester.fall));
      expect(a.state, CourseCatalogState.archived);

      final u = catalog.entryFor(ungroupedCourse.key)!;
      expect(u.source, CourseTermSource.ungrouped);
      expect(u.term, isNull);
      expect(u.state, CourseCatalogState.active);
    });

    test(
        'recalls past course on genuine future extension or human notice and suppresses repeated recall after cursor dismissal',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const pastCourse = CourseRef(
        courseId: '9',
        clazzId: '90',
        name: '往期选修课',
        folderName: '2025年秋',
      );
      final oldSubmitted = Assignment(
        id: 'cx:work:9:90:1',
        courseName: '往期选修课',
        title: '旧学期作业',
        deadlineAt: DateTime.utc(2025, 11, 20),
        requirementsText: '',
        status: 'submitted',
        lastSyncedAt: now,
      );
      final extendedFuture = Assignment(
        id: 'cx:work:9:90:2',
        courseName: '往期选修课',
        title: '补修重交作业',
        deadlineAt: now.add(const Duration(days: 3)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );

      final recalledCatalog = CourseTermCatalog.build(
        courses: const [pastCourse],
        assignments: [oldSubmitted, extendedFuture],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );
      final entry = recalledCatalog.entryFor(pastCourse.key)!;
      expect(entry.state, CourseCatalogState.recalled);
      expect(
        recalledCatalog.matchesAssignmentInStatsScope(
          extendedFuture,
          CourseTermScope.currentTerm,
        ),
        isTrue,
      );
      expect(
        recalledCatalog.matchesAssignmentInStatsScope(
          oldSubmitted,
          CourseTermScope.currentTerm,
        ),
        isFalse,
      );
      expect(
        recalledCatalog.matchesAssignmentInStatsScope(
          oldSubmitted,
          CourseTermScope.pastTerms,
        ),
        isTrue,
      );

      final dismissedPrefs = CourseTermPreferences().withDismissedRecallCursor(
        pastCourse.key,
        entry.latestRecallEventUtc,
      );
      final dismissedCatalog = CourseTermCatalog.build(
        courses: const [pastCourse],
        assignments: [oldSubmitted, extendedFuture],
        notices: const [],
        preferences: dismissedPrefs,
        now: now,
      );
      expect(
        dismissedCatalog.entryFor(pastCourse.key)!.state,
        CourseCatalogState.archived,
      );

      final newHumanNotice = CourseNotice(
        id: 'cx:notice:${'9' * 64}',
        courseId: '9',
        clazzId: '90',
        courseName: '往期选修课',
        senderName: '张教授',
        title: '补考与缓交安排说明',
        publishedAt: extendedFuture.deadlineAt!.add(const Duration(hours: 1)),
        publishedTrusted: true,
        lastSyncedAt: now,
      );
      final reRecalledCatalog = CourseTermCatalog.build(
        courses: const [pastCourse],
        assignments: [oldSubmitted, extendedFuture],
        notices: [newHumanNotice],
        preferences: dismissedPrefs,
        now: now,
      );
      expect(
        reRecalledCatalog.entryFor(pastCourse.key)!.state,
        CourseCatalogState.recalled,
      );

      final unfollowedCatalog = CourseTermCatalog.build(
        courses: const [pastCourse],
        assignments: [extendedFuture],
        notices: [newHumanNotice],
        preferences: dismissedPrefs,
        unfollowedCourseKeys: {pastCourse.key},
        now: now,
      );
      expect(unfollowedCatalog.entryFor(pastCourse.key)!.isFollowed, isFalse);
      expect(
        unfollowedCatalog.matchesAssignmentInStatsScope(
          extendedFuture,
          CourseTermScope.currentTerm,
        ),
        isFalse,
      );
    });

    test(
        'persists term overrides per account, merges schema 9 without wiping local keys, preserves pins and account exams',
        () async {
      final now = DateTime.utc(2026, 11, 20, 4);
      final repo = LocalAssignmentRepository();
      final session = _TermMemorySession('student-a');
      const currentCourse = CourseRef(
        courseId: '1',
        clazzId: '10',
        name: '在学高数',
        folderName: '2026年秋',
      );
      const pastCourse1 = CourseRef(
        courseId: '2',
        clazzId: '20',
        name: '往期线代',
        folderName: '2025年秋',
      );
      const pastCourse2 = CourseRef(
        courseId: '3',
        clazzId: '30',
        name: '往期大英',
        folderName: '2025-2026(2)',
      );

      final currentWork = Assignment(
        id: 'cx:work:1:10:1',
        courseName: '在学高数',
        title: '本周作业',
        deadlineAt: now.add(const Duration(days: 2)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      final pastWork = Assignment(
        id: 'cx:work:2:20:1',
        courseName: '往期线代',
        title: '去年习题',
        deadlineAt: DateTime.utc(2025, 11, 20),
        requirementsText: '',
        status: 'submitted',
        lastSyncedAt: now,
      );
      final accountExam = Assignment(
        id: 'cx:exam:account:account:500',
        source: AssignmentSource.exam,
        exam: ExamInfo(
          examId: '500',
          startAt: now.add(const Duration(days: 5)),
          endAt: now.add(const Duration(days: 5, hours: 2)),
          startTrusted: true,
          endTrusted: true,
          lifecycle: 'scheduled',
        ),
        courseName: '账号考试',
        title: '全国统考',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );

      await repo.activateAccount('student-a');
      await repo.saveCourses(const [currentCourse, pastCourse1, pastCourse2],
          account: 'student-a');
      await repo.mergeAndSave([currentWork, pastWork, accountExam],
          completeSync: true);

      AssignmentStore makeStore() => AssignmentStore(
            repository: repo,
            sessionStore: session,
            notificationService: _TermNoopNotifications(),
            widgetSnapshotService: _TermNoopWidgets(),
            chaoxingClient: _TermNoopChaoxingClient(),
            clock: () => now,
          );

      final store = makeStore();
      await store.restoreSession();

      expect(await store.togglePin(currentWork), isTrue);
      expect(await store.togglePin(accountExam), isTrue);
      expect(store.visibleAssignments.map((a) => a.id),
          unorderedEquals([currentWork.id, accountExam.id]));
      expect(store.localRecordGroups, hasLength(3));
      expect(store.termCatalog.archivablePastCourseKeys,
          unorderedEquals([pastCourse1.key, pastCourse2.key]));

      expect(
        await store.setCourseManualTerm(
          pastCourse1.key,
          const AcademicTerm(2026, AcademicSemester.fall),
        ),
        isTrue,
      );
      expect(store.isCourseActive(pastCourse1.key), isTrue);
      expect(store.pinnedKeys, containsAll([currentWork.id, accountExam.id]));
      expect(await store.archivePastCourses(), isTrue);
      expect(store.termCatalog.entryFor(pastCourse2.key)!.state,
          CourseCatalogState.archived);
      expect(store.termCatalog.archivablePastCourseKeys, isEmpty);

      final snap = await repo.createBackupSnapshot('student-a');
      expect(
          snap.courseTermPreferences.entryFor(pastCourse1.key)!.manualTermKey,
          '2026-fall');
      expect(snap.courseTermPreferences.entryFor(pastCourse2.key)!.archiveMode,
          CourseArchiveMode.archived);

      await store.setCourseArchiveMode(
          pastCourse2.key, CourseArchiveMode.restored);
      expect(await store.restoreLocalBackup(snap), isTrue);
      expect(
        store.courseTermPreferences.entryFor(pastCourse2.key)!.archiveMode,
        CourseArchiveMode.restored,
      );

      await store.loginChaoxing(
          account: 'student-b', password: 'pw', agreementAccepted: true);
      expect(store.courseTermPreferences.isEmpty, isTrue);
      await store.loginChaoxing(
          account: 'student-a', password: 'pw', agreementAccepted: true);
      expect(
        store.courseTermPreferences.entryFor(pastCourse1.key)!.manualTermKey,
        '2026-fall',
      );
      store.dispose();
    });

    testWidgets(
        'CourseListScreen supports manual term adjustment, archive/restore, and batch archive at 320w@2x',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      final repo = LocalAssignmentRepository();
      final session = _TermMemorySession('student-ui');
      const pastCourse = CourseRef(
        courseId: '2',
        clazzId: '20',
        name: '往期物理课',
        folderName: '2025年秋',
        teacherNames: ['陈教授'],
      );
      const currentCourse = CourseRef(
        courseId: '1',
        clazzId: '10',
        name: '在学算法',
        folderName: '2026年秋',
      );
      await repo.activateAccount('student-ui');
      await repo.saveCourses(const [currentCourse, pastCourse],
          account: 'student-ui');
      final store = AssignmentStore(
        repository: repo,
        sessionStore: session,
        notificationService: _TermNoopNotifications(),
        widgetSnapshotService: _TermNoopWidgets(),
        chaoxingClient: _TermNoopChaoxingClient(),
        manageBackgroundSchedule: false,
        clock: () => now,
      );
      addTearDown(store.dispose);
      await store.restoreSession();

      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: CourseListScreen(store: store, clock: () => now),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('course-list-manage-terms')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('course-list-batch-archive')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('course-list-batch-archive')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('course-list-batch-archive')),
        findsNothing,
      );
      expect(
        store.courseTermPreferences.entryFor(pastCourse.key)!.archiveMode,
        CourseArchiveMode.archived,
      );

      final termBtn = find.byKey(ValueKey('course-term-btn-${pastCourse.key}'));
      await tester.scrollUntilVisible(
        termBtn,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(termBtn);
      await tester.pumpAndSettle();
      await tester.tap(termBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('term-option-2026-fall')));
      await tester.pumpAndSettle();
      expect(
        store.courseTermPreferences.entryFor(pastCourse.key)!.manualTermKey,
        '2026-fall',
      );
      expect(tester.takeException(), isNull);
    });

    test(
        'parses tolerant folder labels with prefixes/suffixes while rejecting relative or ambiguous labels',
        () {
      expect(
        AcademicTerm.tryParseFolderLabel('2025-2026(1) 必修'),
        const AcademicTerm(2025, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseFolderLabel('我的课程/2025-2026(1)'),
        const AcademicTerm(2025, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseFolderLabel('2026年秋季课程'),
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseFolderLabel('大二上(2026秋)'),
        const AcademicTerm(2026, AcademicSemester.fall),
      );

      for (final invalid in const [
        '大二上学期',
        '大一下',
        '专业核心课',
        '期末冲刺文件夹',
        '2024-2026(1)',
        '2025秋 2026春',
      ]) {
        expect(AcademicTerm.tryParseFolderLabel(invalid), isNull,
            reason: invalid);
      }
    });

    test(
        'sync-day published change never decides the base term while syncAllTerms past work stays archived',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const ungrouped = CourseRef(courseId: '101', clazzId: '1', name: '新开选修');
      const pastCourse = CourseRef(
        courseId: '102',
        clazzId: '2',
        name: '往期老课',
        folderName: '2025年秋',
      );
      const farFutureCourse = CourseRef(
        courseId: '103',
        clazzId: '3',
        name: '常年题库课',
        folderName: '2025年秋',
      );
      final newWork = Assignment(
        id: 'cx:work:101:1:1',
        courseName: '新开选修',
        title: '第一次讨论',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      final oldCompletedFromSweep = Assignment(
        id: 'cx:work:102:2:1',
        courseName: '往期老课',
        title: '去年已交作业',
        deadlineAt: DateTime.utc(2025, 11, 1),
        requirementsText: '',
        status: 'submitted',
        lastSyncedAt: now,
      );
      final oldNoDeadlinePendingFromSweep = Assignment(
        id: 'cx:work:102:2:2',
        courseName: '往期老课',
        title: '去年无截止旧题',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      final farFutureWork = Assignment(
        id: 'cx:work:103:3:1',
        courseName: '常年题库课',
        title: '超远期练习',
        deadlineAt: now.add(const Duration(days: 400)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );

      final catalog = CourseTermCatalog.build(
        courses: const [ungrouped, pastCourse, farFutureCourse],
        assignments: [
          newWork,
          oldCompletedFromSweep,
          oldNoDeadlinePendingFromSweep,
          farFutureWork,
        ],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
        changes: [
          AssignmentChange(
            assignmentId: newWork.id,
            title: newWork.title,
            courseName: newWork.courseName,
            kind: AssignmentChangeKind.published,
            at: now,
            before: '',
            after: 'pending',
          ),
          AssignmentChange(
            assignmentId: oldCompletedFromSweep.id,
            title: oldCompletedFromSweep.title,
            courseName: oldCompletedFromSweep.courseName,
            kind: AssignmentChangeKind.published,
            at: now,
            before: '',
            after: 'submitted',
          ),
          AssignmentChange(
            assignmentId: oldNoDeadlinePendingFromSweep.id,
            title: oldNoDeadlinePendingFromSweep.title,
            courseName: oldNoDeadlinePendingFromSweep.courseName,
            kind: AssignmentChangeKind.published,
            at: now,
            before: '',
            after: 'pending',
          ),
        ],
      );

      final ungroupedEntry = catalog.entryFor(ungrouped.key)!;
      expect(ungroupedEntry.term, isNull);
      expect(ungroupedEntry.source, CourseTermSource.ungrouped);
      expect(ungroupedEntry.state, CourseCatalogState.active);
      expect(ungroupedEntry.hasCurrentTermEvidence, isFalse);
      expect(catalog.matchesHomeCoursePicker(ungrouped.key, 'currentTerm'),
          isFalse);
      expect(
          catalog.matchesHomeCoursePicker(ungrouped.key, 'currentTerm',
              hasVisibleItems: true),
          isTrue);
      expect(
          catalog.entryFor(pastCourse.key)!.state, CourseCatalogState.archived);
      expect(catalog.matchesHomeCoursePicker(pastCourse.key, 'currentTerm'),
          isFalse);
      expect(catalog.entryFor(farFutureCourse.key)!.state,
          CourseCatalogState.archived);
      expect(
          catalog.matchesHomeCoursePicker(farFutureCourse.key, 'currentTerm'),
          isFalse);
    });

    test(
        'dirty courseEndAt is ignored and only a plausible courseStartAt falls back to courseTime',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      final dirtyEndOnly = CourseRef(
        courseId: '401',
        clazzId: '1',
        name: '无学期线索课',
        courseEndAt: DateTime.utc(2027, 6, 30),
      );
      final legacyStart = CourseRef(
        courseId: '402',
        clazzId: '2',
        name: '有开课时间的往期课',
        courseStartAt: DateTime.utc(2025, 9, 1),
      );
      final farFutureStart = CourseRef(
        courseId: '403',
        clazzId: '3',
        name: '远期开课时间课',
        courseStartAt: now.add(const Duration(days: 200)),
      );

      final catalog = CourseTermCatalog.build(
        courses: [dirtyEndOnly, legacyStart, farFutureStart],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final dirtyEndEntry = catalog.entryFor(dirtyEndOnly.key)!;
      expect(dirtyEndEntry.term, isNull);
      expect(dirtyEndEntry.source, CourseTermSource.ungrouped);
      expect(catalog.isUngroupedCourse(dirtyEndOnly.key), isTrue);
      expect(catalog.matchesHomeCoursePicker(dirtyEndOnly.key, 'pastTerms'),
          isFalse);

      final legacyStartEntry = catalog.entryFor(legacyStart.key)!;
      expect(legacyStartEntry.term,
          const AcademicTerm(2025, AcademicSemester.fall));
      expect(legacyStartEntry.source, CourseTermSource.courseTime);
      expect(legacyStartEntry.state, CourseCatalogState.archived);

      final farFutureStartEntry = catalog.entryFor(farFutureStart.key)!;
      expect(farFutureStartEntry.term, isNull);
      expect(farFutureStartEntry.source, CourseTermSource.ungrouped);
    });

    test(
        'majority vote ignores a single deadline beyond one year and beats a dirty courseEndAt',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      final course = CourseRef(
        courseId: '501',
        clazzId: '1',
        name: '学期分布投票课',
        courseEndAt: now,
      );
      final pastWork = [
        for (var i = 0; i < 8; i++)
          Assignment(
            id: 'cx:work:501:1:$i',
            courseName: '学期分布投票课',
            title: '往期作业$i',
            deadlineAt: DateTime.utc(2025, 10, 10 + i),
            requirementsText: '',
            status: 'submitted',
            lastSyncedAt: now,
          ),
      ];
      final absurdFuture = Assignment(
        id: 'cx:work:501:1:99',
        courseName: '学期分布投票课',
        title: '超一年远期作业',
        deadlineAt: now.add(const Duration(days: 400)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );

      final catalog = CourseTermCatalog.build(
        courses: [course],
        assignments: [...pastWork, absurdFuture],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final entry = catalog.entryFor(course.key)!;
      expect(entry.term, const AcademicTerm(2025, AcademicSemester.fall));
      expect(entry.source, CourseTermSource.activity);
      expect(entry.state, CourseCatalogState.archived);
      expect(
          catalog.matchesCoursePickerScope(
              course.key, CourseTermScope.pastTerms),
          isTrue);
    });

    test(
        'activity falls back to trusted human notices only when no assignment votes',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const course = CourseRef(courseId: '701', clazzId: '1', name: '通知推课');

      final catalog = CourseTermCatalog.build(
        courses: const [course],
        assignments: const [],
        notices: [
          CourseNotice(
            id: 'cx:notice:${'7' * 64}',
            courseId: '701',
            clazzId: '1',
            courseName: '通知推课',
            senderName: '张老师',
            title: '期末安排说明',
            publishedAt: DateTime.utc(2025, 10, 2),
            publishedTrusted: true,
            lastSyncedAt: now,
          ),
          CourseNotice(
            id: 'cx:notice:${'8' * 64}',
            courseId: '701',
            clazzId: '1',
            courseName: '通知推课',
            senderName: '学习通知',
            title: '作业:《通知推课》自动汇总',
            publishedAt: now,
            publishedTrusted: true,
            lastSyncedAt: now,
          ),
        ],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final entry = catalog.entryFor(course.key)!;
      expect(entry.term, const AcademicTerm(2025, AcademicSemester.fall));
      expect(entry.source, CourseTermSource.activity);
    });

    test('exams vote by trusted start or end and notice-only exams never vote',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const course = CourseRef(courseId: '901', clazzId: '1', name: '考试归属课');

      Assignment exam(
        String id, {
        required DateTime startAt,
        required DateTime endAt,
        bool noticeOnly = false,
        DateTime? publishedAt,
        DateTime? availableFromAt,
      }) =>
          Assignment(
            id: 'cx:exam:901:1:$id',
            source: AssignmentSource.exam,
            courseName: '考试归属课',
            title: id,
            deadlineAt: endAt,
            availableFromAt: availableFromAt,
            publishedAt: publishedAt,
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
            exam: ExamInfo(
              examId: id,
              courseId: '901',
              clazzId: '1',
              startAt: startAt,
              endAt: endAt,
              startTrusted: true,
              endTrusted: true,
              noticeOnly: noticeOnly,
            ),
          );

      final catalog = CourseTermCatalog.build(
        courses: const [course],
        assignments: [
          exam(
            'ended',
            startAt: DateTime.utc(2025, 10, 9, 8),
            endAt: DateTime.utc(2025, 10, 9, 10),
          ),
          exam(
            'notice-only',
            startAt: now.add(const Duration(days: 5)),
            endAt: now.add(const Duration(days: 5)),
            noticeOnly: true,
            publishedAt: now,
            availableFromAt: now,
          ),
        ],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final entry = catalog.entryFor(course.key)!;
      expect(entry.term, const AcademicTerm(2025, AcademicSemester.fall));
      expect(entry.source, CourseTermSource.activity);
    });

    test(
        'vote ties prefer the nearest past-or-current term and otherwise the earliest future term',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const tieCourse = CourseRef(courseId: '601', clazzId: '1', name: '平票课程');
      const futureTieCourse =
          CourseRef(courseId: '602', clazzId: '1', name: '未来平票课程');

      Assignment work(String courseId, String courseName, String tag,
              DateTime deadlineAt) =>
          Assignment(
            id: 'cx:work:$courseId:1:$tag',
            courseName: courseName,
            title: tag,
            deadlineAt: deadlineAt,
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
          );

      final catalog = CourseTermCatalog.build(
        courses: const [tieCourse, futureTieCourse],
        assignments: [
          work('601', '平票课程', 'current', now.add(const Duration(days: 5))),
          work('601', '平票课程', 'past', DateTime.utc(2025, 10, 10)),
          work('602', '未来平票课程', 'near-future',
              now.add(const Duration(days: 200))),
          work('602', '未来平票课程', 'far-future',
              now.add(const Duration(days: 330))),
        ],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final currentTie = catalog.entryFor(tieCourse.key)!;
      expect(currentTie.term, const AcademicTerm(2026, AcademicSemester.fall));
      expect(currentTie.source, CourseTermSource.activity);

      final futureTie = catalog.entryFor(futureTieCourse.key)!;
      expect(futureTie.term, const AcademicTerm(2026, AcademicSemester.spring));
      expect(futureTie.source, CourseTermSource.activity);
    });

    test(
        'old template course name yields to the current-term coursework distribution',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const course = CourseRef(
        courseId: '801',
        clazzId: '1',
        name: '2025-2026(1) 大学物理实验',
      );

      final catalog = CourseTermCatalog.build(
        courses: const [course],
        assignments: [
          Assignment(
            id: 'cx:work:801:1:1',
            courseName: course.name,
            title: '本学期实验报告',
            deadlineAt: now.add(const Duration(days: 5)),
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
          ),
        ],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final entry = catalog.entryFor(course.key)!;
      expect(entry.term, const AcademicTerm(2026, AcademicSemester.fall));
      expect(entry.source, CourseTermSource.activity);
      expect(entry.state, CourseCatalogState.active);
    });

    test(
        'matchesHomeCoursePicker isolates ungrouped courses from currentTerm while keeping sync eligibility',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const silentUngrouped =
          CourseRef(courseId: '201', clazzId: '1', name: '静默老课');
      const activeCourse = CourseRef(
        courseId: '202',
        clazzId: '2',
        name: '本学期专业课',
        folderName: '2026年秋',
      );
      final catalog = CourseTermCatalog.build(
        courses: const [silentUngrouped, activeCourse],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      expect(catalog.isActiveOrRecalled(silentUngrouped.key), isTrue);
      expect(catalog.isUngroupedCourse(silentUngrouped.key), isTrue);
      expect(
          catalog.matchesHomeCoursePicker(silentUngrouped.key, 'currentTerm'),
          isFalse);
      expect(
          catalog.matchesHomeCoursePicker(silentUngrouped.key, 'currentTerm',
              hasVisibleItems: true),
          isTrue);
      expect(
          catalog.matchesHomeCoursePicker(
              silentUngrouped.key, 'currentAcademicYear'),
          isFalse);
      expect(
          catalog.matchesHomeCoursePicker(
              silentUngrouped.key, 'currentAcademicYear',
              hasVisibleItems: true),
          isTrue);
      expect(catalog.matchesHomeCoursePicker(silentUngrouped.key, 'allTerms'),
          isTrue);
      expect(catalog.matchesHomeCoursePicker(activeCourse.key, 'currentTerm'),
          isTrue);
      expect(
          catalog.matchesHomeCoursePicker(
              activeCourse.key, 'currentAcademicYear'),
          isTrue);
    });

    test(
        'stats scope enforces 180-day recall horizon while retaining current-term submitted recall work',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const pastCourse = CourseRef(
        courseId: '301',
        clazzId: '1',
        name: '往期补修课',
        folderName: '2025年秋',
      );
      final nearRecall = Assignment(
        id: 'cx:work:301:1:1',
        courseName: '往期补修课',
        title: '三天后补交作业',
        deadlineAt: now.add(const Duration(days: 3)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      final farFutureExercise = Assignment(
        id: 'cx:work:301:1:2',
        courseName: '往期补修课',
        title: '超远期常年练习',
        deadlineAt: now.add(const Duration(days: 400)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      final currentTermSubmitted = Assignment(
        id: 'cx:work:301:1:3',
        courseName: '往期补修课',
        title: '本学期已提交补修',
        deadlineAt: now.subtract(const Duration(days: 2)),
        deadlineTrusted: true,
        publishedAt: null,
        requirementsText: '',
        status: 'submitted',
        lastSyncedAt: now,
      );

      final catalog = CourseTermCatalog.build(
        courses: const [pastCourse],
        assignments: [nearRecall, farFutureExercise, currentTermSubmitted],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      expect(
          catalog.entryFor(pastCourse.key)!.state, CourseCatalogState.recalled);
      expect(
        catalog.matchesAssignmentInStatsScope(
          nearRecall,
          CourseTermScope.currentTerm,
        ),
        isTrue,
      );
      expect(
        catalog.matchesAssignmentInStatsScope(
          currentTermSubmitted,
          CourseTermScope.currentTerm,
        ),
        isTrue,
      );
      expect(
        catalog.matchesAssignmentInStatsScope(
          farFutureExercise,
          CourseTermScope.currentTerm,
        ),
        isFalse,
      );
    });

    test(
        'fromCourseCreationInstant maps Aug pre-creation to fall and Feb to spring without altering fromInstant',
        () {
      expect(
        AcademicTerm.fromCourseCreationInstant(_beijing(2026, 8, 25, 10)),
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.fromCourseCreationInstant(_beijing(2026, 2, 18, 10)),
        const AcademicTerm(2025, AcademicSemester.spring),
      );
      expect(
        AcademicTerm.fromCourseCreationInstant(_beijing(2026, 1, 15, 10)),
        const AcademicTerm(2025, AcademicSemester.fall),
      );
      // AcademicTerm.fromInstant keeps strict Mar 1 / Sep 1 cutoff for homework/exams.
      expect(
        AcademicTerm.fromInstant(_beijing(2026, 8, 25, 10)),
        const AcademicTerm(2025, AcademicSemester.spring),
      );
      expect(
        AcademicTerm.fromInstant(_beijing(2026, 2, 18, 10)),
        const AcademicTerm(2025, AcademicSemester.fall),
      );
    });

    test(
        'clazzId cohort infers zero-activity courses across 3 semesters accurately while blocking promo noise',
        () {
      final now = _beijing(2026, 11, 26, 10);
      const currentFall = AcademicTerm(2026, AcademicSemester.fall);
      const pastSpring = AcademicTerm(2025, AcademicSemester.spring);
      const pastFall = AcademicTerm(2025, AcademicSemester.fall);

      const courses = <CourseRef>[
        // 2026-2027 秋季（15 门：5 有线索 + 10 零作业零通知）
        CourseRef(courseId: '267575898', clazzId: '155943935', name: '离散结构'),
        CourseRef(courseId: '266993156', clazzId: '154422405', name: '大学物理实验B'),
        CourseRef(courseId: '266855292', clazzId: '154055965', name: '习概课外实践'),
        CourseRef(courseId: '266855253', clazzId: '154055842', name: '习概'),
        CourseRef(
            courseId: '266780803', clazzId: '153853883', name: '算法设计与分析实验'),
        CourseRef(courseId: '266780722', clazzId: '153853649', name: '算法设计与分析'),
        CourseRef(
            courseId: '266779539', clazzId: '153850877', name: '实用工程英语写作'),
        CourseRef(courseId: '247179431', clazzId: '153847614', name: '英语应用文写作'),
        CourseRef(courseId: '266640727', clazzId: '153484971', name: '信息安全基础'),
        CourseRef(
            courseId: '266547622', clazzId: '153224530', name: '概率论与数理统计'),
        CourseRef(courseId: '266534181', clazzId: '153183681', name: '毛概课外实践'),
        CourseRef(courseId: '266514411', clazzId: '153121275', name: '毛概'),
        CourseRef(
            courseId: '266499402', clazzId: '153074707', name: '大学物理B（下）'),
        CourseRef(courseId: '266276698', clazzId: '152467590', name: '体育(三)'),
        CourseRef(courseId: '266271672', clazzId: '152453179', name: '影视鉴赏'),
        // 2025-2026 春季（11 门：2 有线索 + 9 零作业零通知）
        CourseRef(
            courseId: '240994784', clazzId: '141297385', name: '中国近现代史纲要'),
        CourseRef(courseId: '260381513', clazzId: '138963634', name: '体育(二)'),
        CourseRef(courseId: '260380570', clazzId: '138962100', name: '程序设计二'),
        CourseRef(courseId: '260379066', clazzId: '138959958', name: '线性代数'),
        CourseRef(
            courseId: '260379065', clazzId: '138959954', name: '高等数学A（二）'),
        CourseRef(courseId: '260379063', clazzId: '138959952', name: '人工智能基础B'),
        CourseRef(courseId: '260379061', clazzId: '138959949', name: '大学生心理健康'),
        CourseRef(
            courseId: '260378806', clazzId: '138959515', name: '大学物理B（上）'),
        CourseRef(courseId: '260378719', clazzId: '138959279', name: '军事理论'),
        CourseRef(courseId: '260377998', clazzId: '138958078', name: '心理健康实践'),
        CourseRef(
            courseId: '260377681', clazzId: '138957382', name: '通用工程英语听说'),
        // 2025-2026 秋季（12 门 + 2 官方竞赛课）
        CourseRef(
            courseId: '259004218',
            clazzId: '136054762',
            name: '2026全国大学生AI答题实践竞赛',
            teacherNames: ['超星小助手']),
        CourseRef(
            courseId: '258750250',
            clazzId: '135623072',
            name: '2025年12月6日1-4节《形势与政策》'),
        CourseRef(
            courseId: '257920901',
            clazzId: '133807271',
            name: '2026全国大学生AI答题实践竞赛',
            teacherNames: ['超星小助手']),
        CourseRef(
            courseId: '256727781', clazzId: '131143331', name: '2025级分班级'),
        CourseRef(courseId: '256045042', clazzId: '130351455', name: '体育(一)'),
        CourseRef(
            courseId: '255971922', clazzId: '129355129', name: '大学生卫生与健康'),
        CourseRef(courseId: '255752174', clazzId: '128814165', name: '信息类专业导论'),
        CourseRef(courseId: '255751307', clazzId: '128812823', name: '程序设计一'),
        CourseRef(courseId: '255750796', clazzId: '128811945', name: '写作与沟通'),
        CourseRef(
            courseId: '255750140', clazzId: '128810598', name: '高等数学A(一)'),
        CourseRef(courseId: '255396471', clazzId: '128810584', name: '大学英语'),
        CourseRef(courseId: '255750045', clazzId: '128810360', name: '思政实践'),
        CourseRef(courseId: '255750018', clazzId: '128810262', name: '思想道德与法治'),
        CourseRef(courseId: '255396478', clazzId: '128810038', name: '军训'),
      ];

      Assignment courseWork(String courseId, String clazzId, DateTime at) =>
          Assignment(
            id: 'cx:work:$courseId:$clazzId:1',
            courseName: '课业课程',
            title: '阶段作业',
            deadlineAt: at,
            deadlineTrusted: true,
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
          );

      final catalog = CourseTermCatalog.build(
        courses: courses,
        assignments: [
          courseWork('266780803', '153853883', _beijing(2026, 11, 28)),
          courseWork('266779539', '153850877', _beijing(2026, 10, 31)),
          courseWork('266640727', '153484971', _beijing(2026, 12, 8)),
          courseWork('266499402', '153074707', _beijing(2027, 1, 24)),
          courseWork('240994784', '141297385', _beijing(2026, 7, 7)),
          courseWork('260379066', '138959958', _beijing(2026, 7, 4)),
          // Official promo course's homework must not corrupt cohort anchors.
          courseWork('259004218', '136054762', _beijing(2026, 11, 30)),
        ],
        notices: [
          CourseNotice(
            id: 'cx:notice:${'1' * 64}',
            courseId: '266547622',
            clazzId: '153224530',
            courseName: '概率论与数理统计',
            senderName: '任课教师',
            title: '上课通知',
            publishedAt: _beijing(2026, 10, 13),
            publishedTrusted: true,
            lastSyncedAt: now,
          ),
        ],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final fallCount = courses
          .where((c) => catalog.matchesHomeCoursePicker(c.key, 'currentTerm'))
          .length;
      final yearCount = courses
          .where((c) =>
              catalog.matchesHomeCoursePicker(c.key, 'currentAcademicYear'))
          .length;
      final pastCount = courses
          .where((c) => catalog.matchesHomeCoursePicker(c.key, 'pastTerms'))
          .length;
      final allCount = courses
          .where((c) => catalog.matchesHomeCoursePicker(c.key, 'allTerms'))
          .length;
      final ungroupedCount = courses
          .where((c) =>
              !catalog.isBlocked(c.key) && catalog.isUngroupedCourse(c.key))
          .length;

      expect(fallCount, 15);
      expect(yearCount, 15);
      expect(pastCount, 23);
      expect(allCount, 38);
      expect(ungroupedCount, 0);

      for (final key in const [
        '266271672:152453179',
        '247179431:153847614',
        '266514411:153121275',
        '267575898:155943935',
      ]) {
        final e = catalog.entryFor(key)!;
        expect(e.term, currentFall, reason: key);
        expect(e.source, CourseTermSource.clazzCohort, reason: key);
        expect(e.state, CourseCatalogState.active, reason: key);
      }

      for (final key in const [
        '260377681:138957382',
        '260381513:138963634',
      ]) {
        final e = catalog.entryFor(key)!;
        expect(e.term, pastSpring, reason: key);
        expect(e.source, CourseTermSource.clazzCohort, reason: key);
        expect(e.state, CourseCatalogState.archived, reason: key);
      }

      for (final key in const [
        '255396478:128810038',
        '256727781:131143331',
      ]) {
        final e = catalog.entryFor(key)!;
        expect(e.term, pastFall, reason: key);
        expect(e.source, CourseTermSource.clazzCohort, reason: key);
        expect(e.state, CourseCatalogState.archived, reason: key);
      }

      expect(catalog.isBlocked('259004218:136054762'), isTrue);
      expect(catalog.isBlocked('257920901:133807271'), isTrue);

      final rawRefs = [
        for (final c in courses)
          ChaoxingCourseRef(
            courseId: c.courseId,
            clazzId: c.clazzId,
            courseName: c.name,
            teacherNames: c.teacherNames,
          ),
      ];
      final selCurrent = SyncScopeSelection.select(
        catalog: rawRefs,
        scope: AssignmentSyncScope.current,
        termCatalog: catalog,
      );
      expect(selCurrent.targetCourses, hasLength(15));
    });

    test(
        'clazzId cohort extrapolates past terms from single current-term anchor and week-1 forward courses with conservative deadzone',
        () {
      final now = _beijing(2026, 11, 20, 10);
      const currentAnchor = CourseRef(
        courseId: '1',
        clazzId: '153500000',
        name: '本学期锚点课',
        folderName: '2026年秋',
      );
      const sameTermEarly = CourseRef(
        courseId: '2',
        clazzId: '150500000', // delta = 3.0M <= 3.8M -> currentTerm
        name: '同批早建无作业课',
      );
      const deadzoneCourse = CourseRef(
        courseId: '3',
        clazzId: '148500000', // delta = 5.0M in (3.8M, 7.5M) -> ungrouped
        name: '过渡死区课',
      );
      const prevSpringCourse = CourseRef(
        courseId: '4',
        clazzId: '141000000', // delta = 12.5M -> -1 term (2025-spring)
        name: '上学期无作业课',
      );
      const prevFallCourse = CourseRef(
        courseId: '5',
        clazzId: '130000000', // delta = 23.5M -> -2 terms (2025-fall)
        name: '上学年秋课',
      );

      final singleCurrentCatalog = CourseTermCatalog.build(
        courses: const [
          currentAnchor,
          sameTermEarly,
          deadzoneCourse,
          prevSpringCourse,
          prevFallCourse,
        ],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      expect(
        singleCurrentCatalog.entryFor(sameTermEarly.key)!.term,
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        singleCurrentCatalog.entryFor(deadzoneCourse.key)!.source,
        CourseTermSource.ungrouped,
      );
      expect(
        singleCurrentCatalog.entryFor(prevSpringCourse.key)!.term,
        const AcademicTerm(2025, AcademicSemester.spring),
      );
      expect(
        singleCurrentCatalog.entryFor(prevFallCourse.key)!.term,
        const AcademicTerm(2025, AcademicSemester.fall),
      );

      // Week-1 scenario: only past anchors exist yet, plus a brand-new current-term course.
      const pastSpringAnchor = CourseRef(
        courseId: '10',
        clazzId: '140000000',
        name: '上学期有作业课',
        folderName: '2026年春',
      );
      const week1Current = CourseRef(
        courseId: '11',
        clazzId: '153000000', // +13M -> +1 step = currentTerm
        name: '开学第一周新课',
      );
      final week1Catalog = CourseTermCatalog.build(
        courses: const [pastSpringAnchor, week1Current],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );
      expect(
        week1Catalog.entryFor(week1Current.key)!.term,
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        week1Catalog.entryFor(week1Current.key)!.source,
        CourseTermSource.clazzCohort,
      );
    });

    test(
        'clazzId cohort interpolates skipped middle term (termGap == 2) accurately',
        () {
      final now = _beijing(2026, 11, 20, 10);
      const fall25 = CourseRef(
        courseId: '21',
        clazzId: '130000000',
        name: '2025秋锚点',
        folderName: '2025年秋',
      );
      const spring26Unanchored = CourseRef(
        courseId: '22',
        clazzId: '141500000',
        name: '夹在中间的无作业课',
      );
      const fall26 = CourseRef(
        courseId: '23',
        clazzId: '153500000',
        name: '2026秋锚点',
        folderName: '2026年秋',
      );

      final catalog = CourseTermCatalog.build(
        courses: const [fall25, spring26Unanchored, fall26],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );
      final e = catalog.entryFor(spring26Unanchored.key)!;
      expect(e.term, const AcademicTerm(2025, AcademicSemester.spring));
      expect(e.source, CourseTermSource.clazzCohort);
    });

    test(
        'clazzId cohort ignores small synthetic IDs, trims single outlier, and aborts on 1v1 inverted anchors',
        () {
      final now = _beijing(2026, 11, 20, 10);

      // 1. Small/alphanumeric synthetic IDs never trigger cohort inference.
      const smallAnchor = CourseRef(
        courseId: '1',
        clazzId: '100',
        name: '小号锚点',
        folderName: '2026年秋',
      );
      const smallBlank = CourseRef(
        courseId: '2',
        clazzId: '105',
        name: '小号无归属',
      );
      final smallCatalog = CourseTermCatalog.build(
        courses: const [smallAnchor, smallBlank],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );
      expect(smallCatalog.entryFor(smallBlank.key)!.source,
          CourseTermSource.ungrouped);

      // 2. Intra-term outlier (1 stale old class at 80M among 5 classes at 153M) is trimmed.
      final trimmedCourses = <CourseRef>[
        for (var i = 0; i < 5; i++)
          CourseRef(
            courseId: '${30 + i}',
            clazzId: '${153000000 + i * 100000}',
            name: '本学期主簇$i',
            folderName: '2026年秋',
          ),
        const CourseRef(
          courseId: '39',
          clazzId: '80000000',
          name: '复用老班的本学期课',
          folderName: '2026年秋',
        ),
        const CourseRef(
          courseId: '40',
          clazzId: '153250000',
          name: '主簇内无作业课',
        ),
      ];
      final trimmedCatalog = CourseTermCatalog.build(
        courses: trimmedCourses,
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );
      expect(
        trimmedCatalog.entryFor('40:153250000')!.term,
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        trimmedCatalog.entryFor('40:153250000')!.source,
        CourseTermSource.clazzCohort,
      );

      // 3. 1v1 inverted anchors (past > current) abort cleanly back to ungrouped.
      const invertedPast = CourseRef(
        courseId: '50',
        clazzId: '155000000',
        name: '倒挂往期课',
        folderName: '2025年秋',
      );
      const invertedCurrent = CourseRef(
        courseId: '51',
        clazzId: '130000000',
        name: '倒挂当前课',
        folderName: '2026年秋',
      );
      const targetCourse = CourseRef(
        courseId: '52',
        clazzId: '140000000',
        name: '待推断课',
      );
      final invertedCatalog = CourseTermCatalog.build(
        courses: const [invertedPast, invertedCurrent, targetCourse],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );
      expect(
        invertedCatalog.entryFor(targetCourse.key)!.source,
        CourseTermSource.ungrouped,
      );
    });
  });
}

class _TermMemorySession extends SecureSessionStore {
  _TermMemorySession(this.account);
  String? account;
  String? password = 'pw';

  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    this.account = account;
    this.password = password;
  }

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingPassword() async => password;

  @override
  Future<String?> readChaoxingDisplayName() async => '学期测试';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;

  @override
  Future<void> clear() async {
    account = null;
    password = null;
  }

  @override
  Future<void> clearWebSession() async {}
}

class _TermNoopNotifications extends LocalNotificationService {
  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;

  @override
  Future<void> removeLegacyAssignmentSchedules() async {}

  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _TermNoopWidgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _TermNoopChaoxingClient extends ChaoxingLocalClient {
  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true, displayName: '学期测试');

  @override
  Future<List<Assignment>> fetchAssignments() async {
    throw StateError('offline');
  }
}
