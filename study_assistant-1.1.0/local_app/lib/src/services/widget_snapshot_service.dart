import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../app/app_deep_links.dart';
import '../models/widget_snapshot.dart';
import '../models/assignment.dart';
import 'assignment_query.dart';

class WidgetSnapshotService {
  static const _groupId = 'group.com.example.studyassistant';
  static const _snapshotKey = 'assignment_snapshot';

  Future<void> saveSnapshot(List<WidgetSnapshotItem> items) async {
    await HomeWidget.setAppGroupId(_groupId);
    await HomeWidget.saveWidgetData<String>(
      _snapshotKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    await HomeWidget.updateWidget(
      iOSName: 'AssignmentWidget',
      qualifiedAndroidName:
          'com.example.studyassistant.AssignmentWidgetProvider',
    );
  }

  Future<void> saveAssignments(List<Assignment> assignments) {
    final now = DateTime.now();
    final groups = AssignmentQuery.home(assignments, now, {});
    final pending = [
      ...groups.near,
      ...groups.uncertain,
      ...groups.noDeadline,
      ...groups.far,
      ...groups.overdue
    ];
    final items = pending
        .take(6)
        .map(
          (assignment) => WidgetSnapshotItem(
            assignmentId: assignment.id,
            title: assignment.title,
            courseName: assignment.courseName,
            deadlineAt:
                assignment.deadlineTrusted ? assignment.deadlineAt : null,
            remainingText: !assignment.deadlineTrusted
                ? assignment.deadlineAt == null
                    ? assignment.deadlineLabel
                    : '截止待确认'
                : assignment.deadlineAt == null
                    ? assignment.deadlineLabel
                    : _remainingText(assignment.deadlineAt!, now),
            urgencyLevel: _urgencyLevel(
                assignment.deadlineTrusted ? assignment.deadlineAt : null, now),
            deepLinkUrl: AppDeepLinks.assignmentUri(assignment.id),
          ),
        )
        .toList();
    return saveSnapshot(items);
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
