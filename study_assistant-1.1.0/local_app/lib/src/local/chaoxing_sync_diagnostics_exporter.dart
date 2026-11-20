import 'dart:convert';
import 'dart:math' as math;

import '../models/sync_report.dart';
import '../services/sync_issue_presentation.dart';

class ChaoxingSyncDiagnosticsExporter {
  const ChaoxingSyncDiagnosticsExporter._();

  /// Exports structural diagnostics only. Never include account identifiers,
  /// cookies, tokens, course names, assignment titles, or raw notice text.
  static String exportJson({
    required String appVersion,
    required SyncReport report,
    required Map<String, int> phaseElapsedMs,
    required Map<String, ({int count, int elapsedMs, int httpFailures})>
        requestTimings,
    DateTime? now,
  }) {
    final groups = groupSyncIssues(report.issues);
    final verification = report.issues
        .where((issue) => issue.kind == SyncIssueKind.verificationRequired)
        .firstOrNull;
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'exportedAtUtc': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'appVersion': appVersion,
      'syncPhase': report.phase.name,
      if (verification != null) 'verificationRequiredStage': verification.stage,
      'attemptedAtUtc': report.attemptedAt?.toUtc().toIso8601String(),
      'lastDataSuccessAtUtc':
          report.lastDataSuccessAt?.toUtc().toIso8601String(),
      'lastFullSuccessAtUtc':
          report.lastFullSuccessAt?.toUtc().toIso8601String(),
      'succeededCourses': report.succeededCourses,
      'failedCourses': report.failedCourses,
      'phaseElapsedMs': phaseElapsedMs,
      'requestTimings': {
        for (final entry in requestTimings.entries)
          entry.key: {
            'count': entry.value.count,
            'elapsedMs': entry.value.elapsedMs,
            'httpFailures': entry.value.httpFailures,
          },
      },
      'sources': [
        for (final source in report.sourceResults)
          {
            'source': source.source,
            'phase': source.phase.name,
            'succeededCourses': source.succeededCourses,
            'failedCourses': source.failedCourses,
            'recordCount': source.recordCount,
            'unconfirmedCount': source.unconfirmedCount,
            'reasonCodes': source.reasonCodes,
          },
      ],
      'issueGroups': [
        for (final group in groups)
          {
            'stage': group.stage,
            'kind': group.kind.name,
            'count': group.count,
            'circuitOpen': group.issues.any((issue) => issue.circuitOpen),
            if (group.issues.any((issue) => issue.retryAfterSeconds != null))
              'maxRetryAfterSeconds': group.issues
                  .map((issue) => issue.retryAfterSeconds)
                  .whereType<int>()
                  .reduce(math.max),
            'httpStatuses': {
              for (final issue in group.issues)
                if (issue.httpStatus != null) issue.httpStatus!,
            }.toList()
              ..sort(),
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
