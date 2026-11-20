import '../models/sync_report.dart';

enum HomeSyncAction { none, read, retry, login, verify, settings }

class HomeSyncPresentation {
  const HomeSyncPresentation(this.summary, this.action,
      {this.showCached = false});
  final String summary;
  final HomeSyncAction action;
  final bool showCached;
  String? get actionLabel => switch (action) {
        HomeSyncAction.none => null,
        HomeSyncAction.read => '读取作业',
        HomeSyncAction.retry => '重试',
        HomeSyncAction.login => '重新登录',
        HomeSyncAction.verify => '完成验证',
        HomeSyncAction.settings => '去处理'
      };
  static HomeSyncPresentation from(SyncReport report,
      {required bool loading,
      required bool hasCache,
      required DateTime now,
      DateTime? successAt,
      bool? hasPreviousData,
      bool serviceWarning = false}) {
    if (loading || report.phase == SyncPhase.running) {
      return HomeSyncPresentation(
          hasCache ? '正在更新…' : '正在读取作业…', HomeSyncAction.none);
    }
    if (report.phase == SyncPhase.failed || report.phase == SyncPhase.partial) {
      final action =
          report.issues.any((i) => i.kind == SyncIssueKind.authExpired)
              ? HomeSyncAction.login
              : report.issues
                      .any((i) => i.kind == SyncIssueKind.verificationRequired)
                  ? HomeSyncAction.verify
                  : HomeSyncAction.retry;
      bool sourceFailed(String name) => report.sourceResults.any((source) =>
          source.source == name &&
          const {SyncSourcePhase.partial, SyncSourcePhase.failed}
              .contains(source.phase));
      final hasWorkListFailure = sourceFailed('courseWork') ||
          (report.sourceResults.isEmpty &&
              report.issues.any((issue) =>
                  issue.stage != 'detail' &&
                  issue.stage != 'courseNotice' &&
                  issue.stage != 'persistence' &&
                  !issue.stage.startsWith('exam')));
      final hasExamFailure = report.incompleteExamSourceCount > 0;
      final hasClassroomFailure = report.sourceResults.any((source) =>
          source.source.startsWith('classroomActivity:') &&
          const {SyncSourcePhase.partial, SyncSourcePhase.failed}
              .contains(source.phase));
      final hasCourseNoticeFailure = sourceFailed('courseNotice');
      final hasDetailFailure =
          report.issues.any((issue) => issue.stage == 'detail') ||
              report.sourceResults
                  .any((source) => source.detailUnconfirmedCount > 0);
      final hasStorageFailure = report.issues.any((issue) =>
          issue.kind == SyncIssueKind.storage || issue.stage == 'persistence');
      final knownSources = {
        'courseWork',
        'exam',
        'examAccount',
        'examNotice',
        'courseNotice',
      };
      final hasOtherSourceFailure = report.sourceResults.any((source) =>
          const {SyncSourcePhase.partial, SyncSourcePhase.failed}
              .contains(source.phase) &&
          !knownSources.contains(source.source) &&
          !source.source.startsWith('classroomActivity:'));
      final categories = [
        hasWorkListFailure,
        hasDetailFailure,
        hasExamFailure,
        hasClassroomFailure,
        hasCourseNoticeFailure,
        hasStorageFailure,
        hasOtherSourceFailure,
      ].where((value) => value).length;
      final updatedButNeedsAttention = hasStorageFailure &&
          categories == 1 &&
          report.issues.any((issue) => issue.stage == 'persistence');
      final showCached = hasCache &&
          successAt != null &&
          (hasPreviousData ?? hasCache) &&
          (hasWorkListFailure ||
              hasExamFailure ||
              hasClassroomFailure ||
              hasOtherSourceFailure);
      final partialSummary = updatedButNeedsAttention
          ? '作业数据已保存，但同步状态记录需要处理'
          : categories > 1
              ? '部分课业信息未更新'
              : hasDetailFailure
                  ? '部分截止时间待确认'
                  : hasCourseNoticeFailure
                      ? '部分课程通知未更新'
                      : hasExamFailure
                          ? '部分考试信息未更新'
                          : hasClassroomFailure
                              ? '部分课堂任务未更新'
                              : '部分课程作业未更新';
      return HomeSyncPresentation(
          report.phase == SyncPhase.partial
              ? partialSummary
              : hasCache
                  ? '更新失败'
                  : '暂时无法读取作业',
          action,
          showCached: report.phase == SyncPhase.failed ? hasCache : showCached);
    }
    if (serviceWarning) {
      return const HomeSyncPresentation(
          '作业已更新，提醒需要处理', HomeSyncAction.settings);
    }
    final updated = report.lastDataSuccessAt ?? successAt;
    if (report.phase == SyncPhase.success || updated != null) {
      final local = updated?.toLocal();
      return HomeSyncPresentation(
          local == null || now.difference(updated!).inMinutes < 1
              ? '刚刚更新'
              : '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} 更新',
          HomeSyncAction.none);
    }
    return const HomeSyncPresentation('尚未读取作业', HomeSyncAction.read);
  }
}
