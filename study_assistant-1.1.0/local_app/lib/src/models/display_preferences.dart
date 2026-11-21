import 'dart:convert';
import '../services/assignment_query.dart';
import 'assignment.dart';

enum WidgetRange { all, today, week }

enum JournalThemeMode {
  system('跟随系统'),
  light('浅色手记'),
  dark('夜间深色');

  const JournalThemeMode(this.label);
  final String label;
}

class DisplayPreferences {
  const DisplayPreferences({
    this.compact = false,
    this.countdown = false,
    this.widgetRange = WidgetRange.all,
    this.themeMode = JournalThemeMode.system,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });
  final bool compact, countdown;
  final WidgetRange widgetRange;
  final JournalThemeMode themeMode;
  final bool soundEnabled, hapticsEnabled;

  DisplayPreferences copyWith({
    bool? compact,
    bool? countdown,
    WidgetRange? widgetRange,
    JournalThemeMode? themeMode,
    bool? soundEnabled,
    bool? hapticsEnabled,
  }) =>
      DisplayPreferences(
        compact: compact ?? this.compact,
        countdown: countdown ?? this.countdown,
        widgetRange: widgetRange ?? this.widgetRange,
        themeMode: themeMode ?? this.themeMode,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      );

  String encode() => jsonEncode({
        'compact': compact,
        'countdown': countdown,
        'range': widgetRange.name,
        'themeMode': themeMode.name,
        'sound': soundEnabled,
        'haptics': hapticsEnabled,
      });

  factory DisplayPreferences.decode(String? raw) {
    try {
      final j = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      return DisplayPreferences(
        compact: j['compact'] == true,
        countdown: j['countdown'] == true,
        widgetRange: WidgetRange.values.firstWhere(
          (r) => r.name == j['range'],
          orElse: () => WidgetRange.all,
        ),
        themeMode: JournalThemeMode.values.firstWhere(
          (mode) => mode.name == j['themeMode'],
          orElse: () => JournalThemeMode.system,
        ),
        soundEnabled: j['sound'] != false,
        hapticsEnabled: j['haptics'] != false,
      );
    } catch (_) {
      return const DisplayPreferences();
    }
  }

  List<Assignment> forWidget(List<Assignment> items, DateTime now) {
    final display = AssignmentQuery.currentDisplay(items, now);
    if (widgetRange == WidgetRange.all) return display;
    final today = AssignmentQuery.dayKey(now);
    final days = widgetRange == WidgetRange.today ? 1 : 7;
    final end = DateTime(today.year, today.month, today.day + days);
    return display
        .where((a) =>
            AssignmentQuery.timelineBucketAt(a, now) ==
                AssignmentDeadlineBucket.notExpiredWithDeadline &&
            a.timelineAt != null &&
            a.timelineTrusted &&
            (a.isExam || !a.deadlineReadFailed) &&
            !AssignmentQuery.dayKey(a.timelineAt!).isBefore(today) &&
            AssignmentQuery.dayKey(a.timelineAt!).isBefore(end))
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
