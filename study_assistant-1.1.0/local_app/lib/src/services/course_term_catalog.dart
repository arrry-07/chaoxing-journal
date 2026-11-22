import '../models/assignment.dart';
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

  static AcademicTerm? tryParseFolderLabel(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;

    final spanMatch = _spanFolderPattern.firstMatch(text);
    if (spanMatch != null) {
      final start = int.tryParse(spanMatch.group(1)!);
      final end = int.tryParse(spanMatch.group(2)!);
      if (start == null ||
          end == null ||
          end != start + 1 ||
          start < 2000 ||
          start > 2100) {
        return null;
      }
      final marker =
          spanMatch.group(3) ?? spanMatch.group(4) ?? spanMatch.group(5) ?? '';
      final isFall = marker == '1' || marker == '一' || marker == '秋';
      final isSpring = marker == '2' || marker == '二' || marker == '春';
      if (isFall) return AcademicTerm(start, AcademicSemester.fall);
      if (isSpring) return AcademicTerm(start, AcademicSemester.spring);
      return null;
    }

    final singleMatch = _singleYearFolderPattern.firstMatch(text);
    if (singleMatch != null) {
      final year = int.tryParse(singleMatch.group(1)!);
      if (year == null || year < 2000 || year > 2100) return null;
      return singleMatch.group(2) == '秋'
          ? AcademicTerm(year, AcademicSemester.fall)
          : AcademicTerm(year - 1, AcademicSemester.spring);
    }

    return null;
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

  factory CourseTermCatalog.build({
    required Iterable<CourseRef> courses,
    required Iterable<Assignment> assignments,
    required Iterable<CourseNotice> notices,
    required CourseTermPreferences preferences,
    required DateTime now,
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
    Set<String> unfollowedCourseKeys = const {},
    Set<String> hiddenAssignmentIds = const {},
  }) {
    final currentTerm = AcademicTerm.fromInstant(now);
    final coursesByKey = <String, CourseRef>{
      for (final c in courses) c.key: c,
    };
    final catalogKeys = <String>{
      ...coursesByKey.keys,
      ...preferences.entries.keys,
    };

    final assignmentsByCourse = <String, List<Assignment>>{};
    for (final a in assignments) {
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

    final entries = <String, CourseTermEntry>{};
    for (final key in catalogKeys) {
      final course = coursesByKey[key];
      final courseRecords = assignmentsByCourse[key] ?? const <Assignment>[];
      final courseNotices = noticesByCourse[key] ?? const <CourseNotice>[];
      final override = preferences.entryFor(key) ?? const CourseTermOverride();

      final trustedActivityTimes = <DateTime>[
        for (final a in courseRecords) ..._trustedAssignmentTimestampsUtc(a),
        for (final n in courseNotices)
          if (n.publishedTrusted &&
              n.publishedAt != null &&
              !isSystemReminderNotice(n))
            n.publishedAt!.toUtc(),
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
      final recallSignals = <DateTime>[];
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
          if (resolved != null && resolved.at.toUtc().isAfter(now.toUtc())) {
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
              a.timelineAt!.toUtc().isAfter(now.toUtc())) {
            recallSignals.add(a.timelineAt!.toUtc());
          }
        }
        for (final ts in _trustedAssignmentTimestampsUtc(a)) {
          if (AcademicTerm.fromInstant(ts) >= currentTerm) {
            recallSignals.add(ts.toUtc());
          }
        }
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

  bool matchesCoursePickerScope(String courseKey, CourseTermScope scope) {
    final entry = _entriesByCourseKey[courseKey];
    if (entry == null) {
      return scope != CourseTermScope.pastTerms;
    }
    return switch (scope) {
      CourseTermScope.allTerms => true,
      CourseTermScope.currentTerm => entry.state != CourseCatalogState.archived,
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
    final completed = CourseworkDeadline.isEffectivelyCompleted(a, _coursework);
    if (!completed) {
      final resolved = a.isExam
          ? null
          : CourseworkDeadline.resolveEntry(
              a,
              CourseworkDeadline.entryFor(a, _coursework),
            );
      if (resolved != null && resolved.at.toUtc().isAfter(now.toUtc())) {
        return true;
      }
      if (a.isExam &&
          a.exam != null &&
          !a.exam!.noticeOnly &&
          !AssignmentQuery.isExamEnded(a, now) &&
          a.timelineTrusted &&
          a.timelineAt != null &&
          a.timelineAt!.toUtc().isAfter(now.toUtc())) {
        return true;
      }
    }
    for (final ts in _trustedAssignmentTimestampsUtc(a)) {
      if (AcademicTerm.fromInstant(ts) >= currentTerm) {
        return true;
      }
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
