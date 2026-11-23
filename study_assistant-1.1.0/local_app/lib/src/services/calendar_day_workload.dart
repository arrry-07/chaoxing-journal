import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import '../models/study_notebook.dart';
import 'assignment_grouping.dart';
import 'assignment_query.dart';
import 'coursework_deadline.dart';

class CalendarDayWorkload {
  const CalendarDayWorkload._();

  static const int busyThreshold = 3;

  /// Counts distinct active unfinished coursework, trusted exams, and dated
  /// personal manual entries on one calendar day.
  static int countForDay({
    required Iterable<Assignment> assignments,
    required Iterable<ManualEntry> manualEntries,
    required DateTime now,
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    final seenAssignments = <String>{};
    for (final assignment in assignments) {
      if (!assignment.isInAssignmentScope ||
          AssignmentQuery.isArchivedPastTerm(assignment, now) ||
          AssignmentQuery.isArchivedClassroomPractice(assignment, now) ||
          CourseworkDeadline.isEffectivelyCompleted(assignment, coursework)) {
        continue;
      }
      final String key;
      if (assignment.isExam) {
        if (AssignmentQuery.isExamEnded(assignment, now) ||
            assignment.exam?.startTrusted != true ||
            assignment.exam?.startAt == null) {
          continue;
        }
        key = AssignmentGrouping.examKey(assignment) ??
            assignment.courseTaskKey ??
            assignment.id;
      } else {
        if (AssignmentQuery.effectiveDeadline(
              assignment,
              coursework: coursework,
            ) ==
            null) {
          continue;
        }
        key = assignment.courseTaskKey ?? assignment.id;
      }
      seenAssignments.add(key);
    }

    final seenManual = <String>{};
    for (final entry in manualEntries) {
      if (entry.done || entry.at == null) continue;
      seenManual.add('manual:${entry.id}');
    }
    return seenAssignments.length + seenManual.length;
  }

  static Map<DateTime, int> countsByDay({
    required Map<DateTime, List<Assignment>> assignmentsByDay,
    required Map<DateTime, List<ManualEntry>> manualByDay,
    required DateTime now,
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    final allDays = <DateTime>{
      ...assignmentsByDay.keys,
      ...manualByDay.keys,
    };
    return {
      for (final day in allDays)
        day: countForDay(
          assignments: assignmentsByDay[day] ?? const <Assignment>[],
          manualEntries: manualByDay[day] ?? const <ManualEntry>[],
          now: now,
          coursework: coursework,
        ),
    };
  }

  static bool isBusyCount(int count) => count >= busyThreshold;
}
