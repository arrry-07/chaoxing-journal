import 'package:flutter/material.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Store extends AssignmentStore {
  _Store(this.rows)
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  final List<Assignment> rows;
  @override
  List<Assignment> get courseAssignments => List.of(rows);
  @override
  Assignment? findAssignment(String id) =>
      rows.where((a) => a.id == id).firstOrNull;
}

Assignment _row(String id,
        {bool ended = false, bool notice = false}) =>
    Assignment(
        id: id,
        source: AssignmentSource.exam,
        deadlineAt: null,
        courseName: '合成课程',
        title: '合成考试',
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026),
        exam: ExamInfo(
            examId: notice ? 'notice' : '123',
            relatedExamId: notice ? '123' : null,
            courseId: '1',
            clazzId: '2',
            noticeOnly: notice,
            lifecycle: ended ? 'ended' : 'unknown'));
void main() {
  test('store display retires ended exams without rewriting submission facts',
      () {
    final row = _row('cx:exam:1:2:123', ended: true);
    final store = _Store([row]);
    expect(store.visibleAssignments, isEmpty);
    expect(store.courseAssignments.single.status, 'pending');
    expect(store.courseAssignments.single.isCompleted, isFalse);
    store.dispose();
  });
  test('store display projects related notices without deleting source records',
      () {
    final store = _Store([
      _row('cx:examNotice:inbox:notice', notice: true),
      _row('cx:exam:1:2:123')
    ]);
    expect(store.visibleAssignments.map((a) => a.id), ['cx:exam:1:2:123']);
    expect(store.courseAssignments, hasLength(2));
    store.dispose();
  });
  testWidgets('detail keeps verified notice supplementation shown by list',
      (tester) async {
    final primary = _row('cx:exam:1:2:123');
    final notice = _row('cx:examNotice:inbox:notice', notice: true).copyWith(
        exam: const ExamInfo(
            examId: 'notice',
            relatedExamId: '123',
            courseId: '1',
            clazzId: '2',
            noticeOnly: true,
            location: '合成考场A'));
    final store = _Store([primary, notice]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssignmentDetailScreen(
                store: store, assignmentId: primary.id))));
    expect(find.text('地点 合成考场A'), findsOneWidget);
    expect(primary.exam!.location, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
