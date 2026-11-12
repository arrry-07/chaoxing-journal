enum SyncPhase { idle, running, success, partial, failed, cancelled }

enum SyncIssueKind {
  network,
  authExpired,
  verificationRequired,
  forbidden,
  notFound,
  rateLimited,
  serverError,
  schemaChanged,
  partial,
  storage,
  notification,
  widget,
  cancelled
}

class SyncIssue {
  const SyncIssue(this.kind, this.message,
      {this.courseKey,
      this.elapsedMs,
      this.httpStatus,
      this.retryAfter,
      this.retryAfterSeconds,
      this.circuitOpen = false,
      this.stage = 'courses'});
  final SyncIssueKind kind;
  final String message, stage;
  final String? courseKey;
  final int? elapsedMs, httpStatus, retryAfterSeconds;

  /// Raw Retry-After header value when the server supplied one.
  final String? retryAfter;
  final bool circuitOpen;

  /// Conservative hint only. The client decides automatic retries from the
  /// status, exception type and retry budget instead of this getter.
  bool get retryable =>
      kind == SyncIssueKind.network || kind == SyncIssueKind.serverError;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'message': message,
        'stage': stage,
        if (courseKey != null) 'courseKey': courseKey,
        if (elapsedMs != null) 'elapsedMs': elapsedMs,
        if (httpStatus != null) 'httpStatus': httpStatus,
        if (retryAfter != null) 'retryAfter': retryAfter,
        if (retryAfterSeconds != null) 'retryAfterSeconds': retryAfterSeconds,
        if (circuitOpen) 'circuitOpen': true,
      };
  factory SyncIssue.fromJson(Map<String, dynamic> json) => SyncIssue(
      SyncIssueKind.values.byName(json['kind'] as String),
      json['message'] as String,
      stage: json['stage'] as String? ?? 'courses',
      courseKey: json['courseKey'] as String?,
      elapsedMs: json['elapsedMs'] as int?,
      httpStatus: json['httpStatus'] as int?,
      retryAfter: json['retryAfter'] as String?,
      retryAfterSeconds: json['retryAfterSeconds'] as int?,
      circuitOpen: json['circuitOpen'] as bool? ?? false);
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

  SyncReport copyWith({
    SyncPhase? phase,
    DateTime? attemptedAt,
    DateTime? lastDataSuccessAt,
    DateTime? lastFullSuccessAt,
    int? succeededCourses,
    int? failedCourses,
    List<SyncIssue>? issues,
  }) =>
      SyncReport(
        phase: phase ?? this.phase,
        attemptedAt: attemptedAt ?? this.attemptedAt,
        lastDataSuccessAt: lastDataSuccessAt ?? this.lastDataSuccessAt,
        lastFullSuccessAt: lastFullSuccessAt ?? this.lastFullSuccessAt,
        succeededCourses: succeededCourses ?? this.succeededCourses,
        failedCourses: failedCourses ?? this.failedCourses,
        issues: issues ?? this.issues,
      );

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
    DateTime? time(String key) =>
        DateTime.tryParse(json[key] as String? ?? '')?.toLocal();
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
        SyncPhase.partial => issues.any((issue) =>
                issue.kind == SyncIssueKind.storage &&
                issue.stage == 'persistence')
            ? '作业数据已保存，但同步状态记录需要处理'
            : '已更新 $succeededCourses 门课程，$failedCourses 门待重试',
        SyncPhase.failed => '本次未能读取作业',
        SyncPhase.cancelled => '本次同步已取消',
        SyncPhase.success => '作业记录已更新',
        SyncPhase.idle => '尚未获取作业',
      };
}

class SyncReadException implements Exception {
  const SyncReadException(this.issue, {this.relatedIssues = const []});
  final SyncIssue issue;
  final List<SyncIssue> relatedIssues;
  Iterable<SyncIssue> get allIssues sync* {
    yield issue;
    yield* relatedIssues;
  }

  @override
  String toString() => issue.message;
}

/// A synchronization was explicitly stopped (logout, Worker cancellation or
/// Store disposal). This is never a legitimate empty result and must not
/// advance the full-success time or be retried as a network failure.
class SyncCancelledException implements Exception {
  const SyncCancelledException();
  @override
  String toString() => '本次同步已取消';
}

/// Memory-only timings for one fixed request category. No URL, query, cookie,
/// account, course/work identifier or response body is retained.
class SyncRequestDiagnostics {
  SyncRequestDiagnostics({
    required this.count,
    required this.failures,
    required this.parseFailures,
    required List<int> httpSamples,
    required List<int> parseSamples,
  })  : httpSamples = List.unmodifiable(httpSamples),
        parseSamples = List.unmodifiable(parseSamples);

  final int count, failures, parseFailures;
  final List<int> httpSamples, parseSamples;

  int get averageHttpMs => _average(httpSamples);
  int get p50HttpMs => _percentile(httpSamples, 50);
  int get p95HttpMs => _percentile(httpSamples, 95);
  int get maxHttpMs =>
      httpSamples.isEmpty ? 0 : httpSamples.reduce((a, b) => a > b ? a : b);

  int get parseCount => parseSamples.length;
  int get averageParseMs => _average(parseSamples);
  int get p50ParseMs => _percentile(parseSamples, 50);
  int get p95ParseMs => _percentile(parseSamples, 95);
  int get maxParseMs =>
      parseSamples.isEmpty ? 0 : parseSamples.reduce((a, b) => a > b ? a : b);

  Map<String, dynamic> toJson() => {
        'count': count,
        'failures': failures,
        'parseFailures': parseFailures,
        'averageHttpMs': averageHttpMs,
        'p50HttpMs': p50HttpMs,
        'p95HttpMs': p95HttpMs,
        'maxHttpMs': maxHttpMs,
        'parseCount': parseCount,
        'averageParseMs': averageParseMs,
        'p50ParseMs': p50ParseMs,
        'p95ParseMs': p95ParseMs,
        'maxParseMs': maxParseMs,
      };

  static int _average(List<int> values) => values.isEmpty
      ? 0
      : (values.reduce((a, b) => a + b) / values.length).round();

  static int _percentile(List<int> values, int percentile) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.of(values)..sort();
    final rank = ((percentile / 100) * sorted.length).ceil() - 1;
    return sorted[rank.clamp(0, sorted.length - 1)];
  }
}

class SyncDiagnostics {
  const SyncDiagnostics({this.fullSyncElapsedMs, this.requests = const {}});

  final int? fullSyncElapsedMs;
  final Map<String, SyncRequestDiagnostics> requests;

  Map<String, dynamic> toJson() => {
        'fullSyncElapsedMs': fullSyncElapsedMs,
        'requests': {
          for (final entry in requests.entries) entry.key: entry.value.toJson()
        },
      };
}
