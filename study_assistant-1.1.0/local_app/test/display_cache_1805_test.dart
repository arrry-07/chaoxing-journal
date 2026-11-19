import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/exam_schedule_presentation.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  test('display projection and notice ranges are resolved once per input', () {
    AssignmentQuery.debugResetDisplayCaches();
    ExamSchedulePresentation.debugResetCache();
    final formal = Assignment(
      id: 'cx:exam:1:2:3',
      source: AssignmentSource.exam,
      courseName: '大学英语',
      title: '开放性期中考试',
      deadlineAt: null,
      requirementsText: '以官方考试列表为准',
      status: 'unknown',
      lastSyncedAt: DateTime.utc(2026, 11, 16),
      exam: const ExamInfo(
        examId: '3',
        courseId: '1',
        clazzId: '2',
      ),
    );
    final notice = Assignment(
      id: 'cx:examNotice:inbox:n',
      source: AssignmentSource.exam,
      courseName: '大学英语',
      title: '开放性期中考试',
      deadlineAt: null,
      requirementsText: '考试时间：11-16 07:06 至 11-30 07:06',
      status: 'unknown',
      lastSyncedAt: DateTime.utc(2026, 11, 16),
      exam: const ExamInfo(
        examId: 'n',
        relatedExamId: '3',
        courseId: '1',
        clazzId: '2',
        noticeOnly: true,
        durationMinutes: 60,
      ),
    );
    final records = [formal, notice];
    final index = AssignmentDisplayIndex.from(records);

    final firstProjection =
        AssignmentQuery.projectDisplay(records, index: index);
    final secondProjection =
        AssignmentQuery.projectDisplay(records, index: index);
    expect(secondProjection.map((item) => item.id),
        firstProjection.map((item) => item.id));

    final first =
        ExamSchedulePresentation.build(formal, records: records, index: index);
    final second =
        ExamSchedulePresentation.build(formal, records: records, index: index);
    expect(identical(first, second), isTrue);
    expect(first.timeline?.clock, '07:06');
    expect(index.noticeRangeReadCount, 1);

    final ranges = AssignmentQuery.displayNoticeRanges(formal,
        records: records, index: index);
    expect(ranges.single.key, contains('11:16:7:6'));
    expect(index.noticeRangeReadCount, 1);
  });

  test(
      'store keeps its display index across status notifications and replaces it on data change',
      () {
    final store = AssignmentStore(
      sessionStore: SecureSessionStore(),
      notificationService: LocalNotificationService(),
      widgetSnapshotService: WidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    final rows = [
      Assignment(
        id: 'cx:work:1:2:1',
        courseName: '课程',
        title: '作业',
        deadlineAt: DateTime.utc(2026, 12, 1),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026, 11, 16),
      )
    ];

    store.replaceAssignmentsForTest(rows);
    final first = store.homeDisplayIndex;
    store.notifyListeners();
    expect(identical(store.homeDisplayIndex, first), isTrue);

    store.replaceAssignmentsForTest(List<Assignment>.of(rows));
    expect(identical(store.homeDisplayIndex, first), isFalse);
  });
}
