enum SyncPhase { idle, running, success, partial, failed }

enum SyncIssueKind {
  network,
  authExpired,
  verificationRequired,
  forbidden,
  schemaChanged,
  partial,
  storage,
  notification,
  widget
}

class SyncIssue {
  const SyncIssue(this.kind, this.message,
      {this.courseKey,
      this.elapsedMs,
      this.httpStatus,
      this.stage = 'courses'});
  final SyncIssueKind kind;
  final String message, stage;
  final String? courseKey;
  final int? elapsedMs, httpStatus;
  bool get retryable => kind != SyncIssueKind.authExpired;
}

class SyncReport {
  const SyncReport(
      {this.phase = SyncPhase.idle,
      this.attemptedAt,
      this.lastDataSuccessAt,
      this.lastFullSuccessAt,
      this.succeededCourses = 0,
      this.failedCourses = 0,
      this.issues = const []});
  final SyncPhase phase;
  final DateTime? attemptedAt, lastDataSuccessAt, lastFullSuccessAt;
  final int succeededCourses, failedCourses;
  final List<SyncIssue> issues;
  String get summary => switch (phase) {
        SyncPhase.running => '正在读取作业…',
        SyncPhase.partial => '已更新 $succeededCourses 门课程，$failedCourses 门待重试',
        SyncPhase.failed => '本次未能读取作业',
        SyncPhase.success => '作业记录已更新',
        SyncPhase.idle => '尚未获取作业',
      };
}

class SyncReadException implements Exception {
  const SyncReadException(this.issue);
  final SyncIssue issue;
  @override
  String toString() => issue.message;
}
