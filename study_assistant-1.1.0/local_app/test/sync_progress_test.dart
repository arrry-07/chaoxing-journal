import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';

void main() {
  test('sync stage labels describe the actual source boundary', () {
    AssignmentSyncProgress progress(AssignmentSyncStage stage,
            {int unconfirmed = 0}) =>
        AssignmentSyncProgress(
          stage: stage,
          assignments: const [],
          pendingDetailIds: const {},
          resolvedCount: 0,
          attemptedCount: 0,
          unconfirmedCount: unconfirmed,
        );
    expect(progress(AssignmentSyncStage.courses).stageLabel, '正在读取课程');
    expect(progress(AssignmentSyncStage.workLists).stageLabel, '正在读取作业');
    expect(progress(AssignmentSyncStage.classroomTasks).stageLabel, '正在读取课堂任务');
    expect(progress(AssignmentSyncStage.exams).stageLabel, '作业已读取 · 正在读取考试');
    expect(progress(AssignmentSyncStage.exams, unconfirmed: 2).stageLabel,
        '作业已读取，部分截止待确认 · 正在读取考试');
  });
}
