import 'package:flutter/foundation.dart';

import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import '../models/study_notebook.dart';
import 'assignment_query.dart';
import 'assignment_grouping.dart';

/// One home-timeline row, either a Chaoxing assignment or a local manual entry.
///
/// Manual entries deliberately stay outside assignment storage, statistics and
/// submission state. This projection is the only place where both sources are
/// mixed for display.
@immutable
class HomeTimelineItem {
  const HomeTimelineItem._({
    this.assignment,
    this.manual,
    this.preparedDisplayAt,
    this.preparedEndAt,
    this.sortIndex = 0,
    this.treatAsActiveForSorting = false,
  });

  factory HomeTimelineItem.assignment(Assignment assignment) =>
      HomeTimelineItem._(assignment: assignment);

  factory HomeTimelineItem.manual(ManualEntry entry) =>
      HomeTimelineItem._(manual: entry);

  final Assignment? assignment;
  final ManualEntry? manual;
  final DateTime? preparedDisplayAt;
  final DateTime? preparedEndAt;
  final int sortIndex;
  final bool treatAsActiveForSorting;

  bool get isManual => manual != null;
  bool get isExam => assignment?.isExam ?? manual?.kind == ManualEntry.kindExam;
  String get itemId => assignment?.id ?? manual!.pinKey;
  String get pinKey => assignment == null
      ? manual!.pinKey
      : AssignmentGrouping.examKey(assignment!) ??
          assignment!.courseTaskKey ??
          assignment!.id;
  String get title => assignment?.title ?? manual!.title;
  String get courseKey => assignment?.courseKey ?? '';
  String get displayCourse {
    final raw = assignment?.courseName ?? manual!.course;
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty || !isManual) return trimmed;
    if (!isExam) return '待办';
    return '考试';
  }

  /// Manual entries use their stored instant; Chaoxing records only use the
  /// trusted display projection, never the raw untrusted deadline.
  DateTime? get displayAt => isManual ? manual!.at : preparedDisplayAt;

  AssignmentDeadlineBucket bucketAt(
    DateTime now, {
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) =>
      assignment == null
          ? HomeManualTimeline.manualBucketAt(
              treatAsActiveForSorting && manual!.done
                  ? manual!.completed(false)
                  : manual!,
              now,
            )
          : AssignmentQuery.timelineBucketAt(
              assignment!,
              now,
              coursework: coursework,
            );
}

class HomeManualTimeline {
  const HomeManualTimeline._();

  static AssignmentDeadlineBucket manualBucketAt(
    ManualEntry entry,
    DateTime now,
  ) {
    if (entry.done) return AssignmentDeadlineBucket.completed;
    final at = entry.at;
    if (at == null) return AssignmentDeadlineBucket.confirmedNoDeadline;
    return at.isAfter(now)
        ? AssignmentDeadlineBucket.notExpiredWithDeadline
        : AssignmentDeadlineBucket.overdue;
  }

  static List<ManualEntry> filterManualEntries(
    List<ManualEntry> entries, {
    String query = '',
    String? selectedCourseName,
    AssignmentDeadlineFilter deadline = AssignmentDeadlineFilter.all,
    AssignmentTypeFilter type = AssignmentTypeFilter.all,
    Set<String> keepVisibleIds = const {},
    required DateTime now,
  }) {
    final needle = query.trim().toLowerCase();
    final course = selectedCourseName?.trim().toLowerCase();
    return [
      for (final entry in entries)
        if ((!entry.done || keepVisibleIds.contains(entry.id)) &&
            _matchesType(entry, type) &&
            (course == null ||
                course.isEmpty ||
                entry.course.trim().toLowerCase() == course) &&
            (needle.isEmpty ||
                entry.title.toLowerCase().contains(needle) ||
                entry.course.toLowerCase().contains(needle) ||
                entry.location.toLowerCase().contains(needle)) &&
            _matchesDeadline(
              entry.done && keepVisibleIds.contains(entry.id)
                  ? entry.completed(false)
                  : entry,
              deadline,
              now,
            ))
          entry,
    ];
  }

  static List<HomeTimelineItem> mergeAndSort({
    required List<Assignment> assignments,
    required List<ManualEntry> manualEntries,
    required HomeSortOrder order,
    required DateTime now,
    List<Assignment> sourceRecords = const [],
    AssignmentDisplayIndex? displayIndex,
    bool prioritizeStartOnly = true,
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
    Set<String> keepVisibleIds = const {},
  }) {
    final sources = sourceRecords.isEmpty ? assignments : sourceRecords;
    final items = <HomeTimelineItem>[
      for (var index = 0; index < assignments.length; index++)
        HomeTimelineItem._(
          assignment: assignments[index],
          sortIndex: index,
          preparedDisplayAt: AssignmentQuery.displayTimelineAt(
            assignments[index],
            records: sources,
            index: displayIndex,
            now: now,
            coursework: coursework,
          ),
          preparedEndAt: assignments[index].exam?.startTrusted == false &&
                  assignments[index].exam?.endTrusted == false
              ? AssignmentQuery.displayTimelineEndAt(
                  assignments[index],
                  records: sources,
                  index: displayIndex,
                  now: now,
                )
              : null,
        ),
      for (var index = 0; index < manualEntries.length; index++)
        HomeTimelineItem._(
          manual: manualEntries[index],
          sortIndex: assignments.length + index,
          preparedDisplayAt: manualEntries[index].at,
          treatAsActiveForSorting:
              keepVisibleIds.contains(manualEntries[index].id),
        ),
    ];
    if (order == HomeSortOrder.grouped) return items;
    items.sort((left, right) => _compare(
          left,
          right,
          order,
          now,
          prioritizeStartOnly,
          coursework,
        ));
    return items;
  }

  static bool _matchesType(ManualEntry entry, AssignmentTypeFilter type) =>
      switch (type) {
        AssignmentTypeFilter.all => true,
        AssignmentTypeFilter.homework || AssignmentTypeFilter.task => false,
        AssignmentTypeFilter.exam ||
        AssignmentTypeFilter.examNotice =>
          entry.kind == ManualEntry.kindExam,
        AssignmentTypeFilter.todo => entry.kind == ManualEntry.kindTodo,
      };

  static bool _matchesDeadline(
    ManualEntry entry,
    AssignmentDeadlineFilter filter,
    DateTime now,
  ) {
    final at = entry.at;
    final bucket = manualBucketAt(entry, now);
    return switch (filter) {
      AssignmentDeadlineFilter.all => true,
      AssignmentDeadlineFilter.next7Days => at != null &&
          at.isAfter(now) &&
          !at.isAfter(now.add(const Duration(days: 7))),
      AssignmentDeadlineFilter.next30Days => at != null &&
          at.isAfter(now) &&
          !at.isAfter(now.add(const Duration(days: 30))),
      AssignmentDeadlineFilter.overdue =>
        bucket == AssignmentDeadlineBucket.overdue,
      AssignmentDeadlineFilter.uncertain => false,
      AssignmentDeadlineFilter.noDeadline =>
        bucket == AssignmentDeadlineBucket.confirmedNoDeadline,
      AssignmentDeadlineFilter.notExpired =>
        bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
            bucket == AssignmentDeadlineBucket.confirmedNoDeadline,
    };
  }

  static int _compare(
    HomeTimelineItem left,
    HomeTimelineItem right,
    HomeSortOrder order,
    DateTime now,
    bool prioritizeStartOnly,
    LocalCourseworkState coursework,
  ) {
    if (order == HomeSortOrder.title) {
      // Name-only ordering still keeps untrusted and overdue records in their
      // bucket rank, matching AssignmentQuery.sortHome.
      final group = AssignmentQuery.nameGroupRank(
        left.bucketAt(now, coursework: coursework),
      ).compareTo(AssignmentQuery.nameGroupRank(
        right.bucketAt(now, coursework: coursework),
      ));
      if (group != 0) return group;
      return _compareNameKeys(left, right, courseFirst: false);
    }
    if (order == HomeSortOrder.courseName) {
      final course = AssignmentQuery.compareNaturalPinyin(
        left.displayCourse,
        right.displayCourse,
      );
      if (course != 0) return course;
      final time = _compareAscending(left.displayAt, right.displayAt);
      if (time != 0) return time;
      return _compareNameKeys(left, right, courseFirst: true);
    }

    final leftTier = _homeTier(
      left,
      order,
      now,
      prioritizeStartOnly,
      coursework,
    );
    final rightTier = _homeTier(
      right,
      order,
      now,
      prioritizeStartOnly,
      coursework,
    );
    final tier = leftTier.compareTo(rightTier);
    if (tier != 0) return tier;
    final leftTime =
        leftTier == 1 ? left.assignment?.availableFromAt : left.displayAt;
    final rightTime =
        rightTier == 1 ? right.assignment?.availableFromAt : right.displayAt;
    if (leftTime == null && rightTime != null) return 1;
    if (rightTime == null && leftTime != null) return -1;
    if (leftTime != null && rightTime != null) {
      final time = leftTime.compareTo(rightTime);
      if (time != 0) {
        final reverse = leftTier == 4
            ? order == HomeSortOrder.deadlineAsc
            : order == HomeSortOrder.deadlineDesc;
        return reverse ? -time : time;
      }
    }
    return _compareNameKeys(left, right, courseFirst: true);
  }

  static int _homeTier(
    HomeTimelineItem item,
    HomeSortOrder order,
    DateTime now,
    bool prioritizeStartOnly,
    LocalCourseworkState coursework,
  ) {
    final bucket = item.bucketAt(now, coursework: coursework);
    if (bucket == AssignmentDeadlineBucket.overdue ||
        _isElapsedNotice(item, now)) {
      return 4;
    }
    final time = item.displayAt;
    if (time != null) {
      return prioritizeStartOnly &&
              order == HomeSortOrder.deadlineAsc &&
              time.isAfter(now.add(const Duration(days: 7)))
          ? 2
          : 0;
    }
    final assignment = item.assignment;
    if (prioritizeStartOnly &&
        assignment != null &&
        _isUndatedActiveWork(assignment) &&
        _hasStartAnchor(assignment)) {
      return 1;
    }
    return 3;
  }

  static bool _isElapsedNotice(HomeTimelineItem item, DateTime now) {
    final assignment = item.assignment;
    final exam = assignment?.exam;
    if (assignment == null || exam == null) return false;
    final end = item.preparedEndAt ?? item.displayAt;
    return exam.startTrusted == false &&
        exam.endTrusted == false &&
        !assignment.isCompleted &&
        item.displayAt != null &&
        end != null &&
        !end.isAfter(now);
  }

  static bool _isUndatedActiveWork(Assignment assignment) =>
      !assignment.isExam &&
      assignment.isPendingConfirmed &&
      assignment.status != 'overdue' &&
      assignment.deadlineAt == null &&
      (!assignment.deadlineReadFailed || _hasStartAnchor(assignment));

  static bool _hasStartAnchor(Assignment assignment) =>
      assignment.availableFromAt != null ||
      (assignment.availableFromText?.trim().isNotEmpty ?? false);

  static int _compareNameKeys(
    HomeTimelineItem left,
    HomeTimelineItem right, {
    required bool courseFirst,
  }) {
    final first = courseFirst
        ? AssignmentQuery.compareNaturalPinyin(
            left.displayCourse,
            right.displayCourse,
          )
        : AssignmentQuery.compareNaturalPinyin(left.title, right.title);
    if (first != 0) return first;
    final second = courseFirst
        ? AssignmentQuery.compareNaturalPinyin(left.title, right.title)
        : AssignmentQuery.compareNaturalPinyin(
            left.displayCourse,
            right.displayCourse,
          );
    if (second != 0) return second;
    final courseKey = AssignmentQuery.compareNaturalPinyin(
      left.courseKey,
      right.courseKey,
    );
    if (courseKey != 0) return courseKey;
    final itemId =
        AssignmentQuery.compareNaturalPinyin(left.itemId, right.itemId);
    if (itemId != 0) return itemId;
    return left.sortIndex.compareTo(right.sortIndex);
  }

  static int _compareAscending(DateTime? left, DateTime? right) {
    if (left == null && right != null) return 1;
    if (right == null && left != null) return -1;
    if (left == null && right == null) return 0;
    return left!.compareTo(right!);
  }
}
