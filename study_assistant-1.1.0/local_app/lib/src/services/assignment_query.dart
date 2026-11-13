import 'package:lpinyin/lpinyin.dart';

import '../models/assignment.dart';
import '../models/home_filters.dart';

export '../models/home_filters.dart'
    show AssignmentDeadlineFilter, HomeSortOrder;

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

int _deadlineGroupRank(AssignmentDeadlineBucket bucket) => switch (bucket) {
      AssignmentDeadlineBucket.notExpiredWithDeadline => 0,
      AssignmentDeadlineBucket.confirmedNoDeadline => 1,
      AssignmentDeadlineBucket.unconfirmed => 2,
      AssignmentDeadlineBucket.overdue => 3,
      AssignmentDeadlineBucket.completed => 4,
    };

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
      : bucket = assignment.deadlineBucketAt(now),
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
              a.isFormal &&
              (followed.isEmpty || followed.contains(a.courseKey)))
          .toList();

  static bool _hasTrustedPendingDeadline(Assignment assignment) =>
      assignment.isPendingConfirmed &&
      !assignment.deadlineReadFailed &&
      assignment.deadlineTrusted;

  /// Lightweight home querying only. It does not reinterpret submission or
  /// deadline states; untrusted deadline rows remain discoverable.
  static List<Assignment> filterHome(
    List<Assignment> records, {
    String query = '',
    String? courseKey,
    AssignmentDeadlineFilter deadline = AssignmentDeadlineFilter.all,
    Set<String> followed = const {},
    required DateTime now,
  }) {
    final needle = query.trim().toLowerCase();
    return scope(records, followed).where((a) {
      if (a.isCompleted || (courseKey != null && a.courseKey != courseKey)) {
        return false;
      }
      if (needle.isNotEmpty &&
          !a.title.toLowerCase().contains(needle) &&
          !a.courseName.toLowerCase().contains(needle)) {
        return false;
      }
      final due = a.deadlineAt;
      final trusted = _hasTrustedPendingDeadline(a);
      final bucket = a.deadlineBucketAt(now);
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
        final group = _deadlineGroupRank(left.bucket)
            .compareTo(_deadlineGroupRank(right.bucket));
        if (group != 0) return group;
        if (left.bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
            left.bucket == AssignmentDeadlineBucket.overdue) {
          final deadline = left.assignment.deadlineAt!
              .compareTo(right.assignment.deadlineAt!);
          if (deadline != 0) {
            return order == HomeSortOrder.deadlineDesc ? -deadline : deadline;
          }
        }
        return left.compareNameKeys(right, HomeSortOrder.courseName);
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
    for (final a in scope(records, followed).where((a) => !a.isCompleted)) {
      switch (a.deadlineBucketAt(now)) {
        case AssignmentDeadlineBucket.completed:
          break;
        case AssignmentDeadlineBucket.unconfirmed:
          g.uncertain.add(a);
        case AssignmentDeadlineBucket.confirmedNoDeadline:
          g.noDeadline.add(a);
        case AssignmentDeadlineBucket.overdue:
          g.overdue.add(a);
        case AssignmentDeadlineBucket.notExpiredWithDeadline:
          final deadline = a.deadlineAt!;
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
      scope(records, followed).where((assignment) {
        final bucket = assignment.deadlineBucketAt(now);
        return (bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
                bucket == AssignmentDeadlineBucket.overdue) &&
            dayKey(assignment.deadlineAt!) ==
                DateTime(day.year, day.month, day.day);
      }).toList()
        ..sort(Assignment.compareByDeadline);
}
