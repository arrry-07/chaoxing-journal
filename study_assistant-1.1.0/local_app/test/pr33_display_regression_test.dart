import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/daily_plan_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment row(String id,
        {required DateTime start,
        bool notice = false,
        String lifecycle = 'scheduled',
        String location = '',
        int? duration}) =>
    Assignment(
        id: notice ? 'cx:examNotice:inbox:$id' : 'cx:exam:1:2:$id',
        source: AssignmentSource.exam,
        courseName: '课程',
        title: notice ? '考试通知' : '考试$id',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: start,
        exam: ExamInfo(
            examId: id,
            relatedExamId: notice ? '3' : null,
            courseId: '1',
            clazzId: '2',
            noticeOnly: notice,
            startAt: start,
            startTrusted: true,
            lifecycle: lifecycle,
            location: location,
            durationMinutes: duration));

class PickerStore extends AssignmentStore {
  PickerStore(this.rows)
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  final List<Assignment> rows;
  @override
  List<Assignment> get courseAssignments => List.of(rows);
}

void main() {
  test('limited widget ranges exclude past opening dates without an ending',
      () {
    final now = DateTime.utc(2026, 11, 16, 2);
    final yesterday = row('1',
        start: now.subtract(const Duration(days: 1)), lifecycle: 'unknown');
    final today = row('2', start: now.add(const Duration(hours: 1)));
    final tomorrow = row('3', start: now.add(const Duration(days: 1)));
    final rows = [yesterday, today, tomorrow];
    expect(
        const DisplayPreferences(widgetRange: WidgetRange.today)
            .forWidget(rows, now),
        [today]);
    expect(
        const DisplayPreferences(widgetRange: WidgetRange.week)
            .forWidget(rows, now),
        [today, tomorrow]);
    expect(const DisplayPreferences().forWidget(rows, now), rows);
  });

  test(
      'formal schedule conflict labels the old venue and excludes its duration',
      () {
    final now = DateTime.utc(2026, 11, 16, 2);
    final formal = row('3', start: now.add(const Duration(days: 1)));
    final stale = row('n',
        notice: true,
        start: now.subtract(const Duration(days: 1)),
        lifecycle: 'ended',
        location: '旧教室',
        duration: 90);
    final projected = AssignmentQuery.projectDisplay([formal, stale]).single;
    expect(projected.timelineAt, formal.timelineAt);
    expect(projected.exam!.lifecycle, 'scheduled');
    expect(projected.exam!.location, '通知原地点：旧教室（已改期，请核对）');
    expect(formal.exam!.location, isEmpty);
    expect(projected.exam!.durationMinutes, isNull);
    final compatible = row('n',
        notice: true, start: formal.timelineAt!, location: '新教室', duration: 60);
    final supplement =
        AssignmentQuery.projectDisplay([formal, compatible]).single;
    expect(supplement.exam!.location, '新教室');
    expect(supplement.exam!.durationMinutes, 60);
  });

  testWidgets(
      'daily plan picker excludes ended exams and projects notice aliases',
      (tester) async {
    final start = DateTime.now().add(const Duration(days: 1));
    final store = PickerStore([
      row('3', start: start),
      row('n', start: start, notice: true),
      row('4', start: start, lifecycle: 'ended'),
      row('5', start: start, lifecycle: 'cancelled'),
    ]);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: DailyPlanScreen(store: store)));
    await tester.ensureVisible(find.text('添加作业到计划'));
    await tester.tap(find.text('添加作业到计划'));
    await tester.pumpAndSettle();
    expect(find.text('选择准备完成的作业'), findsOneWidget);
    expect(find.text('考试3'), findsOneWidget);
    expect(find.text('考试通知'), findsNothing);
    expect(find.text('考试4'), findsNothing);
    expect(find.text('考试5'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
