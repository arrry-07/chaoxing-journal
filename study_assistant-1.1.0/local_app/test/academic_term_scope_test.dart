import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/course_term_preferences.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
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
        'incremental published change elevates ungrouped course without letting syncAllTerms past-course old work pollute currentTerm',
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

      expect(
        catalog.entryFor(ungrouped.key)!.term,
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(catalog.entryFor(ungrouped.key)!.hasCurrentTermEvidence, isTrue);
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
      expect(catalog.matchesHomeCoursePicker(silentUngrouped.key, 'ungrouped'),
          isTrue);
      expect(catalog.matchesHomeCoursePicker(silentUngrouped.key, 'allTerms'),
          isTrue);
      expect(catalog.matchesHomeCoursePicker(activeCourse.key, 'currentTerm'),
          isTrue);
      expect(catalog.matchesHomeCoursePicker(activeCourse.key, 'ungrouped'),
          isFalse);
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
