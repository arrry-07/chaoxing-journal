import 'dart:convert';
import 'package:crypto/crypto.dart';
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
      String? relatedExamId,
      String? noticeText,
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
        relatedExamId: relatedExamId,
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
        requirementsText: notice ? noticeText ?? '考试通知，具体考试安排待核对' : '以官方考试列表为准',
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
    final metadata = _listMetadata(html);
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
      final extra = metadata[call[2]];
      final notes = extra is Map ? _noticeBody(extra['pcExamNotes']) : '';
      final duration =
          extra is Map ? _duration(extra['limitTime']?.toString()) : null;
      rows.add(make(
          id: call[2]!,
          title: text(titleMatch),
          courseId: course.courseId,
          clazzId: course.clazzId,
          courseName: course.courseName,
          status: personalStatus(states.firstOrNull ?? ''),
          stateText: states.join(' '),
          duration: duration,
          location: _field(notes, '考试地点|考场地点|考试场地|地点|考场|教室|考试地址') ?? '',
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
      if (item is! Map || item['title'] is! String) {
        return null;
      }
      final title = _withoutNoticeLinks(text(item['title'] as String));
      final mainBody = _noticeBody(item['content']);
      final richBody = _noticeBody(item['rtf_content']);
      final body = [mainBody, if (richBody != mainBody) richBody]
          .where((s) => s.isNotEmpty)
          .join('\n');
      final card = _examCard(item['attachment']);
      final examTitle = _field(body, '考试名称|试卷名称');
      final isAnnouncement =
          RegExp(r'(?:考试|补考|缓考).{0,8}(?:安排|通知|时间)|(?:安排|通知).{0,8}考试')
              .hasMatch(title);
      // Mentioning exam discipline or registration alone is not an exam event.
      if (card == null && examTitle == null && !isAnnouncement) continue;
      final rawId = item['uuid'];
      if (rawId is! String ||
          rawId.isEmpty ||
          rawId.length > 512 ||
          rawId.trim() != rawId ||
          RegExp(r'[\x00-\x20\x7f]').hasMatch(rawId)) {
        return null;
      }
      // The platform's uuid is an opaque compound resource reference, not
      // necessarily an RFC UUID. Hash it whole to retain stable portable IDs.
      final id = sha256.convert(utf8.encode(rawId)).toString();
      var start = chinaTime(_field(body, '考试开始时间|开始时间|开考时间') ?? '');
      var end = chinaTime(_field(body, '考试结束时间|结束时间|截止时间') ?? '');
      final range = _field(body, '考试起止时间|起止时间|考试时间');
      final rangeTimes = times(range ?? '');
      if (rangeTimes.length == 2) {
        start ??= rangeTimes[0];
        end ??= rangeTimes[1];
      }
      final name = examTitle ?? card?['title'] ?? title;
      rows.add(make(
          id: id,
          title: name.isEmpty ? '考试通知' : name,
          courseName: _field(body, '课程名称') ?? '考试通知',
          courseId: card?['courseId'],
          clazzId: card?['clazzId'],
          relatedExamId: card?['examId'],
          start: start,
          end: end,
          duration: _duration(_field(body, '答题时长|考试时长|时长')),
          location: _field(body, '考试地点|考场地点|考试场地|地点|考场|教室|考试地址') ?? '',
          noticeText: body.isEmpty
              ? title
              : body.substring(0, body.length > 4000 ? 4000 : body.length),
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

  static String _noticeBody(dynamic value) {
    if (value is! String || value.isEmpty) return '';
    final clean = _withoutNoticeLinks(entities(value
            .replaceAll(
                RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>',
                    caseSensitive: false),
                '')
            .replaceAll(
                RegExp(r'<br\b[^>]*>|</(?:p|div|tr|li)>', caseSensitive: false),
                '\n')
            .replaceAll(RegExp(r'<[^>]*>'), ' ')))
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('&nbsp;', ' ');
    return clean
        .split('\n')
        .map((s) => s.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((s) => s.isNotEmpty)
        .join('\n');
  }

  static String? _field(String body, String names) {
    final fields = RegExp('^(?:$names)\\s*[:：]\\s*(.+?)\\s*\$', multiLine: true)
        .allMatches(body)
        .map((m) => m[1]!.replaceAll(_noticeLinkMarker, '').trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return fields.length == 1 ? fields.single : null;
  }

  static int? _duration(String? value) {
    if (value == null) return null;
    final m =
        RegExp(r'^\s*(\d+)\s*(?:分钟|分|min(?:utes?)?)?\s*$', caseSensitive: false)
            .firstMatch(value);
    final n = int.tryParse(m?[1] ?? '');
    return n != null && n > 0 && n <= 10080 ? n : null;
  }

  static const _noticeLinkMarker = '（链接请在官方页面查看）';
  static String _withoutNoticeLinks(String value) => value.replaceAll(
      RegExp(r'''(?:https?://|/examApi/intoexamorwork\?)[^\s<>"'，。；！？）]+''',
          caseSensitive: false),
      _noticeLinkMarker);

  /// Resolve only the list's structured exam card; never open its start URL.
  static Map<String, String>? _examCard(dynamic raw) {
    dynamic attachments = raw;
    if (raw is String) {
      try {
        attachments = jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }
    if (attachments is! List) return null;
    final cards = <String, Map<String, String>>{};
    for (final wrapper in attachments) {
      final card = wrapper is Map ? wrapper['att_web'] : null;
      if (card is! Map || card['examOrWork'] != 'exam') continue;
      final course = card['courseId']?.toString(),
          clazz = card['clazzId']?.toString(),
          id = card['examOrWorkId']?.toString();
      if ([course, clazz, id]
          .any((v) => v == null || !RegExp(r'^[1-9]\d*$').hasMatch(v))) {
        continue;
      }
      final rawUrl = card['url'];
      final uri = rawUrl is String
          ? Uri.tryParse(rawUrl.replaceAll('&amp;', '&'))
          : null;
      if (uri == null ||
          !const {'https', 'http'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          uri.port != (uri.scheme == 'https' ? 443 : 80) ||
          !const {'mooc1-api.chaoxing.com', 'mooc1.chaoxing.com'}
              .contains(uri.host) ||
          uri.path != '/examApi/intoexamorwork') {
        continue;
      }
      final expected = {
        'courseid': course,
        'classid': clazz,
        'clazzid': clazz,
        'taskrefid': id,
        'workorexam': 'exam'
      };
      final found = <String>{};
      var valid = true;
      for (final entry in uri.queryParametersAll.entries) {
        final key = entry.key.toLowerCase();
        if (!expected.containsKey(key)) continue;
        if (entry.value.any((v) => v != expected[key])) {
          valid = false;
          break;
        }
        found.add(key == 'clazzid' ? 'classid' : key);
      }
      if (!valid ||
          !found.containsAll(
              {'courseid', 'classid', 'taskrefid', 'workorexam'})) {
        continue;
      }
      final name = card['title'] is String
          ? _withoutNoticeLinks(text(card['title'] as String))
          : '';
      cards['$course:$clazz:$id'] = {
        'courseId': course!,
        'clazzId': clazz!,
        'examId': id!,
        if (name.isNotEmpty) 'title': name
      };
    }
    return cards.length == 1 ? cards.values.single : null;
  }

  static Map<String, dynamic> _listMetadata(String html) {
    final marker = RegExp(r'\bTestRelationInfo\s*=\s*\{').firstMatch(html);
    if (marker == null) return const {};
    final start = marker.end - 1;
    var depth = 0, quoted = false, escaped = false;
    for (var i = start; i < html.length; i++) {
      final c = html[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
        continue;
      }
      if (c == '"') {
        quoted = true;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}' && --depth == 0) {
        try {
          final value = jsonDecode(html.substring(start, i + 1));
          return value is Map<String, dynamic> ? value : const {};
        } on FormatException {
          return const {};
        }
      }
    }
    return const {};
  }

  /// Join only explicit course/class/exam identities, preserving notice IDs.
  static List<Assignment> enrichNotices(List<Assignment> rows) {
    final exams = {
      for (final a in rows)
        if (a.hasExamIdentity &&
            !a.exam!.noticeOnly &&
            a.availability == AssignmentAvailability.available)
          a.id: a
    };
    String? key(Assignment a) =>
        a.exam?.relatedExamId == null || a.courseId == null || a.clazzId == null
            ? null
            : 'cx:exam:${a.courseId}:${a.clazzId}:${a.exam!.relatedExamId}';
    final peers = <String, List<Assignment>>{};
    for (final a in rows) {
      final k = key(a);
      if (a.isExam && a.exam!.noticeOnly && k != null) (peers[k] ??= []).add(a);
    }
    return rows.map((a) {
      if (!a.isExam || !a.exam!.noticeOnly) return a;
      final k = key(a);
      if (k == null) return a;
      final current = exams[k];
      final info = a.exam!;
      var start = info.startAt, end = info.endAt;
      var startTrusted = info.startTrusted, endTrusted = info.endTrusted;
      var location = info.location, duration = info.durationMinutes;
      var courseName = a.courseName;
      if (current != null) {
        final ref = current.exam!;
        final changed = (startTrusted &&
                ref.startTrusted &&
                start != null &&
                ref.startAt != null &&
                !start.isAtSameMomentAs(ref.startAt!)) ||
            (endTrusted &&
                ref.endTrusted &&
                end != null &&
                ref.endAt != null &&
                !end.isAtSameMomentAs(ref.endAt!));
        if (ref.startTrusted) {
          start = ref.startAt;
          startTrusted = true;
        }
        if (ref.endTrusted) {
          end = ref.endAt;
          endTrusted = true;
        }
        if (changed && !ref.startTrusted) startTrusted = false;
        if (changed && !ref.endTrusted) endTrusted = false;
        if (ref.location.isNotEmpty) {
          location = ref.location;
        } else if (changed && location.isNotEmpty) {
          location = '通知原地点：$location（已改期，请核对）';
        }
        duration = ref.durationMinutes ?? duration;
        courseName = current.courseName;
      }
      final others = (peers[k] ?? const <Assignment>[])
          .where((p) => !identical(p, a))
          .toList();
      final candidates = <String, ExamInfo>{};
      for (final peer in others) {
        final info = peer.exam!;
        if (!info.startTrusted ||
            !info.endTrusted ||
            info.startAt == null ||
            info.endAt == null) {
          continue;
        }
        final startMatches = startTrusted && start != null
            ? start.isAtSameMomentAs(info.startAt!)
            : _matchesNoticeTime(a.requirementsText, info.startAt!, true);
        final endMatches = endTrusted && end != null
            ? end.isAtSameMomentAs(info.endAt!)
            : _matchesNoticeTime(a.requirementsText, info.endAt!, false);
        if (startMatches && endMatches) {
          candidates[
                  '${info.startAt!.millisecondsSinceEpoch}:${info.endAt!.millisecondsSinceEpoch}'] =
              info;
        }
      }
      // Both endpoints must come from one matching, unambiguous full range.
      if (candidates.length == 1) {
        final range = candidates.values.single;
        if (!startTrusted) {
          start = range.startAt;
          startTrusted = true;
        }
        if (!endTrusted) {
          end = range.endAt;
          endTrusted = true;
        }
      }
      final locations = others
          .map((p) => p.exam!.location)
          .where((s) => s.isNotEmpty)
          .toSet();
      final durations =
          others.map((p) => p.exam!.durationMinutes).whereType<int>().toSet();
      final courses =
          others.map((p) => p.courseName).where((s) => s != '考试通知').toSet();
      if (location.isEmpty && locations.length == 1) {
        location = locations.single;
      }
      if (duration == null && durations.length == 1) {
        duration = durations.single;
      }
      if (courseName == '考试通知' && courses.length == 1) {
        courseName = courses.single;
      }
      final ordered = start == null || end == null || !end.isBefore(start);
      final next = ExamInfo(
          examId: info.examId,
          relatedExamId: info.relatedExamId,
          courseId: info.courseId,
          clazzId: info.clazzId,
          startAt: start,
          endAt: end,
          startTrusted: startTrusted && ordered,
          endTrusted: endTrusted && ordered,
          durationMinutes: duration,
          location: location,
          lifecycle: current?.exam?.lifecycle ??
              lifecycle('', start, end, DateTime.now()),
          noticeOnly: true);
      return a.copyWith(
          exam: next,
          courseName: courseName,
          deadlineAt: end,
          clearDeadlineAt: end == null,
          deadlineTrusted: next.endTrusted,
          status: current?.status ?? a.status,
          availability: current?.availability ?? a.availability,
          title: current?.title ?? a.title,
          clearCompletedAt: current?.isCompleted != true);
    }).toList();
  }

  static bool _matchesNoticeTime(String body, DateTime reference, bool start) {
    var raw = _field(body, start ? '考试开始时间|开始时间|开考时间' : '考试结束时间|结束时间|截止时间');
    if (raw == null) {
      final range =
          _field(body, '考试起止时间|起止时间|考试时间')?.split(RegExp(r'\s*(?:至|~|～|—)\s*'));
      if (range != null && range.length == 2) raw = range[start ? 0 : 1];
    }
    if (raw == null) return false;
    final m = RegExp(
            r'^(\d{1,2})[-/月](\d{1,2})日?\s+(\d{1,2})[:：](\d{2})(?::(\d{2}))?$')
        .firstMatch(raw.trim());
    if (m == null) return false;
    final wall = reference.toUtc().add(const Duration(hours: 8));
    return wall.month == int.parse(m[1]!) &&
        wall.day == int.parse(m[2]!) &&
        wall.hour == int.parse(m[3]!) &&
        wall.minute == int.parse(m[4]!) &&
        (m[5] == null || wall.second == int.parse(m[5]!));
  }
}
