import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../app/app_deep_links.dart';
import '../models/assignment.dart';
import '../models/display_preferences.dart';
import '../models/widget_snapshot.dart';
import 'assignment_query.dart';

class WidgetSnapshotService {
  static const _groupId = 'group.com.example.studyassistant';
  static const _snapshotKey = 'assignment_snapshot';
  static const _snapshotAtKey = 'assignment_snapshot_at';
  static const _authenticatedKey = 'assignment_authenticated';
  static const _totalCountKey = 'assignment_total_count';
  static const _rangeLabelKey = 'assignment_range_label';

  bool _pendingAuthenticated = true;
  WidgetRange _pendingRange = WidgetRange.all;
  int? _pendingTotalCount;

  @visibleForTesting
  bool lastSavedAuthenticated = true;

  @visibleForTesting
  int lastSavedTotalCount = 0;

  @visibleForTesting
  String lastSavedRangeLabel = '待完成';

  static String rangeLabel(WidgetRange range) => switch (range) {
        WidgetRange.all => '待完成',
        WidgetRange.today => '今日待办',
        WidgetRange.week => '7日待办',
      };

  Future<void> saveSnapshot(List<WidgetSnapshotItem> items) async {
    final authenticated = _pendingAuthenticated;
    final rangeLabelText = rangeLabel(_pendingRange);
    final totalCount = _pendingTotalCount ?? items.length;
    lastSavedAuthenticated = authenticated;
    lastSavedTotalCount = totalCount;
    lastSavedRangeLabel = rangeLabelText;

    await HomeWidget.setAppGroupId(_groupId);
    await HomeWidget.saveWidgetData<String>(
      _snapshotKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    await HomeWidget.saveWidgetData<String>(
        _snapshotAtKey, DateTime.now().toUtc().toIso8601String());
    await HomeWidget.saveWidgetData<bool>(_authenticatedKey, authenticated);
    await HomeWidget.saveWidgetData<int>(_totalCountKey, totalCount);
    await HomeWidget.saveWidgetData<String>(_rangeLabelKey, rangeLabelText);
    await HomeWidget.updateWidget(
      iOSName: 'AssignmentWidget',
      qualifiedAndroidName:
          'com.example.studyassistant.AssignmentWidgetProvider',
    );
  }

  /// Writes desktop widget snapshot with explicit authentication state and range
  /// label while preserving the original [saveAssignments] override signature
  /// used across existing tests.
  Future<void> saveAssignmentsForContext(
    List<Assignment> assignments, {
    bool authenticated = true,
    WidgetRange range = WidgetRange.all,
  }) async {
    _pendingAuthenticated = authenticated;
    _pendingRange = range;
    try {
      await saveAssignments(assignments);
    } finally {
      _pendingAuthenticated = true;
      _pendingRange = WidgetRange.all;
      _pendingTotalCount = null;
    }
  }

  Future<void> saveAssignments(List<Assignment> assignments) {
    final now = DateTime.now();
    final groups = AssignmentQuery.home(assignments, now, {});
    final pending = [
      ...groups.near,
      ...groups.far,
      ...groups.noDeadline,
      ...groups.uncertain,
      ...groups.overdue
    ];
    _pendingTotalCount = pending.length;
    lastSavedAuthenticated = _pendingAuthenticated;
    lastSavedTotalCount = pending.length;
    lastSavedRangeLabel = rangeLabel(_pendingRange);
    final items = pending.take(6).map(
      (assignment) {
        final bucket = AssignmentQuery.timelineBucketAt(assignment, now);
        final hasTrustedTime =
            bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
                bucket == AssignmentDeadlineBucket.overdue;
        return WidgetSnapshotItem(
          assignmentId: assignment.id,
          title: assignment.title,
          courseName: assignment.courseName,
          deadlineAt: hasTrustedTime ? assignment.timelineAt : null,
          remainingText: switch (bucket) {
            AssignmentDeadlineBucket.overdue => '已逾期',
            AssignmentDeadlineBucket.notExpiredWithDeadline => assignment.isExam
                ? (assignment.timelineAt!.isAfter(now)
                    ? '距开考 ${_remainingText(assignment.timelineAt!, now)}'
                    : '已开考')
                : _remainingText(assignment.timelineAt!, now),
            AssignmentDeadlineBucket.confirmedNoDeadline =>
              assignment.deadlineLabel,
            AssignmentDeadlineBucket.unconfirmed => assignment.isExam
                ? '考试时间未知'
                : (assignment.deadlineReadFailed || !assignment.deadlineTrusted
                    ? assignment.deadlineLabel
                    : '状态或截止待确认'),
            AssignmentDeadlineBucket.completed => '已完成',
          },
          urgencyLevel: assignment.isExam &&
                  assignment.timelineAt != null &&
                  !assignment.timelineAt!.isAfter(now)
              ? 'normal'
              : _urgencyLevel(
                  hasTrustedTime ? assignment.timelineAt : null,
                  now,
                ),
          deepLinkUrl: AppDeepLinks.assignmentUri(assignment.id),
          eventKind: assignment.isExam ? 'examStart' : 'deadline',
        );
      },
    ).toList();
    return saveSnapshot(items).whenComplete(() {
      _pendingTotalCount = null;
    });
  }

  String _remainingText(DateTime deadlineAt, DateTime now) {
    final minutes = (deadlineAt.difference(now).inMilliseconds /
            Duration.millisecondsPerMinute)
        .ceil();
    if (minutes <= 0) {
      return '已截止';
    }
    if (minutes < 60) {
      return '$minutes分钟';
    }
    final hours = (minutes / 60).ceil();
    if (hours < 24) {
      return '$hours小时';
    }
    return '${(hours / 24).ceil()}天';
  }

  String _urgencyLevel(DateTime? deadlineAt, DateTime now) {
    if (deadlineAt == null) return 'unknown';
    final hours = deadlineAt.difference(now).inHours;
    if (hours <= 3) {
      return 'critical';
    }
    if (hours <= 24) {
      return 'soon';
    }
    return 'normal';
  }
}
