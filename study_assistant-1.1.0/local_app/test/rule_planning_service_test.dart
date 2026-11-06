import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/rule_planning_service.dart';

final now = DateTime.utc(2026, 11, 6, 16); // Beijing November 7 midnight.
Assignment work(String id, {DateTime? due, String status = 'pending'}) =>
    Assignment(
        id: 'cx:work:1:2:$id',
        title: '合成$id',
        courseName: '合成课程',
        deadlineAt: due ?? now.add(const Duration(days: 1)),
        requirementsText: '',
        status: status,
        lastSyncedAt: now);
PlanningPreview preview(List<Assignment> rows,
        {int budget = 60,
        Map<String, int>? minutes,
        List<DailyPlanItem> plans = const [],
        String day = '2026-11-07',
        Set<String> hidden = const {},
        Set<String> unfollowed = const {}}) =>
    RulePlanningService.preview(
        assignments: rows,
        selectedIds: rows.map((a) => a.id).toSet(),
        estimates: minutes ?? {for (final a in rows) a.id: 20},
        existingPlans: plans,
        day: day,
        budgetMinutes: budget,
        now: now,
        accountEpoch: 7,
        hiddenIds: hidden,
        unfollowedCourseKeys: unfollowed);
void main() {
  test(
      'exact current deadline is overdue and future day midnight is in its date range',
      () {
    expect(preview([work('now', due: now)]).manual.single.reason,
        PlanningReason.overdue);
    final nextMidnight = DateTime.utc(2026, 11, 7, 16);
    final r = preview([work('midnight', due: nextMidnight)], day: '2026-11-08');
    expect(r.suggested.single.assignment.deadlineAt, nextMidnight);
  });
  test('stable deadline then ID ordering and deterministic budget packing', () {
    final a = work('a'),
        b = work('b'),
        c = work('c', due: now.add(const Duration(days: 2)));
    final r =
        preview([c, b, a], budget: 30, minutes: {a.id: 40, b.id: 20, c.id: 10});
    expect(r.suggested.map((e) => e.assignment.id), [b.id, c.id]);
    expect(r.manual.single.reason, PlanningReason.insufficientBudget);
    expect(r.remainingMinutes, 0);
    expect(() => r.suggested.clear(), throwsUnsupportedError);
  });
  test(
      'unfinished existing plans consume total budget and same-day rows are not duplicated',
      () {
    final a = work('a'), b = work('b');
    final r = preview([a, b],
        budget: 30,
        plans: [
          DailyPlanItem(a.id, '2026-11-07', 20),
          const DailyPlanItem('other', '2026-11-07', 100, done: true),
          const DailyPlanItem('tomorrow', '2026-11-08', 100)
        ]);
    expect(r.existingMinutes, 20);
    expect(r.suggested, isEmpty);
    expect(r.manual.single.assignment.id, b.id);
    expect(r.manual.single.reason, PlanningReason.insufficientBudget);
  });
  test('unknown existing estimate blocks suggestions instead of assuming zero',
      () {
    final r = preview([work('a')],
        plans: [const DailyPlanItem('existing', '2026-11-07', 0)]);
    expect(r.remainingMinutes, isNull);
    expect(r.manual.single.reason, PlanningReason.existingBudgetUnknown);
  });
  test('existing overbudget preserves plans and prevents additions', () {
    final r = preview([work('a')],
        plans: [const DailyPlanItem('existing', '2026-11-07', 100)]);
    expect(r.remainingMinutes, 0);
    expect(r.manual.single.reason, PlanningReason.existingBudgetExceeded);
  });
  test(
      'uncertainty, old deadlines and missing estimates are never auto planned',
      () {
    final rows = [
      work('unknown', status: 'unknown'),
      work('failed').copyWith(deadlineReadFailed: true),
      work('untrusted').copyWith(deadlineTrusted: false),
      work('none').copyWith(clearDeadlineAt: true),
      work('old', due: now.subtract(const Duration(seconds: 1))),
      work('missing')
    ];
    final r = preview(rows, minutes: {});
    expect(r.suggested, isEmpty);
    expect(r.manual.map((e) => e.reason).toSet(), {
      PlanningReason.statusUnknown,
      PlanningReason.deadlineReadFailed,
      PlanningReason.deadlineUntrusted,
      PlanningReason.noDeadline,
      PlanningReason.overdue,
      PlanningReason.missingEstimate
    });
  });
  test('exclude hidden, unfollowed, completed, nonformal and unselected', () {
    final a = work('a');
    final rows = [
      a,
      work('done', status: 'submitted'),
      work('activity').copyWith(id: 'cx:activity:1:2:3')
    ];
    expect(preview(rows, hidden: {a.id}).suggested, isEmpty);
    expect(preview([a], unfollowed: {'1:2'}).suggested, isEmpty);
    final r = RulePlanningService.preview(
        assignments: [a],
        selectedIds: {},
        estimates: {a.id: 20},
        existingPlans: [],
        day: '2026-11-07',
        budgetMinutes: 30,
        now: now,
        accountEpoch: 7);
    expect(r.suggested, isEmpty);
  });
  test('future target excludes deadlines before its Beijing midnight', () {
    final a = work('a', due: DateTime.utc(2026, 11, 7, 15, 59));
    final r = preview([a], day: '2026-11-08');
    expect(r.manual.single.reason, PlanningReason.deadlineBeforeTarget);
  });
  test('invalid budget, date, estimates and duplicate inputs fail explicitly',
      () {
    final a = work('a');
    for (final budget in [0, -1, 1441]) {
      expect(() => preview([a], budget: budget), throwsArgumentError);
    }
    for (final day in ['2026-02-30', '2026-11-06', 'bad']) {
      expect(() => preview([a], day: day), throwsArgumentError);
    }
    expect(() => preview([a], minutes: {a.id: -1}), throwsArgumentError);
    expect(() => preview([a, a]), throwsArgumentError);
  });
  test('permutations preserve decisions and preview never mutates caller data',
      () {
    final a = work('a'), b = work('b'), c = work('c');
    final rows = [c, b, a];
    final estimates = {a.id: 20, b.id: 20, c.id: 20};
    final plans = [const DailyPlanItem('existing', '2026-11-07', 10)];
    final baseline =
        preview(rows, budget: 50, minutes: estimates, plans: plans);
    for (final order in [
      [a, b, c],
      [b, c, a],
      [c, a, b]
    ]) {
      final next = preview(order, budget: 50, minutes: estimates, plans: plans);
      expect(next.suggested.map((e) => e.assignment.id).toList(),
          baseline.suggested.map((e) => e.assignment.id).toList());
      expect(
          next.existingMinutes +
              next.suggested.fold<int>(0, (v, e) => v + e.minutes),
          lessThanOrEqualTo(50));
    }
    expect(rows.map((a) => a.id), [c.id, b.id, a.id]);
    expect(estimates, {a.id: 20, b.id: 20, c.id: 20});
    expect(plans.single.minutes, 10);
    expect(() => baseline.manual.clear(), throwsUnsupportedError);
    rows.clear();
    estimates.clear();
    plans.clear();
    expect(baseline.suggested.length, 2);
  });
  test('zero estimate is not zero-cost work and unknown selection is explicit',
      () {
    final a = work('a');
    expect(preview([a], minutes: {a.id: 0}).manual.single.reason,
        PlanningReason.missingEstimate);
    final r = RulePlanningService.preview(
        assignments: [a],
        selectedIds: {'missing'},
        estimates: {},
        existingPlans: [],
        day: '2026-11-07',
        budgetMinutes: 30,
        now: now,
        accountEpoch: 7);
    expect(r.unavailableIds, ['missing']);
    expect(() => r.unavailableIds.clear(), throwsUnsupportedError);
    expect(r.suggested, isEmpty);
    expect(() => preview([a], minutes: {a.id: 1441}), throwsArgumentError);
    expect(
        () => preview([
              a
            ], plans: [
              DailyPlanItem(a.id, '2026-11-07', 20),
              DailyPlanItem(a.id, '2026-11-07', 20)
            ]),
        throwsArgumentError);
  });
  test(
      'preview carries epoch and rejects stale confirmation without writing anything',
      () {
    final r = preview([work('a')]);
    expect(() => r.ensureCurrentEpoch(8), throwsStateError);
    r.ensureCurrentEpoch(7);
  });
}
