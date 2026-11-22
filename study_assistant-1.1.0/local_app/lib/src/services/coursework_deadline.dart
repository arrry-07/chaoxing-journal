import 'package:flutter/foundation.dart';

import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import 'assignment_grouping.dart';

enum CourseworkDeadlineSource { official, manual }

@immutable
class CourseworkDeadline {
  const CourseworkDeadline({
    required this.at,
    required this.source,
  });

  final DateTime at;
  final CourseworkDeadlineSource source;

  bool get isManual => source == CourseworkDeadlineSource.manual;
  bool get isOfficial => source == CourseworkDeadlineSource.official;

  static String keyFor(Assignment assignment) =>
      AssignmentGrouping.examKey(assignment) ??
      assignment.courseTaskKey ??
      assignment.id;

  static Set<String> aliasesFor(Assignment assignment) => {
        keyFor(assignment),
        assignment.id,
        if (assignment.courseTaskKey != null) assignment.courseTaskKey!,
      };

  static bool sameUtcMinute(DateTime left, DateTime right) {
    final a = left.toUtc();
    final b = right.toUtc();
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  static bool canSetManualDeadline(Assignment assignment) =>
      !assignment.isExam &&
      !assignment.isCompleted &&
      assignment.isInAssignmentScope &&
      (!assignment.deadlineTrusted || assignment.deadlineReadFailed);

  /// Read-only deadline projection keeping official trusted decisions primary
  /// and preventing overtaken stale manual deadlines from resurrecting.
  static CourseworkDeadline? resolve(
    Assignment assignment,
    DateTime? manualDeadlineAt, {
    bool officialTakenOver = false,
  }) {
    if (assignment.isExam) {
      final startAt = assignment.exam?.startAt;
      if (assignment.exam?.startTrusted == true && startAt != null) {
        return CourseworkDeadline(
          at: startAt,
          source: CourseworkDeadlineSource.official,
        );
      }
      return null;
    }
    if (assignment.deadlineTrusted && !assignment.deadlineReadFailed) {
      final officialAt = assignment.deadlineAt;
      if (officialAt == null) return null;
      return CourseworkDeadline(
        at: officialAt,
        source: CourseworkDeadlineSource.official,
      );
    }
    if (officialTakenOver || manualDeadlineAt == null) return null;
    return CourseworkDeadline(
      at: manualDeadlineAt,
      source: CourseworkDeadlineSource.manual,
    );
  }

  static LocalCourseworkEntry? entryFor(
    Assignment assignment,
    LocalCourseworkState state,
  ) {
    if (assignment.isExam || state.isEmpty) return null;
    return state.entryForAliases(aliasesFor(assignment));
  }

  static CourseworkDeadline? resolveEntry(
    Assignment assignment,
    LocalCourseworkEntry? entry,
  ) =>
      resolve(
        assignment,
        entry?.manualDeadlineAt,
        officialTakenOver: entry?.officialTakenOver == true,
      );

  static CourseworkDeadline? resolveFor(
    Assignment assignment,
    LocalCourseworkState state,
  ) =>
      resolveEntry(assignment, entryFor(assignment, state));

  /// Projects the unified deadline bucket without mutating or promoting
  /// official server trust flags.
  static AssignmentDeadlineBucket bucketAt(
    Assignment assignment,
    DateTime now, {
    LocalCourseworkEntry? entry,
    LocalCourseworkState? state,
  }) {
    if (assignment.isCompleted) return AssignmentDeadlineBucket.completed;
    if (assignment.isExam) {
      if (!assignment.timelineTrusted ||
          assignment.timelineAt == null ||
          !assignment.isPendingConfirmed ||
          assignment.exam?.lifecycle == 'ended' ||
          assignment.exam?.lifecycle == 'cancelled' ||
          (assignment.exam?.endTrusted == true &&
              assignment.exam?.endAt != null &&
              !assignment.exam!.endAt!.isAfter(now))) {
        return AssignmentDeadlineBucket.unconfirmed;
      }
      return AssignmentDeadlineBucket.notExpiredWithDeadline;
    }
    final resolvedEntry =
        entry ?? (state == null ? null : entryFor(assignment, state));
    final resolved = resolveEntry(assignment, resolvedEntry);
    if (resolved == null || resolved.isOfficial) {
      return assignment.deadlineBucketAt(now);
    }
    if (assignment.status == 'overdue') {
      return !resolved.at.isAfter(now)
          ? AssignmentDeadlineBucket.overdue
          : AssignmentDeadlineBucket.unconfirmed;
    }
    if (!assignment.isPendingConfirmed) {
      return AssignmentDeadlineBucket.unconfirmed;
    }
    return resolved.at.isAfter(now)
        ? AssignmentDeadlineBucket.notExpiredWithDeadline
        : AssignmentDeadlineBucket.overdue;
  }

  /// Reconciles persisted manual deadlines against fresh official records.
  ///
  /// - Same UTC minute under a trusted official read -> silently clears manual.
  /// - Different trusted official read (or confirmed no-deadline) -> retains old
  ///   manual value for comparison while marking [officialTakenOver] true so a
  ///   later transient read failure cannot resurrect it.
  static LocalCourseworkState reconcileWithAssignments(
    LocalCourseworkState state,
    Iterable<Assignment> records,
  ) {
    if (state.isEmpty) return state;
    var next = state;
    for (final assignment in records) {
      if (assignment.isExam) continue;
      final canonicalKey = keyFor(assignment);
      final aliases = aliasesFor(assignment);
      final existing = next.entryForAliases(aliases);
      if (existing == null || existing.manualDeadlineAt == null) continue;
      final officialTrusted =
          assignment.deadlineTrusted && !assignment.deadlineReadFailed;
      if (officialTrusted) {
        final officialAt = assignment.deadlineAt;
        if (officialAt != null &&
            sameUtcMinute(officialAt, existing.manualDeadlineAt!)) {
          next = next.withEntry(canonicalKey, aliases, null);
        } else {
          next = next.withEntry(
            canonicalKey,
            aliases,
            existing.copyWith(officialTakenOver: true),
          );
        }
      } else {
        // Normalize key onto canonical key without altering takeover state.
        if (next.entries[canonicalKey] != existing) {
          next = next.withEntry(canonicalKey, aliases, existing);
        }
      }
    }
    return next;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CourseworkDeadline &&
        at.toUtc() == other.at.toUtc() &&
        source == other.source;
  }

  @override
  int get hashCode => Object.hash(at.toUtc(), source);
}
