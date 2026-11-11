import 'assignment.dart';

enum AssignmentSyncStage { courses, workLists, details, saving }

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
  })  : assignments = List.unmodifiable(assignments),
        pendingDetailIds = Set.unmodifiable(pendingDetailIds);

  final AssignmentSyncStage stage;
  final List<Assignment> assignments;
  final Set<String> pendingDetailIds;
  final int resolvedCount;
  final int attemptedCount;

  String get stageLabel => switch (stage) {
        AssignmentSyncStage.courses => '正在读取课程',
        AssignmentSyncStage.workLists => '正在读取作业',
        AssignmentSyncStage.details => '正在确认截止时间',
        AssignmentSyncStage.saving => '正在保存作业',
      };
}
