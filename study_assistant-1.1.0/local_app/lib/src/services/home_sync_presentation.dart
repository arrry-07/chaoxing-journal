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
      return HomeSyncPresentation(
          report.phase == SyncPhase.partial
              ? '部分课程未更新'
              : hasCache
                  ? '更新失败，以下为上次记录'
                  : '暂时无法读取作业',
          action,
          showCached: hasCache);
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
