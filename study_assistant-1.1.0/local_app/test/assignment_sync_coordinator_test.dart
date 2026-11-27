import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_term_preferences.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/models/sync_scope.dart';
import 'package:study_assistant_mobile/src/services/assignment_sync_coordinator.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';

void main() {
  final daytime = DateTime(2026, 11, 27, 12);

  test('selection uses the fetched class keys and term evidence per scope', () {
    final refs = [
      const ChaoxingCourseRef(
        courseId: '1',
        clazzId: 'a',
        courseName: 'Current class',
        cpi: 'request-context',
      ),
      ChaoxingCourseRef(
        courseId: '1',
        clazzId: 'b',
        courseName: 'Past class of the same course',
        courseStartAt: DateTime(2025, 9, 15),
      ),
      const ChaoxingCourseRef(
        courseId: '2',
        clazzId: 'a',
        courseName: 'Blocked class',
      ),
    ];
    SyncScopeSelection select(AssignmentSyncScope scope) =>
        AssignmentSyncCoordinator.buildSyncCourseSelector(
          scope: scope,
          targetedCourseKeys: {'1:b'},
          buildTermCatalog: (courses) => _catalog(
            courses,
            now: daytime,
            preferences: CourseTermPreferences(entries: const {
              '1:a': CourseTermOverride(manualTermKey: '2026-fall'),
              '2:a': CourseTermOverride(blockMode: CourseBlockMode.blocked),
            }),
          ),
        )(refs);

    final current = select(AssignmentSyncScope.current);
    expect(current.targetCourses, [same(refs.first)]);
    expect(current.skippedCourseKeys, {'1:b', '2:a'});
    expect(current.includeAccountExams, isTrue);

    final all = select(AssignmentSyncScope.all);
    expect(all.targetCourses, refs.take(2));
    expect(all.skippedCourseKeys, {'2:a'});
    expect(all.includeAccountExams, isTrue);

    for (final scope in [
      AssignmentSyncScope.targeted,
      AssignmentSyncScope.historicalSweep,
    ]) {
      final selected = select(scope);
      expect(selected.scope, scope);
      expect(selected.targetCourses, [refs[1]]);
      expect(selected.skippedCourseKeys, {'1:a', '2:a'});
      expect(selected.includeAccountExams, isFalse);
    }
  });

  group('historical sweep', () {
    final catalog = _catalog(
      [
        for (var id = 1; id <= 7; id++)
          CourseRef(courseId: '$id', clazzId: 'a', name: 'Course $id'),
      ],
      now: daytime,
      preferences: CourseTermPreferences(entries: {
        for (var id = 1; id <= 5; id++)
          '$id:a': const CourseTermOverride(
            archiveMode: CourseArchiveMode.archived,
          ),
        '6:a': const CourseTermOverride(
          archiveMode: CourseArchiveMode.archived,
          blockMode: CourseBlockMode.blocked,
        ),
        '7:a': const CourseTermOverride(manualTermKey: '2026-fall'),
      }),
      unfollowed: {'5:a'},
    );
    final state = HistoricalSweepState(
      lastBatchAtUtc: daytime.subtract(const Duration(hours: 24)).toUtc(),
      cursorIndex: 1,
      pendingRetryKeys: const ['4:a', '5:a', '6:a', '7:a'],
    );

    HistoricalSweepPlan? plan({
      DateTime? at,
      DateTime? backoff,
      Iterable<SyncIssue> issues = const [],
      String? error,
      SyncPhase phase = SyncPhase.success,
    }) =>
        AssignmentSyncCoordinator.planHistoricalSweep(
          phase: phase,
          operationError: error,
          issues: issues,
          clock: () => at ?? daytime,
          serverBackoffUntil: backoff,
          readTermCatalog: () => catalog,
          state: state,
        );

    test('requires daytime success without auth, verification or retry holds',
        () {
      expect(plan(phase: SyncPhase.partial), isNull);
      expect(plan(error: 'primary sync warning'), isNull);
      expect(plan(at: DateTime(2026, 11, 27, 7, 59)), isNull);
      expect(plan(backoff: daytime.add(const Duration(seconds: 1))), isNull);
      for (final kind in [
        SyncIssueKind.verificationRequired,
        SyncIssueKind.rateLimited,
        SyncIssueKind.authExpired,
      ]) {
        expect(plan(issues: [SyncIssue(kind, 'blocked')]), isNull);
      }
      expect(plan(backoff: daytime), isNotNull);
    });

    test('at 24h only followed archived classes enter the capped retry batch',
        () {
      expect(plan(at: daytime.subtract(const Duration(seconds: 1))), isNull);
      final due = plan()!;
      expect(due.courseKeys, ['4:a', '2:a', '3:a']);
      final next = due.recordResult(
        state,
        reportedFailedKeys: {'2:a', '5:a'},
        abortedMidBatch: false,
      );
      expect(next.pendingRetryKeys, ['2:a']);
      expect(next.lastBatchAtUtc, daytime.toUtc());
      expect(next.cursorIndex, 3);

      final aborted = due.recordResult(
        state,
        reportedFailedKeys: {},
        abortedMidBatch: true,
      );
      expect(aborted.pendingRetryKeys, due.courseKeys);
    });
  });

  test('backoff honors the longest positive delay and clears only on success',
      () {
    const issues = [
      SyncIssue(SyncIssueKind.network, 'no delay'),
      SyncIssue(SyncIssueKind.serverError, 'expired', retryAfterSeconds: -1),
      SyncIssue(SyncIssueKind.rateLimited, 'short', retryAfterSeconds: 10),
      SyncIssue(SyncIssueKind.rateLimited, 'long', retryAfterSeconds: 40),
    ];
    final backoff = AssignmentSyncCoordinator.serverBackoffUpdate;
    expect(
      backoff(issues: issues, phase: SyncPhase.failed, clock: () => daytime)
          ?.until,
      daytime.add(const Duration(seconds: 40)),
    );
    expect(
      backoff(
        issues: issues.take(2),
        phase: SyncPhase.partial,
        clock: () => fail('keeping backoff must not need a clock'),
      ),
      isNull,
    );
    expect(
      backoff(
        issues: const [],
        phase: SyncPhase.success,
        clock: () => fail('clearing backoff must not need a clock'),
      ),
      (until: null),
    );
  });

  test('cancelled report keeps prior success times and uses current counters',
      () {
    final dataAt = daytime.subtract(const Duration(hours: 1));
    final fullAt = daytime.subtract(const Duration(days: 1));
    final current = SyncReport(
      phase: SyncPhase.running,
      attemptedAt: daytime,
      lastDataSuccessAt: dataAt,
      lastCurrentSuccessAt: dataAt,
      syncScope: AssignmentSyncScope.targeted,
      plannedCourses: 4,
      skippedCourses: 1,
      issues: const [SyncIssue(SyncIssueKind.network, 'old issue')],
    );
    final result = AssignmentSyncCoordinator.cancelledReport(
      current,
      lastFullSuccessAt: fullAt,
      succeededCourses: 2,
      failedCourses: 1,
    );
    expect(result.phase, SyncPhase.cancelled);
    expect(result.attemptedAt, daytime);
    expect(result.lastDataSuccessAt, dataAt);
    expect(result.lastCurrentSuccessAt, dataAt);
    expect(result.lastFullSuccessAt, fullAt);
    expect(result.syncScope, AssignmentSyncScope.targeted);
    expect(result.plannedCourses, 4);
    expect(result.skippedCourses, 1);
    expect(result.succeededCourses, 2);
    expect(result.failedCourses, 1);
    expect(result.issues.single.kind, SyncIssueKind.cancelled);
    expect(result.issues.single.stage, 'request');
  });

  test('failed report keeps collected issues and attributes storage separately',
      () {
    const readIssue = SyncIssue(SyncIssueKind.rateLimited, 'retry later');
    final previousFullAt = daytime.subtract(const Duration(days: 1));
    SyncReport report(Object error, {List<SyncIssue> issues = const []}) =>
        AssignmentSyncCoordinator.failedReport(
          SyncReport(
              phase: SyncPhase.running, lastFullSuccessAt: previousFullAt),
          lastAttemptAt: daytime,
          lastFullSuccessAt: null,
          readIssues: issues,
          error: error,
          message: 'friendly message',
        );

    final storage = report(
      const LocalStorageWriteException('storage timeout'),
      issues: const [readIssue],
    );
    expect(storage.phase, SyncPhase.failed);
    expect(storage.attemptedAt, daytime);
    expect(storage.lastFullSuccessAt, previousFullAt);
    expect(storage.issues.first, same(readIssue));
    expect(storage.issues.last.kind, SyncIssueKind.storage);
    expect(storage.issues.last.stage, 'persistence');
    expect(storage.issues.last.message, 'friendly message');

    expect(report(StateError('network'), issues: const [readIssue]).issues,
        [readIssue]);
    expect(report(const SyncReadException(readIssue)).issues.single, readIssue);
    expect(report(const ChaoxingAuthenticationException()).issues.single.kind,
        SyncIssueKind.authExpired);
    expect(report(StateError('network')).issues.single.kind,
        SyncIssueKind.network);
  });
}

CourseTermCatalog _catalog(
  Iterable<CourseRef> courses, {
  required DateTime now,
  required CourseTermPreferences preferences,
  Set<String> unfollowed = const {},
}) =>
    CourseTermCatalog.build(
      courses: courses,
      assignments: const [],
      notices: const [],
      preferences: preferences,
      now: now,
      unfollowedCourseKeys: unfollowed,
    );
