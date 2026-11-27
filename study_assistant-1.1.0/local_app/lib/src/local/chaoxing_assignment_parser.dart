import 'dart:async';
import 'dart:isolate';

import '../models/assignment.dart';

const int _kWorkHtmlIsolateThreshold = 32 * 1024;

List<Assignment> _parseWorkHtmlIsolateEntry(
  String html,
  String fallbackCourseName,
  String sourcePrefix,
  String baseUriRaw,
  int parsedAtMs,
) =>
    ChaoxingAssignmentParser.parseWorkHtml(
      html,
      fallbackCourseName: fallbackCourseName,
      sourcePrefix: sourcePrefix,
      baseUri: Uri.parse(baseUriRaw),
      now: DateTime.fromMillisecondsSinceEpoch(parsedAtMs),
    );

class DeadlineEvidence {
  const DeadlineEvidence(
      {this.deadlineAt,
      this.availableFromAt,
      this.availableFromText,
      this.rawText,
      this.noLimit = false,
      this.notOpen = false,
      this.missingYear = false,
      this.startEvidenceConflict = false,
      this.startOnly = false});
  final DateTime? deadlineAt;
  final DateTime? availableFromAt;
  final String? availableFromText;
  final String? rawText;
  final bool noLimit, missingYear, notOpen;
  final bool startEvidenceConflict;
  final bool startOnly;
}

class ChaoxingAssignmentParser {
  static const int isolateParseThreshold = _kWorkHtmlIsolateThreshold;

  static final List<RegExp> _courseNamePatterns = [
    RegExp(
      r'''class=["'][^"']*course-name[^"']*["'][^>]*>([^<]+)''',
      caseSensitive: false,
    ),
    RegExp(
      r'''class=["'][^"']*courseName[^"']*["'][^>]*>([^<]+)''',
      caseSensitive: false,
    ),
    RegExp(r'课程[:：]\s*([^<\n\r]+)'),
  ];

  static final List<RegExp> _blockCourseNamePatterns = [
    _courseNamePatterns[0],
    _courseNamePatterns[1],
  ];

  static final RegExp _itemBlockRegex = RegExp(
    r'''<(?:div|li)[^>]*(?:class=["'][^"']*(?:work|homework|task|作业)[^"']*["']|data-id=["'][^"']+["']|data(?:-url)?=["'][^"']*(?:doHomeWork|taskrefId|workId|/work/)[^"']*["'])[^>]*>.*?</(?:div|li)>''',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  static final List<RegExp> _blockTitlePatterns = [
    RegExp(r'''(?:data-title|title)=["']([^"']+)["']''', caseSensitive: false),
    RegExp(
      r'''class=["'][^"']*(?:title|work-title|task-title)[^"']*["'][^>]*>([^<]+)''',
      caseSensitive: false,
    ),
    RegExp(r'<a[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true),
    RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true),
  ];

  static final RegExp _statusTagRegex =
      RegExp(r'<(p|span|em|i)\b([^>]*)>([^<]*)</\1>', caseSensitive: false);

  static final RegExp _absoluteDeadlineRegex = RegExp(
    r'(?:截止(?:时间)?|结束时间)\s*[:：]?\s*((?:20\d{2}[-/年])?\d{1,2}[-/月]\d{1,2}日?\s+\d{1,2}[:：]\d{2}(?:[:：]\d{2})?)',
  );

  static final List<RegExp> _remainingDeadlinePatterns = [
    RegExp(r'(剩余\s*\d+\s*天(?:\s*\d+\s*(?:小时|时))?(?:\s*\d+\s*(?:分钟|分))?)'),
    RegExp(r'(剩余\s*\d+\s*(?:小时|时)(?:\s*\d+\s*(?:分钟|分))?)'),
    RegExp(r'(剩余\s*\d+\s*(?:分钟|分))'),
  ];

  static final RegExp _daysRegex = RegExp(r'(\d+)\s*天');
  static final RegExp _hoursRegex = RegExp(r'(\d+)\s*(?:小时|时)');
  static final RegExp _minutesRegex = RegExp(r'(\d+)\s*(?:分钟|分)');

  static final RegExp _fallbackDeadlineTailRegex =
      RegExp(r'截止时间[:：]?\s*20\d{2}.*$');
  static final RegExp _fallbackRemainingTailRegex =
      RegExp(r'剩余\s*\d+\s*(?:天|小时|时|分钟|分).*$');
  static final RegExp _fallbackStatusWordRegex =
      RegExp(r'\b(?:未提交|已提交|待批阅|已完成|已过期)\b');

  static final List<RegExp> _sourceUrlPatterns = [
    RegExp(r'''<a[^>]+href=["']([^"']+)["']''', caseSensitive: false),
    RegExp(
      r'''data(?:-url)?=["']([^"']*(?:doHomeWork|taskrefId|workId|/work/)[^"']*)["']''',
      caseSensitive: false,
    ),
  ];

  static final List<RegExp> _directSourceIdPatterns = [
    RegExp(r'''data-id=["']([^"']+)["']''', caseSensitive: false),
    RegExp(
      r'(?:[?&]|^)(?:taskrefId|workId|workid|jobid|activeId|id)=([A-Za-z0-9_-]+)',
      caseSensitive: false,
    ),
  ];

  static final RegExp _spanTagRegex =
      RegExp(r'<span[^>]*>(.*?)</span>', caseSensitive: false, dotAll: true);

  static final RegExp _statusOrTimeTextRegex = RegExp(
    r'(未提交|已提交|待批阅|已完成|已过期|剩余|截止|开始|查看|得分|分数|成绩|20\d{2}[-/年])',
  );

  static final List<RegExp> _requirementPatterns = [
    RegExp(
      r'''class=["'][^"']*(?:desc|require|content|detail)[^"']*["'][^>]*>(.*?)</''',
      caseSensitive: false,
      dotAll: true,
    ),
  ];

  static final RegExp _chinaTimeRegex = RegExp(
    r'^(?:(20\d\d)[-/年])?(\d{1,2})[-/月](\d{1,2})日?\s+(\d{1,2}):(\d\d)(?::(\d\d))?$',
  );

  static final RegExp _inputTagRegex =
      RegExp(r'<input\b[^>]*>', caseSensitive: false);
  static final RegExp _liRowRegex =
      RegExp(r'<li\b([^>]*)>(.*?)</li>', caseSensitive: false, dotAll: true);
  static final RegExp _overHidden2TitleRegex = RegExp(
    r'''<p\b[^>]*class=["'][^"']*overHidden2[^"']*["'][^>]*>(.*?)</p>''',
    dotAll: true,
  );
  static final RegExp _scriptTagRegex = RegExp(
    r'<script\b[^>]*>.*?</script>',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _emptyWorkHintRegex = RegExp(r'暂无作业|没有作业');
  static final RegExp _zeroWorkCounterRegex = RegExp(r'<span>\s*0/0\s*</span>');

  static final RegExp _scriptOrStyleRegex = RegExp(
    r'<(script|style)\b[^>]*>[\s\S]*?</\1>',
    caseSensitive: false,
  );
  static final RegExp _htmlCommentRegex = RegExp(r'<!--[\s\S]*?-->');

  static const String _detailTimeToken =
      r'(?:20\d{2}[-/年])?\d{1,2}[-/月]\d{1,2}日?\s+\d{1,2}[:：]\d{2}(?:[:：]\d{2})?';
  static final RegExp _detailPeriodRegex = RegExp(
    '(?:作答时间|答题时间|作业时间)\\s*[:：]?\\s*($_detailTimeToken)\\s*(?:至|~|～|—|--)\\s*($_detailTimeToken|不限|无截止时间|长期有效)',
  );
  static final RegExp _detailLabeledStartRegex = RegExp(
    '(?:作答开始时间|答题开始时间|作业开始时间|考试开始时间|开始时间|开放时间)\\s*[:：]?\\s*($_detailTimeToken)',
  );
  static final RegExp _detailDeadlineLabelRegex = RegExp(
    r'(?:作答截止时间|提交截止时间|答题结束时间|截止时间|截止日期|结束时间)\s*[:：]?',
  );
  static final RegExp _detailDeadlineValueRegex = RegExp(
    '(?:作答截止时间|提交截止时间|答题结束时间|截止时间|截止日期|结束时间)\\s*[:：]?\\s*($_detailTimeToken|不限|无截止时间|长期有效)',
  );
  static final RegExp _detailNoLimitPeriodRegex = RegExp(
    r'(?:作答时间|答题时间)\s*[:：]?\s*(?:不限|无截止时间|长期有效)',
  );
  static final RegExp _yearPrefixRegex = RegExp(r'^20\d{2}[-/年]');
  static final RegExp _detailDatePartsRegex = RegExp(
    r'^(?:(20\d{2})[-/年])?(\d{1,2})[-/月](\d{1,2})日?\s+(\d{1,2})[:：](\d{2})(?:[:：](\d{2}))?$',
  );

  static final RegExp _htmlTagRegex = RegExp(r'<[^>]+>');
  static final RegExp _hexEntityRegex = RegExp(r'&#x([0-9a-fA-F]+);');
  static final RegExp _decEntityRegex = RegExp(r'&#(\d+);');

  static const int _maxAttrRegexCache = 64;
  static final Map<String, RegExp> _attrRegexCache = {};

  static bool _isFakeAsyncWidgetTestZone() {
    var inDebugOrTest = false;
    assert(() {
      inDebugOrTest = true;
      return true;
    }());
    if (!inDebugOrTest) return false;
    final probe = Timer(Duration.zero, () {});
    final isFake = probe.runtimeType.toString().contains('Fake');
    probe.cancel();
    return isFake;
  }

  static Future<List<Assignment>> parseWorkHtmlAsync(
    String html, {
    required String fallbackCourseName,
    required String sourcePrefix,
    required Uri baseUri,
    DateTime? now,
  }) {
    final parsedAt = now ?? DateTime.now();
    if (html.length <= isolateParseThreshold || _isFakeAsyncWidgetTestZone()) {
      return Future<List<Assignment>>.value(
        parseWorkHtml(
          html,
          fallbackCourseName: fallbackCourseName,
          sourcePrefix: sourcePrefix,
          baseUri: baseUri,
          now: parsedAt,
        ),
      );
    }
    final baseUriRaw = baseUri.toString();
    final parsedAtMs = parsedAt.millisecondsSinceEpoch;
    return Isolate.run(
      () => _parseWorkHtmlIsolateEntry(
        html,
        fallbackCourseName,
        sourcePrefix,
        baseUriRaw,
        parsedAtMs,
      ),
    );
  }

  static List<Assignment> parseWorkHtml(
    String html, {
    required String fallbackCourseName,
    required String sourcePrefix,
    required Uri baseUri,
    DateTime? now,
  }) {
    final parsedAt = now ?? DateTime.now();
    final courseName =
        _firstMatch(html, _courseNamePatterns)?.trim() ?? fallbackCourseName;

    final candidates = _itemBlockRegex
        .allMatches(html)
        .map((match) => match.group(0)!)
        .toList();

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
    ).replaceAll(_whitespaceRegex, ' ').trim();
    final deadline = _extractDeadline(cleanText, now);
    final title = _firstMatch(block, _blockTitlePatterns)?.trim() ??
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
    for (final tag in _statusTagRegex.allMatches(block)) {
      final value = _decodeEntities(tag[3]!).trim();
      if ((_attr(tag[2]!, 'class') ?? '')
          .split(_whitespaceRegex)
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
    final absolute = _absoluteDeadlineRegex.firstMatch(cleanText)?[1];
    if (absolute != null) {
      final value = _parseChinaTime(absolute, now);
      if (value != null) {
        return _ParsedDeadline(rawText: absolute, value: value);
      }
    }
    final remaining = _firstMatch(cleanText, _remainingDeadlinePatterns);
    if (remaining == null) {
      return null;
    }

    final days = _firstInt(remaining, _daysRegex) ?? 0;
    final hours = _firstInt(remaining, _hoursRegex) ?? 0;
    final minutes = _firstInt(remaining, _minutesRegex) ?? 0;
    return _ParsedDeadline(
      rawText: remaining,
      value: now.add(Duration(days: days, hours: hours, minutes: minutes)),
    );
  }

  static String _fallbackTitle(String cleanText) {
    return cleanText
        .replaceFirst(_fallbackDeadlineTailRegex, '')
        .replaceFirst(_fallbackRemainingTailRegex, '')
        .replaceAll(_fallbackStatusWordRegex, '')
        .trim();
  }

  static String? _extractSourceUrl(String block) {
    return _firstMatch(block, _sourceUrlPatterns);
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

    return _firstMatch(block, _directSourceIdPatterns);
  }

  static String _extractBlockCourseName(String block, String fallback) {
    final named = _firstMatch(block, _blockCourseNamePatterns);
    if (named != null && named.trim().isNotEmpty) {
      return _decodeEntities(_stripTags(named)).trim();
    }

    final spanTexts = _spanTagRegex
        .allMatches(block)
        .map(
          (match) => _decodeEntities(
            _stripTags(match.group(1) ?? ''),
          ).replaceAll(_whitespaceRegex, ' ').trim(),
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
    return _statusOrTimeTextRegex.hasMatch(text);
  }

  static String _extractRequirement(String block, String cleanText) {
    final desc = _firstMatch(block, _requirementPatterns);
    return _decodeEntities(_stripTags(desc ?? cleanText)).trim();
  }

  static DateTime? _parseChinaTime(String raw, DateTime now) {
    final normalized = raw.trim().replaceAll('：', ':');
    final m = _chinaTimeRegex.firstMatch(normalized);
    if (m == null) return null;
    final year = int.tryParse(m[1] ?? '');
    if (year == null) return null;
    final month = int.parse(m[2]!), day = int.parse(m[3]!);
    final hour = int.parse(m[4]!),
        minute = int.parse(m[5]!),
        second = int.parse(m[6] ?? '0');
    if (hour > 23 || minute > 59 || second > 59) return null;
    DateTime? best;
    for (final y in [year]) {
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

  static String? _attr(String tag, String name) {
    var pattern = _attrRegexCache[name];
    if (pattern == null) {
      if (_attrRegexCache.length >= _maxAttrRegexCache) {
        _attrRegexCache.remove(_attrRegexCache.keys.first);
      }
      pattern = RegExp(
        '(?:^|\\s)$name\\s*=\\s*(["\\\'])(.*?)\\1',
        caseSensitive: false,
        dotAll: true,
      );
      _attrRegexCache[name] = pattern;
    }
    return pattern.firstMatch(tag)?[2];
  }

  static String? hiddenValue(String html, String name) {
    for (final m in _inputTagRegex.allMatches(html)) {
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
    for (final row in _liRowRegex.allMatches(html)) {
      final opening = row[1]!;
      if (!(_attr(opening, 'onclick') ?? '').contains('goTask')) continue;
      final title = _overHidden2TitleRegex.firstMatch(row[2]!)?[1];
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
    final visible = _stripTags(html.replaceAll(_scriptTagRegex, ''));
    return _emptyWorkHintRegex.hasMatch(visible) ||
            _zeroWorkCounterRegex.hasMatch(html)
        ? result
        : null;
  }

  static DateTime? parseDetailDeadline(String html, {DateTime? now}) =>
      readDetailDeadline(html, now: now).deadlineAt;

  static DeadlineEvidence readDetailDeadline(String html,
      {DateTime? now, DateTime? startedAt}) {
    final clean = html
        .replaceAll(_scriptOrStyleRegex, ' ')
        .replaceAll(_htmlCommentRegex, ' ');
    final text = _decodeEntities(_stripTags(clean))
        .replaceAll(_whitespaceRegex, ' ')
        .trim();
    final period = _detailPeriodRegex.firstMatch(text);
    final labeledStart = _detailLabeledStartRegex.firstMatch(text);
    final hasDeadlineLabel = _detailDeadlineLabelRegex.hasMatch(text);
    String? raw;
    String? start;
    if (period != null) {
      raw = period[2];
      start = period[1];
    }
    start ??= labeledStart?[1];
    DateTime? availableFrom;
    var startEvidenceConflict = false;
    if (start != null) {
      if (_yearPrefixRegex.hasMatch(start)) {
        availableFrom = _parseChinaTime(start, now ?? DateTime.now());
        if (availableFrom != null &&
            startedAt != null &&
            availableFrom.toUtc().millisecondsSinceEpoch ~/ 60000 !=
                startedAt.toUtc().millisecondsSinceEpoch ~/ 60000) {
          availableFrom = null;
          startEvidenceConflict = true;
        }
      } else if (startedAt != null) {
        final absoluteStart = startedAt.toUtc().add(const Duration(hours: 8));
        final visibleStart = _parseChinaTime(
            '${absoluteStart.year}-$start', now ?? DateTime.now());
        if (visibleStart != null &&
            visibleStart.toUtc().millisecondsSinceEpoch ~/ 60000 ==
                startedAt.toUtc().millisecondsSinceEpoch ~/ 60000) {
          availableFrom = startedAt;
        } else {
          startEvidenceConflict = true;
        }
      }
    } else if (startedAt != null) {
      availableFrom = startedAt;
    }
    raw ??= _detailDeadlineValueRegex.firstMatch(text)?[1];
    if (raw == null && _detailNoLimitPeriodRegex.hasMatch(text)) {
      return DeadlineEvidence(
          noLimit: true,
          rawText: '不限',
          availableFromAt: availableFrom,
          availableFromText: start,
          startEvidenceConflict: startEvidenceConflict);
    }
    if (raw == null) {
      final notOpen = text.contains('未开始') || text.contains('尚未开放');
      return notOpen
          ? DeadlineEvidence(
              notOpen: true,
              rawText: '尚未开放',
              availableFromAt: availableFrom,
              availableFromText: start,
              startEvidenceConflict: startEvidenceConflict)
          : DeadlineEvidence(
              availableFromAt: availableFrom,
              availableFromText: start,
              startEvidenceConflict: startEvidenceConflict,
              startOnly: period == null &&
                  labeledStart != null &&
                  !hasDeadlineLabel &&
                  !startEvidenceConflict);
    }
    if (const ['不限', '无截止时间', '长期有效'].contains(raw)) {
      return DeadlineEvidence(
          noLimit: true,
          rawText: raw,
          availableFromAt: availableFrom,
          availableFromText: start,
          startEvidenceConflict: startEvidenceConflict);
    }
    final parts = _detailDatePartsRegex.firstMatch(raw);
    if (parts == null) {
      return DeadlineEvidence(
          availableFromAt: availableFrom,
          availableFromText: start,
          startEvidenceConflict: startEvidenceConflict);
    }
    final parsedAt = now ?? DateTime.now();
    final month = int.parse(parts[2]!);
    final day = int.parse(parts[3]!);
    final time = '${parts[4]}:${parts[5]}:${parts[6] ?? '00'}';
    DateTime? deadlineInYear(int year) =>
        _parseChinaTime('$year-$month-$day $time', parsedAt);

    var year = int.tryParse(parts[1] ?? '');
    if (year == null && start != null && !startEvidenceConflict) {
      DateTime? matchedStart;
      if (_yearPrefixRegex.hasMatch(start)) {
        matchedStart = _parseChinaTime(start, parsedAt);
      } else if (startedAt != null) {
        // Only the same work's absolute start can disambiguate a yearless
        // period. Match the displayed start to the minute in Beijing time;
        // current date, course term and upload tokens are not evidence.
        final absoluteStart = startedAt.toUtc().add(const Duration(hours: 8));
        final visibleStart =
            _parseChinaTime('${absoluteStart.year}-$start', parsedAt);
        if (visibleStart != null &&
            visibleStart.toUtc().millisecondsSinceEpoch ~/ 60000 ==
                startedAt.toUtc().millisecondsSinceEpoch ~/ 60000) {
          matchedStart = visibleStart;
        }
      }
      if (matchedStart != null) {
        final startBeijing = matchedStart.toUtc().add(const Duration(hours: 8));
        year = startBeijing.year;
        final candidate = deadlineInYear(year);
        if (candidate != null && candidate.isBefore(matchedStart)) {
          year++;
        } else if (candidate == null &&
            month == 2 &&
            day == 29 &&
            startBeijing.month > 2) {
          // Only a start past February can roll an invalid leap day forward.
          final nextLeapDay = deadlineInYear(year + 1);
          if (nextLeapDay != null && !nextLeapDay.isBefore(matchedStart)) {
            year++;
          }
        }
      }
    }
    if (year == null) {
      return DeadlineEvidence(
          rawText: raw,
          missingYear: true,
          availableFromAt: availableFrom,
          availableFromText: start,
          startEvidenceConflict: startEvidenceConflict);
    }
    return DeadlineEvidence(
        deadlineAt: deadlineInYear(year),
        rawText: raw,
        availableFromAt: availableFrom,
        availableFromText: start,
        startEvidenceConflict: startEvidenceConflict);
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
      value.replaceAll(_htmlTagRegex, ' ');

  static String _decodeEntities(String value) {
    String decodeCodePoint(Match match, int radix) {
      final codePoint = int.tryParse(match.group(1)!, radix: radix);
      if (codePoint == null ||
          codePoint <= 0 ||
          codePoint > 0x10ffff ||
          (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
        return match.group(0)!;
      }
      return String.fromCharCode(codePoint);
    }

    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAllMapped(
          _hexEntityRegex,
          (match) => decodeCodePoint(match, 16),
        )
        .replaceAllMapped(
          _decEntityRegex,
          (match) => decodeCodePoint(match, 10),
        );
  }
}

class _ParsedDeadline {
  const _ParsedDeadline({required this.rawText, required this.value});

  final String rawText;
  final DateTime value;
}
