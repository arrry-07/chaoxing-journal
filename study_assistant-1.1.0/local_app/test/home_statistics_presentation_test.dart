import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_statistics.dart';
import 'package:study_assistant_mobile/src/services/home_sync_presentation.dart';

void main() {
  test('statistics partitions 31 records and percentages sum to 100', () {
    final stats = AssignmentStatistics([
      for (var i = 0; i < 31; i++)
        Assignment(
            id: 'cx:work:1:2:$i',
            courseName: '课',
            title: '题',
            deadlineAt: null,
            requirementsText: '',
            status: i < 20
                ? 'submitted'
                : i < 28
                    ? 'returned'
                    : 'unknown',
            lastSyncedAt: DateTime.now())
    ]);
    expect(stats.counts, [20, 8, 3]);
    expect(stats.total, 31);
    expect(stats.percentages, [64, 26, 10]);
    for (final n in [0, 1, 1000]) {
      final s = AssignmentStatistics([
        for (var i = 0; i < n; i++)
          Assignment(
              id: 'cx:work:1:2:$i',
              courseName: '课',
              title: '题',
              deadlineAt: null,
              requirementsText: '',
              status: 'unknown',
              lastSyncedAt: DateTime.now())
      ]);
      expect(s.percentages, n == 0 ? [0, 0, 0] : [0, 0, 100]);
    }
  });
  test('sync actions match auth, verification, retry, and running cache states',
      () {
    final now = DateTime.now();
    for (final cache in [false, true]) {
      for (final pair in [
        (SyncIssueKind.authExpired, HomeSyncAction.login),
        (SyncIssueKind.verificationRequired, HomeSyncAction.verify),
        (SyncIssueKind.network, HomeSyncAction.retry)
      ]) {
        final p = HomeSyncPresentation.from(
            SyncReport(
                phase: SyncPhase.failed,
                issues: [SyncIssue(pair.$1, 'fixture')]),
            loading: false,
            hasCache: cache,
            now: now);
        expect(p.action, pair.$2);
        expect(p.showCached, cache);
      }
      final p = HomeSyncPresentation.from(
          const SyncReport(phase: SyncPhase.running),
          loading: true,
          hasCache: cache,
          now: now);
      expect(p.action, HomeSyncAction.none);
      expect(p.summary, cache ? '正在更新…' : '正在读取作业…');
    }
  });
}
