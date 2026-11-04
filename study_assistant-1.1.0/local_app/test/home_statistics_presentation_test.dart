import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_statistics.dart';
import 'package:study_assistant_mobile/src/services/home_sync_presentation.dart';

void main() {
  test('completion rate rounds consistently after splitting expired work', () {
    final stats = AssignmentStatistics([
      for (var i = 0; i < 31; i++)
        Assignment(
            id: 'cx:work:1:2:$i',
            courseName: '课',
            title: '题',
            deadlineAt: i >= 27 ? DateTime(2000) : null,
            requirementsText: '',
            status: i < 20 ? 'submitted' : 'pending',
            lastSyncedAt: DateTime(2026)),
    ], now: DateTime(2026));
    expect(stats.counts, [20, 7, 4, 0]);
    expect(stats.percentages[0], 65);
    expect(stats.percentages.reduce((a, b) => a + b), 100);
  });
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
    expect(stats.counts, [20, 8, 0, 3]);
    expect(stats.total, 31);
    expect(stats.percentages, [65, 26, 0, 9]);
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
      expect(s.percentages, n == 0 ? [0, 0, 0, 0] : [0, 0, 0, 100]);
    }
  });
  test('expired requires confirmed pending and a reliable past deadline', () {
    Assignment work(String status,
            {bool trusted = true, bool failed = false, DateTime? due}) =>
        Assignment(
            id: 'cx:work:1:2:3',
            courseName: '课',
            title: '题',
            deadlineAt: due ?? DateTime(2000),
            deadlineTrusted: trusted,
            deadlineReadFailed: failed,
            requirementsText: '',
            status: status,
            lastSyncedAt: DateTime.now());
    final stats = AssignmentStatistics([
      work('submitted'),
      work('pending'),
      work('returned'),
      work('unknown'),
      work('overdue', trusted: false),
      work('pending', failed: true),
      work('pending', due: DateTime(2100)),
    ]);
    expect(stats.counts, [1, 3, 2, 1]);
    expect(stats.percentages.reduce((a, b) => a + b), 100);
  });
  test('deadline equal to the shared reference instant stays pending', () {
    final now = DateTime.utc(2026, 11, 5, 12);
    final record = Assignment(
        id: 'cx:work:1:2:3',
        courseName: '课',
        title: '题',
        deadlineAt: now,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now);
    expect(AssignmentStatistics([record], now: now).counts, [0, 1, 0, 0]);
    expect(
        AssignmentStatistics([record],
                now: now.add(const Duration(milliseconds: 1)))
            .counts,
        [0, 0, 1, 0]);
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
