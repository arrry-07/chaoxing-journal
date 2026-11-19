import '../local/chaoxing_exam_parser.dart';

/// A wall-clock value from a notice. It is display evidence, not a trusted
/// scheduling instant.
class ExamWallTime {
  const ExamWallTime(
      this.year, this.month, this.day, this.hour, this.minute, this.second);

  final int? year, second;
  final int month, day, hour, minute;

  String get key => '$year:$month:$day:$hour:$minute:${second ?? 0}';

  String get label {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${year == null ? '' : '$year-'}'
        '${two(month)}-${two(day)} ${two(hour)}:${two(minute)}'
        '${second == null ? '' : ':${two(second!)}'}';
  }

  bool matches(DateTime instant) {
    final value = instant.toUtc().add(const Duration(hours: 8));
    return (year == null || year == value.year) &&
        month == value.month &&
        day == value.day &&
        hour == value.hour &&
        minute == value.minute &&
        (second == null || second == value.second);
  }

  /// Project wall time into an ordering instant. A missing year uses
  /// [displayYear]; the result is never persisted or promoted to trust.
  DateTime? projectedAt(int displayYear) {
    final effectiveYear = year ?? displayYear;
    final local =
        DateTime.utc(effectiveYear, month, day, hour, minute, second ?? 0);
    if (local.year != effectiveYear ||
        local.month != month ||
        local.day != day ||
        local.hour != hour ||
        local.minute != minute) {
      return null;
    }
    return local.subtract(const Duration(hours: 8));
  }

  static final _pattern = RegExp(
      r'(?<!\d)(?:(\d{4})[-/年])?(\d{1,2})[-/月](\d{1,2})日?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?(?![\d:])');

  static List<ExamWallTime> read(String text) {
    final result = <ExamWallTime>[];
    final matches = _pattern.allMatches(text).toList();
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
    for (final match in matches) {
      final year = int.tryParse(match[1] ?? '');
      final month = int.parse(match[2]!);
      final day = int.parse(match[3]!);
      final hour = int.parse(match[4]!);
      final minute = int.parse(match[5]!);
      final second = int.tryParse(match[6] ?? '');
      final check = DateTime.utc(year ?? 2000, month, day);
      if ((year != null && year < 1) ||
          check.month != month ||
          check.day != day ||
          hour > 23 ||
          minute > 59 ||
          (second != null && second > 59)) {
        return [];
      }
      result.add(ExamWallTime(year, month, day, hour, minute, second));
    }
    return result;
  }
}

class ExamNoticeRange {
  const ExamNoticeRange(this.start, this.end);

  final ExamWallTime? start, end;

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

  static const _labels =
      '考试起止时间|起止时间|考试时间|考试开始时间|开始时间|开考时间|考试结束时间|结束时间|截止时间|答题时长|考试时长|时长|课程名称|试卷名称|考试名称|考试地点|地点';

  static List<String> _fields(String body, String name) => RegExp(
          '(?:^|[ \\t;；。])(?:$name)[ \\t]*[:：][ \\t]*(.*?)(?=\\n|[ \\t]+(?:$_labels|[\\u4e00-\\u9fff]{2,16}|[A-Za-z][A-Za-z ]{1,24})[ \\t]*[:：]|\$)',
          multiLine: true)
      .allMatches(body)
      .map((match) => match[1]!.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  static ExamNoticeRange? read(String raw) {
    final body = ChaoxingExamParser.noticeBodyForDisplay(raw);
    final values = _fields(body, '考试起止时间|起止时间|考试时间');
    if (values.length > 1) return null;
    if (values.isNotEmpty) {
      final range = ExamWallTime.read(values.single);
      return range.length == 2 ? ExamNoticeRange(range[0], range[1]) : null;
    }
    final startValues = _fields(body, '考试开始时间|开始时间|开考时间');
    final endValues = _fields(body, '考试结束时间|结束时间|截止时间');
    if (startValues.length > 1 || endValues.length > 1) return null;
    final starts = ExamWallTime.read(startValues.firstOrNull ?? '');
    final ends = ExamWallTime.read(endValues.firstOrNull ?? '');
    if (starts.length > 1 ||
        ends.length > 1 ||
        (starts.isEmpty && ends.isEmpty)) {
      return null;
    }
    return ExamNoticeRange(starts.firstOrNull, ends.firstOrNull);
  }
}
