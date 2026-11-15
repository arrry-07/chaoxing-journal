import '../models/assignment.dart';
import 'chaoxing_api_parser.dart';
import 'chaoxing_assignment_parser.dart';

/// List-only parsing. Scores, paper links and question content are discarded.
class ChaoxingExamParser {
  static String entities(String raw) => raw
      .replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (m) {
        final token = m[1]!;
        final code = int.tryParse(
            token.startsWith('x') ? token.substring(1) : token,
            radix: token.startsWith('x') ? 16 : 10);
        return code != null && code > 0 && code <= 0x10ffff
            ? String.fromCharCode(code)
            : m[0]!;
      })
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
  static String text(String raw) => raw
      .replaceAll(
          RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
          '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  static String? attr(String raw, String key) =>
      RegExp('\\b$key\\s*=\\s*(["\x27])(.*?)\\1',
              caseSensitive: false, dotAll: true)
          .firstMatch(raw)?[2]
          ?.replaceAll('&amp;', '&');
  static DateTime? chinaTime(String raw) {
    final m = RegExp(
            r'(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?')
        .firstMatch(raw);
    if (m == null) return null;
    final n = [for (var i = 1; i <= 6; i++) int.parse(m[i] ?? '0')];
    final wall = DateTime.utc(n[0], n[1], n[2], n[3], n[4], n[5]);
    if (wall.year != n[0] ||
        wall.month != n[1] ||
        wall.day != n[2] ||
        wall.hour != n[3] ||
        wall.minute != n[4] ||
        wall.second != n[5]) {
      return null;
    }
    return wall.subtract(const Duration(hours: 8)).toLocal();
  }

  static List<DateTime> times(String raw) =>
      RegExp(r'\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?\s+\d{1,2}:\d{2}(?::\d{2})?')
          .allMatches(text(raw))
          .map((m) => chinaTime(m[0]!))
          .whereType<DateTime>()
          .toList();
  static String personalStatus(String raw) {
    final v = text(raw).replaceAll(RegExp(r'\s+'), '');
    if (const {'完成', '已完成', '已交卷', '已提交', '待批阅', '已批阅', '已批改'}.contains(v)) {
      return 'submitted';
    }
    if (const {'未开始', '未开考', '待考试', '待考', '未作答', '未交卷', '进行中', '考试中', '未完成'}
        .contains(v)) {
      return 'pending';
    }
    return 'unknown';
  }

  static String lifecycle(
      String raw, DateTime? start, DateTime? end, DateTime now) {
    if (RegExp(r'已取消|考试取消').hasMatch(raw)) return 'cancelled';
    if (end != null && !end.isAfter(now)) return 'ended';
    if (start != null && start.isAfter(now)) return 'scheduled';
    if (start != null && end != null) return 'inProgress';
    if (RegExp(r'未开始|未开考').hasMatch(raw)) return 'scheduled';
    if (RegExp(r'进行中|考试中').hasMatch(raw)) return 'inProgress';
    if (RegExp(r'已结束').hasMatch(raw)) return 'ended';
    return 'unknown';
  }

  static Assignment make(
      {required String id,
      required String title,
      String? courseId,
      String? clazzId,
      String courseName = '考试',
      required String status,
      DateTime? start,
      DateTime? end,
      String location = '',
      int? duration,
      String stateText = '',
      bool notice = false,
      DateTime? now}) {
    final at = now ?? DateTime.now();
    final validRange = start == null || end == null || !end.isBefore(start);
    final info = ExamInfo(
        examId: id,
        courseId: courseId,
        clazzId: clazzId,
        startAt: start,
        endAt: end,
        startTrusted: start != null && validRange,
        endTrusted: end != null && validRange,
        durationMinutes: duration,
        location: location,
        lifecycle: lifecycle(stateText, start, end, at),
        noticeOnly: notice);
    return Assignment(
        id: notice
            ? 'cx:examNotice:inbox:$id'
            : 'cx:exam:${courseId ?? 'account'}:${clazzId ?? 'account'}:$id',
        source: AssignmentSource.exam,
        exam: info,
        courseName: courseName,
        title: title,
        deadlineAt: end,
        deadlineTrusted: info.endTrusted,
        requirementsText: notice ? '考试通知，具体考试安排待核对' : '以官方考试列表为准',
        status: status,
        lastSyncedAt: at,
        submitUrl: notice
            ? 'https://notice.chaoxing.com/pc/notice/myNotice'
            : courseId == null
                ? 'https://mooc1-api.chaoxing.com/exam-ans/exam/test/examcode/examlist'
                : Uri.https(
                    'mooc1-api.chaoxing.com',
                    '/phone/moocAnalysis/examList',
                    {'courseId': courseId, 'classId': clazzId!}).toString());
  }

  static ({List<Assignment> rows, bool more})? phone(
      String html, ChaoxingCourseRef course,
      {DateTime? now}) {
    final rows = <Assignment>[];
    final seen = <String>{};
    for (final m in RegExp(r'<tr\b([^>]*)>(.*?)</tr>',
            caseSensitive: false, dotAll: true)
        .allMatches(html)) {
      final data = attr(m[1]!, 'data');
      if (data == null) continue;
      final u = Uri.tryParse(data);
      final q = u?.queryParameters;
      final id = q?['taskrefId'];
      final cells =
          RegExp(r'<td\b[^>]*>(.*?)</td>', caseSensitive: false, dotAll: true)
              .allMatches(m[2]!)
              .toList();
      if (u == null ||
          u.path != '/exam/phone/task-exam' ||
          (u.hasAuthority && !u.host.endsWith('.chaoxing.com')) ||
          q?['courseId'] != course.courseId ||
          q?['classId'] != course.clazzId ||
          id == null ||
          !RegExp(r'^\d+$').hasMatch(id) ||
          cells.length < 3 ||
          !seen.add(id)) {
        return null;
      }
      final title = text(cells[0][1]!);
      if (title.isEmpty) return null;
      rows.add(make(
          id: id,
          title: title,
          courseId: course.courseId,
          clazzId: course.clazzId,
          courseName: course.courseName,
          status: personalStatus(cells[2][1]!),
          stateText: text(cells[2][1]!),
          now: now));
    }
    if (rows.isEmpty &&
        !RegExp(r'<p\b[^>]*class=["\x27][^"\x27]*blankTips[^"\x27]*["\x27][^>]*>\s*您好，本课程下暂未收到考试')
            .hasMatch(html)) {
      return null;
    }
    return (rows: rows, more: RegExp(r'\bhavemore\s*=\s*true').hasMatch(html));
  }

  /// PC rows are accepted only with matching hidden course/class identities.
  static ({List<Assignment> rows, int total})? coursePc(
      String html, ChaoxingCourseRef course,
      {DateTime? now}) {
    for (final entry
        in {'courseId': course.courseId, 'classId': course.clazzId}.entries) {
      if (ChaoxingAssignmentParser.hiddenValue(html, entry.key) !=
          entry.value) {
        return null;
      }
    }
    final totalMatch =
        RegExp(r'Math\.ceil\(\s*(\d+)\s*/\s*9\s*\)').firstMatch(html);
    if (totalMatch == null) return null;
    final total = int.parse(totalMatch[1]!);
    final rows = <Assignment>[];
    for (final m in RegExp(r'<li\b([^>]*)>(.*?)</li>',
            caseSensitive: false, dotAll: true)
        .allMatches(html)) {
      if (!(attr(m[1]!, 'class') ?? '').split(' ').contains('lookLi')) continue;
      final row = entities(m[2]!);
      final call =
          RegExp(r'goTest\(\s*["\x27](\d+)["\x27]\s*,\s*["\x27](\d+)["\x27]')
              .firstMatch(row);
      if (call == null || call[1] != course.courseId) return null;
      final titleMatch = RegExp(r'<a\b([^>]*)>', caseSensitive: false)
          .allMatches(row)
          .map((a) => attr(a[1]!, 'title'))
          .whereType<String>()
          .firstOrNull;
      if (titleMatch == null || text(titleMatch).isEmpty) return null;
      final ts = times(row);
      final states = RegExp(r'<strong\b[^>]*>([^<]*)', caseSensitive: false)
          .allMatches(row)
          .map((s) => text(s[1]!))
          .where((s) => s.isNotEmpty)
          .toList();
      rows.add(make(
          id: call[2]!,
          title: text(titleMatch),
          courseId: course.courseId,
          clazzId: course.clazzId,
          courseName: course.courseName,
          status: personalStatus(states.firstOrNull ?? ''),
          stateText: states.join(' '),
          start: ts.length == 2 ? ts[0] : null,
          end: ts.length == 2 ? ts[1] : null,
          now: now));
    }
    if (rows.isEmpty && (total != 0 || !text(html).contains('暂无内容'))) {
      return null;
    }
    return (rows: rows, total: total);
  }

  static ({List<Assignment> rows, int total})? account(String html,
      {DateTime? now}) {
    if (!RegExp(r'class=["\x27][^"\x27]*dataTable').hasMatch(html) ||
        !text(html).contains('作答状态')) {
      return null;
    }
    final count =
        RegExp(r'Math\.ceil\(\s*(\d+)\s*/\s*12\s*\)').firstMatch(html);
    if (count == null) return null;
    final total = int.parse(count[1]!);
    final rows = <Assignment>[];
    for (final row in RegExp(r'<tr\b([^>]*)>(.*?)</tr>',
            dotAll: true, caseSensitive: false)
        .allMatches(html)) {
      if (!(attr(row[1]!, 'class') ?? '').split(' ').contains('dataTr')) {
        continue;
      }
      final cells =
          RegExp(r'<td\b[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false)
              .allMatches(row[2]!)
              .map((m) => text(m[1]!))
              .toList();
      // A display ordinal is not an exam identity. Unsupported rows fail visibly.
      final id = attr(row[1]!, 'data-examid');
      if (id == null || !RegExp(r'^\d+$').hasMatch(id) || cells.length < 9) {
        return null;
      }
      final ts = times(cells[2]);
      rows.add(make(
          id: id,
          title: cells[1],
          status: personalStatus(cells[5]),
          stateText: cells[4],
          start: ts.isNotEmpty ? ts[0] : null,
          end: ts.length == 2 ? ts[1] : null,
          duration: int.tryParse(cells[3]),
          now: now));
    }
    if (rows.isEmpty && total != 0) return null;
    return (rows: rows, total: total);
  }

  static ({List<Assignment> rows, String? cursor})? notices(dynamic payload,
      {DateTime? now}) {
    if (payload is! Map || payload['status'] != true) return null;
    final box = payload['notices'];
    if (box == null) return (rows: <Assignment>[], cursor: null);
    if (box is! Map || box['list'] is! List) return null;
    final rows = <Assignment>[];
    for (final item in box['list'] as List) {
      if (item is! Map || item['uuid'] is! String || item['title'] is! String) {
        return null;
      }
      final id = item['uuid'] as String;
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) return null;
      final title = text(item['title'] as String);
      final content =
          item['content'] is String ? text(item['content'] as String) : '';
      // This is deliberately a candidate notice, never a formal exam or date.
      if (!'$title $content'.contains('考试')) continue;
      rows.add(make(
          id: id,
          title: title.isEmpty ? '考试通知' : title,
          courseName: '考试通知',
          status: 'unknown',
          notice: true,
          now: now));
    }
    final cursor = box['lastGetId']?.toString();
    return (
      rows: rows,
      cursor: (box['list'] as List).isEmpty || cursor == null || cursor.isEmpty
          ? null
          : cursor
    );
  }
}
