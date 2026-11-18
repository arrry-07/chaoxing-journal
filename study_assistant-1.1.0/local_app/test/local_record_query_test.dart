import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/services/assignment_statistics.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/local_record_query.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'review_core_remediation_test.dart' as f;

class _NoopNotifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

Assignment _work({
  required String id,
  String courseId = '1',
  String clazzId = '2',
  String courseName = '高等数学',
  required String title,
  required String status,
  DateTime? deadlineAt,
  bool deadlineTrusted = true,
  bool deadlineReadFailed = false,
  DateTime? lastSyncedAt,
}) =>
    Assignment(
      id: 'cx:work:$courseId:$clazzId:$id',
      courseName: courseName,
      title: title,
      deadlineAt: deadlineAt,
      deadlineTrusted: deadlineTrusted,
      deadlineReadFailed: deadlineReadFailed,
      requirementsText: '',
      status: status,
      lastSyncedAt: lastSyncedAt ?? DateTime.utc(2026, 11, 17, 0),
    );

Assignment _exam({
  required String examId,
  String? courseId = '1',
  String? clazzId = '2',
  bool accountOnly = false,
  String courseName = '高等数学',
  required String title,
  String status = 'pending',
  DateTime? startAt,
  bool startTrusted = true,
  String lifecycle = 'scheduled',
  bool noticeOnly = false,
  String? relatedExamId,
}) =>
    Assignment(
      id: noticeOnly
          ? 'cx:examNotice:inbox:$examId'
          : accountOnly
              ? 'cx:exam:account:account:$examId'
              : 'cx:exam:$courseId:$clazzId:$examId',
      source: AssignmentSource.exam,
      courseName: courseName,
      title: title,
      deadlineAt: null,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.utc(2026, 11, 17, 0),
      exam: ExamInfo(
        examId: examId,
        relatedExamId: relatedExamId,
        courseId: accountOnly ? null : courseId,
        clazzId: accountOnly ? null : clazzId,
        startAt: startAt,
        startTrusted: startTrusted,
        lifecycle: lifecycle,
        noticeOnly: noticeOnly,
      ),
    );

void main() {
  test(
      'StatsTimeRange uses DST-safe Beijing calendar boundaries and excludes untrusted times',
      () {
    // UTC 2026-11-01 00:00 -> Beijing 2026-11-01 08:00 (also US DST fall-back day).
    final now = DateTime.utc(2026, 11, 1, 0, 0);
    // 7-day window in Beijing: [2026-11-01, 2026-11-08)
    final todayEarlierOverdue = _work(
      id: 'today-overdue',
      title: '今天早些时候已逾期',
      status: 'pending',
      // Beijing 2026-11-01 06:00
      deadlineAt: DateTime.utc(2026, 10, 31, 22, 0),
    );
    final yesterday = _work(
      id: 'yesterday',
      title: '昨天截止',
      status: 'pending',
      // Beijing 2026-10-31 23:59
      deadlineAt: DateTime.utc(2026, 10, 31, 15, 59),
    );
    final day6Completed = _work(
      id: 'day6-done',
      title: '第7天内已完成',
      status: 'submitted',
      // Beijing 2026-11-07 23:59
      deadlineAt: DateTime.utc(2026, 11, 7, 15, 59),
    );
    final day7Outside = _work(
      id: 'day7-outside',
      title: '第8天边界外',
      status: 'pending',
      // Beijing 2026-11-08 00:00
      deadlineAt: DateTime.utc(2026, 11, 7, 16, 0),
    );
    final day29Inside30 = _work(
      id: 'day29-inside',
      title: '第30天边界内',
      status: 'pending',
      // Beijing 2026-11-30 23:00
      deadlineAt: DateTime.utc(2026, 11, 30, 15, 0),
    );
    final day30Outside30 = _work(
      id: 'day30-outside',
      title: '第31天边界外',
      status: 'pending',
      // Beijing 2026-12-01 00:00
      deadlineAt: DateTime.utc(2026, 11, 30, 16, 0),
    );
    final undated = _work(
      id: 'undated',
      title: '无截止日期',
      status: 'pending',
      deadlineAt: null,
    );
    final untrusted = _work(
      id: 'untrusted',
      title: '年份待确认',
      status: 'pending',
      deadlineAt: DateTime.utc(2026, 11, 3, 4, 0),
      deadlineTrusted: false,
    );
    final readFailed = _work(
      id: 'read-failed',
      title: '读取失败保留旧值',
      status: 'pending',
      deadlineAt: DateTime.utc(2026, 11, 3, 4, 0),
      deadlineReadFailed: true,
    );

    final all = [
      todayEarlierOverdue,
      yesterday,
      day6Completed,
      day7Outside,
      day29Inside30,
      day30Outside30,
      undated,
      untrusted,
      readFailed,
    ];

    final seven = LocalRecordQuery.filterStatsRecords(
      all,
      StatsTimeRange.next7Days,
      now,
    );
    expect(seven.records.map((a) => a.title), ['今天早些时候已逾期', '第7天内已完成']);
    expect(seven.excludedUnscheduledCount, 3);

    final thirty = LocalRecordQuery.filterStatsRecords(
      all,
      StatsTimeRange.next30Days,
      now,
    );
    expect(
      thirty.records.map((a) => a.title),
      ['今天早些时候已逾期', '第7天内已完成', '第8天边界外', '第30天边界内'],
    );
    expect(thirty.excludedUnscheduledCount, 3);

    final full = LocalRecordQuery.filterStatsRecords(
      all,
      StatsTimeRange.all,
      now,
    );
    expect(full.records, hasLength(all.length));
    expect(full.excludedUnscheduledCount, 0);
  });

  test('LocalRecordQuery status counts match AssignmentStatistics buckets 1:1',
      () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final now = DateTime.utc(2026, 11, 17, 2);
    final store = AssignmentStore(
      sessionStore: SecureSessionStore(),
      notificationService: _NoopNotifications(),
      widgetSnapshotService: _NoopWidgets(),
    );
    addTearDown(store.dispose);

    final wDone = _work(
      id: '1',
      courseId: '10',
      clazzId: '2',
      courseName: '高等数学',
      title: 'Completed Task',
      status: 'submitted',
      deadlineAt: now.add(const Duration(days: 2)),
    );
    final wPending = _work(
      id: '2',
      courseId: '10',
      clazzId: '3',
      courseName: '高等数学',
      title: 'Pending Class 3',
      status: 'pending',
      deadlineAt: now.add(const Duration(days: 3)),
    );
    final wOverdue = _work(
      id: '3',
      courseId: '10',
      clazzId: '2',
      courseName: '高等数学',
      title: 'Overdue Task',
      status: 'pending',
      deadlineAt: now.subtract(const Duration(days: 1)),
    );
    final wUnknown = _work(
      id: '4',
      courseId: '10',
      clazzId: '2',
      courseName: '高等数学',
      title: 'Unknown Task',
      status: 'unknown',
      deadlineAt: now.add(const Duration(days: 1)),
    );
    final accExam = _exam(
      examId: '9001',
      accountOnly: true,
      courseName: '账号考试',
      title: '全校外语水平考试',
      status: 'pending',
      startAt: now.add(const Duration(days: 5)),
    );
    final unfollowedWork = _work(
      id: '5',
      courseId: '99',
      clazzId: '1',
      courseName: '已退选选修课',
      title: 'Unfollowed Work',
      status: 'pending',
      deadlineAt: now.add(const Duration(days: 1)),
    );
    final unsupportedActivity = Assignment(
      id: 'cx:activity:10:2:888',
      source: AssignmentSource.classroomActivity,
      activityType: 99,
      courseName: '高等数学',
      title: 'Unsupported Activity',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );

    store.replaceAssignmentsForTest([
      wDone,
      wPending,
      wOverdue,
      wUnknown,
      accExam,
      unfollowedWork,
      unsupportedActivity,
    ]);
    await store.followCourse('99:1', false);

    // Overview buckets on Stats assignments must match LocalRecordQuery(followedStats) 1:1.
    final stats = AssignmentStatistics(store.statsAssignments, now: now);
    expect(stats.completed, 1);
    expect(stats.pending, 2); // wPending + accExam
    expect(stats.expired, 1);
    expect(stats.unknown, 1);

    for (final entry in {
      LocalRecordStatusFilter.completed: stats.completed,
      LocalRecordStatusFilter.pending: stats.pending,
      LocalRecordStatusFilter.overdue: stats.expired,
      LocalRecordStatusFilter.unknown: stats.unknown,
    }.entries) {
      final result = LocalRecordQuery.query(
        store,
        LocalRecordFilterSpec(
          scope: LocalRecordScopeFilter.followedStats,
          status: entry.key,
        ),
        now,
      );
      expect(result.groups.length, entry.value, reason: '${entry.key}');
    }

    // Same-name classes distinguish courseKey 10:2 vs 10:3.
    final class2Unfinished = LocalRecordQuery.query(
      store,
      const LocalRecordFilterSpec(
        scope: LocalRecordScopeFilter.followedStats,
        courseKey: '10:2',
        status: LocalRecordStatusFilter.unfinished,
      ),
      now,
    );
    expect(
      class2Unfinished.groups.map((g) => g.primary.id),
      [wUnknown.id, wOverdue.id],
    );

    final sortedByLastSync = LocalRecordQuery.query(
      store,
      const LocalRecordFilterSpec(sort: LocalRecordSortOrder.lastSyncedDesc),
      now,
    );
    expect(sortedByLastSync.groups, isNotEmpty);

    final class3Unfinished = LocalRecordQuery.query(
      store,
      const LocalRecordFilterSpec(
        scope: LocalRecordScopeFilter.followedStats,
        courseKey: '10:3',
        status: LocalRecordStatusFilter.unfinished,
      ),
      now,
    );
    expect(class3Unfinished.groups.map((g) => g.primary.id), [wPending.id]);

    // Account exam scope only matches account exam.
    final accountExamResult = LocalRecordQuery.query(
      store,
      const LocalRecordFilterSpec(
        scope: LocalRecordScopeFilter.accountExam,
        status: LocalRecordStatusFilter.unfinished,
      ),
      now,
    );
    expect(accountExamResult.groups.map((g) => g.primary.id), [accExam.id]);

    // Case-insensitive search matches lowercase/uppercase.
    final searchResult = LocalRecordQuery.query(
      store,
      const LocalRecordFilterSpec(query: 'pending CLASS'),
      now,
    );
    expect(searchResult.groups.map((g) => g.primary.id), [wPending.id]);

    // Course options disambiguate duplicate course names by clazzId.
    expect(
      class2Unfinished.courseOptions
          .where((o) => o.courseKey.startsWith('10:'))
          .map((o) => o.label)
          .toList(),
      ['高等数学 · 班级 2', '高等数学 · 班级 3'],
    );
  });

  test('DisplayPreferences.forWidget 7-day range respects DST calendar days',
      () {
    // 2026-11-01 00:00 UTC -> 08:00 Beijing on a US DST fall-back transition week
    final now = DateTime.utc(2026, 11, 1, 0, 0);
    final day6LastMinute = _work(
      id: 'd6',
      title: '第7天晚上',
      status: 'pending',
      deadlineAt: DateTime.utc(2026, 11, 7, 15, 30), // Beijing Nov 7 23:30
    );
    final res = const DisplayPreferences(widgetRange: WidgetRange.week)
        .forWidget([day6LastMinute], now);
    expect(res.map((a) => a.id), [day6LastMinute.id]);
  });

  test(
      'LocalRecordFilterSpec parses status=hidden and stats drill-down params cleanly',
      () {
    final hidden = LocalRecordFilterSpec.fromQueryParameters(
      const {'status': 'hidden'},
    );
    expect(hidden.category, LocalRecordCategory.hidden);
    expect(hidden.status, LocalRecordStatusFilter.all);

    final stats = LocalRecordFilterSpec.fromQueryParameters(const {
      'from': 'stats',
      'scope': 'followedStats',
      'status': 'unfinished',
      'courseKey': '10:2',
      'range': 'next7Days',
    });
    expect(stats.from, 'stats');
    expect(stats.category, LocalRecordCategory.coursework);
    expect(stats.scope, LocalRecordScopeFilter.followedStats);
    expect(stats.status, LocalRecordStatusFilter.unfinished);
    expect(stats.courseKey, '10:2');
    expect(stats.timeRange, StatsTimeRange.next7Days);
    expect(stats.isStatsScoped, isTrue);

    final reset = stats.resetToAllLocal();
    expect(reset.scope, LocalRecordScopeFilter.allLocal);
    expect(reset.status, LocalRecordStatusFilter.all);
    expect(reset.courseKey, isNull);
    expect(reset.timeRange, StatsTimeRange.all);
  });

  test(
      'findAnyAssignment resolves hidden records while findAssignment remains visible-only',
      () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: _NoopNotifications(),
      widgetSnapshotService: _NoopWidgets(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final target = _work(
      id: 'h1',
      title: '隐藏记录',
      status: 'pending',
    );
    await store.repository.mergeAndSave([target]);
    await store.refreshAssignments();
    expect(store.findAssignment(target.id), isNotNull);

    await store.setAssignmentsHidden([target.id], true);
    expect(store.findAssignment(target.id), isNull);
    expect(store.findAnyAssignment(target.id)?.id, target.id);
    expect(store.courseworkGroupFor(target.id)?.hidden, isTrue);
  });
}
