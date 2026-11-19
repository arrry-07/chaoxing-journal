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

enum AssignmentTypeFilter {
  all('全部'),
  homework('作业'),
  task('任务'),
  exam('考试'),
  examNotice('考试通知');

  const AssignmentTypeFilter(this.label);
  final String label;
}

const homeTypeFilterChoices = [
  AssignmentTypeFilter.all,
  AssignmentTypeFilter.homework,
  AssignmentTypeFilter.exam
];
const homeSortOrderChoices = [
  HomeSortOrder.deadlineAsc,
  HomeSortOrder.deadlineDesc,
  HomeSortOrder.courseName
];
HomeSortOrder normalizedHomeSort(HomeSortOrder order) =>
    order == HomeSortOrder.grouped || order == HomeSortOrder.title
        ? HomeSortOrder.deadlineAsc
        : order;
AssignmentTypeFilter normalizedHomeType(AssignmentTypeFilter type) =>
    switch (type) {
      AssignmentTypeFilter.task => AssignmentTypeFilter.homework,
      AssignmentTypeFilter.examNotice => AssignmentTypeFilter.exam,
      _ => type,
    };

/// UI preferences only; relative deadlines are evaluated against the current time.
class HomeFilters {
  const HomeFilters({
    this.query = '',
    this.courseKey,
    this.deadline = AssignmentDeadlineFilter.all,
    this.sortOrder = HomeSortOrder.deadlineAsc,
    this.type = AssignmentTypeFilter.all,
  });

  final String query;
  final String? courseKey;
  final AssignmentDeadlineFilter deadline;
  final HomeSortOrder sortOrder;
  final AssignmentTypeFilter type;

  String encode() => jsonEncode({
        'query': query.trim(),
        'courseKey': courseKey,
        'deadline': deadline.name,
        'sortOrder': sortOrder.name,
        'type': type.name,
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
          type: normalizedHomeType(AssignmentTypeFilter.values
                  .where((type) => type.name == value['type'])
                  .firstOrNull ??
              AssignmentTypeFilter.all),
          sortOrder: normalizedHomeSort(sortOrder));
    } catch (_) {
      return const HomeFilters();
    }
  }
}
