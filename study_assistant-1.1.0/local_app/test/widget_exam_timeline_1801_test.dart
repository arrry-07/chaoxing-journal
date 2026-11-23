import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/widget_snapshot.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class Capture extends WidgetSnapshotService {
  Capture({super.clock});
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

  test(
      'cross-day in-progress exam stays in widget range with started copy and normal urgency',
      () async {
    // Start and now cross Beijing midnight (UTC 15:30 = 23:30 BJT, UTC 17:30 = 01:30+1d BJT).
    final fixedNow = DateTime.utc(2026, 11, 20, 17, 30);
    final start = DateTime.utc(2026, 11, 20, 15, 30);
    final end = DateTime.utc(2026, 11, 21, 1, 0);
    final ongoingExam = Assignment(
      id: 'cx:exam:1:2:cross1',
      source: AssignmentSource.exam,
      courseName: '计算机网络',
      title: '跨天在线机考',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: fixedNow,
      exam: ExamInfo(
        examId: 'cross1',
        courseId: '1',
        clazzId: '2',
        lifecycle: 'inProgress',
        startAt: start,
        startTrusted: true,
        endAt: end,
        endTrusted: true,
      ),
    );
    final filtered = const DisplayPreferences(widgetRange: WidgetRange.today)
        .forWidget([ongoingExam], fixedNow);
    expect(filtered, hasLength(1));

    final service = Capture(clock: () => fixedNow);
    await service.saveAssignmentsForContext(
      filtered,
      authenticated: true,
      range: WidgetRange.today,
    );
    expect(service.items, hasLength(1));
    final item = service.items.single;
    expect(item.eventKind, 'examStart');
    expect(item.deadlineSource, 'official');
    expect(item.remainingText, '已开考');
    expect(item.urgencyLevel, 'normal');
    expect(item.deepLinkUrl,
        'studyassistant:///assignments/cx%3Aexam%3A1%3A2%3Across1');
  });
}
