import '../models/assignment.dart';

class ChaoxingAssignmentParser {
  static List<Assignment> parseWorkHtml(
    String html, {
    required String fallbackCourseName,
    required String sourcePrefix,
    required Uri baseUri,
    DateTime? now,
  }) {
    final parsedAt = now ?? DateTime.now();
    final courseName = _firstMatch(html, [
          RegExp(
            r'class=["'
            '][^"'
            ']*course-name[^"'
            ']*["'
            '][^>]*>([^<]+)',
            caseSensitive: false,
          ),
          RegExp(
            r'class=["'
            '][^"'
            ']*courseName[^"'
            ']*["'
            '][^>]*>([^<]+)',
            caseSensitive: false,
          ),
          RegExp(r'课程[:：]\s*([^<\n\r]+)'),
        ])?.trim() ??
        fallbackCourseName;

    final itemRegex = RegExp(
      r'<(?:div|li)[^>]*(?:class=["'
      '][^"'
      ']*(?:work|homework|task|作业)[^"'
      ']*["'
      ']|data-id=["'
      '][^"'
      ']+["'
      ']|data(?:-url)?=["'
      '][^"'
      ']*(?:doHomeWork|taskrefId|workId|/work/)[^"'
      ']*["'
      '])[^>]*>.*?</(?:div|li)>',
      caseSensitive: false,
      dotAll: true,
    );
    final blocks =
        itemRegex.allMatches(html).map((match) => match.group(0)!).toList();
    final candidates = blocks;

    final seen = <String>{};
    final assignments = <Assignment>[];
    for (final block in candidates) {
      final assignment = _parseBlock(
        block,
        courseName: courseName,
        sourcePrefix: sourcePrefix,
        baseUri: baseUri,
        now: parsedAt,
      );
      if (assignment != null && seen.add(assignment.id)) {
        assignments.add(assignment);
      }
    }
    return assignments;
  }

  static Assignment? _parseBlock(
    String block, {
    required String courseName,
    required String sourcePrefix,
    required Uri baseUri,
    required DateTime now,
  }) {
    final cleanText = _decodeEntities(
      _stripTags(block),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    final deadline = _extractDeadline(cleanText, now);
    final title = _firstMatch(block, [
          RegExp(
            r'(?:data-title|title)=["'
            ']([^"'
            ']+)["'
            ']',
            caseSensitive: false,
          ),
          RegExp(
            r'class=["'
            '][^"'
            ']*(?:title|work-title|task-title)[^"'
            ']*["'
            '][^>]*>([^<]+)',
            caseSensitive: false,
          ),
          RegExp(r'<a[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true),
          RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true),
        ])?.trim() ??
        _fallbackTitle(cleanText);
    if (title.isEmpty) {
      return null;
    }

    final statusText = _statusText(block);
    if (title.contains('互评') && statusText == '已互评') return null;
    final sourceUrl = _extractSourceUrl(block);
    final sourceId = _extractSourceId(block, sourceUrl) ??
        '${_decodeEntities(_stripTags(title))}:${deadline?.rawText ?? ''}';
    final blockCourseName = _extractBlockCourseName(block, courseName);

    return Assignment(
      id: 'cx:$sourcePrefix:$sourceId',
      courseName: blockCourseName,
      title: _decodeEntities(_stripTags(title)).trim(),
      deadlineAt: deadline?.value,
      requirementsText: _extractRequirement(block, cleanText),
      status: Assignment.statusFromChaoxing(statusText, null),
      submitUrl: sourceUrl == null
          ? null
          : baseUri.resolve(_decodeEntities(sourceUrl)).toString(),
      lastSyncedAt: now,
    );
  }

  static String? _statusText(String block) {
    for (final tag
        in RegExp(r'<(p|span|em|i)\b([^>]*)>([^<]*)</\1>', caseSensitive: false)
            .allMatches(block)) {
      final value = _decodeEntities(tag[3]!).trim();
      if ((_attr(tag[2]!, 'class') ?? '')
          .split(RegExp(r'\s+'))
          .contains('status')) {
        return value;
      }
      if (tag[1] == 'span' &&
          const {'已互评', '未完成', '未提交', '已提交', '待批阅', '已批阅', '待提交'}
              .contains(value)) {
        return value;
      }
    }
    return null;
  }

  static _ParsedDeadline? _extractDeadline(String cleanText, DateTime now) {
    final absolute = RegExp(
            r'(?:截止(?:时间)?|结束时间)\s*[:：]?\s*((?:20\d{2}[-/年])?\d{1,2}[-/月]\d{1,2}日?\s+\d{1,2}:\d{2}(?::\d{2})?)')
        .firstMatch(cleanText)?[1];
    if (absolute != null) {
      final value = _parseChinaTime(absolute, now);
      if (value != null) {
        return _ParsedDeadline(rawText: absolute, value: value);
      }
    }
    final remaining = _firstMatch(cleanText, [
      RegExp(r'(剩余\s*\d+\s*天(?:\s*\d+\s*(?:小时|时))?(?:\s*\d+\s*(?:分钟|分))?)'),
      RegExp(r'(剩余\s*\d+\s*(?:小时|时)(?:\s*\d+\s*(?:分钟|分))?)'),
      RegExp(r'(剩余\s*\d+\s*(?:分钟|分))'),
    ]);
    if (remaining == null) {
      return null;
    }

    final days = _firstInt(remaining, RegExp(r'(\d+)\s*天')) ?? 0;
    final hours = _firstInt(remaining, RegExp(r'(\d+)\s*(?:小时|时)')) ?? 0;
    final minutes = _firstInt(remaining, RegExp(r'(\d+)\s*(?:分钟|分)')) ?? 0;
    return _ParsedDeadline(
      rawText: remaining,
      value: now.add(Duration(days: days, hours: hours, minutes: minutes)),
    );
  }

  static String _fallbackTitle(String cleanText) {
    return cleanText
        .replaceFirst(RegExp(r'截止时间[:：]?\s*20\d{2}.*$'), '')
        .replaceFirst(RegExp(r'剩余\s*\d+\s*(?:天|小时|时|分钟|分).*$'), '')
        .replaceAll(RegExp(r'\b(?:未提交|已提交|待批阅|已完成|已过期)\b'), '')
        .trim();
  }

  static String? _extractSourceUrl(String block) {
    return _firstMatch(block, [
      RegExp(
        r'<a[^>]+href=["'
        ']([^"'
        ']+)["'
        ']',
        caseSensitive: false,
      ),
      RegExp(
        r'data(?:-url)?=["'
        ']([^"'
        ']*(?:doHomeWork|taskrefId|workId|/work/)[^"'
        ']*)["'
        ']',
        caseSensitive: false,
      ),
    ]);
  }

  static String? _extractSourceId(String block, String? sourceUrl) {
    if (sourceUrl != null) {
      final fromUrl = _queryParam(sourceUrl, const [
        'taskrefId',
        'workId',
        'workid',
        'jobid',
        'activeId',
        'id',
      ]);
      if (fromUrl != null) {
        return fromUrl;
      }
    }

    final direct = _firstMatch(block, [
      RegExp(
        r'data-id=["'
        ']([^"'
        ']+)["'
        ']',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:[?&]|^)(?:taskrefId|workId|workid|jobid|activeId|id)=([A-Za-z0-9_-]+)',
        caseSensitive: false,
      ),
    ]);
    return direct;
  }

  static String _extractBlockCourseName(String block, String fallback) {
    final named = _firstMatch(block, [
      RegExp(
        r'class=["'
        '][^"'
        ']*course-name[^"'
        ']*["'
        '][^>]*>([^<]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'class=["'
        '][^"'
        ']*courseName[^"'
        ']*["'
        '][^>]*>([^<]+)',
        caseSensitive: false,
      ),
    ]);
    if (named != null && named.trim().isNotEmpty) {
      return _decodeEntities(_stripTags(named)).trim();
    }

    final spanTexts =
        RegExp(r'<span[^>]*>(.*?)</span>', caseSensitive: false, dotAll: true)
            .allMatches(block)
            .map(
              (match) => _decodeEntities(
                _stripTags(match.group(1) ?? ''),
              ).replaceAll(RegExp(r'\s+'), ' ').trim(),
            )
            .where((text) => text.isNotEmpty);
    for (final text in spanTexts) {
      if (!_looksLikeStatusOrTime(text)) {
        return text;
      }
    }
    return fallback;
  }

  static bool _looksLikeStatusOrTime(String text) {
    return RegExp(
      r'(未提交|已提交|待批阅|已完成|已过期|剩余|截止|开始|查看|得分|分数|成绩|20\d{2}[-/年])',
    ).hasMatch(text);
  }

  static String _extractRequirement(String block, String cleanText) {
    final desc = _firstMatch(block, [
      RegExp(
        r'class=["'
        '][^"'
        ']*(?:desc|require|content|detail)[^"'
        ']*["'
        '][^>]*>(.*?)</',
        caseSensitive: false,
        dotAll: true,
      ),
    ]);
    return _decodeEntities(_stripTags(desc ?? cleanText)).trim();
  }

  static DateTime? _parseChinaTime(String raw, DateTime now) {
    final m = RegExp(
            r'^(?:(20\d\d)[-/年])?(\d{1,2})[-/月](\d{1,2})日?\s+(\d{1,2}):(\d\d)(?::(\d\d))?$')
        .firstMatch(raw);
    if (m == null) return null;
    final year = int.tryParse(m[1] ?? '');
    final month = int.parse(m[2]!), day = int.parse(m[3]!);
    final hour = int.parse(m[4]!),
        minute = int.parse(m[5]!),
        second = int.parse(m[6] ?? '0');
    if (hour > 23 || minute > 59 || second > 59) return null;
    DateTime? best;
    for (final y
        in year == null ? [now.year - 1, now.year, now.year + 1] : [year]) {
      final wall = DateTime.utc(y, month, day, hour, minute, second);
      if (wall.month != month || wall.day != day) continue;
      final dt = wall.subtract(const Duration(hours: 8)).toLocal();
      if (best == null ||
          dt.difference(now).abs() < best.difference(now).abs()) {
        best = dt;
      }
    }
    return best;
  }

  static String? _attr(String tag, String name) =>
      RegExp('(?:^|\\s)$name\\s*=\\s*(["\\\'])(.*?)\\1',
              caseSensitive: false, dotAll: true)
          .firstMatch(tag)?[2];

  static String? hiddenValue(String html, String name) {
    for (final m
        in RegExp(r'<input\b[^>]*>', caseSensitive: false).allMatches(html)) {
      if (_attr(m[0]!, 'id') == name || _attr(m[0]!, 'name') == name) {
        return _decodeEntities(_attr(m[0]!, 'value') ?? '');
      }
    }
    return null;
  }

  // Work list and answer-period formats adapted from xuexitong-cli.
  // Copyright (c) 2026 Wu Jiale, MIT (references/xuexitong-cli/LICENSE).
  static List<Assignment>? parseSignedWorkList(String html,
      {required String courseId,
      required String clazzId,
      required String courseName,
      required Uri baseUri,
      DateTime? now}) {
    if (html.contains('没有此页面访问权限')) return null;
    final result = <Assignment>[];
    final seen = <String>{};
    for (final row in RegExp(r'<li\b([^>]*)>(.*?)</li>',
            caseSensitive: false, dotAll: true)
        .allMatches(html)) {
      final opening = row[1]!;
      if (!(_attr(opening, 'onclick') ?? '').contains('goTask')) continue;
      final title = RegExp(
              r'''<p\b[^>]*class=["'][^"']*overHidden2[^"']*["'][^>]*>(.*?)</p>''',
              dotAll: true)
          .firstMatch(row[2]!)?[1];
      var url = _decodeEntities(_attr(opening, 'data') ?? '');
      if (url.contains('%') && !url.contains('/')) {
        try {
          url = Uri.decodeComponent(url);
        } on FormatException {
          return null;
        } on ArgumentError {
          return null;
        }
      }
      final link = Uri.tryParse(_decodeEntities(url));
      if (link == null) return null;
      final uri = baseUri.resolveUri(link);
      final id = _queryParam(uri.toString(), const ['workId', 'taskrefId']);
      if (id == null ||
          id.isEmpty ||
          title == null ||
          url.isEmpty ||
          uri.scheme != 'https' ||
          !uri.host.endsWith('.chaoxing.com')) {
        return null;
      }
      if (!seen.add(id)) continue;
      final text = _decodeEntities(_stripTags(title)).trim();
      if (text.isEmpty) return null;
      result.add(Assignment(
          id: 'cx:work:$courseId:$clazzId:$id',
          courseName: courseName,
          title: text,
          deadlineAt: null,
          requirementsText: text,
          status: Assignment.statusFromChaoxing(_statusText(row[2]!), null),
          submitUrl: uri.toString(),
          lastSyncedAt: now ?? DateTime.now()));
    }
    if (result.isNotEmpty) return result;
    final visible = _stripTags(html.replaceAll(
        RegExp(r'<script\b[^>]*>.*?</script>',
            dotAll: true, caseSensitive: false),
        ''));
    return RegExp(r'暂无作业|没有作业').hasMatch(visible) ||
            RegExp(r'<span>\s*0/0\s*</span>').hasMatch(html)
        ? result
        : null;
  }

  static DateTime? parseDetailDeadline(String html, {DateTime? now}) {
    final text =
        _decodeEntities(_stripTags(html)).replaceAll(RegExp(r'\s+'), ' ');
    final end = RegExp(
            r'作答时间\s*[:：]\s*(?:20\d{2}-)?\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}\s*至\s*((?:20\d{2}-)?\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})')
        .firstMatch(text)?[1];
    return end == null
        ? _extractDeadline(text, now ?? DateTime.now())?.value
        : _parseChinaTime(end, now ?? DateTime.now());
  }

  static int? _firstInt(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String? _queryParam(String url, List<String> names) {
    final decoded = _decodeEntities(url);
    final uri = Uri.tryParse(decoded);
    if (uri == null) {
      return null;
    }
    for (final name in names) {
      for (final entry in uri.queryParameters.entries) {
        if (entry.key.toLowerCase() == name.toLowerCase()) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static String? _firstMatch(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  static String _stripTags(String value) =>
      value.replaceAll(RegExp(r'<[^>]+>'), ' ');

  static String _decodeEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final codePoint = int.tryParse(match.group(1)!, radix: 16);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    }).replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final codePoint = int.tryParse(match.group(1)!);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    });
  }
}

class _ParsedDeadline {
  const _ParsedDeadline({required this.rawText, required this.value});

  final String rawText;
  final DateTime value;
}
