import '../models/assignment.dart';
import '../models/home_filters.dart';

export '../models/home_filters.dart'
    show AssignmentDeadlineFilter, HomeSortOrder;

enum _HomeDeadlineGroup { dated, uncertain, noDeadline }

int _compareText(String left, String right) =>
    left.trim().toLowerCase().compareTo(right.trim().toLowerCase());

int _compareCourseKey(Assignment left, Assignment right) =>
    (left.courseKey ?? '').compareTo(right.courseKey ?? '');

int _compareHomeTieBreak(Assignment left, Assignment right) {
  final course = _compareText(left.courseName, right.courseName);
  if (course != 0) return course;
  final title = _compareText(left.title, right.title);
  if (title != 0) return title;
  final courseKey = _compareCourseKey(left, right);
  if (courseKey != 0) return courseKey;
  return left.id.compareTo(right.id);
}

_HomeDeadlineGroup _homeDeadlineGroup(Assignment assignment) {
  if (assignment.deadlineTrusted &&
      !assignment.deadlineReadFailed &&
      assignment.deadlineAt != null) {
    return _HomeDeadlineGroup.dated;
  }
  if (assignment.deadlineTrusted &&
      !assignment.deadlineReadFailed &&
      assignment.deadlineAt == null) {
    return _HomeDeadlineGroup.noDeadline;
  }
  return _HomeDeadlineGroup.uncertain;
}

int _compareHomeAssignments(
    Assignment left, Assignment right, HomeSortOrder order) {
  switch (order) {
    case HomeSortOrder.grouped:
      return 0;
    case HomeSortOrder.deadlineAsc:
    case HomeSortOrder.deadlineDesc:
      final group = _homeDeadlineGroup(left)
          .index
          .compareTo(_homeDeadlineGroup(right).index);
      if (group != 0) return group;
      if (_homeDeadlineGroup(left) == _HomeDeadlineGroup.dated) {
        final deadline = left.deadlineAt!.compareTo(right.deadlineAt!);
        if (deadline != 0) {
          return order == HomeSortOrder.deadlineDesc ? -deadline : deadline;
        }
      }
      return _compareHomeTieBreak(left, right);
    case HomeSortOrder.courseName:
      final course = _compareText(left.courseName, right.courseName);
      return course == 0 ? _compareHomeTieBreak(left, right) : course;
    case HomeSortOrder.title:
      final title = _compareText(left.title, right.title);
      return title == 0 ? _compareHomeTieBreak(left, right) : title;
  }
}

class HomeAssignmentGroups {
  final near = <Assignment>[],
      far = <Assignment>[],
      overdue = <Assignment>[],
      uncertain = <Assignment>[],
      noDeadline = <Assignment>[];
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

  static bool _hasTrustedPendingDeadline(Assignment assignment) =>
      assignment.isPendingConfirmed &&
      !assignment.deadlineReadFailed &&
      assignment.deadlineTrusted;

  static bool _hasUncertainStatusOrDeadline(Assignment assignment) =>
      !assignment.isPendingConfirmed ||
      assignment.deadlineReadFailed ||
      !assignment.deadlineTrusted;

  /// Lightweight home querying only. It does not reinterpret submission or
  /// deadline states; untrusted deadline rows remain discoverable.
  static List<Assignment> filterHome(
    List<Assignment> records, {
    String query = '',
    String? courseKey,
    AssignmentDeadlineFilter deadline = AssignmentDeadlineFilter.all,
    Set<String> followed = const {},
    required DateTime now,
  }) {
    final needle = query.trim().toLowerCase();
    return scope(records, followed).where((a) {
      if (a.isCompleted || (courseKey != null && a.courseKey != courseKey)) {
        return false;
      }
      if (needle.isNotEmpty &&
          !a.title.toLowerCase().contains(needle) &&
          !a.courseName.toLowerCase().contains(needle)) {
        return false;
      }
      final due = a.deadlineAt;
      final trusted = _hasTrustedPendingDeadline(a);
      final uncertain = _hasUncertainStatusOrDeadline(a);
      return switch (deadline) {
        AssignmentDeadlineFilter.all => true,
        AssignmentDeadlineFilter.next7Days => trusted &&
            due != null &&
            due.isAfter(now) &&
            !due.isAfter(now.add(const Duration(days: 7))),
        AssignmentDeadlineFilter.next30Days => trusted &&
            due != null &&
            due.isAfter(now) &&
            !due.isAfter(now.add(const Duration(days: 30))),
        AssignmentDeadlineFilter.overdue =>
          trusted && due != null && due.isBefore(now),
        AssignmentDeadlineFilter.uncertain => uncertain,
        AssignmentDeadlineFilter.noDeadline => trusted && due == null,
      };
    }).toList();
  }

  static List<Assignment> sortHome(
      List<Assignment> records, HomeSortOrder order) {
    final sorted = List<Assignment>.of(records);
    if (order != HomeSortOrder.grouped) {
      sorted.sort((left, right) => _compareHomeAssignments(left, right, order));
    }
    return sorted;
  }

  static HomeAssignmentGroups home(
      List<Assignment> records, DateTime now, Set<String> followed) {
    final g = HomeAssignmentGroups();
    for (final a in scope(records, followed).where((a) => !a.isCompleted)) {
      final d = a.deadlineAt;
      if (_hasUncertainStatusOrDeadline(a)) {
        g.uncertain.add(a);
      } else if (d == null) {
        g.noDeadline.add(a);
      } else if (d.isBefore(now)) {
        g.overdue.add(a);
      } else if (d.isAfter(now.add(const Duration(days: 30)))) {
        g.far.add(a);
      } else {
        g.near.add(a);
      }
    }
    for (final list in [g.near, g.far, g.uncertain, g.noDeadline]) {
      list.sort((left, right) =>
          _compareHomeAssignments(left, right, HomeSortOrder.deadlineAsc));
    }
    g.overdue.sort((left, right) =>
        _compareHomeAssignments(left, right, HomeSortOrder.deadlineDesc));
    return g;
  }

  static List<Assignment> forDay(
          List<Assignment> records, DateTime day, Set<String> followed) =>
      scope(records, followed)
          .where((a) =>
              !a.isCompleted &&
              a.deadlineAt != null &&
              a.deadlineTrusted &&
              !a.deadlineReadFailed &&
              dayKey(a.deadlineAt!) == DateTime(day.year, day.month, day.day))
          .toList()
        ..sort(Assignment.compareByDeadline);
}
