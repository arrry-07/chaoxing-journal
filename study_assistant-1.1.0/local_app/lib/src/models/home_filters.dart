import 'dart:convert';

enum AssignmentDeadlineFilter {
  all,
  next7Days,
  next30Days,
  overdue,
  uncertain,
  noDeadline,
  notExpired,
}

const homeDeadlineFilterChoices = [
  AssignmentDeadlineFilter.all,
  AssignmentDeadlineFilter.notExpired,
  AssignmentDeadlineFilter.overdue,
];

enum HomeSortOrder {
  grouped,
  deadlineAsc,
  deadlineDesc,
  courseName,
  title,
}

/// UI preferences only; relative deadlines are evaluated against the current time.
class HomeFilters {
  const HomeFilters({
    this.query = '',
    this.courseKey,
    this.deadline = AssignmentDeadlineFilter.all,
    this.sortOrder = HomeSortOrder.grouped,
  });

  final String query;
  final String? courseKey;
  final AssignmentDeadlineFilter deadline;
  final HomeSortOrder sortOrder;

  String encode() => jsonEncode({
        'query': query.trim(),
        'courseKey': courseKey,
        'deadline': deadline.name,
        'sortOrder': sortOrder.name,
      });

  factory HomeFilters.decode(String? raw) {
    if (raw == null) return const HomeFilters();
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['query'] is! String ||
          (value['courseKey'] != null && value['courseKey'] is! String)) {
        return const HomeFilters();
      }
      final encodedDeadline = AssignmentDeadlineFilter.values
          .where((f) => f.name == value['deadline'])
          .firstOrNull;
      if (encodedDeadline == null) return const HomeFilters();
      final deadline = switch (encodedDeadline) {
        AssignmentDeadlineFilter.noDeadline =>
          AssignmentDeadlineFilter.notExpired,
        AssignmentDeadlineFilter.next7Days ||
        AssignmentDeadlineFilter.next30Days ||
        AssignmentDeadlineFilter.uncertain =>
          AssignmentDeadlineFilter.all,
        _ => encodedDeadline,
      };
      final sortOrder = HomeSortOrder.values
              .where((order) => order.name == value['sortOrder'])
              .firstOrNull ??
          HomeSortOrder.grouped;
      return HomeFilters(
          query: (value['query'] as String).trim(),
          courseKey: value['courseKey'] == '' ? null : value['courseKey'],
          deadline: deadline,
          sortOrder: sortOrder);
    } catch (_) {
      return const HomeFilters();
    }
  }
}
