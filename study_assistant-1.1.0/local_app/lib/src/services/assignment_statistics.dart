import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import 'assignment_query.dart';
import 'coursework_deadline.dart';

enum AssignmentStatBucket { completed, pending, expired, unknown }

class AssignmentStatistics {
  static AssignmentStatBucket classify(
    Assignment a,
    DateTime referenceTime, {
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    if (CourseworkDeadline.isEffectivelyCompleted(a, coursework)) {
      return AssignmentStatBucket.completed;
    }
    if (a.isExam) {
      if (a.exam!.noticeOnly || AssignmentQuery.isExamEnded(a, referenceTime)) {
        return AssignmentStatBucket.unknown;
      }
      return a.isPendingConfirmed
          ? AssignmentStatBucket.pending
          : AssignmentStatBucket.unknown;
    }
    switch (CourseworkDeadline.bucketAt(a, referenceTime, state: coursework)) {
      case AssignmentDeadlineBucket.completed:
        return AssignmentStatBucket.completed;
      case AssignmentDeadlineBucket.overdue:
        return AssignmentStatBucket.expired;
      case AssignmentDeadlineBucket.notExpiredWithDeadline:
      case AssignmentDeadlineBucket.confirmedNoDeadline:
        return AssignmentStatBucket.pending;
      case AssignmentDeadlineBucket.unconfirmed:
        return a.isPendingConfirmed
            ? AssignmentStatBucket.pending
            : AssignmentStatBucket.unknown;
    }
  }

  /// Whether a record is counted in the Stats overview completion ratio and
  /// status buckets. Pure broadcast exam notices (`exam.noticeOnly`) that have
  /// not been marked completed stay visible in Local Records ("全部状态") while
  /// being excluded from overview completion denominators and status buckets.
  static bool isCountedInOverview(
    Assignment a, {
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    if (CourseworkDeadline.isEffectivelyCompleted(a, coursework)) {
      return true;
    }
    if (a.isExam && a.exam != null && a.exam!.noticeOnly) {
      return false;
    }
    return true;
  }

  /// Whether a record needs active student follow-up inside the per-course
  /// "各课程待处理" list.
  ///
  /// Completed work (official or marked locally), cancelled/ended exams, pure
  /// broadcast exam notices (`noticeOnly`), and elapsed historical classroom
  /// practices without confirmed submission status stay accessible in Local
  /// Records and Overview counts, without cluttering actionable per-course
  /// pending rows.
  static bool isPendingCourseAttention(
    Assignment a,
    DateTime referenceTime, {
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    if (CourseworkDeadline.isEffectivelyCompleted(a, coursework)) return false;
    if (a.isExam) {
      if (a.exam!.noticeOnly || AssignmentQuery.isExamEnded(a, referenceTime)) {
        return false;
      }
    }
    if (AssignmentQuery.isArchivedClassroomPractice(a, referenceTime)) {
      return false;
    }
    return true;
  }

  AssignmentStatistics(
    Iterable<Assignment> records, {
    DateTime? now,
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    final referenceTime = now ?? DateTime.now();
    for (final a in records) {
      switch (classify(a, referenceTime, coursework: coursework)) {
        case AssignmentStatBucket.completed:
          if (a.isCompleted) {
            officialCompleted++;
          } else {
            localCompleted++;
          }
        case AssignmentStatBucket.expired:
          expired++;
        case AssignmentStatBucket.pending:
          pending++;
        case AssignmentStatBucket.unknown:
          unknown++;
      }
    }
  }
  int officialCompleted = 0,
      localCompleted = 0,
      pending = 0,
      expired = 0,
      unknown = 0;
  int get completed => officialCompleted + localCompleted;
  int get total => completed + pending + expired + unknown;
  List<int> get counts => [completed, pending, expired, unknown];
  // Keep the headline completion rate conventionally rounded, independent of
  // how unfinished work is split. Apportion the remaining labels to total 100;
  // the ring angles always use the exact counts.
  List<int> get percentages {
    if (total == 0) return [0, 0, 0, 0];
    final out = counts.map((n) => n * 100 ~/ total).toList();
    out[0] = (completed * 100 / total).round();
    final order = [1, 2, 3]..sort((a, b) {
        final c = (counts[b] * 100 % total).compareTo(counts[a] * 100 % total);
        return c == 0 ? a.compareTo(b) : c;
      });
    final remainder = 100 - out.reduce((a, b) => a + b);
    for (var i = 0; i < remainder; i++) {
      out[order[i]]++;
    }
    return out;
  }
}
