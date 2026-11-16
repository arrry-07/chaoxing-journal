import 'package:lpinyin/lpinyin.dart';

import '../models/assignment.dart';
import '../models/home_filters.dart';
import 'exam_wall_time.dart';

export '../models/home_filters.dart'
    show AssignmentDeadlineFilter, AssignmentTypeFilter, HomeSortOrder;

class _NaturalKey {
  _NaturalKey(String value)
      : raw = value.trim(),
        folded = _fold(value);

  final String raw;
  final String folded;

  static String _fold(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return PinyinHelper.getPinyinE(
      trimmed,
      separator: '',
      defPinyin: '#',
      format: PinyinFormat.WITHOUT_TONE,
    ).toLowerCase();
  }
}

int _compareNatural(String left, String right) {
  final a = left.runes.toList(growable: false);
  final b = right.runes.toList(growable: false);
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final aDigit = a[i] >= 0x30 && a[i] <= 0x39;
    final bDigit = b[j] >= 0x30 && b[j] <= 0x39;
    if (aDigit && bDigit) {
      final aStart = i;
      final bStart = j;
      while (i < a.length && a[i] >= 0x30 && a[i] <= 0x39) {
        i++;
      }
      while (j < b.length && b[j] >= 0x30 && b[j] <= 0x39) {
        j++;
      }
      final aRun = a.sublist(aStart, i);
      final bRun = b.sublist(bStart, j);
      var aSignificant = 0;
      while (aSignificant + 1 < aRun.length && aRun[aSignificant] == 0x30) {
        aSignificant++;
      }
      var bSignificant = 0;
      while (bSignificant + 1 < bRun.length && bRun[bSignificant] == 0x30) {
        bSignificant++;
      }
      final aLength = aRun.length - aSignificant;
      final bLength = bRun.length - bSignificant;
      if (aLength != bLength) return aLength.compareTo(bLength);
      for (var offset = 0; offset < aLength; offset++) {
        final comparison =
            aRun[aSignificant + offset].compareTo(bRun[bSignificant + offset]);
        if (comparison != 0) return comparison;
      }
      if (aRun.length != bRun.length) {
        return aRun.length.compareTo(bRun.length);
      }
      continue;
    }
    if (a[i] != b[j]) return a[i].compareTo(b[j]);
    i++;
    j++;
  }
  return (a.length - i).compareTo(b.length - j);
}

int _compareKey(_NaturalKey left, _NaturalKey right) {
  final folded = _compareNatural(left.folded, right.folded);
  if (folded != 0) return folded;
  return _compareNatural(left.raw, right.raw);
}

int _nameGroupRank(AssignmentDeadlineBucket bucket) => switch (bucket) {
      AssignmentDeadlineBucket.notExpiredWithDeadline ||
      AssignmentDeadlineBucket.confirmedNoDeadline =>
        0,
      AssignmentDeadlineBucket.unconfirmed => 1,
      AssignmentDeadlineBucket.overdue => 2,
      AssignmentDeadlineBucket.completed => 3,
    };

class _PreparedAssignment {
  _PreparedAssignment(this.assignment, this.index, DateTime now, this.displayAt)
      : bucket = AssignmentQuery.timelineBucketAt(assignment, now),
        ended =
            assignment.isExam && AssignmentQuery.isExamEnded(assignment, now),
        course = _NaturalKey(assignment.courseName),
        title = _NaturalKey(assignment.title),
        courseKey = _NaturalKey(assignment.courseKey ?? ''),
        id = _NaturalKey(assignment.id);

  final Assignment assignment;
  final int index;
  final AssignmentDeadlineBucket bucket;
  final DateTime? displayAt;
  final bool ended;
  final _NaturalKey course;
  final _NaturalKey title;
  final _NaturalKey courseKey;
  final _NaturalKey id;

  int compareNameKeys(_PreparedAssignment other, HomeSortOrder order) {
    final name = order == HomeSortOrder.courseName
        ? _compareKey(course, other.course)
        : _compareKey(title, other.title);
    if (name != 0) return name;
    final secondary = order == HomeSortOrder.courseName
        ? _compareKey(title, other.title)
        : _compareKey(course, other.course);
    if (secondary != 0) return secondary;
    final key = _compareKey(courseKey, other.courseKey);
    if (key != 0) return key;
    final assignmentId = _compareKey(id, other.id);
    if (assignmentId != 0) return assignmentId;
    return index.compareTo(other.index);
  }

  /// The home timeline keeps actionable, undated, and historical records ahead
  /// of overdue work. An overdue date being earlier must never put it first.
  int get homeTier {
    if (bucket == AssignmentDeadlineBucket.overdue) return 2;
    if (bucket == AssignmentDeadlineBucket.completed || ended) return 1;
    if (bucket == AssignmentDeadlineBucket.confirmedNoDeadline) return 1;
    if (bucket == AssignmentDeadlineBucket.notExpiredWithDeadline) return 0;
    // A display-only exam projection is valid timeline evidence for ordering,
    // without promoting its start time or calendar trust in the model. Course
    // work with unknown submission state remains in the undated middle tier.
    if (assignment.isExam && displayAt != null) return 0;
    return 1;
  }
}

class HomeAssignmentGroups {
  final near = <Assignment>[],
      far = <Assignment>[],
      overdue = <Assignment>[],
      uncertain = <Assignment>[],
      noDeadline = <Assignment>[];
}

class _DisplayProjection {
  _DisplayProjection(List<Assignment> records) {
    for (final assignment in records) {
      final key = AssignmentQuery.examDisplayKey(assignment);
      if (key == null) continue;
      (sourcesByKey[key] ??= []).add(assignment);
      final previous = representatives[key];
      if (previous == null ||
          (previous.exam!.noticeOnly && !assignment.exam!.noticeOnly) ||
          (previous.exam!.noticeOnly == assignment.exam!.noticeOnly &&
              assignment.id.compareTo(previous.id) < 0)) {
        representatives[key] = assignment;
      }
    }
    final emitted = <String>{};
    for (final assignment in records) {
      final key = AssignmentQuery.examDisplayKey(assignment);
      if (key == null) {
        projected.add(assignment);
      } else if (emitted.add(key)) {
        projected.add(AssignmentQuery._supplementDisplay(
            representatives[key]!, sourcesByKey[key]!));
      }
    }
  }

  final Map<String, List<Assignment>> sourcesByKey = {};
  final Map<String, Assignment> representatives = {};
  final List<Assignment> projected = [];
}

/// Immutable display index for one record source snapshot. It contains only
/// data-derived projections and parsed notice ranges; time-dependent filtering,
/// sorting and calendar decisions are recomputed by the caller.
class AssignmentDisplayIndex {
  AssignmentDisplayIndex.from(List<Assignment> records)
      : _origin = records,
        sources = List<Assignment>.unmodifiable(records) {
    final projection = _DisplayProjection(records);
    projected = List<Assignment>.unmodifiable(projection.projected);
    for (final entry in projection.sourcesByKey.entries) {
      sourcesByKey[entry.key] = List<Assignment>.unmodifiable(entry.value);
    }
  }

  final List<Assignment> sources;
  final List<Assignment> _origin;
  final Map<String, List<Assignment>> sourcesByKey = {};
  late final List<Assignment> projected;
  final Map<String, ExamNoticeRange?> _rangesByText = {};
  int _noticeRangeReadCount = 0;
  int get noticeRangeReadCount => _noticeRangeReadCount;

  bool matches(List<Assignment> records) => identical(_origin, records);

  List<Assignment> sourcesFor(Assignment representative, String key) =>
      sourcesByKey[key] ?? [representative];

  ExamNoticeRange? readNoticeRange(String raw) {
    if (_rangesByText.containsKey(raw)) return _rangesByText[raw];
    _noticeRangeReadCount++;
    final value = ExamNoticeRange.read(raw);
    _rangesByText[raw] = value;
    return value;
  }
}

class AssignmentQuery {
  static Expando<_DisplayProjection> _displayProjections =
      Expando<_DisplayProjection>();
  static int _projectionBuildCount = 0;
  static int _noticeRangeReadCount = 0;

  static int get debugProjectionBuildCount => _projectionBuildCount;
  static int get debugNoticeRangeReadCount => _noticeRangeReadCount;

  static void debugResetDisplayCaches() {
    _displayProjections = Expando<_DisplayProjection>();
    _projectionBuildCount = 0;
    _noticeRangeReadCount = 0;
  }

  static _DisplayProjection _displayProjectionFor(List<Assignment> records) {
    final cached = _displayProjections[records];
    if (cached != null) return cached;
    _projectionBuildCount++;
    final created = _DisplayProjection(records);
    _displayProjections[records] = created;
    return created;
  }

  static ExamNoticeRange? _cachedNoticeRange(String raw) {
    _noticeRangeReadCount++;
    return ExamNoticeRange.read(raw);
  }

  static DateTime beijing(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 8));
  static DateTime dayKey(DateTime instant) {
    final d = beijing(instant);
    return DateTime(d.year, d.month, d.day);
  }

  // An empty followed set means all courses; exclusions are applied by the store.
  static List<Assignment> scope(
          List<Assignment> records, Set<String> followed) =>
      records
          .where((a) =>
              a.isInAssignmentScope &&
              (followed.isEmpty ||
                  (a.isExam && a.courseKey == null) ||
                  followed.contains(a.courseKey)))
          .toList();

  /// Display-only identity. Never use this projection for persistence/statistics.
  static String? examDisplayKey(Assignment a) {
    if (!a.hasExamIdentity) return null;
    final e = a.exam!;
    final course = e.courseId, clazz = e.clazzId;
    final exam = e.noticeOnly ? e.relatedExamId : e.examId;
    bool valid(String? v) => v != null && RegExp(r'^[0-9]+$').hasMatch(v);
    if (!valid(course) || !valid(clazz) || !valid(exam)) return null;
    return '$course:$clazz:$exam';
  }

  /// All original source IDs remain available for details/archive integration.
  static List<Assignment> displaySources(
    Assignment representative,
    List<Assignment> records, {
    AssignmentDisplayIndex? index,
  }) {
    final key = examDisplayKey(representative);
    if (key == null) return [representative];
    if (index != null && index.matches(records)) {
      return List<Assignment>.of(index.sourcesFor(representative, key));
    }
    final cached = _displayProjectionFor(records).sourcesByKey[key];
    return cached == null ? [representative] : List<Assignment>.of(cached);
  }

  /// Resolve one unambiguous wall-time range from an exam's linked notices.
  /// This is display evidence only and is never promoted into exam trust.
  static List<ExamNoticeRange> displayNoticeRanges(
    Assignment assignment, {
    List<Assignment> records = const [],
    AssignmentDisplayIndex? index,
  }) {
    final exam = assignment.exam;
    if (exam == null) return const [];
    final sources = displaySources(assignment, records, index: index);
    if (exam.noticeOnly &&
        !sources.any((source) => source.id == assignment.id)) {
      sources.add(assignment);
    }
    final durations = sources
        .where((source) => source.exam?.noticeOnly == true)
        .map((source) => source.exam!.durationMinutes)
        .whereType<int>()
        .toSet();
    if (durations.length > 1) return const [];
    final ranges = <String, ExamNoticeRange>{};
    for (final source
        in sources.where((item) => item.exam?.noticeOnly == true)) {
      final range = index != null && index.matches(records)
          ? index.readNoticeRange(source.requirementsText)
          : _cachedNoticeRange(source.requirementsText);
      if (range == null) continue;
      if ((exam.startTrusted &&
              exam.startAt != null &&
              range.start != null &&
              !range.start!.matches(exam.startAt!)) ||
          (exam.endTrusted &&
              exam.endAt != null &&
              range.end != null &&
              !range.end!.matches(exam.endAt!))) {
        continue;
      }
      final prior = ranges[range.key];
      if (prior == null || range.precision > prior.precision) {
        ranges[range.key] = range;
      }
    }
    return ranges.values.toList();
  }

  static ExamNoticeRange? displayNoticeRange(
    Assignment assignment, {
    List<Assignment> records = const [],
    AssignmentDisplayIndex? index,
  }) {
    final ranges =
        displayNoticeRanges(assignment, records: records, index: index);
    return ranges.length == 1 ? ranges.single : null;
  }

  /// A display-only opening time used to mix exams and coursework in list
  /// order. Yearless notices use the current Beijing year without promoting
  /// trust, writing a timestamp, or scheduling a reminder.
  static DateTime? displayTimelineAt(
    Assignment assignment, {
    List<Assignment> records = const [],
    AssignmentDisplayIndex? index,
    required DateTime now,
  }) {
    if (!assignment.isExam) {
      return assignment.timelineTrusted && !assignment.deadlineReadFailed
          ? assignment.timelineAt
          : null;
    }
    final exam = assignment.exam!;
    if (exam.startTrusted && exam.startAt != null) return exam.startAt;
    final range =
        displayNoticeRange(assignment, records: records, index: index);
    return range?.start?.projectedAt(beijing(now).year);
  }

  static DateTime? displayTimelineEndAt(
    Assignment assignment, {
    List<Assignment> records = const [],
    AssignmentDisplayIndex? index,
    required DateTime now,
  }) {
    if (!assignment.isExam) {
      return assignment.timelineTrusted && !assignment.deadlineReadFailed
          ? assignment.timelineAt
          : null;
    }
    final exam = assignment.exam!;
    if (exam.endTrusted && exam.endAt != null) return exam.endAt;
    final range =
        displayNoticeRange(assignment, records: records, index: index);
    final noticeEnd = range?.end?.projectedAt(beijing(now).year);
    if (noticeEnd != null) return noticeEnd;
    final start =
        displayTimelineAt(assignment, records: records, index: index, now: now);
    final duration = exam.durationMinutes;
    return start != null && duration != null && duration > 0
        ? start.add(Duration(minutes: duration))
        : null;
  }

  static Assignment _supplementDisplay(
      Assignment primary, List<Assignment> sources) {
    if (!primary.isExam || sources.length < 2) return primary;
    final e = primary.exam!;
    final notices =
        sources.where((a) => a.exam!.noticeOnly).map((a) => a.exam!).toList();
    if (notices.isEmpty) return primary;
    final starts = notices
        .where((n) => n.startTrusted && n.startAt != null)
        .map((n) => n.startAt!.toUtc())
        .toSet();
    final ends = notices
        .where((n) => n.endTrusted && n.endAt != null)
        .map((n) => n.endAt!.toUtc())
        .toSet();
    final states =
        notices.map((n) => n.lifecycle).where((v) => v != 'unknown').toSet();
    final locations = notices
        .map((n) => n.location.trim())
        .where((v) => v.isNotEmpty)
        .toSet();
    final durations =
        notices.map((n) => n.durationMinutes).whereType<int>().toSet();
    final uniqueStart = starts.length == 1 ? starts.single : null;
    final uniqueEnd = ends.length == 1 ? ends.single : null;
    final conflict = starts.length > 1 ||
        ends.length > 1 ||
        states.length > 1 ||
        (uniqueStart != null &&
            uniqueEnd != null &&
            uniqueEnd.isBefore(uniqueStart));
    // Sync time and hashed resource IDs say nothing about publication order.
    // Conflicting notices remain discoverable but cannot retire an exam.
    if (e.noticeOnly && conflict) {
      return primary.copyWith(
          exam: ExamInfo(
        examId: e.examId,
        relatedExamId: e.relatedExamId,
        courseId: e.courseId,
        clazzId: e.clazzId,
        startAt: e.startAt,
        endAt: e.endAt,
        startTrusted: false,
        endTrusted: false,
        lifecycle: 'unknown',
        noticeOnly: true,
        location: '',
        durationMinutes: null,
      ));
    }
    final contradictsFormal = !e.noticeOnly &&
        ((e.startTrusted &&
                e.startAt != null &&
                starts.any((v) => v != e.startAt!.toUtc())) ||
            (e.endTrusted &&
                e.endAt != null &&
                ends.any((v) => v != e.endAt!.toUtc())) ||
            (e.lifecycle != 'unknown' && states.any((v) => v != e.lifecycle)));
    final canSupplement = !conflict && !contradictsFormal;
    var start = e.startAt ?? (canSupplement ? uniqueStart : null);
    var end = e.endAt ?? (canSupplement ? uniqueEnd : null);
    if (start != null && end != null && end.isBefore(start)) {
      start = e.startAt;
      end = e.endAt;
    }
    return primary.copyWith(
        exam: ExamInfo(
      examId: e.examId, relatedExamId: e.relatedExamId,
      courseId: e.courseId, clazzId: e.clazzId,
      startAt: start, endAt: end,
      startTrusted: e.startAt != null ? e.startTrusted : start != null,
      endTrusted: e.endAt != null ? e.endTrusted : end != null,
      // A notice cannot resolve an unknown formal lifecycle without chronology.
      lifecycle: e.lifecycle, noticeOnly: e.noticeOnly,
      location: canSupplement && e.location.isEmpty && locations.length == 1
          ? locations.single
          : e.location,
      durationMinutes: e.durationMinutes ??
          (canSupplement && durations.length == 1 ? durations.single : null),
    ));
  }

  /// Select a real record, preserving its original ID and submission state.
  /// A formal exam wins over its notices, including when it is submitted.
  static List<Assignment> projectDisplay(
    List<Assignment> records, {
    AssignmentDisplayIndex? index,
  }) {
    final source = index != null && index.matches(records)
        ? index.projected
        : _displayProjectionFor(records).projected;
    return List<Assignment>.of(source);
  }

  static bool isExamEnded(Assignment a, DateTime now) {
    if (!a.isExam) return false;
    final e = a.exam!;
    return e.lifecycle == 'ended' ||
        e.lifecycle == 'cancelled' ||
        (e.endTrusted && e.endAt != null && !e.endAt!.isAfter(now));
  }

  static List<Assignment> currentDisplay(
    List<Assignment> records,
    DateTime now, {
    AssignmentDisplayIndex? index,
  }) =>
      projectDisplay(records, index: index)
          .where((a) =>
              !a.isCompleted &&
              !isExamEnded(a, now) &&
              !isArchivedClassroomPractice(a, now))
          .toList();

  /// A trusted, elapsed classroom deadline with no confirmed submission is a
  /// local historical observation, not a current task to reconcile. Formal
  /// coursework and untrusted/yearless times stay in the current scope.
  static bool isArchivedClassroomPractice(Assignment assignment, DateTime now) {
    final deadline = assignment.deadlineAt;
    return assignment.isSupportedClassroomTask &&
        assignment.status == 'unknown' &&
        assignment.deadlineTrusted &&
        !assignment.deadlineReadFailed &&
        deadline != null &&
        !deadline.isAfter(now);
  }

  static bool isUnknownExam(Assignment a, DateTime now) =>
      a.isExam &&
      !a.isCompleted &&
      !isExamEnded(a, now) &&
      (!a.timelineTrusted || a.timelineAt == null);

  static List<Assignment> calendarDisplay(
          List<Assignment> records, DateTime now) =>
      projectDisplay(records).where((a) => isCalendarDated(a, now)).toList();

  static bool _hasTrustedPendingDeadline(Assignment assignment) =>
      assignment.isPendingConfirmed &&
      assignment.timelineTrusted &&
      (assignment.isExam || !assignment.deadlineReadFailed);

  /// Exams are placed by their opening time. An exam ending is not evidence
  /// that this student submitted it, nor does opening make it overdue.
  static AssignmentDeadlineBucket timelineBucketAt(
      Assignment assignment, DateTime now) {
    if (!assignment.isExam) return assignment.deadlineBucketAt(now);
    if (assignment.isCompleted) return AssignmentDeadlineBucket.completed;
    final exam = assignment.exam;
    if (exam == null ||
        !assignment.timelineTrusted ||
        assignment.timelineAt == null ||
        !assignment.isPendingConfirmed ||
        exam.lifecycle == 'ended' ||
        exam.lifecycle == 'cancelled' ||
        (exam.endTrusted && exam.endAt != null && !exam.endAt!.isAfter(now))) {
      return AssignmentDeadlineBucket.unconfirmed;
    }
    return AssignmentDeadlineBucket.notExpiredWithDeadline;
  }

  static bool matchesType(Assignment assignment, AssignmentTypeFilter type) =>
      switch (type) {
        AssignmentTypeFilter.all => true,
        AssignmentTypeFilter.homework =>
          assignment.isFormal || assignment.isSupportedClassroomTask,
        AssignmentTypeFilter.task => assignment.isSupportedClassroomTask,
        AssignmentTypeFilter.exam => assignment.isExam,
        AssignmentTypeFilter.examNotice =>
          assignment.isExam && assignment.exam?.noticeOnly == true,
      };

  static bool isCalendarDated(Assignment assignment, DateTime now) {
    if ((!assignment.isExam && assignment.isCompleted) ||
        !assignment.timelineTrusted ||
        assignment.timelineAt == null) {
      return false;
    }
    if (assignment.isExam) {
      final pastDay = dayKey(assignment.timelineAt!).isBefore(dayKey(now));
      return (!assignment.isCompleted && !isExamEnded(assignment, now)) ||
          pastDay;
    }
    final bucket = assignment.deadlineBucketAt(now);
    return bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
        bucket == AssignmentDeadlineBucket.overdue;
  }

  static bool _displayExamNotExpired(
    Assignment assignment,
    List<Assignment> sources,
    DateTime now, {
    AssignmentDisplayIndex? index,
  }) {
    if (displayTimelineAt(assignment,
            records: sources, index: index, now: now) ==
        null) {
      return false;
    }
    final end = displayTimelineEndAt(assignment,
        records: sources, index: index, now: now);
    return end == null || end.isAfter(now);
  }

  /// Lightweight home querying only. It does not reinterpret submission or
  /// deadline states; untrusted deadline rows remain discoverable.
  static List<Assignment> filterHome(
    List<Assignment> records, {
    String query = '',
    String? courseKey,
    AssignmentDeadlineFilter deadline = AssignmentDeadlineFilter.all,
    AssignmentTypeFilter type = AssignmentTypeFilter.all,
    bool includeHistorical = false,
    Set<String> followed = const {},
    AssignmentDisplayIndex? index,
    required DateTime now,
  }) {
    final needle = query.trim().toLowerCase();
    final sourceRecords =
        index != null && index.matches(records) && followed.isEmpty
            ? records
            : scope(records, followed);
    return projectDisplay(sourceRecords, index: index).where((a) {
      if (isArchivedClassroomPractice(a, now)) return false;
      final historical = a.isCompleted || (a.isExam && isExamEnded(a, now));
      if ((!includeHistorical && historical) ||
          !matchesType(a, type) ||
          (courseKey != null && a.courseKey != courseKey)) {
        return false;
      }
      if (needle.isNotEmpty &&
          !a.title.toLowerCase().contains(needle) &&
          !a.courseName.toLowerCase().contains(needle)) {
        return false;
      }
      final due =
          displayTimelineAt(a, records: sourceRecords, index: index, now: now);
      final bucket = timelineBucketAt(a, now);
      final trusted =
          a.isExam ? !historical && due != null : _hasTrustedPendingDeadline(a);
      return switch (deadline) {
        AssignmentDeadlineFilter.all => true,
        AssignmentDeadlineFilter.next7Days => trusted &&
            due != null &&
            due.isAfter(now) &&
            !due.isAfter(now.add(const Duration(days: 7))),
        AssignmentDeadlineFilter.next30Days => trusted &&
            due != null &&
            due.isAfter(now) &&
            !due.isAfter(now.add(const Duration(days: 30))),
        AssignmentDeadlineFilter.overdue =>
          bucket == AssignmentDeadlineBucket.overdue,
        AssignmentDeadlineFilter.uncertain =>
          bucket == AssignmentDeadlineBucket.unconfirmed,
        AssignmentDeadlineFilter.noDeadline =>
          bucket == AssignmentDeadlineBucket.confirmedNoDeadline,
        AssignmentDeadlineFilter.notExpired => historical
            ? false
            : a.isExam
                ? _displayExamNotExpired(a, sourceRecords, now, index: index)
                : bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
                    bucket == AssignmentDeadlineBucket.confirmedNoDeadline,
      };
    }).toList();
  }

  /// Recommendation is independent of the user's chronological list order.
  static Assignment? nextActionable(List<Assignment> records,
      {required DateTime now}) {
    final eligible = currentDisplay(scope(records, {}), now)
        .where((a) =>
            a.isPendingConfirmed &&
            a.timelineTrusted &&
            (a.isExam || !a.deadlineReadFailed) &&
            a.timelineAt != null &&
            a.timelineAt!.isAfter(now))
        .toList();
    return sortHome(eligible, HomeSortOrder.deadlineAsc, now: now).firstOrNull;
  }

  static List<Assignment> sortHome(
    List<Assignment> records,
    HomeSortOrder order, {
    required DateTime now,
    List<Assignment> sourceRecords = const [],
    AssignmentDisplayIndex? displayIndex,
  }) {
    if (order == HomeSortOrder.grouped) {
      return List<Assignment>.of(records);
    }
    final sources = sourceRecords.isEmpty ? records : sourceRecords;
    final prepared = [
      for (var index = 0; index < records.length; index++)
        _PreparedAssignment(
          records[index],
          index,
          now,
          displayTimelineAt(records[index],
              records: sources, index: displayIndex, now: now),
        ),
    ];
    prepared.sort((left, right) {
      if (order == HomeSortOrder.deadlineAsc ||
          order == HomeSortOrder.deadlineDesc) {
        final tier = left.homeTier.compareTo(right.homeTier);
        if (tier != 0) return tier;
        if (left.homeTier == 1) {
          return left.compareNameKeys(right, HomeSortOrder.courseName);
        }
        final leftTime = left.displayAt;
        final rightTime = right.displayAt;
        if (leftTime == null && rightTime != null) return 1;
        if (rightTime == null && leftTime != null) return -1;
        if (leftTime != null && rightTime != null) {
          final time = leftTime.compareTo(rightTime);
          if (time != 0) {
            return order == HomeSortOrder.deadlineDesc ? -time : time;
          }
        }
        return left.compareNameKeys(right, HomeSortOrder.courseName);
      }
      if (order == HomeSortOrder.courseName) {
        final course = _compareKey(left.course, right.course);
        if (course != 0) return course;
        final l = left.displayAt;
        final r = right.displayAt;
        if (l == null && r != null) return 1;
        if (r == null && l != null) return -1;
        if (l != null && r != null && l != r) return l.compareTo(r);
        return left.compareNameKeys(right, order);
      }
      final group =
          _nameGroupRank(left.bucket).compareTo(_nameGroupRank(right.bucket));
      if (group != 0) return group;
      return left.compareNameKeys(right, order);
    });
    return [for (final entry in prepared) entry.assignment];
  }

  static HomeAssignmentGroups home(
      List<Assignment> records, DateTime now, Set<String> followed) {
    final g = HomeAssignmentGroups();
    for (final a in currentDisplay(scope(records, followed), now)) {
      switch (timelineBucketAt(a, now)) {
        case AssignmentDeadlineBucket.completed:
          break;
        case AssignmentDeadlineBucket.unconfirmed:
          g.uncertain.add(a);
        case AssignmentDeadlineBucket.confirmedNoDeadline:
          g.noDeadline.add(a);
        case AssignmentDeadlineBucket.overdue:
          g.overdue.add(a);
        case AssignmentDeadlineBucket.notExpiredWithDeadline:
          final deadline = a.timelineAt!;
          if (deadline.isAfter(now.add(const Duration(days: 30)))) {
            g.far.add(a);
          } else {
            g.near.add(a);
          }
      }
    }
    for (final list in [g.near, g.far]) {
      final sorted = sortHome(list, HomeSortOrder.deadlineAsc, now: now);
      list
        ..clear()
        ..addAll(sorted);
    }
    for (final list in [g.uncertain, g.noDeadline]) {
      final sorted = sortHome(list, HomeSortOrder.courseName, now: now);
      list
        ..clear()
        ..addAll(sorted);
    }
    final sortedOverdue =
        sortHome(g.overdue, HomeSortOrder.deadlineDesc, now: now);
    g.overdue
      ..clear()
      ..addAll(sortedOverdue);
    return g;
  }

  static List<Assignment> forDay(
    List<Assignment> records,
    DateTime day,
    Set<String> followed, {
    required DateTime now,
  }) =>
      projectDisplay(scope(records, followed)).where((assignment) {
        return isCalendarDated(assignment, now) &&
            dayKey(assignment.timelineAt!) ==
                DateTime(day.year, day.month, day.day);
      }).toList()
        ..sort((a, b) {
          final time = a.timelineAt!.compareTo(b.timelineAt!);
          return time != 0 ? time : Assignment.compareByDeadline(a, b);
        });
}
