import '../models/assignment.dart';

class HomeAssignmentGroups {
  final near = <Assignment>[],
      far = <Assignment>[],
      overdue = <Assignment>[],
      uncertain = <Assignment>[];
}

class AssignmentQuery {
  static DateTime beijing(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 8));
  static DateTime dayKey(DateTime instant) {
    final d = beijing(instant);
    return DateTime(d.year, d.month, d.day);
  }

  // An empty followed set means all courses; exclusions are applied by the store.
  static List<Assignment> scope(
          List<Assignment> records, Set<String> followed) =>
      records
          .where((a) =>
              a.isFormal &&
              (followed.isEmpty || followed.contains(a.courseKey)))
          .toList();
  static HomeAssignmentGroups home(
      List<Assignment> records, DateTime now, Set<String> followed) {
    final g = HomeAssignmentGroups();
    for (final a in scope(records, followed).where((a) => !a.isCompleted)) {
      final d = a.deadlineAt;
      if (!a.isPendingConfirmed || d == null || !a.deadlineTrusted) {
        g.uncertain.add(a);
      } else if (d.isBefore(now)) {
        g.overdue.add(a);
      } else if (d.isAfter(now.add(const Duration(days: 30)))) {
        g.far.add(a);
      } else {
        g.near.add(a);
      }
    }
    for (final list in [g.near, g.far, g.uncertain]) {
      list.sort(Assignment.compareByDeadline);
    }
    g.overdue.sort((a, b) => Assignment.compareByDeadline(b, a));
    return g;
  }

  static List<Assignment> forDay(
          List<Assignment> records, DateTime day, Set<String> followed) =>
      scope(records, followed)
          .where((a) =>
              !a.isCompleted &&
              a.deadlineAt != null &&
              a.deadlineTrusted &&
              dayKey(a.deadlineAt!) == DateTime(day.year, day.month, day.day))
          .toList()
        ..sort(Assignment.compareByDeadline);
}
