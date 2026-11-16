import 'package:intl/intl.dart';
import '../local/chaoxing_exam_parser.dart';
import '../models/assignment.dart';
import 'assignment_query.dart';

/// Display-only evidence. Never use these labels for ordering or alarms.
class ExamSchedulePresentation {
  const ExamSchedulePresentation(
      this.cardTimeLines, this.detailTimeLines, this.verificationNote);
  final List<String> cardTimeLines, detailTimeLines;
  final String? verificationNote;

  static ExamSchedulePresentation build(Assignment a,
      {List<Assignment> records = const []}) {
    final e = a.exam;
    if (e == null) return const ExamSchedulePresentation([], [], null);
    final sources = AssignmentQuery.displaySources(a, records);
    if (e.noticeOnly && !sources.any((s) => s.id == a.id)) sources.add(a);
    final ranges = <String, _NoticeRange>{};
    for (final source in sources.where((s) => s.exam?.noticeOnly == true)) {
      final range = _NoticeRange.read(source.requirementsText);
      if (range == null) continue;
      if ((e.startTrusted &&
              e.startAt != null &&
              range.start != null &&
              !range.start!.matches(e.startAt!)) ||
          (e.endTrusted &&
              e.endAt != null &&
              range.end != null &&
              !range.end!.matches(e.endAt!))) {
        continue;
      }
      final prior = ranges[range.key];
      if (prior == null || range.precision > prior.precision) {
        ranges[range.key] = range;
      }
    }
    String absolute(DateTime at, bool explicitSeconds) =>
        DateFormat(explicitSeconds || at.second != 0
                ? 'yyyy年M月d日 HH:mm:ss'
                : 'yyyy年M月d日 HH:mm')
            .format(AssignmentQuery.beijing(at));
    final startSeconds = ranges.values.any((r) => r.start?.second != null);
    final endSeconds = ranges.values.any((r) => r.end?.second != null);
    final trusted = <String>[
      if (e.startTrusted && e.startAt != null)
        '开考 ${absolute(e.startAt!, startSeconds)}',
      if (e.endTrusted && e.endAt != null)
        '结束 ${absolute(e.endAt!, endSeconds)}',
    ];
    if (e.startTrusted &&
        e.startAt != null &&
        e.endTrusted &&
        e.endAt != null) {
      return ExamSchedulePresentation(trusted, trusted, null);
    }
    if (ranges.length > 1) {
      final labels = ranges.values.map((r) => r.label).toList()..sort();
      return ExamSchedulePresentation(
          trusted, [...trusted, ...labels], '通知时间存在不一致，请查看官方通知');
    }
    if (ranges.isEmpty) return ExamSchedulePresentation(trusted, trusted, null);
    final range = ranges.values.single;
    final lines = trusted.isEmpty
        ? <String>[range.label]
        : <String>[
            ...trusted,
            if (!e.startTrusted && range.start != null)
              '开考（通知） ${range.start!.label}',
            if (!e.endTrusted && range.end != null)
              '结束（通知） ${range.end!.label}',
          ];
    return ExamSchedulePresentation(lines, lines,
        range.missingYear ? '通知未注明年份，暂不作为定时依据' : '通知原文时间尚未核实，暂不作为定时依据');
  }
}

class _WallTime {
  _WallTime(
      this.year, this.month, this.day, this.hour, this.minute, this.second);
  final int? year, second;
  final int month, day, hour, minute;
  String get key => '$year:$month:$day:$hour:$minute:${second ?? 0}';
  String get label {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${year == null ? '' : '$year-'}${two(month)}-${two(day)} ${two(hour)}:${two(minute)}${second == null ? '' : ':${two(second!)}'}';
  }

  bool matches(DateTime at) {
    final d = AssignmentQuery.beijing(at);
    return (year == null || year == d.year) &&
        month == d.month &&
        day == d.day &&
        hour == d.hour &&
        minute == d.minute &&
        (second == null || second == d.second);
  }

  static final pattern = RegExp(
      r'(?<!\d)(?:(\d{4})[-/年])?(\d{1,2})[-/月](\d{1,2})日?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?(?![\d:])');
  static List<_WallTime> read(String text) {
    final result = <_WallTime>[];
    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty || matches.length > 2) return [];
    final prefix = text.substring(0, matches.first.start).trim();
    if (prefix.isNotEmpty && prefix != '北京时间') return [];
    if (!RegExp(r'^[\s。.;；]*$').hasMatch(text.substring(matches.last.end))) {
      return [];
    }
    if (matches.length == 2 &&
        !RegExp(r'^\s*(?:至|到|[-—~～])\s*$')
            .hasMatch(text.substring(matches.first.end, matches.last.start))) {
      return [];
    }
    for (final m in matches) {
      final y = int.tryParse(m[1] ?? '');
      final mo = int.parse(m[2]!),
          day = int.parse(m[3]!),
          h = int.parse(m[4]!),
          min = int.parse(m[5]!);
      final sec = int.tryParse(m[6] ?? '');
      final check = DateTime.utc(y ?? 2000, mo, day);
      if ((y != null && y < 1) ||
          check.month != mo ||
          check.day != day ||
          h > 23 ||
          min > 59 ||
          (sec != null && sec > 59)) {
        return [];
      }
      result.add(_WallTime(y, mo, day, h, min, sec));
    }
    return result;
  }
}

class _NoticeRange {
  _NoticeRange(this.start, this.end);
  final _WallTime? start, end;
  String get key => '${start?.key}|${end?.key}';
  int get precision =>
      (start?.second == null ? 0 : 1) + (end?.second == null ? 0 : 1);
  bool get missingYear =>
      (start != null && start!.year == null) ||
      (end != null && end!.year == null);
  String get label => start != null && end != null
      ? '考试时间：${start!.label} 至 ${end!.label}'
      : start != null
          ? '开考（通知） ${start!.label}'
          : '结束（通知） ${end!.label}';
  static const labels =
      '考试起止时间|起止时间|考试时间|考试开始时间|开始时间|开考时间|考试结束时间|结束时间|截止时间|答题时长|考试时长|时长|课程名称|试卷名称|考试名称|考试地点|地点';
  static List<String> fields(String body, String name) => RegExp(
          '(?:^|[ \\t;；。])(?:$name)[ \\t]*[:：][ \\t]*(.*?)(?=\\n|[ \\t]+(?:$labels|[\u4e00-\u9fff]{2,16}|[A-Za-z][A-Za-z ]{1,24})[ \\t]*[:：]|\$)',
          multiLine: true)
      .allMatches(body)
      .map((m) => m[1]!.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();
  static _NoticeRange? read(String raw) {
    final body = ChaoxingExamParser.noticeBodyForDisplay(raw);
    final values = fields(body, '考试起止时间|起止时间|考试时间');
    if (values.length > 1) return null;
    if (values.isNotEmpty) {
      final range = _WallTime.read(values.single);
      return range.length == 2 ? _NoticeRange(range[0], range[1]) : null;
    }
    final startValues = fields(body, '考试开始时间|开始时间|开考时间');
    final endValues = fields(body, '考试结束时间|结束时间|截止时间');
    if (startValues.length > 1 || endValues.length > 1) return null;
    final starts = _WallTime.read(startValues.firstOrNull ?? '');
    final ends = _WallTime.read(endValues.firstOrNull ?? '');
    if (starts.length > 1 ||
        ends.length > 1 ||
        (starts.isEmpty && ends.isEmpty)) {
      return null;
    }
    return _NoticeRange(starts.firstOrNull, ends.firstOrNull);
  }
}
