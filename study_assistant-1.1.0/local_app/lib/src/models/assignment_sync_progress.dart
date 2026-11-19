import 'assignment.dart';

enum AssignmentSyncStage {
  courses,
  workLists,
  details,
  classroomTasks,
  exams,
  saving,
}

/// In-memory progress for the first visible homework snapshot.
///
/// This never participates in persistence or reminder planning. It only lets
/// the foreground home screen show list data while detail requests continue.
class AssignmentSyncProgress {
  AssignmentSyncProgress({
    required this.stage,
    required List<Assignment> assignments,
    required Set<String> pendingDetailIds,
    required this.resolvedCount,
    required this.attemptedCount,
    this.unconfirmedCount = 0,
  })  : assignments = List.unmodifiable(assignments),
        pendingDetailIds = Set.unmodifiable(pendingDetailIds);

  final AssignmentSyncStage stage;
  final List<Assignment> assignments;
  final Set<String> pendingDetailIds;
  final int resolvedCount;
  final int attemptedCount;
  final int unconfirmedCount;

  String get stageLabel => switch (stage) {
        AssignmentSyncStage.courses => '正在读取课程',
        AssignmentSyncStage.workLists => '正在读取作业',
        AssignmentSyncStage.details => '正在确认截止时间',
        AssignmentSyncStage.classroomTasks => '正在读取课堂任务',
        AssignmentSyncStage.exams =>
          unconfirmedCount > 0 ? '作业已读取，部分截止待确认 · 正在读取考试' : '作业已读取 · 正在读取考试',
        AssignmentSyncStage.saving => '正在保存作业',
      };
}
