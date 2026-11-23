import 'package:flutter/foundation.dart';

import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import 'assignment_grouping.dart';
import 'assignment_query.dart';
import 'coursework_deadline.dart';

@immutable
class HomeUpcomingExam {
  const HomeUpcomingExam({
    required this.assignment,
    required this.startAt,
    required this.daysUntil,
  });

  final Assignment assignment;
  final DateTime startAt;
  final int daysUntil;

  bool get isToday => daysUntil <= 0;

  String get label => isToday
      ? '近期考试 · 《${assignment.title}》今天'
      : '近期考试 · 《${assignment.title}》$daysUntil 天后';

  /// Selects the nearest trusted formal exam in `[now, now + 14 days]`.
  static HomeUpcomingExam? select(
    List<Assignment> catalogAssignments, {
    required DateTime now,
    AssignmentDisplayIndex? index,
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
    String? courseKey,
  }) {
    final projected = AssignmentQuery.projectDisplay(
      catalogAssignments,
      index: index,
    );
    final maxStart = now.add(const Duration(days: 14));
    final seenKeys = <String>{};
    final eligible = <({Assignment assignment, DateTime startAt})>[];

    for (final assignment in projected) {
      if (!assignment.isExam || !assignment.isInAssignmentScope) continue;
      if (courseKey != null && assignment.courseKey != courseKey) continue;
      if (CourseworkDeadline.isEffectivelyCompleted(assignment, coursework) ||
          assignment.isCompleted) {
        continue;
      }
      if (AssignmentQuery.isExamEnded(assignment, now) ||
          AssignmentQuery.isArchivedPastTerm(assignment, now)) {
        continue;
      }
      final exam = assignment.exam!;
      if (exam.noticeOnly ||
          !exam.startTrusted ||
          exam.startAt == null ||
          exam.lifecycle == 'cancelled' ||
          exam.lifecycle == 'ended') {
        continue;
      }
      final startAt = exam.startAt!;
      if (startAt.isBefore(now) || startAt.isAfter(maxStart)) continue;
      final identityKey = AssignmentGrouping.examKey(assignment) ??
          assignment.courseTaskKey ??
          assignment.id;
      if (!seenKeys.add(identityKey)) continue;
      eligible.add((assignment: assignment, startAt: startAt));
    }

    if (eligible.isEmpty) return null;
    eligible.sort((left, right) {
      final time = left.startAt.compareTo(right.startAt);
      if (time != 0) return time;
      final course =
          left.assignment.courseName.compareTo(right.assignment.courseName);
      if (course != 0) return course;
      final title = left.assignment.title.compareTo(right.assignment.title);
      if (title != 0) return title;
      return left.assignment.id.compareTo(right.assignment.id);
    });
    final nearest = eligible.first;
    final rawDays = AssignmentQuery.dayKey(nearest.startAt)
        .difference(AssignmentQuery.dayKey(now))
        .inDays;
    return HomeUpcomingExam(
      assignment: nearest.assignment,
      startAt: nearest.startAt,
      daysUntil: rawDays < 0 ? 0 : rawDays,
    );
  }
}
