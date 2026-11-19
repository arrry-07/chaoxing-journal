import 'package:intl/intl.dart';

import '../models/assignment.dart';
import 'assignment_query.dart';
import 'exam_wall_time.dart';

/// A wall-time label for list layout, never a persisted scheduling instant.
class ExamTimelineStamp {
  const ExamTimelineStamp(
      {required this.key, required this.heading, required this.clock});

  final String key, heading, clock;

  static ExamTimelineStamp _fromWallTime(ExamWallTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final year = time.year;
    final weekday = year == null
        ? ''
        : ' 周${'一二三四五六日'[DateTime.utc(year, time.month, time.day).weekday - 1]}';
    return ExamTimelineStamp(
      key: '${year ?? 'notice'}:${time.month}:${time.day}',
      heading:
          '${year == null ? '' : '$year年'}${time.month}月${time.day}日$weekday',
      clock: '${two(time.hour)}:${two(time.minute)}',
    );
  }

  /// Long windows read as a range so an opening date alone cannot look expired.
  static ExamTimelineStamp _range(ExamWallTime start, ExamWallTime end) {
    final from = _fromWallTime(start);
    final endYear = end.year != start.year ? '${end.year}年' : '';
    return ExamTimelineStamp(
      key: 'range:${from.key}:${end.year ?? 'notice'}:${end.month}:${end.day}',
      heading: '${from.heading}–$endYear${end.month}月${end.day}日',
      clock: from.clock,
    );
  }
}

/// Display-only evidence. These labels never change reminder or calendar trust.
class ExamSchedulePresentation {
  const ExamSchedulePresentation(
      this.cardTimeLines, this.detailTimeLines, this.verificationNote,
      {this.timeline});

  final List<String> cardTimeLines, detailTimeLines;
  final String? verificationNote;
  final ExamTimelineStamp? timeline;
  static Expando<_PresentationCacheEntry> _cache =
      Expando<_PresentationCacheEntry>();

  static void debugResetCache() {
    _cache = Expando<_PresentationCacheEntry>();
  }

  static ExamSchedulePresentation build(Assignment a,
      {List<Assignment> records = const [], AssignmentDisplayIndex? index}) {
    final cacheKey = index ?? records;
    final cached = _cache[a];
    if (cached != null && identical(cached.sourceKey, cacheKey)) {
      return cached.value;
    }
    final value = _build(a, records, index);
    _cache[a] = _PresentationCacheEntry(cacheKey, value);
    return value;
  }

  static ExamSchedulePresentation _build(
      Assignment a, List<Assignment> records, AssignmentDisplayIndex? index) {
    final exam = a.exam;
    if (exam == null) {
      return const ExamSchedulePresentation([], [], null);
    }
    final displayRanges =
        AssignmentQuery.displayNoticeRanges(a, records: records, index: index);
    final ranges = <String, ExamNoticeRange>{
      for (final range in displayRanges) range.key: range,
    };
    final trustedStart =
        exam.startTrusted && exam.startAt != null ? exam.startAt! : null;
    final start =
        trustedStart == null ? null : AssignmentQuery.beijing(trustedStart);
    final wallStart = start != null
        ? ExamWallTime(start.year, start.month, start.day, start.hour,
            start.minute, start.second)
        : ranges.length == 1
            ? ranges.values.single.start
            : null;
    ExamWallTime? wallEnd;
    if (exam.endTrusted && exam.endAt != null) {
      final value = AssignmentQuery.beijing(exam.endAt!);
      wallEnd = ExamWallTime(value.year, value.month, value.day, value.hour,
          value.minute, value.second);
    } else if (ranges.length == 1) {
      wallEnd = ranges.values.single.end;
    } else if (trustedStart != null &&
        exam.durationMinutes != null &&
        exam.durationMinutes! > 0) {
      final value = AssignmentQuery.beijing(
          trustedStart.add(Duration(minutes: exam.durationMinutes!)));
      wallEnd = ExamWallTime(value.year, value.month, value.day, value.hour,
          value.minute, value.second);
    }
    final crossDay = wallStart != null &&
        wallEnd != null &&
        (wallEnd.year != wallStart.year ||
            wallEnd.month != wallStart.month ||
            wallEnd.day != wallStart.day);
    final timeline = wallStart == null
        ? null
        : crossDay
            ? ExamTimelineStamp._range(wallStart, wallEnd)
            : ExamTimelineStamp._fromWallTime(wallStart);
    ExamSchedulePresentation result(
            List<String> card, List<String> detail, String? note) =>
        ExamSchedulePresentation(card, detail, note, timeline: timeline);
    String absolute(DateTime value, bool explicitSeconds) =>
        DateFormat(explicitSeconds || value.second != 0
                ? 'yyyy年M月d日 HH:mm:ss'
                : 'yyyy年M月d日 HH:mm')
            .format(AssignmentQuery.beijing(value));
    final startSeconds =
        ranges.values.any((range) => range.start?.second != null);
    final endSeconds = ranges.values.any((range) => range.end?.second != null);
    final trusted = <String>[
      if (trustedStart != null) '开考 ${absolute(trustedStart, startSeconds)}',
      if (exam.endTrusted && exam.endAt != null)
        '结束 ${absolute(exam.endAt!, endSeconds)}',
    ];
    if (trustedStart != null && exam.endTrusted && exam.endAt != null) {
      return result(trusted, trusted, null);
    }
    if (ranges.length > 1) {
      final labels = ranges.values.map((range) => range.label).toList()..sort();
      return result(trusted, [...trusted, ...labels], '通知时间存在不一致，请查看官方通知');
    }
    if (ranges.isEmpty) return result(trusted, trusted, null);
    final range = ranges.values.single;
    final lines = trusted.isEmpty
        ? <String>[range.label]
        : <String>[
            ...trusted,
            if (trustedStart == null && range.start != null)
              '开考（通知） ${range.start!.label}',
            if (!exam.endTrusted && range.end != null)
              '结束（通知） ${range.end!.label}',
          ];
    return result(lines, lines,
        range.missingYear ? '通知未注明年份，暂不作为定时依据' : '通知原文时间尚未核实，暂不作为定时依据');
  }
}

class _PresentationCacheEntry {
  const _PresentationCacheEntry(this.sourceKey, this.value);
  final Object sourceKey;
  final ExamSchedulePresentation value;
}
