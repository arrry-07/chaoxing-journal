import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import '../models/study_notebook.dart';
import 'assignment_grouping.dart';
import 'assignment_query.dart';
import 'coursework_deadline.dart';

@immutable
class TodoCopyResult {
  const TodoCopyResult({required this.text, required this.count});

  static const empty = TodoCopyResult(text: null, count: 0);

  final String? text;
  final int count;

  bool get isEmpty => count == 0 || text == null || text!.isEmpty;
}

class _CopyTodoEntry {
  const _CopyTodoEntry({
    required this.identityKey,
    required this.beijingDay,
    required this.at,
    required this.rawTitle,
    required this.rawCourseName,
    required this.isExam,
    required this.isManual,
  });

  final String identityKey;
  final DateTime beijingDay;
  final DateTime at;
  final String rawTitle;
  final String rawCourseName;
  final bool isExam;
  final bool isManual;
}

class TodoCopyFormatter {
  const TodoCopyFormatter._();

  static final RegExp _controlAndBidi = RegExp(
    r'[\x00-\x1F\x7F-\x9F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
  );
  static final RegExp _httpUrl = RegExp(r'https?://\S+', caseSensitive: false);
  static final RegExp _wwwUrl = RegExp(r'\bwww\.\S+', caseSensitive: false);
  static final RegExp _chaoxingUrl = RegExp(
    r'\b[a-z0-9.-]*chaoxing\.com\S*',
    caseSensitive: false,
  );
  static final RegExp _signedQueryParam = RegExp(
    r'(?:^|[\s?&;])(?:enc|cpi|token|sign|sig|cookie|session|jsessionid|uid|_uid|_d|vc3|uf|fid|auth|secret|password|passwd|pwd|account|username)=[^\s&;)）\]]+',
    caseSensitive: false,
  );
  static final RegExp _bearerToken = RegExp(
    r'\bBearer\s+[A-Za-z0-9._\-~+/]+=*',
    caseSensitive: false,
  );
  static final RegExp _accountField = RegExp(
    r'(?:学号|账号|用户名|姓名|手机号|手机|电话|密码|口令|cookie|token|session|authorization)\s*[:：=]\s*[^\s)）\]]+',
    caseSensitive: false,
  );
  static final RegExp _email = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );
  static final RegExp _mainlandPhone = RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)');
  static final RegExp _hexToken = RegExp(r'\b[0-9a-fA-F]{24,}\b');
  static final RegExp _longDigits = RegExp(r'(?<!\d)\d{10,}(?!\d)');
  static final RegExp _emptyBrackets = RegExp(
    r'\(\s*[,，;；、\s]*\)|（\s*[,，;；、\s]*）|\[\s*[,，;；、\s]*\]',
  );
  static final RegExp _multiSpace = RegExp(r'\s+');

  /// Strips control/bidi chars, URLs, signed tokens, and PII-like fields
  /// before exporting plain-text summaries to the clipboard.
  static String sanitizeField(String raw) {
    var cleaned = raw
        .replaceAll(_controlAndBidi, ' ')
        .replaceAll(_httpUrl, ' ')
        .replaceAll(_wwwUrl, ' ')
        .replaceAll(_chaoxingUrl, ' ')
        .replaceAll(_signedQueryParam, ' ')
        .replaceAll(_bearerToken, ' ')
        .replaceAll(_accountField, ' ')
        .replaceAll(_email, ' ')
        .replaceAll(_mainlandPhone, ' ')
        .replaceAll(_hexToken, ' ')
        .replaceAll(_longDigits, ' ');
    String previous;
    do {
      previous = cleaned;
      cleaned = cleaned.replaceAll(_emptyBrackets, ' ');
    } while (cleaned != previous);
    return cleaned.replaceAll(_multiSpace, ' ').trim();
  }

  /// Formats active deadlines, trusted exams, and dated personal entries
  /// spanning Beijing calendar days `[today, today + 6]`.
  static TodoCopyResult formatNext7Days(
    List<Assignment> catalogAssignments, {
    List<ManualEntry> manualEntries = const [],
    required DateTime now,
    AssignmentDisplayIndex? index,
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    final todayDay = AssignmentQuery.dayKey(now);
    final lastDay = DateTime(todayDay.year, todayDay.month, todayDay.day + 6);
    final projected = AssignmentQuery.projectDisplay(
      catalogAssignments,
      index: index,
    );

    final seenKeys = <String>{};
    final items = <_CopyTodoEntry>[];

    for (final assignment in projected) {
      if (!assignment.isInAssignmentScope ||
          AssignmentQuery.isArchivedPastTerm(assignment, now) ||
          AssignmentQuery.isArchivedClassroomPractice(assignment, now) ||
          CourseworkDeadline.isEffectivelyCompleted(assignment, coursework)) {
        continue;
      }
      final identityKey = AssignmentGrouping.examKey(assignment) ??
          assignment.courseTaskKey ??
          assignment.id;
      if (!seenKeys.add(identityKey)) continue;

      if (assignment.isExam) {
        final exam = assignment.exam!;
        if (AssignmentQuery.isExamEnded(assignment, now) ||
            exam.noticeOnly ||
            !exam.startTrusted ||
            exam.startAt == null) {
          continue;
        }
        final startAt = exam.startAt!;
        if (startAt.isBefore(now)) continue;
        final day = AssignmentQuery.dayKey(startAt);
        if (day.isBefore(todayDay) || day.isAfter(lastDay)) continue;
        items.add(_CopyTodoEntry(
          identityKey: identityKey,
          beijingDay: day,
          at: startAt,
          rawTitle: assignment.title,
          rawCourseName: assignment.courseName,
          isExam: true,
          isManual: false,
        ));
      } else {
        if (!assignment.isFormal && !assignment.isSupportedClassroomTask) {
          continue;
        }
        if (AssignmentQuery.timelineBucketAt(
              assignment,
              now,
              coursework: coursework,
            ) !=
            AssignmentDeadlineBucket.notExpiredWithDeadline) {
          continue;
        }
        final resolved = AssignmentQuery.effectiveDeadline(
          assignment,
          coursework: coursework,
        );
        if (resolved == null) continue;
        final day = AssignmentQuery.dayKey(resolved.at);
        if (day.isBefore(todayDay) || day.isAfter(lastDay)) continue;
        items.add(_CopyTodoEntry(
          identityKey: identityKey,
          beijingDay: day,
          at: resolved.at,
          rawTitle: assignment.title,
          rawCourseName: assignment.courseName,
          isExam: false,
          isManual: resolved.isManual,
        ));
      }
    }

    for (final entry in manualEntries) {
      final at = entry.at;
      if (entry.done || at == null) continue;
      final isExam = entry.kind == 'exam';
      if (isExam ? at.isBefore(now) : !at.isAfter(now)) continue;
      final day = AssignmentQuery.dayKey(at);
      if (day.isBefore(todayDay) || day.isAfter(lastDay)) continue;
      final identityKey = 'manual:${entry.id}';
      if (!seenKeys.add(identityKey)) continue;
      items.add(_CopyTodoEntry(
        identityKey: identityKey,
        beijingDay: day,
        at: at,
        rawTitle: entry.title,
        rawCourseName: entry.course,
        isExam: isExam,
        isManual: true,
      ));
    }

    if (items.isEmpty) return TodoCopyResult.empty;

    items.sort((left, right) {
      final dayCmp = left.beijingDay.compareTo(right.beijingDay);
      if (dayCmp != 0) return dayCmp;
      final timeCmp = left.at.toUtc().compareTo(right.at.toUtc());
      if (timeCmp != 0) return timeCmp;
      return left.identityKey.compareTo(right.identityKey);
    });

    final crossYear = todayDay.year != lastDay.year;
    String rangeBound(DateTime day) => crossYear
        ? '${day.year}年${day.month}月${day.day}日'
        : '${day.month}月${day.day}日';

    final buffer = StringBuffer()
      ..write('近 7 天待办（${rangeBound(todayDay)}–${rangeBound(lastDay)}，北京时间）');

    DateTime? currentDay;
    for (final item in items) {
      if (currentDay != item.beijingDay) {
        currentDay = item.beijingDay;
        final weekday = '一二三四五六日'[currentDay.weekday - 1];
        final showYear = currentDay.year != todayDay.year;
        buffer
          ..write('\n\n')
          ..write(
            '${showYear ? '${currentDay.year}年' : ''}'
            '${currentDay.month}月${currentDay.day}日 周$weekday',
          );
      }
      final timeStr =
          DateFormat('HH:mm').format(AssignmentQuery.beijing(item.at));
      final kindTag =
          '${item.isExam ? '开考' : '截止'}${item.isManual ? '（手动）' : ''}';
      final sanitizedTitle = sanitizeField(item.rawTitle);
      final title = sanitizedTitle.isEmpty
          ? (item.isExam ? '未命名考试' : '未命名待办')
          : sanitizedTitle;
      final course = sanitizeField(item.rawCourseName);
      buffer.write('\n- $timeStr $kindTag');
      if (course.isNotEmpty) {
        buffer.write(' · $course');
      }
      buffer.write(' · $title');
    }

    return TodoCopyResult(text: buffer.toString(), count: items.length);
  }
}
