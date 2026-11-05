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
  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'message': message,
        'stage': stage,
        if (courseKey != null) 'courseKey': courseKey,
        if (elapsedMs != null) 'elapsedMs': elapsedMs,
        if (httpStatus != null) 'httpStatus': httpStatus,
      };
  factory SyncIssue.fromJson(Map<String, dynamic> json) => SyncIssue(
      SyncIssueKind.values.byName(json['kind'] as String),
      json['message'] as String,
      stage: json['stage'] as String? ?? 'courses',
      courseKey: json['courseKey'] as String?,
      elapsedMs: json['elapsedMs'] as int?,
      httpStatus: json['httpStatus'] as int?);
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
  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'attemptedAt': attemptedAt?.toUtc().toIso8601String(),
        'lastDataSuccessAt': lastDataSuccessAt?.toUtc().toIso8601String(),
        'lastFullSuccessAt': lastFullSuccessAt?.toUtc().toIso8601String(),
        'succeededCourses': succeededCourses,
        'failedCourses': failedCourses,
        'issues': issues.map((i) => i.toJson()).toList(),
      };
  factory SyncReport.fromJson(Map<String, dynamic> json) {
    final phase = SyncPhase.values.byName(json['phase'] as String);
    final interrupted = phase == SyncPhase.running;
    DateTime? time(String key) => DateTime.tryParse(json[key] as String? ?? '');
    return SyncReport(
        phase: interrupted ? SyncPhase.failed : phase,
        attemptedAt: time('attemptedAt'),
        lastDataSuccessAt: time('lastDataSuccessAt'),
        lastFullSuccessAt: time('lastFullSuccessAt'),
        succeededCourses: json['succeededCourses'] as int? ?? 0,
        failedCourses: json['failedCourses'] as int? ?? 0,
        issues: interrupted
            ? const [SyncIssue(SyncIssueKind.network, '上次同步未完成，请重新读取作业')]
            : (json['issues'] as List? ?? [])
                .map((i) => SyncIssue.fromJson(i as Map<String, dynamic>))
                .toList());
  }
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
