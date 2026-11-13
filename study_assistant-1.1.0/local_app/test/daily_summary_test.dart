import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

void main() {
  test('summary disabled by default, seven bounded stable IDs when enabled',
      () {
    final now = DateTime.utc(2026, 11, 6, 13);
    expect(DailySummary.build([], PersonalWorkspace(), now, null), isEmpty);
    final p = PersonalWorkspace(summaryEnabled: true, summaryHour: 20);
    final rows = DailySummary.build([], p, now, null);
    expect(rows.length, 7);
    expect(rows.first.at, DateTime.utc(2026, 11, 7, 12));
    expect(rows.map((r) => r.id).toSet().length, 7);
    expect(
        rows.map((r) => r.id),
        DailySummary.build([], p, now.add(const Duration(minutes: 1)), null)
            .map((r) => r.id));
  });
  test('snapshot counts do not confuse personal completion with submission',
      () {
    final at = DateTime.utc(2026, 11, 6, 12);
    final a = Assignment(
        id: 'x',
        title: 'private-title',
        courseName: 'private-course',
        status: 'pending',
        requirementsText: '',
        deadlineAt: at,
        deadlineTrusted: true,
        lastSyncedAt: at);
    final p = PersonalWorkspace(
        summaryEnabled: true,
        plans: [const DailyPlanItem('x', '2026-11-06', 30, done: true)]);
    final r =
        DailySummary.build([a], p, at.subtract(const Duration(hours: 2)), at)
            .first;
    expect(r.body, contains('今日截止 1 项'));
    expect(r.body, contains('个人计划 0 项'));
    expect(r.body, isNot(contains('private')));
  });

  test('summary excludes status-conflict dates from trusted due counts', () {
    final now = DateTime.utc(2026, 11, 6, 13);
    final due = DateTime.utc(2026, 11, 7, 12);
    final p = PersonalWorkspace(summaryEnabled: true, summaryHour: 20);
    Assignment row(String id, String status) => Assignment(
          id: 'cx:work:1:2:$id',
          title: id,
          courseName: '课程',
          status: status,
          requirementsText: '',
          deadlineAt: due,
          deadlineTrusted: true,
          lastSyncedAt: now,
        );

    final summary = DailySummary.build(
            [row('unknown', 'unknown'), row('overdue', 'overdue')], p, now, now)
        .first;

    expect(summary.body, contains('今日截止 0 项'));
  });
}
