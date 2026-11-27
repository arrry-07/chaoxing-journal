import 'dart:math';

import '../local/chaoxing_local_client.dart';
import '../local/local_assignment_repository.dart';
import '../models/course.dart';
import '../models/sync_report.dart';
import '../models/sync_scope.dart';
import 'course_term_catalog.dart';
import 'daytime_check_policy.dart';

/// Pure course selection, background sweep, and reporting rules for a sync.
abstract final class AssignmentSyncCoordinator {
  static SyncCourseSelector buildSyncCourseSelector({
    required AssignmentSyncScope scope,
    required Set<String> targetedCourseKeys,
    required CourseTermCatalog Function(List<CourseRef>) buildTermCatalog,
  }) {
    return (catalog) {
      final liveCatalog = buildTermCatalog([
        for (final ref in catalog)
          CourseRef(
            courseId: ref.courseId,
            clazzId: ref.clazzId,
            name: ref.courseName,
            teacherNames: ref.teacherNames,
            folderName: ref.folderName,
            clazzName: ref.clazzName,
            courseStartAt: ref.courseStartAt,
            courseEndAt: ref.courseEndAt,
          ),
      ]);
      return SyncScopeSelection.select(
        catalog: catalog,
        scope: scope,
        termCatalog: liveCatalog,
        targetedCourseKeys: targetedCourseKeys,
      );
    };
  }

  static HistoricalSweepPlan? planHistoricalSweep({
    required SyncPhase phase,
    required String? operationError,
    required Iterable<SyncIssue> issues,
    required DateTime Function() clock,
    required DateTime? serverBackoffUntil,
    required CourseTermCatalog Function() readTermCatalog,
    required HistoricalSweepState state,
  }) {
    if (phase != SyncPhase.success || operationError != null) return null;
    if (issues.any((issue) => const {
          SyncIssueKind.verificationRequired,
          SyncIssueKind.rateLimited,
          SyncIssueKind.authExpired,
        }.contains(issue.kind))) {
      return null;
    }
    final now = clock();
    if (!DaytimeCheckPolicy.isInWindow(now)) return null;
    if (serverBackoffUntil?.isAfter(now) ?? false) return null;

    final eligibleKeys = [
      for (final entry in readTermCatalog().entries)
        if (entry.isFollowed &&
            !entry.isBlocked &&
            entry.state == CourseCatalogState.archived)
          entry.courseKey,
    ];
    final batch = state.selectNextBatch(eligibleKeys, now: now);
    if (batch.isEmpty) return null;
    return HistoricalSweepPlan._(batch, eligibleKeys, now);
  }

  /// A null result keeps the existing backoff. A record with null [until]
  /// clears a previous backoff after a successful sync.
  static ({DateTime? until})? serverBackoffUpdate({
    required Iterable<SyncIssue> issues,
    required SyncPhase phase,
    required DateTime Function() clock,
  }) {
    final seconds = issues
        .map((issue) => issue.retryAfterSeconds ?? 0)
        .where((value) => value > 0)
        .fold<int>(0, max);
    if (seconds == 0 && phase != SyncPhase.success) return null;
    return (
      until: seconds == 0 ? null : clock().add(Duration(seconds: seconds))
    );
  }

  static SyncReport cancelledReport(
    SyncReport current, {
    required DateTime? lastFullSuccessAt,
    required int succeededCourses,
    required int failedCourses,
  }) =>
      SyncReport(
        phase: SyncPhase.cancelled,
        attemptedAt: current.attemptedAt,
        lastDataSuccessAt: current.lastDataSuccessAt,
        lastCurrentSuccessAt: current.lastCurrentSuccessAt,
        lastFullSuccessAt: lastFullSuccessAt ?? current.lastFullSuccessAt,
        syncScope: current.syncScope,
        plannedCourses: current.plannedCourses,
        skippedCourses: current.skippedCourses,
        succeededCourses: succeededCourses,
        failedCourses: failedCourses,
        issues: const [
          SyncIssue(SyncIssueKind.cancelled, cancelledMessage,
              stage: 'request'),
        ],
      );

  static const cancelledMessage = '本次同步已取消';

  static SyncReport failedReport(
    SyncReport current, {
    required DateTime? lastAttemptAt,
    required DateTime? lastFullSuccessAt,
    required List<SyncIssue> readIssues,
    required Object error,
    required String message,
  }) =>
      SyncReport(
        phase: SyncPhase.failed,
        attemptedAt: current.attemptedAt ?? lastAttemptAt,
        lastDataSuccessAt: current.lastDataSuccessAt,
        lastCurrentSuccessAt: current.lastCurrentSuccessAt,
        lastFullSuccessAt: lastFullSuccessAt ?? current.lastFullSuccessAt,
        syncScope: current.syncScope,
        plannedCourses: current.plannedCourses,
        skippedCourses: current.skippedCourses,
        issues: [
          ...readIssues,
          if (error is LocalStorageWriteException)
            SyncIssue(SyncIssueKind.storage, message, stage: 'persistence')
          else if (readIssues.isEmpty)
            error is SyncReadException
                ? error.issue
                : SyncIssue(
                    error is ChaoxingAuthenticationException
                        ? SyncIssueKind.authExpired
                        : SyncIssueKind.network,
                    message,
                  ),
        ],
      );
}

class HistoricalSweepPlan {
  const HistoricalSweepPlan._(this.courseKeys, this._eligibleKeys, this._at);

  final List<String> courseKeys;
  final List<String> _eligibleKeys;
  final DateTime _at;

  HistoricalSweepState recordResult(
    HistoricalSweepState state, {
    required Set<String> reportedFailedKeys,
    required bool abortedMidBatch,
  }) =>
      state.recordBatchResult(
        plannedKeys: courseKeys,
        failedKeys: {
          ...reportedFailedKeys.where(courseKeys.contains),
          if (abortedMidBatch && reportedFailedKeys.isEmpty) ...courseKeys,
        },
        eligiblePastCourseKeys: _eligibleKeys,
        at: _at,
      );
}
