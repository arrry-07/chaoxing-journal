import 'dart:convert';
import '../services/assignment_query.dart';

/// UI preferences only; relative deadlines are evaluated against the current time.
class HomeFilters {
  const HomeFilters({
    this.query = '',
    this.courseKey,
    this.deadline = AssignmentDeadlineFilter.all,
  });

  final String query;
  final String? courseKey;
  final AssignmentDeadlineFilter deadline;

  String encode() => jsonEncode({
        'query': query.trim(),
        'courseKey': courseKey,
        'deadline': deadline.name,
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
      final deadline = AssignmentDeadlineFilter.values
          .where((f) => f.name == value['deadline'])
          .firstOrNull;
      if (deadline == null) return const HomeFilters();
      return HomeFilters(
          query: (value['query'] as String).trim(),
          courseKey: value['courseKey'] == '' ? null : value['courseKey'],
          deadline: deadline);
    } catch (_) {
      return const HomeFilters();
    }
  }
}
