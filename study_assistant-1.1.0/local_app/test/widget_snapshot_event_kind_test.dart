import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/widget_snapshot.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Snapshot extends WidgetSnapshotService {
  List<WidgetSnapshotItem> items = [];

  @override
  Future<void> saveSnapshot(List<WidgetSnapshotItem> items) async {
    this.items = items;
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 17, 8);

  Assignment exam(String id, DateTime start) => Assignment(
        id: 'cx:exam:1:2:$id',
        source: AssignmentSource.exam,
        courseName: '课程',
        title: '考试',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
        exam: ExamInfo(
          examId: id,
          courseId: '1',
          clazzId: '2',
          startAt: start,
          startTrusted: true,
          lifecycle: 'scheduled',
        ),
      );

  Assignment work(String id, DateTime deadline) => Assignment(
        id: 'cx:work:1:2:$id',
        courseName: '课程',
        title: '作业',
        deadlineAt: deadline,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      );

  test('widget JSON distinguishes exam start from an assignment deadline',
      () async {
    final start = now.add(const Duration(hours: 2));
    final deadline = now.add(const Duration(hours: 3));
    final snapshot = _Snapshot();

    await snapshot.saveAssignments([
      exam('3', start),
      work('4', deadline),
    ]);

    final byId = {
      for (final item in snapshot.items)
        item.assignmentId:
            jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>,
    };
    final examJson = byId['cx:exam:1:2:3']!;
    final workJson = byId['cx:work:1:2:4']!;
    expect(examJson['eventKind'], 'examStart');
    expect(workJson['eventKind'], 'deadline');
    expect(DateTime.parse(examJson['deadlineAt'] as String).toUtc(),
        start.toUtc());
    expect(DateTime.parse(workJson['deadlineAt'] as String).toUtc(),
        deadline.toUtc());
  });

  test('old or unknown widget snapshots fall back to a deadline', () {
    final base = <String, dynamic>{
      'assignmentId': 'cx:work:1:2:5',
      'title': '旧作业',
      'courseName': '课程',
      'deadlineAt': now.add(const Duration(days: 1)).toIso8601String(),
      'remainingText': '1天',
      'urgencyLevel': 'normal',
      'deepLinkUrl': 'studyassistant:///assignments/old',
    };
    final old = WidgetSnapshotItem.fromJson(base);
    final unknown = WidgetSnapshotItem.fromJson({
      ...base,
      'eventKind': 'unsupported',
    });

    expect(old.toJson()['eventKind'], 'deadline');
    expect(unknown.toJson()['eventKind'], 'deadline');
  });
}
