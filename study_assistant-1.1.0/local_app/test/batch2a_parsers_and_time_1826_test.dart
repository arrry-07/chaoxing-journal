import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/services/daytime_check_policy.dart';

Assignment _row(String title, DateTime deadline) => Assignment(
      id: 'cx:work:1:2:$title',
      courseName: '同一课程',
      title: title,
      deadlineAt: deadline,
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime(2026, 11, 8),
    );

void main() {
  final due = DateTime(2026, 11, 11, 9);

  test('FB-005 course ordering breaks same-instant ties for every input order',
      () {
    final rows = [_row('A', due), _row('B', due.toUtc()), _row('C', due)];
    const permutations = [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];
    for (final indexes in permutations) {
      final ordered = AssignmentQuery.sortHome(
        indexes.map((i) => rows[i]).toList(),
        HomeSortOrder.courseName,
        now: DateTime(2026, 11, 10),
      );
      expect(ordered.map((row) => row.title), ['A', 'B', 'C'],
          reason: 'input order $indexes');
    }
  });

  test('deadline change ignores UTC and local views of one instant', () {
    final original = _row('A', due);
    final updated = _row('A', due.toUtc());
    expect(
      AssignmentChange.compare([original], [updated], {updated.id}, due),
      isEmpty,
    );
  });

  test('assignment reminder buckets a UTC deadline in the device zone', () {
    final row = _row('A', due.toUtc());
    final plan = AssignmentReminderPlanner.planAfterSync(
      accountHash: 'account-hash',
      sessionEpoch: 1,
      assignments: [row],
      hiddenAssignmentIds: const {},
      unfollowedCourseKeys: const {},
      knownAssignmentIds: {row.id},
      sentNewAssignmentIds: const {},
      baselineCompleted: true,
      completeSync: true,
      detectNewAssignments: false,
      newAssignmentReminderEnabled: false,
      reminderOffsetsMinutes: const [180],
      now: DateTime(2026, 11, 10, 20),
    );
    expect(plan.deadlineEvents.single.notifyAt, DateTime(2026, 11, 11, 7, 30));
  });

  test('daytime check uses local date and hour for UTC clock inputs', () {
    final local = DateTime(2026, 11, 11, 8);
    expect(DaytimeCheckPolicy.isInWindow(local.toUtc()), isTrue);
    expect(
      DaytimeCheckPolicy.isInWindow(
          local.subtract(const Duration(seconds: 1)).toUtc()),
      isFalse,
    );
    expect(
      DaytimeCheckPolicy.nextTarget(
        localNow: local.toUtc(),
        lastAttemptAt: null,
        intervalMinutes: 240,
      ),
      local,
    );
    expect(
      DaytimeCheckPolicy.nextAfterExecution(
        DateTime(2026, 11, 11, 23, 30).toUtc(),
        240,
      ),
      DateTime(2026, 11, 12, 8),
    );
  });

  test('stored UTC timestamps reopen as local instants', () {
    final entry = ManualEntry(id: 'one', title: '笔记', kind: 'todo', at: due);
    expect(ManualEntry.fromJson(entry.toJson()).at, due);
  });

  test('change log timestamps reopen as local instants', () {
    final change = AssignmentChange(
      assignmentId: 'one',
      title: '作业',
      courseName: '课程',
      kind: AssignmentChangeKind.deadline,
      at: due,
      before: '',
      after: '新时间',
    );
    expect(AssignmentChange.fromJson(change.toJson()).at, due);
  });

  test('daily summary projects Beijing delivery to a device-local instant', () {
    final schedule = DailySummary.build(
      const [],
      PersonalWorkspace(summaryEnabled: true, summaryHour: 20),
      DateTime.utc(2026, 11, 11, 11),
      null,
    );
    expect(schedule.first.at, DateTime.utc(2026, 11, 11, 12).toLocal());
  });
}
