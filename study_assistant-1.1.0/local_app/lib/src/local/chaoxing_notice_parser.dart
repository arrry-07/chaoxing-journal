import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/course_notice.dart';
import 'chaoxing_api_parser.dart';
import 'chaoxing_exam_parser.dart';
import 'chaoxing_param_helper.dart';

class ChaoxingNoticeParser {
  const ChaoxingNoticeParser._();

  static final RegExp _urlPattern =
      RegExp(r'https?://[^\s<>"\x27\uFF09\)]+', caseSensitive: false);

  static String sanitizeNoticeText(String raw) {
    var clean = ChaoxingExamParser.noticeBodyForDisplay(raw);
    if (clean.isEmpty) {
      clean = ChaoxingExamParser.text(raw);
    }
    clean = clean.replaceAllMapped(_urlPattern, (match) {
      final rawUrl = match[0]!;
      final uri = Uri.tryParse(rawUrl);
      if (uri == null || uri.host.isEmpty) return '';
      return '${uri.scheme}://${uri.host}${uri.path}';
    });
    if (clean.length > 4000) {
      clean = clean.substring(0, 4000);
    }
    return clean.trim();
  }

  static final _publicationTimePattern = RegExp(
    r'^(\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?)(?:\s+(\d{1,2}[:：]\d{2}(?:[:：]\d{2})?))?$',
  );

  static ({DateTime? at, bool trusted}) _parsePublishMeta(Object? sendTime) {
    final raw = switch (sendTime) {
      int value => value.toString(),
      String value => value.trim(),
      _ => '',
    };
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      final epoch = int.tryParse(raw);
      if (epoch == null || epoch <= 0) return (at: null, trusted: false);
      final millis = epoch < 100000000000 ? epoch * 1000 : epoch;
      if (millis > 8640000000000000) return (at: null, trusted: false);
      return (at: DateTime.fromMillisecondsSinceEpoch(millis), trusted: true);
    }

    final match = _publicationTimePattern.firstMatch(raw);
    if (match == null) return (at: null, trusted: false);
    final day = match[1]!, clock = match[2];
    final at = ChaoxingExamParser.chinaTime('$day ${clock ?? '00:00'}');
    return (at: at, trusted: at != null && clock != null);
  }

  static DateTime? _extractEventTime(String body) {
    final labeled =
        RegExp(r'(?:截止时间|提交时间|活动时间|考试开始时间|开考时间|结束时间|时间)\s*[:：]\s*([^\n]+)')
            .allMatches(body)
            .map((m) => ChaoxingExamParser.chinaTime(m[1]!))
            .whereType<DateTime>()
            .toList();
    if (labeled.length == 1) return labeled.single;
    if (labeled.length > 1) return labeled.first;
    return null;
  }

  static ({String? courseId, String? clazzId, String courseName})
      _resolveCourse(
    dynamic attachment,
    String title,
    String body,
    List<ChaoxingCourseRef> courses,
  ) {
    dynamic decoded = attachment;
    if (attachment is String && attachment.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(attachment);
      } on FormatException {
        decoded = null;
      }
    }
    if (decoded is List) {
      for (final wrapper in decoded) {
        if (wrapper is! Map) continue;
        final card = wrapper['att_web'] ?? wrapper['att_chat_course'];
        if (card is Map) {
          final courseId = ChaoxingParamHelper.singleMapValue(
              card, ChaoxingParamHelper.courseIdKeys);
          final clazzId = ChaoxingParamHelper.singleMapValue(
              card, ChaoxingParamHelper.clazzIdKeys);
          final name = (card['courseName'] ?? card['title'])?.toString().trim();
          if (courseId != null &&
              clazzId != null &&
              RegExp(r'^[1-9]\d*$').hasMatch(courseId) &&
              RegExp(r'^[1-9]\d*$').hasMatch(clazzId)) {
            final matched = courses
                .where((c) => c.courseId == courseId && c.clazzId == clazzId)
                .firstOrNull;
            return (
              courseId: courseId,
              clazzId: clazzId,
              courseName: matched?.courseName ??
                  (name != null && name.isNotEmpty ? name : '课程通知'),
            );
          }
        }
      }
    }

    if (courses.isNotEmpty) {
      final byName = <String, List<ChaoxingCourseRef>>{};
      for (final c in courses) {
        (byName[c.courseName.trim()] ??= []).add(c);
      }
      final candidates = <ChaoxingCourseRef>[];
      for (final entry in byName.entries) {
        if (entry.value.length != 1) continue;
        final name = entry.key;
        if (name.length < 2) continue;
        final inTitle = title.contains('《$name》') ||
            title.startsWith(name) ||
            title.contains('[$name]') ||
            title.contains('【$name】');
        final inBody = RegExp('^课程名称\\s*[:：]\\s*${RegExp.escape(name)}\\s*\$',
                multiLine: true)
            .hasMatch(body);
        if (inTitle || inBody) {
          candidates.add(entry.value.single);
        }
      }
      if (candidates.length == 1) {
        final c = candidates.single;
        return (
          courseId: c.courseId,
          clazzId: c.clazzId,
          courseName: c.courseName,
        );
      }
    }

    final explicitName = RegExp(r'^课程名称\s*[:：]\s*(.+?)\s*$', multiLine: true)
        .firstMatch(body)?[1]
        ?.trim();
    return (
      courseId: null,
      clazzId: null,
      courseName: explicitName != null && explicitName.isNotEmpty
          ? explicitName
          : '通知中心',
    );
  }

  static ({List<CourseNotice> rows, String? cursor})? parsePage(
    dynamic payload, {
    List<ChaoxingCourseRef> courses = const [],
    DateTime? now,
  }) {
    if (payload is! Map || payload['status'] != true) return null;
    final box = payload['notices'];
    if (box == null) return (rows: <CourseNotice>[], cursor: null);
    if (box is! Map || box['list'] is! List) return null;
    final syncedAt = now ?? DateTime.now();
    final rows = <CourseNotice>[];
    for (final item in box['list'] as List) {
      if (item is! Map || item['title'] is! String) return null;
      final rawUuid = item['uuid'];
      if (rawUuid is! String ||
          rawUuid.isEmpty ||
          rawUuid.length > 512 ||
          rawUuid.trim() != rawUuid ||
          RegExp(r'[\x00-\x20\x7f]').hasMatch(rawUuid)) {
        return null;
      }
      final title = sanitizeNoticeText(item['title'] as String);
      if (title.isEmpty) continue;
      final content = sanitizeNoticeText((item['content'] ?? '').toString());
      final rich = sanitizeNoticeText((item['rtf_content'] ?? '').toString());
      final summary = [content, if (rich.isNotEmpty && rich != content) rich]
          .where((s) => s.isNotEmpty)
          .join('\n');
      final boundedSummary =
          summary.length > 4000 ? summary.substring(0, 4000) : summary;
      final course = _resolveCourse(
        item['attachment'],
        title,
        boundedSummary,
        courses,
      );
      final published = _parsePublishMeta(item['sendTime']);
      final extractedAt = _extractEventTime(boundedSummary);
      final sender = ChaoxingExamParser.text(
        (item['createrName'] ?? '').toString(),
      );
      final boundedSender =
          sender.length > 120 ? sender.substring(0, 120) : sender;
      final digest = sha256.convert(utf8.encode(rawUuid)).toString();
      rows.add(CourseNotice(
        id: 'cx:notice:$digest',
        courseId: course.courseId,
        clazzId: course.clazzId,
        courseName: course.courseName.length > 200
            ? course.courseName.substring(0, 200)
            : course.courseName,
        senderName: boundedSender,
        title: title.length > 500 ? title.substring(0, 500) : title,
        summary: boundedSummary,
        publishedAt: published.at,
        publishedTrusted: published.trusted,
        extractedEventAt: extractedAt,
        extractedEventTrusted: extractedAt != null,
        platformUnread: item['isread']?.toString() == '0',
        localRead: false,
        lastSyncedAt: syncedAt,
      ));
    }
    final list = box['list'] as List;
    final cursor = box['lastGetId']?.toString();
    final hasNext = list.isNotEmpty &&
        box['lastPage'] != true &&
        cursor != null &&
        cursor.isNotEmpty;
    return (rows: rows, cursor: hasNext ? cursor : null);
  }
}
