import 'package:lpinyin/lpinyin.dart';

import '../models/assignment.dart';
import '../models/home_filters.dart';

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
  _PreparedAssignment(this.assignment, this.index, DateTime now)
      : bucket = AssignmentQuery.timelineBucketAt(assignment, now),
        course = _NaturalKey(assignment.courseName),
        title = _NaturalKey(assignment.title),
        courseKey = _NaturalKey(assignment.courseKey ?? ''),
        id = _NaturalKey(assignment.id);

  final Assignment assignment;
  final int index;
  final AssignmentDeadlineBucket bucket;
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
}

class HomeAssignmentGroups {
  final near = <Assignment>[],
      far = <Assignment>[],
      overdue = <Assignment>[],
      uncertain = <Assignment>[],
      noDeadline = <Assignment>[];
}

class AssignmentQuery {
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
      Assignment representative, List<Assignment> records) {
    final key = examDisplayKey(representative);
    return key == null
        ? [representative]
        : records.where((a) => examDisplayKey(a) == key).toList();
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
        location: locations.length == 1 ? locations.single : '',
        durationMinutes: durations.length == 1 ? durations.single : null,
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
    final canSupplementTime = !conflict && !contradictsFormal;
    var start = e.startAt ?? (canSupplementTime ? uniqueStart : null);
    var end = e.endAt ?? (canSupplementTime ? uniqueEnd : null);
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
      location: e.location.isEmpty && locations.length == 1
          ? locations.single
          : e.location,
      durationMinutes: e.durationMinutes ??
          (durations.length == 1 ? durations.single : null),
    ));
  }

  /// Select a real record, preserving its original ID and submission state.
  /// A formal exam wins over its notices, including when it is submitted.
  static List<Assignment> projectDisplay(List<Assignment> records) {
    final representatives = <String, Assignment>{};
    final sources = <String, List<Assignment>>{};
    for (final a in records) {
      final key = examDisplayKey(a);
      if (key == null) continue;
      sources.putIfAbsent(key, () => []).add(a);
      final previous = representatives[key];
      if (previous == null ||
          (previous.exam!.noticeOnly && !a.exam!.noticeOnly) ||
          (previous.exam!.noticeOnly == a.exam!.noticeOnly &&
              a.id.compareTo(previous.id) < 0)) {
        representatives[key] = a;
      }
    }
    final emitted = <String>{};
    return [
      for (final a in records)
        if (examDisplayKey(a) case final key?) ...[
          if (emitted.add(key))
            _supplementDisplay(representatives[key]!, sources[key]!),
        ] else
          a
    ];
  }

  static bool isExamEnded(Assignment a, DateTime now) {
    if (!a.isExam) return false;
    final e = a.exam!;
    return e.lifecycle == 'ended' ||
        e.lifecycle == 'cancelled' ||
        (e.endTrusted && e.endAt != null && !e.endAt!.isAfter(now));
  }

  static List<Assignment> currentDisplay(
          List<Assignment> records, DateTime now) =>
      projectDisplay(records)
          .where((a) => !a.isCompleted && !isExamEnded(a, now))
          .toList();

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
        AssignmentTypeFilter.homework => assignment.isFormal,
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

  /// Lightweight home querying only. It does not reinterpret submission or
  /// deadline states; untrusted deadline rows remain discoverable.
  static List<Assignment> filterHome(
    List<Assignment> records, {
    String query = '',
    String? courseKey,
    AssignmentDeadlineFilter deadline = AssignmentDeadlineFilter.all,
    AssignmentTypeFilter type = AssignmentTypeFilter.all,
    Set<String> followed = const {},
    required DateTime now,
  }) {
    final needle = query.trim().toLowerCase();
    return currentDisplay(scope(records, followed), now).where((a) {
      if (a.isCompleted ||
          !matchesType(a, type) ||
          (courseKey != null && a.courseKey != courseKey)) {
        return false;
      }
      if (needle.isNotEmpty &&
          !a.title.toLowerCase().contains(needle) &&
          !a.courseName.toLowerCase().contains(needle)) {
        return false;
      }
      final due = a.timelineAt;
      final bucket = timelineBucketAt(a, now);
      final trusted = _hasTrustedPendingDeadline(a) &&
          (!a.isExam ||
              bucket == AssignmentDeadlineBucket.notExpiredWithDeadline);
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
        AssignmentDeadlineFilter.notExpired =>
          bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
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
  }) {
    if (order == HomeSortOrder.grouped) {
      return List<Assignment>.of(records);
    }
    final prepared = [
      for (var index = 0; index < records.length; index++)
        _PreparedAssignment(records[index], index, now),
    ];
    prepared.sort((left, right) {
      if (order == HomeSortOrder.deadlineAsc ||
          order == HomeSortOrder.deadlineDesc) {
        final leftTime = left.assignment.timelineTrusted &&
                (left.assignment.isExam || !left.assignment.deadlineReadFailed)
            ? left.assignment.timelineAt
            : null;
        final rightTime = right.assignment.timelineTrusted &&
                (right.assignment.isExam ||
                    !right.assignment.deadlineReadFailed)
            ? right.assignment.timelineAt
            : null;
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
        final l = (left.assignment.timelineTrusted &&
                (left.assignment.isExam || !left.assignment.deadlineReadFailed))
            ? left.assignment.timelineAt
            : null;
        final r = right.assignment.timelineTrusted &&
                (right.assignment.isExam ||
                    !right.assignment.deadlineReadFailed)
            ? right.assignment.timelineAt
            : null;
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
