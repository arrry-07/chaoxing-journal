import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/widget_snapshot.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class Capture extends WidgetSnapshotService {
  List<WidgetSnapshotItem> items = [];
  @override
  Future<void> saveSnapshot(List<WidgetSnapshotItem> items) async {
    this.items = items;
  }
}

void main() {
  test(
      'widget week range projects before filtering and snapshot uses opening time',
      () async {
    final now = DateTime.now();
    final start = now.add(const Duration(days: 1));
    Assignment record(String id, {bool notice = false}) => Assignment(
        id: notice ? 'cx:examNotice:inbox:$id' : 'cx:exam:1:2:$id',
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
            relatedExamId: notice ? '3' : null,
            noticeOnly: notice,
            lifecycle: 'scheduled',
            startAt: notice ? start : null,
            startTrusted: notice));
    final rows = [record('3'), record('n', notice: true)];
    final filtered = const DisplayPreferences(widgetRange: WidgetRange.week)
        .forWidget(rows, now);
    expect(filtered, hasLength(1));
    expect(filtered.single.id, rows.first.id);
    expect(filtered.single.timelineAt!.toUtc(), start.toUtc());
    final service = Capture();
    await service.saveAssignments(filtered);
    expect(service.items, hasLength(1));
    expect(service.items.single.deadlineAt!.toUtc(), start.toUtc());
    expect(service.items.single.remainingText, startsWith('距开考'));
    expect(
        const DisplayPreferences(widgetRange: WidgetRange.today)
            .forWidget(rows, now),
        isEmpty);
    expect(rows.first.timelineAt, isNull);
  });

  test('widget uses exam opening time, deduplicates and excludes ended',
      () async {
    final now = DateTime.now();
    Assignment record(String id,
            {bool notice = false, String lifecycle = 'scheduled'}) =>
        Assignment(
            id: notice ? 'cx:examNotice:inbox:$id' : 'cx:exam:1:2:$id',
            source: AssignmentSource.exam,
            courseName: '课程',
            title: '考试',
            deadlineAt: null,
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
            exam: ExamInfo(
                examId: id,
                relatedExamId: notice ? '3' : null,
                courseId: '1',
                clazzId: '2',
                noticeOnly: notice,
                lifecycle: lifecycle,
                startAt: now.add(const Duration(hours: 2)),
                startTrusted: true));
    final service = Capture();
    final a = record('3');
    await service.saveAssignments(
        [a, record('n', notice: true), record('4', lifecycle: 'ended')]);
    expect(service.items, hasLength(1));
    expect(service.items.single.assignmentId, a.id);
    expect(service.items.single.deadlineAt!.toUtc(), a.timelineAt!.toUtc());
    expect(service.items.single.remainingText, startsWith('距开考'));
    expect(service.items.single.remainingText, isNot(contains('截止')));
  });
}
