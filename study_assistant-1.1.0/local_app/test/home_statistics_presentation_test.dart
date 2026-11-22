import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/local_coursework_state.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_statistics.dart';
import 'package:study_assistant_mobile/src/services/home_sync_presentation.dart';

void main() {
  test('completion rate rounds consistently after splitting expired work', () {
    final stats = AssignmentStatistics([
      for (var i = 0; i < 31; i++)
        Assignment(
            id: 'cx:work:1:2:$i',
            courseName: '课',
            title: '题',
            deadlineAt: i >= 27 ? DateTime(2000) : null,
            requirementsText: '',
            status: i < 20 ? 'submitted' : 'pending',
            lastSyncedAt: DateTime(2026)),
    ], now: DateTime(2026));
    expect(stats.counts, [20, 7, 4, 0]);
    expect(stats.percentages[0], 65);
    expect(stats.percentages.reduce((a, b) => a + b), 100);
  });
  test('statistics partitions 31 records and percentages sum to 100', () {
    final stats = AssignmentStatistics([
      for (var i = 0; i < 31; i++)
        Assignment(
            id: 'cx:work:1:2:$i',
            courseName: '课',
            title: '题',
            deadlineAt: null,
            requirementsText: '',
            status: i < 20
                ? 'submitted'
                : i < 28
                    ? 'returned'
                    : 'unknown',
            lastSyncedAt: DateTime.now())
    ]);
    expect(stats.counts, [20, 8, 0, 3]);
    expect(stats.total, 31);
    expect(stats.percentages, [65, 26, 0, 9]);
    for (final n in [0, 1, 1000]) {
      final s = AssignmentStatistics([
        for (var i = 0; i < n; i++)
          Assignment(
              id: 'cx:work:1:2:$i',
              courseName: '课',
              title: '题',
              deadlineAt: null,
              requirementsText: '',
              status: 'unknown',
              lastSyncedAt: DateTime.now())
      ]);
      expect(s.percentages, n == 0 ? [0, 0, 0, 0] : [0, 0, 0, 100]);
    }
  });
  test('expired requires confirmed pending and a reliable past deadline', () {
    Assignment work(String status,
            {bool trusted = true, bool failed = false, DateTime? due}) =>
        Assignment(
            id: 'cx:work:1:2:3',
            courseName: '课',
            title: '题',
            deadlineAt: due ?? DateTime(2000),
            deadlineTrusted: trusted,
            deadlineReadFailed: failed,
            requirementsText: '',
            status: status,
            lastSyncedAt: DateTime.now());
    final stats = AssignmentStatistics([
      work('submitted'),
      work('pending'),
      work('returned'),
      work('unknown'),
      work('overdue', trusted: false),
      work('pending', failed: true),
      work('pending', due: DateTime(2100)),
    ]);
    expect(stats.counts, [1, 3, 2, 1]);
    expect(stats.percentages.reduce((a, b) => a + b), 100);
  });
  test('deadline equal to the shared reference instant is expired', () {
    final now = DateTime.utc(2026, 11, 5, 12);
    final record = Assignment(
        id: 'cx:work:1:2:3',
        courseName: '课',
        title: '题',
        deadlineAt: now,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now);
    expect(AssignmentStatistics([record], now: now).counts, [0, 0, 1, 0]);
    expect(
        AssignmentStatistics([record],
                now: now.subtract(const Duration(milliseconds: 1)))
            .counts,
        [0, 1, 0, 0]);
  });
  test('sync actions match auth, verification, retry, and running cache states',
      () {
    final now = DateTime.now();
    for (final cache in [false, true]) {
      for (final pair in [
        (SyncIssueKind.authExpired, HomeSyncAction.login),
        (SyncIssueKind.verificationRequired, HomeSyncAction.verify),
        (SyncIssueKind.network, HomeSyncAction.retry)
      ]) {
        final p = HomeSyncPresentation.from(
            SyncReport(
                phase: SyncPhase.failed,
                issues: [SyncIssue(pair.$1, 'fixture')]),
            loading: false,
            hasCache: cache,
            now: now);
        expect(p.action, pair.$2);
        expect(p.showCached, cache);
      }
      final p = HomeSyncPresentation.from(
          const SyncReport(phase: SyncPhase.running),
          loading: true,
          hasCache: cache,
          now: now);
      expect(p.action, HomeSyncAction.none);
      expect(p.summary, cache ? '正在更新…' : '正在读取作业…');
    }
  });

  test('failed sync with cache and pure network issue uses gentle retry state',
      () {
    final presentation = HomeSyncPresentation.from(
      const SyncReport(
        phase: SyncPhase.failed,
        issues: [SyncIssue(SyncIssueKind.network, 'fixture')],
      ),
      loading: false,
      hasCache: true,
      now: DateTime.utc(2026, 11, 13),
      successAt: DateTime.utc(2026, 11, 13).subtract(const Duration(hours: 1)),
    );

    expect(presentation.summary, '网络暂不可用');
    expect(presentation.action, HomeSyncAction.retry);
    expect(presentation.showCached, isTrue);
    expect(presentation.gentle, isTrue);

    final storageFailure = HomeSyncPresentation.from(
      const SyncReport(
        phase: SyncPhase.failed,
        issues: [SyncIssue(SyncIssueKind.storage, 'disk')],
      ),
      loading: false,
      hasCache: true,
      now: DateTime.utc(2026, 11, 13),
    );
    expect(storageFailure.summary, '更新失败');
    expect(storageFailure.gentle, isFalse);

    final noCache = HomeSyncPresentation.from(
      const SyncReport(
        phase: SyncPhase.failed,
        issues: [SyncIssue(SyncIssueKind.network, 'offline')],
      ),
      loading: false,
      hasCache: false,
      now: DateTime.utc(2026, 11, 13),
    );
    expect(noCache.summary, '暂时无法读取作业');
    expect(noCache.gentle, isFalse);
  });

  test('partial sync summary follows the actual failing source', () {
    final now = DateTime.utc(2026, 11, 19);
    HomeSyncPresentation present(
      List<SyncIssue> issues, {
      List<SyncSourceResult> sources = const [],
    }) =>
        HomeSyncPresentation.from(
          SyncReport(
            phase: SyncPhase.partial,
            issues: issues,
            sourceResults: sources,
          ),
          loading: false,
          hasCache: true,
          now: now,
          successAt: now.subtract(const Duration(days: 1)),
        );

    final detail = present(
      const [
        SyncIssue(
          SyncIssueKind.schemaChanged,
          '作业详情未提供截止信息',
          stage: 'detail',
        ),
      ],
      sources: const [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
          succeededCourses: 40,
          detailUnconfirmedCount: 1,
        ),
      ],
    );
    expect(detail.summary, '部分截止时间待确认');
    expect(detail.showCached, isFalse);

    final work = present(
      const [],
      sources: const [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.partial,
          succeededCourses: 39,
          failedCourses: 1,
        ),
      ],
    );
    expect(work.summary, '部分课程作业未更新');
    expect(work.showCached, isTrue);

    final exam = present(
      const [],
      sources: const [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
          succeededCourses: 40,
        ),
        SyncSourceResult(
          source: 'exam',
          phase: SyncSourcePhase.partial,
          failedCourses: 1,
        ),
      ],
    );
    expect(exam.summary, '部分考试信息未更新');
    expect(exam.showCached, isTrue);

    final multiple = present(
      const [
        SyncIssue(
          SyncIssueKind.partial,
          '部分截止时间尚未确认',
          stage: 'detail',
        ),
      ],
      sources: const [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.partial,
          succeededCourses: 39,
          failedCourses: 1,
          detailUnconfirmedCount: 2,
        ),
        SyncSourceResult(
          source: 'classroomActivity:42',
          phase: SyncSourcePhase.partial,
          failedCourses: 1,
        ),
      ],
    );
    expect(multiple.summary, '部分课业信息未更新');
    expect(multiple.showCached, isTrue);
  });

  test('fresh preview is not called a cached fallback on first partial sync',
      () {
    final now = DateTime.utc(2026, 11, 19);
    const report = SyncReport(
      phase: SyncPhase.partial,
      sourceResults: [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.partial,
          succeededCourses: 39,
          failedCourses: 1,
        ),
      ],
    );
    final fresh = HomeSyncPresentation.from(
      report,
      loading: false,
      hasCache: true,
      hasPreviousData: false,
      now: now,
      successAt: now.subtract(const Duration(days: 1)),
    );
    expect(fresh.showCached, isFalse);
    final cached = HomeSyncPresentation.from(
      report,
      loading: false,
      hasCache: true,
      hasPreviousData: true,
      now: now,
      successAt: DateTime.utc(2026, 11, 18),
    );
    expect(cached.showCached, isTrue);
  });

  group('Phase 1C freshness boundaries and HomeDueSummary', () {
    test('stale freshness uses strict > 24h boundary and floor days', () {
      final now = DateTime.utc(2026, 11, 20, 4, 30); // Beijing 12:30

      String presentAt(Duration age) {
        final ts = now.subtract(age);
        return HomeSyncPresentation.from(
          SyncReport(phase: SyncPhase.success, lastDataSuccessAt: ts),
          loading: false,
          hasCache: true,
          now: now,
          successAt: ts,
        ).summary;
      }

      expect(presentAt(const Duration(seconds: 40)), '刚刚更新');
      expect(presentAt(const Duration(hours: 23, minutes: 59)),
          isNot(contains('天前更新')));
      expect(presentAt(const Duration(hours: 24)), contains('更新'));
      expect(presentAt(const Duration(hours: 24)), isNot(contains('天前更新')));
      expect(presentAt(const Duration(hours: 24, minutes: 1)), '1天前更新');
      expect(presentAt(const Duration(hours: 49)), '2天前更新');

      final serviceWarning = HomeSyncPresentation.from(
        SyncReport(
          phase: SyncPhase.success,
          lastDataSuccessAt: now.subtract(const Duration(hours: 30)),
        ),
        loading: false,
        hasCache: true,
        now: now,
        serviceWarning: true,
      );
      expect(serviceWarning.action, HomeSyncAction.settings);
      expect(serviceWarning.gentle, isFalse);

      final verifyPriority = HomeSyncPresentation.from(
        const SyncReport(
          phase: SyncPhase.failed,
          issues: [
            SyncIssue(SyncIssueKind.network, 'timeout'),
            SyncIssue(SyncIssueKind.verificationRequired, '9010'),
          ],
        ),
        loading: false,
        hasCache: true,
        now: now,
      );
      expect(verifyPriority.action, HomeSyncAction.verify);
      expect(verifyPriority.gentle, isFalse);
    });

    test(
        'HomeDueSummary follows Beijing natural days and excludes exams/overdue/untrusted',
        () {
      // Beijing 2026-11-20 00:10 (UTC 2026-11-19 16:10)
      final now = DateTime.utc(2026, 11, 19, 16, 10);
      Assignment work(
        String id, {
        required DateTime? due,
        String status = 'pending',
        bool trusted = true,
        bool failed = false,
        AssignmentSource? source,
        int? activityType,
      }) =>
          Assignment(
            id: id,
            source: source,
            activityType: activityType,
            courseName: '计算机网络',
            title: id,
            deadlineAt: due,
            deadlineTrusted: trusted,
            deadlineReadFailed: failed,
            requirementsText: '',
            status: status,
            lastSyncedAt: now,
          );

      final summary = HomeDueSummary.from([
        // Due today in Beijing (2026-11-20 23:59) -> UTC 2026-11-20 15:59
        work('cx:work:1:2:today1', due: DateTime.utc(2026, 11, 20, 15, 59)),
        // Classroom task due tomorrow (2026-11-21 12:00 Beijing)
        work(
          'cx:activity:1:2:act1',
          source: AssignmentSource.classroomActivity,
          activityType: 42,
          due: DateTime.utc(2026, 11, 21, 4, 0),
        ),
        // Due day 3 inclusive (2026-11-22 23:59 Beijing -> UTC 2026-11-22 15:59)
        work('cx:work:1:2:day3', due: DateTime.utc(2026, 11, 22, 15, 59)),
        // Day 4 (2026-11-23 00:01 Beijing -> UTC 2026-11-22 16:01) -> excluded
        work('cx:work:1:2:day4', due: DateTime.utc(2026, 11, 22, 16, 1)),
        // Already overdue earlier today -> excluded
        work('cx:work:1:2:overdue',
            due: now.subtract(const Duration(minutes: 5))),
        // Untrusted deadline -> excluded
        work('cx:work:1:2:untrusted',
            due: DateTime.utc(2026, 11, 20, 12, 0), trusted: false),
        // Read failed -> excluded
        work('cx:work:1:2:failed',
            due: DateTime.utc(2026, 11, 20, 12, 0), failed: true),
        // Completed today -> excluded from pending
        work('cx:work:1:2:done',
            due: DateTime.utc(2026, 11, 20, 10, 0), status: 'submitted'),
        // Exam -> excluded (handled by Phase 5 exam banner)
        Assignment(
          id: 'cx:exam:1:2:e1',
          source: AssignmentSource.exam,
          courseName: '计算机网络',
          title: '期中考试',
          deadlineAt: null,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
          exam: ExamInfo(
            examId: 'e1',
            courseId: '1',
            clazzId: '2',
            startAt: DateTime.utc(2026, 11, 20, 6, 0),
            startTrusted: true,
            lifecycle: 'scheduled',
          ),
        ),
      ], now: now);

      expect(summary.dueToday, 1);
      expect(summary.dueIn3Days, 3);
      expect(summary.completedToday, 1);
      expect(summary.label(compact: true), '今日 1 · 3日 3');
      expect(summary.label(compact: false), '今日待交 1 · 3日内 3');

      final allSubmittedToday = HomeDueSummary.from([
        work('cx:work:1:2:done-today',
            due: DateTime.utc(2026, 11, 20, 10, 0), status: 'submitted'),
        work('cx:work:1:2:tomorrow', due: DateTime.utc(2026, 11, 21, 10, 0)),
      ], now: now);
      expect(allSubmittedToday.dueToday, 0);
      expect(allSubmittedToday.completedToday, 1);
      expect(allSubmittedToday.dueIn3Days, 1);
      expect(allSubmittedToday.label(compact: true), '今日已交完 · 3日 1');

      final finishedAll = HomeDueSummary.from([
        work('cx:work:1:2:done-today',
            due: DateTime.utc(2026, 11, 20, 10, 0), status: 'graded'),
      ], now: now);
      expect(finishedAll.label(compact: true), '今日已交完');
      expect(finishedAll.label(compact: false), '今日已交完');

      final noneToday = HomeDueSummary.from([
        work('cx:work:1:2:next-week', due: DateTime.utc(2026, 11, 28, 10, 0)),
      ], now: now);
      expect(noneToday.dueToday, 0);
      expect(noneToday.completedToday, 0);
      expect(noneToday.dueIn3Days, 0);
      expect(noneToday.label(compact: true), '今日无待交');
    });

    test(
        'Phase 2C AssignmentStatistics includes locallyCompleted and tracks official vs local counts',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      final localDoneWork = Assignment(
        id: 'cx:work:1:2:local',
        courseName: '计算机网络',
        title: '本机已完成作业',
        deadlineAt: now.add(const Duration(days: 2)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      final officialDoneWork = Assignment(
        id: 'cx:work:1:2:official',
        courseName: '计算机网络',
        title: '官方已交作业',
        deadlineAt: now.add(const Duration(days: 2)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'submitted',
        lastSyncedAt: now,
      );
      final stillPendingWork = Assignment(
        id: 'cx:work:1:2:pending',
        courseName: '计算机网络',
        title: '仍待提交作业',
        deadlineAt: now.add(const Duration(days: 3)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );
      final state = LocalCourseworkState()
          .withLocallyCompleted(localDoneWork.id, const [], true)
          .withLocallyCompleted(officialDoneWork.id, const [], true);

      final stats = AssignmentStatistics(
        [localDoneWork, officialDoneWork, stillPendingWork],
        now: now,
        coursework: state,
      );
      expect(stats.officialCompleted, 1);
      expect(stats.localCompleted, 1);
      expect(stats.completed, 2);
      expect(stats.pending, 1);
      expect(
        AssignmentStatistics.isPendingCourseAttention(
          localDoneWork,
          now,
          coursework: state,
        ),
        isFalse,
      );
    });
  });
}
