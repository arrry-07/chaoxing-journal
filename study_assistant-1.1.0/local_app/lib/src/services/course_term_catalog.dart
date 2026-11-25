import '../models/assignment.dart';
import '../models/assignment_change.dart';
import '../models/course.dart';
import '../models/course_notice.dart';
import '../models/course_term_preferences.dart';
import '../models/local_coursework_state.dart';
import 'assignment_query.dart';
import 'coursework_deadline.dart';

enum AcademicSemester { fall, spring }

enum CourseTermSource { manual, folder, activity, ungrouped }

enum CourseCatalogState { active, recalled, archived }

enum CourseTermScope {
  currentTerm('本学期'),
  currentAcademicYear('当前学年'),
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

  static final RegExp _keyPattern = RegExp(r'^(20\d{2})-(fall|spring)$');
  static final RegExp _spanFolderPattern = RegExp(
    r'^(20\d{2})\s*[-—~/－至]\s*(20\d{2})\s*(?:学年)?\s*(?:[\(\[（【]?\s*([12一二])\s*[\)\]）】]?|第\s*([12一二])\s*学期|(?:年\s*)?(秋|春)(?:季学期|季|学期)?)\s*$',
  );
  static final RegExp _singleYearFolderPattern = RegExp(
    r'^(20\d{2})\s*(?:年\s*)?(秋|春)(?:季学期|季|学期)?\s*$',
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
    r'(?<!\d)(20\d{2})\s*[-—~/－至]\s*(20\d{2})\s*(?:学年)?\s*(?:[\(\[（【]?\s*([12一二])\s*[\)\]）】]?|第\s*([12一二])\s*学期|(?:年\s*)?(秋|春)(?:季学期|季|学期)?)',
  );
  static final RegExp _singleYearFolderLoosePattern = RegExp(
    r'(?<!\d)(20\d{2})\s*(?:年\s*)?(秋|春)(?:季学期|季|学期)?',
  );

  static AcademicTerm? tryParseFolderLabel(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;

    final spanMatch = _spanFolderPattern.firstMatch(text);
    if (spanMatch != null) {
      return _parseSpanMatch(spanMatch);
    }

    final singleMatch = _singleYearFolderPattern.firstMatch(text);
    if (singleMatch != null) {
      return _parseSingleYearMatch(singleMatch);
    }

    final matchedTerms = <AcademicTerm>{};
    final spanRanges = <(int, int)>[];
    for (final match in _spanFolderLoosePattern.allMatches(text)) {
      final parsed = _parseSpanMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
      spanRanges.add((match.start, match.end));
    }

    for (final match in _singleYearFolderLoosePattern.allMatches(text)) {
      final overlapsSpan = spanRanges.any(
        (range) => match.start < range.$2 && match.end > range.$1,
      );
      if (overlapsSpan) continue;
      final parsed = _parseSingleYearMatch(match);
      if (parsed == null) return null;
      matchedTerms.add(parsed);
    }

    return matchedTerms.length == 1 ? matchedTerms.first : null;
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
    final isFall = marker == '1' || marker == '一' || marker == '秋';
    final isSpring = marker == '2' || marker == '二' || marker == '春';
    if (isFall) return AcademicTerm(start, AcademicSemester.fall);
    if (isSpring) return AcademicTerm(start, AcademicSemester.spring);
    return null;
  }

  static AcademicTerm? _parseSingleYearMatch(RegExpMatch match) {
    final year = int.tryParse(match.group(1)!);
    if (year == null || year < 2000 || year > 2100) return null;
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

  /// Matches Chaoxing automated reminder broadcasts verified in Phase 3A.
  static bool isSystemReminderNotice(CourseNotice notice) =>
      notice.isSystemReminder;

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

    final baseIsPastByCourse = <String, bool>{};
    for (final key in catalogKeys) {
      final course = coursesByKey[key];
      final courseRecords = assignmentsByCourse[key] ?? const <Assignment>[];
      final courseNotices = noticesByCourse[key] ?? const <CourseNotice>[];
      final override = preferences.entryFor(key) ?? const CourseTermOverride();
      final baseActivityUtc = _maxUtc([
        for (final a in courseRecords) ..._trustedAssignmentTimestampsUtc(a),
        for (final n in courseNotices)
          if (n.publishedTrusted &&
              n.publishedAt != null &&
              !isSystemReminderNotice(n))
            n.publishedAt!.toUtc(),
      ]);
      final manualTerm = AcademicTerm.tryParseKey(override.manualTermKey);
      final folderTerm = AcademicTerm.tryParseFolderLabel(course?.folderName);
      final baseTerm = manualTerm ??
          folderTerm ??
          (baseActivityUtc != null
              ? AcademicTerm.fromInstant(baseActivityUtc)
              : null);
      baseIsPastByCourse[key] = baseTerm != null && baseTerm < currentTerm;
    }

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

      final manualTerm = AcademicTerm.tryParseKey(override.manualTermKey);
      final folderTerm = AcademicTerm.tryParseFolderLabel(course?.folderName);

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
      } else if (latestActivityUtc != null) {
        term = AcademicTerm.fromInstant(latestActivityUtc);
        source = CourseTermSource.activity;
        explanation = '按可信活动推断（${term.label}）';
      } else {
        term = null;
        source = CourseTermSource.ungrouped;
        explanation = '未分组（保守保留在学）';
      }

      DateTime? latestRecallEventUtc;
      final recallSignals = <DateTime>[...publishedChangeTimes];
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
        courseName: course?.name ??
            courseRecords.firstOrNull?.courseName ??
            courseNotices.firstOrNull?.courseName ??
            key,
        term: term,
        source: source,
        explanation: explanation,
        state: state,
        override: override,
        latestTrustedActivityUtc: latestActivityUtc,
        latestRecallEventUtc: latestRecallEventUtc,
        isFollowed: !unfollowedCourseKeys.contains(key),
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

  bool isActiveOrRecalled(String courseKey) {
    final entry = _entriesByCourseKey[courseKey];
    return entry == null || entry.state != CourseCatalogState.archived;
  }

  bool isRecalled(String courseKey) =>
      _entriesByCourseKey[courseKey]?.state == CourseCatalogState.recalled;

  bool isArchived(String courseKey) =>
      _entriesByCourseKey[courseKey]?.state == CourseCatalogState.archived;

  List<String> get archivablePastCourseKeys => [
        for (final entry in _entriesByCourseKey.values)
          if (entry.override.archiveMode == CourseArchiveMode.auto &&
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
    return switch (filterId) {
      'allTerms' => true,
      'pastTerms' => entry != null &&
          (entry.state == CourseCatalogState.archived ||
              (entry.term != null && entry.term! < currentTerm)),
      'ungrouped' => entry != null && entry.isUngrouped && !hasVisibleItems,
      _ => (hasVisibleItems &&
              (entry == null || entry.state != CourseCatalogState.archived)) ||
          (entry != null && entry.hasCurrentTermEvidence),
    };
  }

  bool matchesCoursePickerScope(String courseKey, CourseTermScope scope) {
    final entry = _entriesByCourseKey[courseKey];
    if (entry == null) {
      return scope != CourseTermScope.pastTerms;
    }
    return switch (scope) {
      CourseTermScope.allTerms => true,
      CourseTermScope.currentTerm => entry.hasCurrentTermEvidence,
      CourseTermScope.currentAcademicYear =>
        entry.state == CourseCatalogState.recalled ||
            entry.term == null ||
            entry.term!.academicYearStart == currentTerm.academicYearStart,
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
    if (courseKey != null && _unfollowedCourseKeys.contains(courseKey)) {
      return false;
    }
    if (courseKey == null) {
      return scope != CourseTermScope.pastTerms;
    }
    final entry = _entriesByCourseKey[courseKey];
    if (entry == null) {
      return scope != CourseTermScope.pastTerms;
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
