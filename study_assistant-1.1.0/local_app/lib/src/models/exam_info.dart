/// Metadata from list surfaces only. No question, grade or access token is kept.
class ExamInfo {
  const ExamInfo(
      {required this.examId,
      this.relatedExamId,
      this.courseId,
      this.clazzId,
      this.startAt,
      this.endAt,
      this.startTrusted = false,
      this.endTrusted = false,
      this.durationMinutes,
      this.location = '',
      this.lifecycle = 'unknown',
      this.noticeOnly = false,
      this.noticeStartAt,
      this.noticeEndAt});
  final String examId;

  /// Verified exam identity referenced by a notice; never its business ID.
  final String? relatedExamId;
  final String? courseId, clazzId;
  final DateTime? startAt, endAt;
  final DateTime? noticeStartAt, noticeEndAt;
  final bool startTrusted, endTrusted, noticeOnly;
  final int? durationMinutes;
  final String location, lifecycle;

  /// Keep unavailable historical time visible, without reusing it for alarms.
  ExamInfo retainingHistoricalTimes(ExamInfo previous) {
    final start = startAt ?? previous.startAt, end = endAt ?? previous.endAt;
    final ordered = start == null || end == null || !end.isBefore(start);
    final keepNoticeAnchor = noticeOnly &&
        previous.noticeOnly &&
        examId == previous.examId &&
        courseId == previous.courseId &&
        clazzId == previous.clazzId;
    final keepRelatedExamId = keepNoticeAnchor &&
        courseId != null &&
        courseId!.trim().isNotEmpty &&
        clazzId != null &&
        clazzId!.trim().isNotEmpty;
    var nextNoticeStart =
        noticeStartAt ?? (keepNoticeAnchor ? previous.noticeStartAt : null);
    var nextNoticeEnd =
        noticeEndAt ?? (keepNoticeAnchor ? previous.noticeEndAt : null);
    if (nextNoticeStart != null &&
        nextNoticeEnd != null &&
        nextNoticeEnd.isBefore(nextNoticeStart)) {
      // Drop incompatible history. A reversed pair from this read is invalid.
      final freshRangeReversed = noticeStartAt != null &&
          noticeEndAt != null &&
          noticeEndAt!.isBefore(noticeStartAt!);
      nextNoticeStart = freshRangeReversed ? null : noticeStartAt;
      nextNoticeEnd = freshRangeReversed ? null : noticeEndAt;
    }
    return ExamInfo(
        examId: examId,
        relatedExamId: relatedExamId ??
            (keepRelatedExamId ? previous.relatedExamId : null),
        courseId: courseId,
        clazzId: clazzId,
        startAt: start,
        endAt: end,
        startTrusted: startAt != null && startTrusted && ordered,
        endTrusted: endAt != null && endTrusted && ordered,
        durationMinutes: durationMinutes ?? previous.durationMinutes,
        location: location.isEmpty ? previous.location : location,
        lifecycle: lifecycle,
        noticeOnly: noticeOnly,
        noticeStartAt: nextNoticeStart,
        noticeEndAt: nextNoticeEnd);
  }

  Map<String, dynamic> toJson() => {
        'examId': examId,
        if (relatedExamId != null) 'relatedExamId': relatedExamId,
        'courseId': courseId,
        'clazzId': clazzId,
        'startAt': startAt?.toUtc().toIso8601String(),
        'endAt': endAt?.toUtc().toIso8601String(),
        'startTrusted': startTrusted,
        'endTrusted': endTrusted,
        'durationMinutes': durationMinutes,
        'location': location,
        'lifecycle': lifecycle,
        'noticeOnly': noticeOnly,
        if (noticeOnly && noticeStartAt != null)
          'noticeStartAt': noticeStartAt!.toUtc().toIso8601String(),
        if (noticeOnly && noticeEndAt != null)
          'noticeEndAt': noticeEndAt!.toUtc().toIso8601String(),
      };
  factory ExamInfo.fromJson(Map<String, dynamic> j) {
    DateTime? time(String key) {
      final raw = j[key];
      return raw is String &&
              RegExp(r'(?:[zZ]|[+-]\d{2}:?\d{2})$').hasMatch(raw)
          ? DateTime.tryParse(raw)?.toLocal()
          : null;
    }

    final start = time('startAt'), end = time('endAt');
    final validRange = start == null || end == null || !end.isBefore(start);
    final noticeOnly = j['noticeOnly'] == true;
    var noticeStart = noticeOnly ? time('noticeStartAt') : null;
    var noticeEnd = noticeOnly ? time('noticeEndAt') : null;
    if (noticeStart != null &&
        noticeEnd != null &&
        noticeEnd.isBefore(noticeStart)) {
      noticeStart = null;
      noticeEnd = null;
    }
    final related = j['relatedExamId'];
    final course = j['courseId'] as String?, clazz = j['clazzId'] as String?;
    if (related != null &&
        (related is! String ||
            RegExp(r'[0-9]+').matchAsPrefix(related)?.end != related.length ||
            !noticeOnly ||
            course == null ||
            course.trim().isEmpty ||
            clazz == null ||
            clazz.trim().isEmpty)) {
      throw const FormatException('考试通知关联身份无效');
    }
    return ExamInfo(
        examId: j['examId'] as String,
        relatedExamId: related as String?,
        courseId: course,
        clazzId: clazz,
        startAt: start,
        endAt: end,
        startTrusted: j['startTrusted'] == true && start != null && validRange,
        endTrusted: j['endTrusted'] == true && end != null && validRange,
        durationMinutes:
            j['durationMinutes'] is int && (j['durationMinutes'] as int) > 0
                ? j['durationMinutes'] as int
                : null,
        location: j['location'] as String? ?? '',
        lifecycle: const {
          'scheduled',
          'inProgress',
          'ended',
          'cancelled',
          'unknown'
        }.contains(j['lifecycle'])
            ? j['lifecycle'] as String
            : 'unknown',
        noticeOnly: noticeOnly,
        noticeStartAt: noticeStart,
        noticeEndAt: noticeEnd);
  }
}
