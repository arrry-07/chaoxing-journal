import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../app/app_deep_links.dart';
import '../models/assignment.dart';
import '../models/display_preferences.dart';
import '../models/local_coursework_state.dart';
import '../models/widget_snapshot.dart';
import 'assignment_query.dart';
import 'course_term_catalog.dart';

class WidgetSnapshotService {
  WidgetSnapshotService({DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  static const _groupId = 'group.com.example.studyassistant';
  static const _snapshotKey = 'assignment_snapshot';
  static const _snapshotAtKey = 'assignment_snapshot_at';
  static const _authenticatedKey = 'assignment_authenticated';
  static const _totalCountKey = 'assignment_total_count';
  static const _rangeLabelKey = 'assignment_range_label';

  DateTime Function() clock;
  Future<void>? _snapshotWrites;
  bool _pendingAuthenticated = true;
  WidgetRange _pendingRange = WidgetRange.all;
  int? _pendingTotalCount;
  LocalCourseworkState? _pendingCoursework;
  CourseTermCatalog? _pendingTermCatalog;
  DateTime? _pendingNow;

  /// Account-scoped local coursework overrides applied during widget sync.
  LocalCourseworkState courseworkState = const LocalCourseworkState.empty();

  /// Account-scoped active course term catalog applied during widget sync.
  CourseTermCatalog? termCatalog;

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
    await HomeWidget.saveWidgetData<String>(_snapshotAtKey,
        authenticated ? clock().toUtc().toIso8601String() : null);
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
  }) {
    final capturedCoursework =
        authenticated ? courseworkState : const LocalCourseworkState.empty();
    final capturedCatalog = authenticated ? termCatalog : null;
    final capturedNow = clock();
    final write = (_snapshotWrites ?? Future<void>.value()).then((_) async {
      _pendingAuthenticated = authenticated;
      _pendingRange = range;
      _pendingCoursework = capturedCoursework;
      _pendingTermCatalog = capturedCatalog;
      _pendingNow = capturedNow;
      try {
        await saveAssignments(authenticated ? assignments : const []);
      } finally {
        _pendingAuthenticated = true;
        _pendingRange = WidgetRange.all;
        _pendingTotalCount = null;
        _pendingCoursework = null;
        _pendingTermCatalog = null;
        _pendingNow = null;
      }
    });
    _snapshotWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> saveAssignments(List<Assignment> assignments) {
    final effectiveNow = _pendingNow ?? clock();
    final coursework = _pendingCoursework ?? courseworkState;
    final activeCatalog = _pendingTermCatalog ?? termCatalog;
    final scopedAssignments = activeCatalog == null
        ? assignments
        : assignments
            .where((a) =>
                a.courseKey == null ||
                activeCatalog.isActiveOrRecalled(a.courseKey!))
            .toList();
    final groups = AssignmentQuery.home(
      scopedAssignments,
      effectiveNow,
      {},
      coursework: coursework,
    );
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
        final bucket = AssignmentQuery.timelineBucketAt(
          assignment,
          effectiveNow,
          coursework: coursework,
        );
        final effectiveDeadline = assignment.isExam
            ? null
            : AssignmentQuery.effectiveDeadline(
                assignment,
                coursework: coursework,
              );
        final resolvedAt =
            assignment.isExam ? assignment.timelineAt : effectiveDeadline?.at;
        final hasEffectiveTime =
            bucket == AssignmentDeadlineBucket.notExpiredWithDeadline ||
                bucket == AssignmentDeadlineBucket.overdue;
        final isManualDeadline = hasEffectiveTime &&
            !assignment.isExam &&
            effectiveDeadline?.isManual == true;
        return WidgetSnapshotItem(
          assignmentId: assignment.id,
          title: assignment.title,
          courseName: assignment.courseName,
          deadlineAt: hasEffectiveTime ? resolvedAt : null,
          remainingText: switch (bucket) {
            AssignmentDeadlineBucket.overdue => '已逾期',
            AssignmentDeadlineBucket.notExpiredWithDeadline => assignment.isExam
                ? (resolvedAt!.isAfter(effectiveNow)
                    ? '距开考 ${_remainingText(resolvedAt, effectiveNow)}'
                    : '已开考')
                : _remainingText(resolvedAt!, effectiveNow),
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
                  resolvedAt != null &&
                  !resolvedAt.isAfter(effectiveNow)
              ? 'normal'
              : _urgencyLevel(
                  hasEffectiveTime ? resolvedAt : null,
                  effectiveNow,
                ),
          deepLinkUrl: AppDeepLinks.assignmentUri(assignment.id),
          eventKind: assignment.isExam ? 'examStart' : 'deadline',
          deadlineSource: isManualDeadline ? 'manual' : 'official',
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
