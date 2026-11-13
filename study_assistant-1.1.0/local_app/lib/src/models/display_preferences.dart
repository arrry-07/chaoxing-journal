import 'dart:convert';
import '../services/assignment_query.dart';
import 'assignment.dart';

enum WidgetRange { all, today, week }

class DisplayPreferences {
  const DisplayPreferences(
      {this.compact = false,
      this.countdown = false,
      this.widgetRange = WidgetRange.all});
  final bool compact, countdown;
  final WidgetRange widgetRange;
  String encode() => jsonEncode(
      {'compact': compact, 'countdown': countdown, 'range': widgetRange.name});
  factory DisplayPreferences.decode(String? raw) {
    try {
      final j = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      return DisplayPreferences(
          compact: j['compact'] == true,
          countdown: j['countdown'] == true,
          widgetRange: WidgetRange.values.firstWhere(
              (r) => r.name == j['range'],
              orElse: () => WidgetRange.all));
    } catch (_) {
      return const DisplayPreferences();
    }
  }
  List<Assignment> forWidget(List<Assignment> items, DateTime now) {
    if (widgetRange == WidgetRange.all) return items;
    final today = AssignmentQuery.dayKey(now);
    final end =
        today.add(Duration(days: widgetRange == WidgetRange.today ? 1 : 7));
    return items
        .where((a) =>
            a.deadlineBucketAt(now) ==
                AssignmentDeadlineBucket.notExpiredWithDeadline &&
            AssignmentQuery.dayKey(a.deadlineAt!).isBefore(end))
        .toList();
  }

  static String remaining(DateTime deadline, DateTime now) {
    final minutes = (deadline.difference(now).inMilliseconds / 60000).ceil();
    if (minutes <= 0) return '已截止';
    if (minutes < 60) return '剩余$minutes分钟';
    if (minutes < 1440) return '剩余${(minutes / 60).ceil()}小时';
    return '剩余${(minutes / 1440).ceil()}天';
  }
}
