import 'dart:math' as math;

import '../models/assignment.dart';
import '../models/assignment_change.dart';
import '../models/course.dart';
import '../models/course_notice.dart';
import '../models/course_term_preferences.dart';
import '../models/local_coursework_state.dart';
import 'assignment_query.dart';
import 'coursework_deadline.dart';

enum AcademicSemester { fall, spring }

enum CourseTermSource {
  manual,
  folder,
  courseName,
  clazzName,
  activity,
  courseTime,
  clazzCohort,
  ungrouped,
}

enum CourseCatalogState { active, recalled, archived }

enum CourseTermScope {
  currentTerm('本学期'),
  currentAcademicYear('本学年'),
  pastTerms('往期'),
  allTerms('全部学期');

  const CourseTermScope(this.label);
  final String label;
}

class AcademicTerm implements Comparable<AcademicTerm> {
  const AcademicTerm(this.academicYearStart, this.semester);

  final int academicYearStart;
  final AcademicSemester semester;

  String get key => '$academicYearStart-${semester.name}';

  String get label =>
      '$academicYearStart-${academicYearStart + 1} ${semester == AcademicSemester.fall ? '秋季' : '春季'}';

  String get shortLabel =>
      '$academicYearStart${semester == AcademicSemester.fall ? '秋' : '春'}';

  String get academicYearLabel =>
      '$academicYearStart-${academicYearStart + 1} 学年';

  AcademicTerm get previous => semester == AcademicSemester.spring
      ? AcademicTerm(academicYearStart, AcademicSemester.fall)
      : AcademicTerm(academicYearStart - 1, AcademicSemester.spring);

  int get _ordinal =>
      academicYearStart * 2 + (semester == AcademicSemester.spring ? 1 : 0);

  AcademicTerm? _shift(int deltaTerms) {
    final target = _ordinal + deltaTerms;
    if (target < 4000 || target > 4201) return null;
    return AcademicTerm(
      target ~/ 2,
      target.isOdd ? AcademicSemester.spring : AcademicSemester.fall,
    );
  }

  static AcademicTerm fromInstant(DateTime instant) {
    final beijing = AssignmentQuery.beijing(instant);
    if (beijing.month >= 9) {
      return AcademicTerm(beijing.year, AcademicSemester.fall);
    }
    if (beijing.month <= 2) {
      return AcademicTerm(beijing.year - 1, AcademicSemester.fall);
    }
    return AcademicTerm(beijing.year - 1, AcademicSemester.spring);
  }

  static AcademicTerm fromCourseCreationInstant(DateTime instant) {
    final beijing = AssignmentQuery.beijing(instant);
    if (beijing.month >= 8) {
      return AcademicTerm(beijing.year, AcademicSemester.fall);
    }
    if (beijing.month == 1) {
      return AcademicTerm(beijing.year - 1, AcademicSemester.fall);
    }
    return AcademicTerm(beijing.year - 1, AcademicSemester.spring);
  }

  static final RegExp _keyPattern = RegExp(r'^(20\d{2})-(fall|spring)$');
  static final RegExp _spanFolderPattern = RegExp(
    r'^(20\d{2})\s*[-—~/－至]\s*(20\d{2})\s*(?:学年)?\s*(?:[\(\[（【\-—~]?\s*([12一二])(?![\d])\s*[\)\]）】]?|第\s*([12一二])\s*学期|(?:年\s*)?(秋|春|上|下)(?:季学期|季|学期)?)\s*$',
  );
  static final RegExp _shortSpanFolderPattern = RegExp(
    r'^(2\d)\s*[-—~/－至]\s*(2\d)\s*(?:学年)?\s*(?:[\(\[（【\-—~]?\s*([12一二])(?![\d])\s*[\)\]）】]?|第\s*([12一二])\s*学期|(?:年\s*)?(秋|春|上|下)(?:季学期|季|学期)?)\s*$',
  );
  static final RegExp _singleYearFolderPattern = RegExp(
    r'^(20\d{2})\s*(?:年\s*)?(秋|春)(?:季学期|季|学期)?\s*$',
  );
  static final RegExp _shortSingleYearFolderPattern = RegExp(
    r'^(2\d)\s*(?:年\s*)?(秋|春)(?:季学期|季|学期)?\s*$',
  );

  static AcademicTerm? tryParseKey(String? raw) {
    if (raw == null) return null;
    final match = _keyPattern.firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    if (year == null || year < 2000 || year > 2100) return null;
    return AcademicTerm(
      year,
      match.group(2) == 'fall'
          ? AcademicSemester.fall
          : AcademicSemester.spring,
    );
  }

  static final RegExp _spanFolderLoosePattern = RegExp(
    r'(?<![a-zA-Z\d])(20\d{2})\s*[-—~/－至]\s*(20\d{2})\s*(?:学年)?\s*(?:[\(\[（【\-—~]?\s*([12一二])(?![\d])\s*[\)\]）】]?|第\s*([12一二])\s*学期|(?:年\s*)?(秋|春|上|下)(?:季学期|季|学期)?)',
  );
  static final RegExp _shortSpanFolderLoosePattern = RegExp(
    r'(?<![a-zA-Z\d])(2\d)\s*[-—~/－至]\s*(2\d)\s*(?:学年)?\s*(?:[\(\[（【\-—~]?\s*([12一二])(?![\d])\s*[\)\]）】]?|第\s*([12一二])\s*学期|(?:年\s*)?(秋|春|上|下)(?:季学期|季|学期)?)',
  );
  static final RegExp _academicYearOrdinalPattern = RegExp(
    r'(?<![a-zA-Z\d])(20\d{2})\s*学年\s*第?\s*([12一二])\s*学期',
  );
  static final RegExp _singleYearFolderLoosePattern = RegExp(
    r'(?<![a-zA-Z\d])(20\d{2})\s*(?:年\s*)?(秋|春)(?:季学期|季|学期)?',
  );
  static final RegExp _shortSingleYearLoosePattern = RegExp(
    r'(?<![a-zA-Z\d.])(2\d)\s*(?:年\s*)?(秋|春)(?:季学期|季|学期)?',
  );
  static final RegExp _courseNameNoisePattern = RegExp(
    r'(?<!\d)(?:20)?\d{2}\s*(?:级|届|版|年制|期)',
  );
  static final RegExp _courseYearMonthSepPattern = RegExp(
    r'(?<![a-zA-Z\d])(20\d{2})\s*(?:'
    r'年\s*(\d{1,2})\s*月(?:\s*(\d{1,2})\s*[日号]?)?'
    r'|'
    r'[\.\-/]\s*(\d{1,2})(?:\s*[\.\-/]\s*(\d{1,2})|\s*月)?'
    r')(?![\d级届版班组节讲章周次])',
  );
  static final RegExp _courseYearMonthCompactPattern = RegExp(
    r'(?<![a-zA-Z\d])(20\d{2})(0[1-9]|1[0-2])(?:(0[1-9]|[12]\d|3[01]))?(?![\d级届版班组节讲章周次])',
  );

  static AcademicTerm? tryParseCourseName(String? raw) {
    final original = raw?.trim();
    if (original == null || original.isEmpty) return null;
    final text = original.replaceAll(_courseNameNoisePattern, ' ');

    final matchedTerms = <AcademicTerm>{};
    final spanRanges = <(int, int)>[];
    final singleRanges = <(int, int)>[];

    bool overlapsEarlier(int start, int end) =>
        spanRanges.any((r) => start < r.$2 && end > r.$1) ||
        singleRanges.any((r) => start < r.$2 && end > r.$1);

    for (final match in _spanFolderLoosePattern.allMatches(text)) {
      final parsed = _parseSpanMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    for (final match in _shortSpanFolderLoosePattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final parsed = _parseShortSpanMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    for (final match in _academicYearOrdinalPattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final year = int.tryParse(match.group(1)!);
      final marker = match.group(2) ?? '';
      if (year == null || year < 2000 || year > 2100) return null;
      final parsed = (marker == '1' || marker == '一')
          ? AcademicTerm(year, AcademicSemester.fall)
          : (marker == '2' || marker == '二')
              ? AcademicTerm(year, AcademicSemester.spring)
              : null;
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    for (final match in _singleYearFolderLoosePattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final parsed = _parseSingleYearMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      singleRanges.add((match.start, match.end));
    }

    for (final match in _shortSingleYearLoosePattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final parsed = _parseShortSingleYearMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      singleRanges.add((match.start, match.end));
    }

    AcademicTerm? parseYearMonth(int? year, int? month, int? day) {
      if (year == null ||
          year < 2000 ||
          year > 2100 ||
          month == null ||
          month < 1 ||
          month > 12) {
        return null;
      }
      if (day != null) {
        final check = DateTime.utc(year, month, day);
        if (check.year != year || check.month != month || check.day != day) {
          return null;
        }
      }
      return AcademicTerm.fromInstant(DateTime.utc(year, month, 15));
    }

    for (final match in _courseYearMonthSepPattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final year = int.tryParse(match.group(1)!);
      final monthRaw = match.group(2) ?? match.group(4);
      final month = monthRaw == null ? null : int.tryParse(monthRaw);
      final dayRaw = match.group(3) ?? match.group(5);
      final day = dayRaw == null ? null : int.tryParse(dayRaw);
      final parsed = parseYearMonth(year, month, day);
      if (parsed == null) {
        if (month != null && month >= 1 && month <= 12 && day != null) {
          return null;
        }
        continue;
      }
      matchedTerms.add(parsed);
      singleRanges.add((match.start, match.end));
    }

    for (final match in _courseYearMonthCompactPattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final year = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      final dayRaw = match.group(3);
      final day = dayRaw == null ? null : int.tryParse(dayRaw);
      final parsed = parseYearMonth(year, month, day);
      if (parsed == null) {
        if (month != null && month >= 1 && month <= 12 && day != null) {
          return null;
        }
        continue;
      }
      matchedTerms.add(parsed);
      singleRanges.add((match.start, match.end));
    }

    return matchedTerms.length == 1 ? matchedTerms.first : null;
  }

  static AcademicTerm? tryParseFolderLabel(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;

    final spanMatch = _spanFolderPattern.firstMatch(text);
    if (spanMatch != null) {
      return _parseSpanMatch(spanMatch);
    }

    final shortSpanMatch = _shortSpanFolderPattern.firstMatch(text);
    if (shortSpanMatch != null) {
      return _parseShortSpanMatch(shortSpanMatch);
    }

    final singleMatch = _singleYearFolderPattern.firstMatch(text);
    if (singleMatch != null) {
      return _parseSingleYearMatch(singleMatch);
    }

    final shortSingleMatch = _shortSingleYearFolderPattern.firstMatch(text);
    if (shortSingleMatch != null) {
      return _parseShortSingleYearMatch(shortSingleMatch);
    }

    final matchedTerms = <AcademicTerm>{};
    final spanRanges = <(int, int)>[];
    bool overlapsEarlier(int start, int end) =>
        spanRanges.any((range) => start < range.$2 && end > range.$1);

    for (final match in _spanFolderLoosePattern.allMatches(text)) {
      final parsed = _parseSpanMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    for (final match in _shortSpanFolderLoosePattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final parsed = _parseShortSpanMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    for (final match in _academicYearOrdinalPattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final year = int.tryParse(match.group(1)!);
      final marker = match.group(2) ?? '';
      if (year == null || year < 2000 || year > 2100) return null;
      final parsed = (marker == '1' || marker == '一')
          ? AcademicTerm(year, AcademicSemester.fall)
          : (marker == '2' || marker == '二')
              ? AcademicTerm(year, AcademicSemester.spring)
              : null;
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    for (final match in _singleYearFolderLoosePattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final parsed = _parseSingleYearMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    for (final match in _shortSingleYearLoosePattern.allMatches(text)) {
      if (overlapsEarlier(match.start, match.end)) continue;
      final parsed = _parseShortSingleYearMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    return matchedTerms.length == 1 ? matchedTerms.first : null;
  }

  static AcademicTerm? _parseSpanMarker(int start, String marker) {
    final isFall =
        marker == '1' || marker == '一' || marker == '秋' || marker == '上';
    final isSpring =
        marker == '2' || marker == '二' || marker == '春' || marker == '下';
    if (isFall) return AcademicTerm(start, AcademicSemester.fall);
    if (isSpring) return AcademicTerm(start, AcademicSemester.spring);
    return null;
  }

  static AcademicTerm? _parseSpanMatch(RegExpMatch match) {
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    if (start == null ||
        end == null ||
        end != start + 1 ||
        start < 2000 ||
        start > 2100) {
      return null;
    }
    final marker = match.group(3) ?? match.group(4) ?? match.group(5) ?? '';
    return _parseSpanMarker(start, marker);
  }

  static AcademicTerm? _parseShortSpanMatch(RegExpMatch match) {
    final startShort = int.tryParse(match.group(1)!);
    final endShort = int.tryParse(match.group(2)!);
    if (startShort == null || endShort == null || endShort != startShort + 1) {
      return null;
    }
    final start = 2000 + startShort;
    final marker = match.group(3) ?? match.group(4) ?? match.group(5) ?? '';
    return _parseSpanMarker(start, marker);
  }

  static AcademicTerm? _parseSingleYearMatch(RegExpMatch match) {
    final year = int.tryParse(match.group(1)!);
    if (year == null || year < 2000 || year > 2100) return null;
    return match.group(2) == '秋'
        ? AcademicTerm(year, AcademicSemester.fall)
        : AcademicTerm(year - 1, AcademicSemester.spring);
  }

  static AcademicTerm? _parseShortSingleYearMatch(RegExpMatch match) {
    final shortYear = int.tryParse(match.group(1)!);
    if (shortYear == null) return null;
    final year = 2000 + shortYear;
    return match.group(2) == '秋'
        ? AcademicTerm(year, AcademicSemester.fall)
        : AcademicTerm(year - 1, AcademicSemester.spring);
  }

  static List<AcademicTerm> recentSelectableTerms(
    DateTime now, {
    int count = 6,
  }) {
    final out = <AcademicTerm>[];
    var cursor = fromInstant(now);
    for (var i = 0; i < count; i++) {
      out.add(cursor);
      cursor = cursor.previous;
    }
    return List.unmodifiable(out);
  }

  @override
  int compareTo(AcademicTerm other) {
    final byYear = academicYearStart.compareTo(other.academicYearStart);
    if (byYear != 0) return byYear;
    final aOrder = semester == AcademicSemester.fall ? 0 : 1;
    final bOrder = other.semester == AcademicSemester.fall ? 0 : 1;
    return aOrder.compareTo(bOrder);
  }

  bool operator <(AcademicTerm other) => compareTo(other) < 0;
  bool operator <=(AcademicTerm other) => compareTo(other) <= 0;
  bool operator >(AcademicTerm other) => compareTo(other) > 0;
  bool operator >=(AcademicTerm other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AcademicTerm &&
      academicYearStart == other.academicYearStart &&
      semester == other.semester;

  @override
  int get hashCode => Object.hash(academicYearStart, semester);
}

class CourseTermEntry {
  const CourseTermEntry({
    required this.courseKey,
    required this.courseName,
    required this.term,
    required this.source,
    required this.explanation,
    required this.state,
    required this.override,
    required this.latestTrustedActivityUtc,
    required this.latestRecallEventUtc,
    required this.isFollowed,
    this.isAutoPromo = false,
  });

  final String courseKey;
  final String courseName;
  final AcademicTerm? term;
  final CourseTermSource source;
  final String explanation;
  final CourseCatalogState state;
  final CourseTermOverride override;
  final DateTime? latestTrustedActivityUtc;
  final DateTime? latestRecallEventUtc;
  final bool isFollowed;
  final bool isAutoPromo;

  bool get isBlocked =>
      override.blockMode == CourseBlockMode.blocked ||
      (isAutoPromo && override.blockMode == CourseBlockMode.auto);

  bool get isAutoBlockedPromo =>
      isAutoPromo && override.blockMode == CourseBlockMode.auto;

  bool get isManuallyBlocked => override.blockMode == CourseBlockMode.blocked;

  bool get isUngrouped =>
      source == CourseTermSource.ungrouped &&
      override.archiveMode == CourseArchiveMode.auto;

  bool get hasCurrentTermEvidence =>
      override.archiveMode == CourseArchiveMode.restored ||
      state == CourseCatalogState.recalled ||
      (state == CourseCatalogState.active && !isUngrouped);

  String get stateLabel => switch (state) {
        CourseCatalogState.active => term?.label ?? '未分组',
        CourseCatalogState.recalled => '${term?.label ?? '往期'} · 补修/近期活跃',
        CourseCatalogState.archived => '${term?.label ?? '往期'} · 已归档',
      };
}

class _ClazzIdCluster {
  const _ClazzIdCluster({
    required this.term,
    required this.minId,
    required this.maxId,
    required this.medianId,
    required this.count,
  });

  final AcademicTerm term;
  final int minId;
  final int maxId;
  final int medianId;
  final int count;
}

class _BaseCourseResolution {
  const _BaseCourseResolution({
    required this.term,
    required this.source,
    required this.explanation,
    required this.isBlocked,
    required this.isAutoPromo,
  });

  final AcademicTerm? term;
  final CourseTermSource source;
  final String explanation;
  final bool isBlocked;
  final bool isAutoPromo;
}

class CourseTermCatalog {
  const CourseTermCatalog._({
    required this.currentTerm,
    required this.now,
    required Map<String, CourseTermEntry> entriesByCourseKey,
    required Set<String> unfollowedCourseKeys,
    required Set<String> hiddenAssignmentIds,
    required LocalCourseworkState coursework,
  })  : _entriesByCourseKey = entriesByCourseKey,
        _unfollowedCourseKeys = unfollowedCourseKeys,
        _hiddenAssignmentIds = hiddenAssignmentIds,
        _coursework = coursework;

  final AcademicTerm currentTerm;
  final DateTime now;
  final Map<String, CourseTermEntry> _entriesByCourseKey;
  final Set<String> _unfollowedCourseKeys;
  final Set<String> _hiddenAssignmentIds;
  final LocalCourseworkState _coursework;

  static const Duration maxFutureRecallHorizon = Duration(days: 180);

  static const List<String> _officialPromoKeywords = [
    '官方举办',
    '学习通官方',
    '超星官方',
    '超星尔雅官方',
    '泛雅官方',
    '官方活动',
    '官方赛事',
    '官方推荐',
    '学习通活动',
    '超星活动',
    '超星集团',
    '超星小助手',
    '官方助手',
    '活动主办方',
    '超星杯',
    '学习通杯',
    '共读活动',
    '打卡挑战赛',
    '官方训练营',
    '官方公开课',
    '官方体验课',
    '有奖征集',
    '学习通使用指南',
    '学习通新手引导',
    '学习通新生引导',
    '超星平台使用',
    '超星平台操作',
  ];

  static bool isOfficialPromoCourse(
    String? courseName, [
    Iterable<String> teacherNames = const [],
  ]) {
    final fields = <String>[
      if (courseName != null && courseName.trim().isNotEmpty)
        courseName.trim().toLowerCase(),
      for (final t in teacherNames)
        if (t.trim().isNotEmpty) t.trim().toLowerCase(),
    ];
    if (fields.isEmpty) return false;
    for (final text in fields) {
      for (final keyword in _officialPromoKeywords) {
        if (text.contains(keyword)) return true;
      }
    }
    return false;
  }

  /// Matches Chaoxing automated reminder broadcasts verified in Phase 3A.
  static bool isSystemReminderNotice(CourseNotice notice) =>
      notice.isSystemReminder;

  static const Duration maxFutureActivityVoteHorizon = Duration(days: 365);

  static const int _minChaoxingCohortClazzId = 10000000;
  static const int _maxIntraTermClazzIdSpan = 9000000;
  static const int _tightSameTermClazzIdDelta = 3800000;
  static const int _currentTermForwardClazzIdDelta = 6000000;
  static const int _earliestPastSameTermClazzIdDelta = 7500000;
  static const int _pastStepBoundaryClazzIdDelta = 7500000;
  static const int _defaultSemesterClazzIdStep = 11500000;
  static const int _minCalibratedSemesterClazzIdStep = 9000000;
  static const int _maxCalibratedSemesterClazzIdStep = 15000000;
  static const int _maxExtrapolatedTermSteps = 12;

  static int? _parseCohortClazzId(CourseRef? course) {
    if (course == null) return null;
    final trimmed = course.clazzId.trim();
    if (trimmed.isEmpty || !RegExp(r'^\d+$').hasMatch(trimmed)) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < _minChaoxingCohortClazzId) return null;
    return parsed;
  }

  static int _sortedMedian(List<int> sorted) {
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) ~/ 2;
  }

  static Map<String, AcademicTerm> _inferTermsByClazzIdCohort({
    required Iterable<String> catalogKeys,
    required Map<String, CourseRef> coursesByKey,
    required Map<String, _BaseCourseResolution> baseByKey,
    required AcademicTerm currentTerm,
  }) {
    final idsByTerm = <AcademicTerm, List<int>>{};
    for (final key in catalogKeys) {
      final base = baseByKey[key]!;
      if (base.isBlocked) continue;
      final term = base.term;
      if (term == null || term > currentTerm) continue;
      final clazzId = _parseCohortClazzId(coursesByKey[key]);
      if (clazzId == null) continue;
      (idsByTerm[term] ??= []).add(clazzId);
    }
    if (idsByTerm.isEmpty) return const {};

    final candidates = <_ClazzIdCluster>[];
    for (final entry in idsByTerm.entries) {
      final ids = entry.value..sort();
      late final List<int> kept;
      if (ids.last - ids.first <= _maxIntraTermClazzIdSpan) {
        kept = ids;
      } else {
        var left = 0;
        var bestStart = 0;
        var bestEnd = -1;
        for (var right = 0; right < ids.length; right++) {
          while (ids[right] - ids[left] > _maxIntraTermClazzIdSpan) {
            left++;
          }
          final count = right - left + 1;
          final bestCount = bestEnd - bestStart + 1;
          if (count > bestCount || (count == bestCount && left > bestStart)) {
            bestStart = left;
            bestEnd = right;
          }
        }
        final bestCount = bestEnd - bestStart + 1;
        if (bestCount * 2 <= ids.length) continue;
        kept = ids.sublist(bestStart, bestEnd + 1);
      }
      candidates.add(
        _ClazzIdCluster(
          term: entry.key,
          minId: kept.first,
          maxId: kept.last,
          medianId: _sortedMedian(kept),
          count: kept.length,
        ),
      );
    }
    if (candidates.isEmpty) return const {};
    candidates.sort((a, b) => a.term.compareTo(b.term));

    var isStrictlyMonotonic = true;
    for (var i = 0; i < candidates.length - 1; i++) {
      if (candidates[i].maxId >= candidates[i + 1].minId) {
        isStrictlyMonotonic = false;
        break;
      }
    }

    late final List<_ClazzIdCluster> clusters;
    if (isStrictlyMonotonic) {
      clusters = candidates;
    } else {
      final n = candidates.length;
      final dp = List<int>.generate(n, (i) => candidates[i].count);
      final ways = List<int>.filled(n, 1);
      final prev = List<int>.filled(n, -1);
      var totalWeight = 0;
      for (var i = 0; i < n; i++) {
        totalWeight += candidates[i].count;
        for (var j = 0; j < i; j++) {
          if (candidates[j].maxId < candidates[i].minId) {
            final weight = dp[j] + candidates[i].count;
            if (weight > dp[i]) {
              dp[i] = weight;
              ways[i] = ways[j];
              prev[i] = j;
            } else if (weight == dp[i]) {
              ways[i] = math.min(2, ways[i] + ways[j]);
            }
          }
        }
      }
      var bestWeight = 0;
      for (final w in dp) {
        if (w > bestWeight) bestWeight = w;
      }
      var bestEnd = -1;
      var totalBestWays = 0;
      for (var i = 0; i < n; i++) {
        if (dp[i] == bestWeight) {
          bestEnd = i;
          totalBestWays = math.min(2, totalBestWays + ways[i]);
        }
      }
      if (totalBestWays != 1 || bestWeight * 2 <= totalWeight || bestEnd < 0) {
        return const {};
      }
      final chosen = <_ClazzIdCluster>[];
      var cursor = bestEnd;
      while (cursor != -1) {
        chosen.add(candidates[cursor]);
        cursor = prev[cursor];
      }
      clusters = chosen.reversed.toList(growable: false);
    }

    final slopes = <int>[];
    for (var i = 0; i < clusters.length; i++) {
      for (var j = i + 1; j < clusters.length; j++) {
        final termDiff = clusters[j].term._ordinal - clusters[i].term._ordinal;
        if (termDiff <= 0) continue;
        final slope = (clusters[j].medianId - clusters[i].medianId) ~/ termDiff;
        if (slope >= 7500000 && slope <= 18000000) {
          slopes.add(slope);
        }
      }
    }
    late final int step;
    if (slopes.isEmpty) {
      step = _defaultSemesterClazzIdStep;
    } else {
      slopes.sort();
      step = _sortedMedian(slopes).clamp(
        _minCalibratedSemesterClazzIdStep,
        _maxCalibratedSemesterClazzIdStep,
      );
    }

    AcademicTerm? inferForId(int id) {
      for (final cluster in clusters) {
        if (id >= cluster.minId && id <= cluster.maxId) {
          return cluster.term;
        }
      }
      final first = clusters.first;
      if (id < first.minId) {
        final delta = first.minId - id;
        if (first.term < currentTerm) {
          if (delta <= _earliestPastSameTermClazzIdDelta) {
            return first.term;
          }
          final steps = math.max(1, (delta / step).round());
          if (steps > _maxExtrapolatedTermSteps) return null;
          return first.term._shift(-steps);
        }
        if (delta <= _tightSameTermClazzIdDelta) {
          return currentTerm;
        }
        if (delta >= _pastStepBoundaryClazzIdDelta) {
          final steps = math.max(1, (delta / step).round());
          if (steps > _maxExtrapolatedTermSteps) return null;
          return currentTerm._shift(-steps);
        }
        return null;
      }

      final last = clusters.last;
      if (id > last.maxId) {
        final delta = id - last.maxId;
        if (last.term == currentTerm) {
          return delta <= _currentTermForwardClazzIdDelta ? currentTerm : null;
        }
        if (delta <= _tightSameTermClazzIdDelta) {
          return last.term;
        }
        if (delta >= _pastStepBoundaryClazzIdDelta) {
          final steps = math.max(1, (delta / step).round());
          final maxForward = currentTerm._ordinal - last.term._ordinal;
          if (steps <= maxForward) {
            return last.term._shift(steps);
          }
          if (id <=
              last.maxId +
                  maxForward * step +
                  _currentTermForwardClazzIdDelta) {
            return currentTerm;
          }
          return null;
        }
        return null;
      }

      for (var i = 0; i < clusters.length - 1; i++) {
        final low = clusters[i];
        final high = clusters[i + 1];
        if (id > low.maxId && id < high.minId) {
          final dLow = id - low.maxId;
          final dHigh = high.minId - id;
          final termGap = high.term._ordinal - low.term._ordinal;
          if (dHigh <= _tightSameTermClazzIdDelta && dHigh * 2 <= dLow) {
            return high.term;
          }
          if (dLow <= _tightSameTermClazzIdDelta && dLow * 2 <= dHigh) {
            return low.term;
          }
          if (termGap == 1) {
            if (low.term < currentTerm && high.term < currentTerm) {
              return dLow <= dHigh ? low.term : high.term;
            }
            return null;
          }
          if (termGap >= 2) {
            final span = high.medianId - low.medianId;
            if (span <= 0) return null;
            final offset = (((id - low.medianId) / span) * termGap)
                .round()
                .clamp(0, termGap);
            if (offset == termGap && high.term == currentTerm) {
              return null;
            }
            return low.term._shift(offset);
          }
          return null;
        }
      }
      return null;
    }

    final inferred = <String, AcademicTerm>{};
    for (final key in catalogKeys) {
      final base = baseByKey[key]!;
      if (base.isBlocked || base.term != null) continue;
      final clazzId = _parseCohortClazzId(coursesByKey[key]);
      if (clazzId == null) continue;
      final guessed = inferForId(clazzId);
      if (guessed != null) {
        inferred[key] = guessed;
      }
    }
    return inferred;
  }

  static AcademicTerm? _courseStartTerm(
    CourseRef? course,
    DateTime maxRecallUtc,
  ) {
    final startAt = course?.courseStartAt;
    if (startAt == null) return null;
    if (startAt.toUtc().isAfter(maxRecallUtc)) return null;
    return AcademicTerm.fromCourseCreationInstant(startAt);
  }

  /// Picks the single timestamp an assignment may vote with.
  ///
  /// Deadline or trusted exam time wins over live-sync publication metadata so a
  /// single record cannot vote twice across semesters. Implausibly far future
  /// timestamps are dropped instead of falling through to weaker evidence.
  static DateTime? _representativeAssignmentTimestampUtc(
    Assignment a, {
    required DateTime nowUtc,
  }) {
    final maxVoteUtc = nowUtc.add(maxFutureActivityVoteHorizon);
    DateTime? candidate;
    if (a.isExam) {
      final exam = a.exam;
      if (exam == null || exam.noticeOnly) return null;
      if (exam.startTrusted && exam.startAt != null) {
        candidate = exam.startAt!.toUtc();
      } else if (exam.endTrusted && exam.endAt != null) {
        candidate = exam.endAt!.toUtc();
      }
    } else if (a.deadlineTrusted &&
        !a.deadlineReadFailed &&
        a.deadlineAt != null) {
      candidate = a.deadlineAt!.toUtc();
    }
    final hasLiveSync = a.lastSyncedAt.millisecondsSinceEpoch > 0;
    if (candidate == null && hasLiveSync && a.availableFromAt != null) {
      candidate = a.availableFromAt!.toUtc();
    }
    if (candidate == null && hasLiveSync && a.publishedAt != null) {
      candidate = a.publishedAt!.toUtc();
    }
    if (candidate == null || candidate.isAfter(maxVoteUtc)) return null;
    return candidate;
  }

  static int _compareVotePreference(
    AcademicTerm candidate,
    AcademicTerm current,
    AcademicTerm currentTerm,
  ) {
    final candidateAtOrBefore = candidate <= currentTerm;
    final currentAtOrBefore = current <= currentTerm;
    if (candidateAtOrBefore != currentAtOrBefore) {
      return candidateAtOrBefore ? -1 : 1;
    }
    if (candidateAtOrBefore) {
      return current.compareTo(candidate);
    }
    return candidate.compareTo(current);
  }

  /// Votes every non-hidden record at most once and returns the majority term.
  ///
  /// Notices only vote when no assignment provides usable evidence, so system
  /// broadcasts and sync-day change timestamps never decide a course term.
  static AcademicTerm? _resolveActivityTermByVote({
    required Iterable<Assignment> assignments,
    required Iterable<CourseNotice> notices,
    required DateTime nowUtc,
    required AcademicTerm currentTerm,
    required Set<String> hiddenAssignmentIds,
  }) {
    final votes = <AcademicTerm, int>{};
    for (final a in assignments) {
      if (hiddenAssignmentIds.contains(a.id)) continue;
      final at = _representativeAssignmentTimestampUtc(a, nowUtc: nowUtc);
      if (at == null) continue;
      final term = AcademicTerm.fromInstant(at);
      votes[term] = (votes[term] ?? 0) + 1;
    }
    if (votes.isEmpty) {
      final maxVoteUtc = nowUtc.add(maxFutureActivityVoteHorizon);
      for (final n in notices) {
        if (!n.publishedTrusted ||
            n.publishedAt == null ||
            isSystemReminderNotice(n)) {
          continue;
        }
        final at = n.publishedAt!.toUtc();
        if (at.isAfter(maxVoteUtc)) continue;
        final term = AcademicTerm.fromInstant(at);
        votes[term] = (votes[term] ?? 0) + 1;
      }
    }
    AcademicTerm? best;
    var bestCount = 0;
    for (final vote in votes.entries) {
      final term = vote.key;
      final count = vote.value;
      if (best == null || count > bestCount) {
        best = term;
        bestCount = count;
        continue;
      }
      if (count < bestCount) continue;
      if (_compareVotePreference(term, best, currentTerm) < 0) {
        best = term;
      }
    }
    return best;
  }

  static List<DateTime> _trustedAssignmentTimestampsUtc(Assignment a) {
    final times = <DateTime>[];
    final hasLiveSync = a.lastSyncedAt.millisecondsSinceEpoch > 0;
    if (hasLiveSync && a.publishedAt != null) {
      times.add(a.publishedAt!.toUtc());
    }
    if (hasLiveSync && a.availableFromAt != null) {
      times.add(a.availableFromAt!.toUtc());
    }
    if (a.isExam) {
      final exam = a.exam;
      if (exam != null && !exam.noticeOnly) {
        if (exam.startTrusted && exam.startAt != null) {
          times.add(exam.startAt!.toUtc());
        }
        if (exam.endTrusted && exam.endAt != null) {
          times.add(exam.endAt!.toUtc());
        }
      }
    } else if (a.deadlineTrusted &&
        !a.deadlineReadFailed &&
        a.deadlineAt != null) {
      times.add(a.deadlineAt!.toUtc());
    }
    return times;
  }

  static DateTime? _maxUtc(Iterable<DateTime> items) {
    DateTime? best;
    for (final item in items) {
      final utc = item.toUtc();
      if (best == null || utc.isAfter(best)) {
        best = utc;
      }
    }
    return best;
  }

  static bool _hasDeadlineBeforeTerm(
    Assignment a,
    AcademicTerm currentTerm,
  ) {
    if (a.isExam) {
      final exam = a.exam;
      if (exam != null && !exam.noticeOnly) {
        if (exam.startTrusted &&
            exam.startAt != null &&
            AcademicTerm.fromInstant(exam.startAt!) < currentTerm) {
          return true;
        }
        if (exam.endTrusted &&
            exam.endAt != null &&
            AcademicTerm.fromInstant(exam.endAt!) < currentTerm) {
          return true;
        }
      }
      return false;
    }
    return a.deadlineTrusted &&
        !a.deadlineReadFailed &&
        a.deadlineAt != null &&
        AcademicTerm.fromInstant(a.deadlineAt!) < currentTerm;
  }

  static List<DateTime> _trustedCurrentTermDeadlineOrExamTimesUtc(
    Assignment a,
    AcademicTerm currentTerm,
  ) {
    final times = <DateTime>[];
    if (a.isExam) {
      final exam = a.exam;
      if (exam != null && !exam.noticeOnly) {
        if (exam.startTrusted &&
            exam.startAt != null &&
            AcademicTerm.fromInstant(exam.startAt!) == currentTerm) {
          times.add(exam.startAt!.toUtc());
        }
        if (exam.endTrusted &&
            exam.endAt != null &&
            AcademicTerm.fromInstant(exam.endAt!) == currentTerm) {
          times.add(exam.endAt!.toUtc());
        }
      }
    } else if (a.deadlineTrusted &&
        !a.deadlineReadFailed &&
        a.deadlineAt != null &&
        AcademicTerm.fromInstant(a.deadlineAt!) == currentTerm) {
      times.add(a.deadlineAt!.toUtc());
    }
    return times;
  }

  static bool _hasNearFutureOrCurrentTermSignal(
    Assignment a, {
    required DateTime nowUtc,
    required DateTime maxRecallUtc,
    required AcademicTerm currentTerm,
    required LocalCourseworkState coursework,
  }) {
    if (a.isExam) {
      if (a.exam != null &&
          !a.exam!.noticeOnly &&
          !AssignmentQuery.isExamEnded(a, nowUtc) &&
          a.timelineTrusted &&
          a.timelineAt != null) {
        final atUtc = a.timelineAt!.toUtc();
        if (atUtc.isAfter(nowUtc) && !atUtc.isAfter(maxRecallUtc)) {
          return true;
        }
      }
    } else {
      final resolved = CourseworkDeadline.resolveEntry(
        a,
        CourseworkDeadline.entryFor(a, coursework),
      );
      if (resolved != null) {
        final atUtc = resolved.at.toUtc();
        if (atUtc.isAfter(nowUtc) && !atUtc.isAfter(maxRecallUtc)) {
          return true;
        }
      }
    }
    final hasLiveSync = a.lastSyncedAt.millisecondsSinceEpoch > 0;
    if (hasLiveSync &&
        a.publishedAt != null &&
        AcademicTerm.fromInstant(a.publishedAt!) >= currentTerm) {
      return true;
    }
    if (hasLiveSync &&
        a.availableFromAt != null &&
        AcademicTerm.fromInstant(a.availableFromAt!) >= currentTerm) {
      return true;
    }
    return false;
  }

  factory CourseTermCatalog.build({
    required Iterable<CourseRef> courses,
    required Iterable<Assignment> assignments,
    required Iterable<CourseNotice> notices,
    required CourseTermPreferences preferences,
    required DateTime now,
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
    Set<String> unfollowedCourseKeys = const {},
    Set<String> hiddenAssignmentIds = const {},
    Iterable<AssignmentChange> changes = const [],
  }) {
    final nowUtc = now.toUtc();
    final maxRecallUtc = nowUtc.add(maxFutureRecallHorizon);
    final currentTerm = AcademicTerm.fromInstant(now);
    final coursesByKey = <String, CourseRef>{
      for (final c in courses) c.key: c,
    };
    final catalogKeys = <String>{
      ...coursesByKey.keys,
      ...preferences.entries.keys,
    };

    final assignmentsByCourse = <String, List<Assignment>>{};
    final assignmentsById = <String, Assignment>{};
    for (final a in assignments) {
      assignmentsById[a.id] = a;
      final key = a.courseKey;
      if (key == null || !catalogKeys.contains(key)) continue;
      (assignmentsByCourse[key] ??= []).add(a);
    }
    final noticesByCourse = <String, List<CourseNotice>>{};
    for (final n in notices) {
      final key = n.courseKey;
      if (key == null || !catalogKeys.contains(key)) continue;
      (noticesByCourse[key] ??= []).add(n);
    }

    final baseByKey = <String, _BaseCourseResolution>{};
    for (final key in catalogKeys) {
      final course = coursesByKey[key];
      final courseRecords = assignmentsByCourse[key] ?? const <Assignment>[];
      final courseNotices = noticesByCourse[key] ?? const <CourseNotice>[];
      final override = preferences.entryFor(key) ?? const CourseTermOverride();
      final activityTerm = _resolveActivityTermByVote(
        assignments: courseRecords,
        notices: courseNotices,
        nowUtc: nowUtc,
        currentTerm: currentTerm,
        hiddenAssignmentIds: hiddenAssignmentIds,
      );
      final resolvedCourseName = course?.name ??
          courseRecords.firstOrNull?.courseName ??
          courseNotices.firstOrNull?.courseName;
      final isAutoPromo = isOfficialPromoCourse(
        resolvedCourseName,
        course?.teacherNames ?? const [],
      );
      final isBlocked = override.blockMode == CourseBlockMode.blocked ||
          (isAutoPromo && override.blockMode == CourseBlockMode.auto);
      final manualTerm = AcademicTerm.tryParseKey(override.manualTermKey);
      final folderTerm = AcademicTerm.tryParseFolderLabel(course?.folderName);
      final courseNameTerm =
          AcademicTerm.tryParseCourseName(resolvedCourseName);
      final clazzNameTerm =
          AcademicTerm.tryParseCourseName(course?.normalizedClazzName);
      final courseTimeTerm = _courseStartTerm(course, maxRecallUtc);

      late final AcademicTerm? term;
      late final CourseTermSource source;
      late final String explanation;
      if (manualTerm != null) {
        term = manualTerm;
        source = CourseTermSource.manual;
        explanation = '手动归属（${manualTerm.label}）';
      } else if (folderTerm != null) {
        term = folderTerm;
        source = CourseTermSource.folder;
        explanation = '目录「${course!.folderName!.trim()}」';
      } else if (activityTerm != null) {
        term = activityTerm;
        source = CourseTermSource.activity;
        explanation = '按课业时间分布识别（${activityTerm.label}）';
      } else if (courseNameTerm != null) {
        term = courseNameTerm;
        source = CourseTermSource.courseName;
        explanation = '按课程名识别（${courseNameTerm.label}）';
      } else if (clazzNameTerm != null) {
        term = clazzNameTerm;
        source = CourseTermSource.clazzName;
        explanation = '按班级名识别（${clazzNameTerm.label}）';
      } else if (courseTimeTerm != null) {
        term = courseTimeTerm;
        source = CourseTermSource.courseTime;
        explanation = '按课程时间识别（${courseTimeTerm.label}）';
      } else {
        term = null;
        source = CourseTermSource.ungrouped;
        explanation = '未分组（保守保留在学）';
      }
      baseByKey[key] = _BaseCourseResolution(
        term: term,
        source: source,
        explanation: explanation,
        isBlocked: isBlocked,
        isAutoPromo: isAutoPromo,
      );
    }

    final cohortByKey = _inferTermsByClazzIdCohort(
      catalogKeys: catalogKeys,
      coursesByKey: coursesByKey,
      baseByKey: baseByKey,
      currentTerm: currentTerm,
    );

    final baseIsPastByCourse = <String, bool>{
      for (final key in catalogKeys)
        key: () {
          final resolved = baseByKey[key]!.term ?? cohortByKey[key];
          return resolved != null && resolved < currentTerm;
        }(),
    };

    final publishedChangeTimesByCourse = <String, List<DateTime>>{};
    for (final change in changes) {
      if (change.kind != AssignmentChangeKind.published) continue;
      if (AcademicTerm.fromInstant(change.at) != currentTerm) continue;
      if (hiddenAssignmentIds.contains(change.assignmentId)) continue;
      final a = assignmentsById[change.assignmentId];
      if (a == null) continue;
      final key = a.courseKey;
      if (key == null || !catalogKeys.contains(key)) continue;
      if (CourseworkDeadline.isEffectivelyCompleted(a, coursework)) continue;
      if (_hasDeadlineBeforeTerm(a, currentTerm)) continue;
      if ((baseIsPastByCourse[key] ?? false) &&
          !_hasNearFutureOrCurrentTermSignal(
            a,
            nowUtc: nowUtc,
            maxRecallUtc: maxRecallUtc,
            currentTerm: currentTerm,
            coursework: coursework,
          )) {
        continue;
      }
      (publishedChangeTimesByCourse[key] ??= []).add(change.at.toUtc());
    }

    final entries = <String, CourseTermEntry>{};
    for (final key in catalogKeys) {
      final course = coursesByKey[key];
      final courseRecords = assignmentsByCourse[key] ?? const <Assignment>[];
      final courseNotices = noticesByCourse[key] ?? const <CourseNotice>[];
      final override = preferences.entryFor(key) ?? const CourseTermOverride();
      final base = baseByKey[key]!;
      final publishedChangeTimes =
          publishedChangeTimesByCourse[key] ?? const <DateTime>[];

      final trustedActivityTimes = <DateTime>[
        for (final a in courseRecords) ..._trustedAssignmentTimestampsUtc(a),
        for (final n in courseNotices)
          if (n.publishedTrusted &&
              n.publishedAt != null &&
              !isSystemReminderNotice(n))
            n.publishedAt!.toUtc(),
        ...publishedChangeTimes,
      ];
      final latestActivityUtc = _maxUtc(trustedActivityTimes);

      final resolvedCourseName = course?.name ??
          courseRecords.firstOrNull?.courseName ??
          courseNotices.firstOrNull?.courseName;
      final cohortTerm = cohortByKey[key];
      final term = base.term ?? cohortTerm;
      final source = base.term != null
          ? base.source
          : cohortTerm != null
              ? CourseTermSource.clazzCohort
              : CourseTermSource.ungrouped;
      final explanation = base.term != null
          ? base.explanation
          : cohortTerm != null
              ? '按同批班级时段推测（${cohortTerm.label}）'
              : base.explanation;

      DateTime? latestRecallEventUtc;
      final recallSignals = <DateTime>[
        if (term != null && term < currentTerm) ...publishedChangeTimes,
      ];
      for (final a in courseRecords) {
        if (hiddenAssignmentIds.contains(a.id)) continue;
        final completed = CourseworkDeadline.isEffectivelyCompleted(
          a,
          coursework,
        );
        if (!completed) {
          final resolved = a.isExam
              ? null
              : CourseworkDeadline.resolveEntry(
                  a,
                  CourseworkDeadline.entryFor(a, coursework),
                );
          if (resolved != null &&
              resolved.at.toUtc().isAfter(nowUtc) &&
              !resolved.at.toUtc().isAfter(maxRecallUtc)) {
            recallSignals.add(
              _maxUtc([
                    resolved.at,
                    ..._trustedAssignmentTimestampsUtc(a),
                  ]) ??
                  resolved.at.toUtc(),
            );
          } else if (a.isExam &&
              a.exam != null &&
              !a.exam!.noticeOnly &&
              !AssignmentQuery.isExamEnded(a, now) &&
              a.timelineTrusted &&
              a.timelineAt != null &&
              a.timelineAt!.toUtc().isAfter(nowUtc) &&
              !a.timelineAt!.toUtc().isAfter(maxRecallUtc)) {
            recallSignals.add(a.timelineAt!.toUtc());
          }
        }
        final hasLiveSync = a.lastSyncedAt.millisecondsSinceEpoch > 0;
        if (hasLiveSync &&
            a.publishedAt != null &&
            AcademicTerm.fromInstant(a.publishedAt!) >= currentTerm) {
          recallSignals.add(a.publishedAt!.toUtc());
        }
        if (hasLiveSync &&
            a.availableFromAt != null &&
            AcademicTerm.fromInstant(a.availableFromAt!) >= currentTerm) {
          recallSignals.add(a.availableFromAt!.toUtc());
        }
        recallSignals.addAll(
          _trustedCurrentTermDeadlineOrExamTimesUtc(a, currentTerm),
        );
      }
      for (final n in courseNotices) {
        if (n.publishedTrusted &&
            n.publishedAt != null &&
            !isSystemReminderNotice(n) &&
            AcademicTerm.fromInstant(n.publishedAt!) >= currentTerm) {
          recallSignals.add(n.publishedAt!.toUtc());
        }
      }
      latestRecallEventUtc = _maxUtc(recallSignals);

      late final CourseCatalogState state;
      switch (override.archiveMode) {
        case CourseArchiveMode.archived:
          state = CourseCatalogState.archived;
        case CourseArchiveMode.restored:
          state = CourseCatalogState.active;
        case CourseArchiveMode.auto:
          if (term == null || term >= currentTerm) {
            state = CourseCatalogState.active;
          } else {
            final cursor = override.dismissedRecallCursorUtc;
            final hasNewRecall = latestRecallEventUtc != null &&
                (cursor == null || latestRecallEventUtc.isAfter(cursor));
            state = hasNewRecall
                ? CourseCatalogState.recalled
                : CourseCatalogState.archived;
          }
      }

      entries[key] = CourseTermEntry(
        courseKey: key,
        courseName: resolvedCourseName ?? key,
        term: term,
        source: source,
        explanation: explanation,
        state: state,
        override: override,
        latestTrustedActivityUtc: latestActivityUtc,
        latestRecallEventUtc: latestRecallEventUtc,
        isFollowed: !unfollowedCourseKeys.contains(key),
        isAutoPromo: base.isAutoPromo,
      );
    }

    return CourseTermCatalog._(
      currentTerm: currentTerm,
      now: now,
      entriesByCourseKey: Map.unmodifiable(entries),
      unfollowedCourseKeys: unfollowedCourseKeys,
      hiddenAssignmentIds: hiddenAssignmentIds,
      coursework: coursework,
    );
  }

  CourseTermEntry? entryFor(String courseKey) => _entriesByCourseKey[courseKey];

  Iterable<CourseTermEntry> get entries => _entriesByCourseKey.values;

  bool isBlocked(String courseKey) =>
      _entriesByCourseKey[courseKey]?.isBlocked ?? false;

  List<CourseTermEntry> get autoBlockedPromoEntries => [
        for (final entry in _entriesByCourseKey.values)
          if (entry.isAutoBlockedPromo) entry,
      ];

  List<CourseTermEntry> get manuallyBlockedEntries => [
        for (final entry in _entriesByCourseKey.values)
          if (entry.isManuallyBlocked) entry,
      ];

  bool isActiveOrRecalled(String courseKey) {
    final entry = _entriesByCourseKey[courseKey];
    if (entry == null) return true;
    if (entry.isBlocked) return false;
    return entry.state != CourseCatalogState.archived;
  }

  bool isRecalled(String courseKey) =>
      _entriesByCourseKey[courseKey]?.state == CourseCatalogState.recalled;

  bool isArchived(String courseKey) =>
      _entriesByCourseKey[courseKey]?.state == CourseCatalogState.archived;

  List<String> get archivablePastCourseKeys => [
        for (final entry in _entriesByCourseKey.values)
          if (!entry.isBlocked &&
              entry.override.archiveMode == CourseArchiveMode.auto &&
              entry.state == CourseCatalogState.archived &&
              entry.term != null &&
              entry.term! < currentTerm)
            entry.courseKey,
      ];

  bool isUngroupedCourse(String courseKey) =>
      _entriesByCourseKey[courseKey]?.isUngrouped ?? false;

  bool matchesHomeCoursePicker(
    String courseKey,
    String filterId, {
    bool hasVisibleItems = false,
  }) {
    final entry = _entriesByCourseKey[courseKey];
    if (entry != null && entry.isBlocked) return false;
    return switch (filterId) {
      'allTerms' => true,
      'pastTerms' => entry != null &&
          (entry.state == CourseCatalogState.archived ||
              (entry.term != null && entry.term! < currentTerm)),
      'currentAcademicYear' => (hasVisibleItems &&
              (entry == null || entry.state != CourseCatalogState.archived)) ||
          (entry != null &&
              (entry.state == CourseCatalogState.recalled ||
                  (entry.term != null &&
                      entry.term!.academicYearStart ==
                          currentTerm.academicYearStart))),
      _ => (hasVisibleItems &&
              (entry == null || entry.state != CourseCatalogState.archived)) ||
          (entry != null && entry.hasCurrentTermEvidence),
    };
  }

  bool matchesCoursePickerScope(String courseKey, CourseTermScope scope) {
    final entry = _entriesByCourseKey[courseKey];
    if (entry != null && entry.isBlocked) return false;
    if (entry == null) {
      return scope != CourseTermScope.pastTerms;
    }
    return switch (scope) {
      CourseTermScope.allTerms => true,
      CourseTermScope.currentTerm => entry.hasCurrentTermEvidence,
      CourseTermScope.currentAcademicYear =>
        entry.state == CourseCatalogState.recalled ||
            (entry.term != null &&
                entry.term!.academicYearStart == currentTerm.academicYearStart),
      CourseTermScope.pastTerms => entry.state == CourseCatalogState.archived ||
          (entry.term != null && entry.term! < currentTerm),
    };
  }

  bool _isRecordCurrentTermOrRecall(Assignment a) {
    if (_hiddenAssignmentIds.contains(a.id)) return false;
    final nowUtc = now.toUtc();
    final maxRecallUtc = nowUtc.add(maxFutureRecallHorizon);
    final completed = CourseworkDeadline.isEffectivelyCompleted(a, _coursework);
    if (!completed) {
      final resolved = a.isExam
          ? null
          : CourseworkDeadline.resolveEntry(
              a,
              CourseworkDeadline.entryFor(a, _coursework),
            );
      if (resolved != null) {
        final atUtc = resolved.at.toUtc();
        if (atUtc.isAfter(nowUtc) && !atUtc.isAfter(maxRecallUtc)) {
          return true;
        }
      }
      if (a.isExam &&
          a.exam != null &&
          !a.exam!.noticeOnly &&
          !AssignmentQuery.isExamEnded(a, now) &&
          a.timelineTrusted &&
          a.timelineAt != null) {
        final atUtc = a.timelineAt!.toUtc();
        if (atUtc.isAfter(nowUtc) && !atUtc.isAfter(maxRecallUtc)) {
          return true;
        }
      }
    }
    final hasLiveSync = a.lastSyncedAt.millisecondsSinceEpoch > 0;
    if (hasLiveSync &&
        a.publishedAt != null &&
        AcademicTerm.fromInstant(a.publishedAt!) >= currentTerm) {
      return true;
    }
    if (hasLiveSync &&
        a.availableFromAt != null &&
        AcademicTerm.fromInstant(a.availableFromAt!) >= currentTerm) {
      return true;
    }
    if (_trustedCurrentTermDeadlineOrExamTimesUtc(a, currentTerm).isNotEmpty) {
      return true;
    }
    return false;
  }

  bool _isRecordInCurrentAcademicYear(Assignment a, CourseTermEntry entry) {
    final timestamps = _trustedAssignmentTimestampsUtc(a);
    if (timestamps.isNotEmpty) {
      return timestamps.any(
        (ts) =>
            AcademicTerm.fromInstant(ts).academicYearStart ==
            currentTerm.academicYearStart,
      );
    }
    if (_isRecordCurrentTermOrRecall(a)) return true;
    return entry.term == null ||
        entry.term!.academicYearStart == currentTerm.academicYearStart;
  }

  bool matchesAssignmentInStatsScope(Assignment a, CourseTermScope scope) {
    final courseKey = a.courseKey;
    if (courseKey != null &&
        (_unfollowedCourseKeys.contains(courseKey) || isBlocked(courseKey))) {
      return false;
    }
    if (courseKey == null) {
      return scope != CourseTermScope.pastTerms;
    }
    final entry = _entriesByCourseKey[courseKey];
    if (entry == null) {
      return scope != CourseTermScope.pastTerms;
    }
    if (entry.isBlocked) {
      return false;
    }
    switch (scope) {
      case CourseTermScope.allTerms:
        return true;
      case CourseTermScope.currentTerm:
        if (entry.state == CourseCatalogState.active) return true;
        if (entry.state == CourseCatalogState.archived) return false;
        return _isRecordCurrentTermOrRecall(a);
      case CourseTermScope.currentAcademicYear:
        if (entry.state == CourseCatalogState.recalled) {
          return _isRecordInCurrentAcademicYear(a, entry);
        }
        return entry.term == null ||
            entry.term!.academicYearStart == currentTerm.academicYearStart;
      case CourseTermScope.pastTerms:
        if (entry.state == CourseCatalogState.recalled) {
          return !_isRecordCurrentTermOrRecall(a);
        }
        return entry.state == CourseCatalogState.archived ||
            (entry.term != null && entry.term! < currentTerm);
    }
  }
}
