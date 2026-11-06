import '../models/assignment.dart';
import '../models/personal_workspace.dart';

/// Reasons describe a preview, never platform submission or an actual schedule.
enum PlanningReason {
  statusUnknown,
  deadlineReadFailed,
  deadlineUntrusted,
  noDeadline,
  overdue,
  deadlineBeforeTarget,
  missingEstimate,
  insufficientBudget,
  existingBudgetUnknown,
  existingBudgetExceeded,
}

class PlanningSuggestion {
  const PlanningSuggestion(this.assignment, this.minutes);
  final Assignment assignment;
  final int minutes;
}

class ManualPlanningItem {
  const ManualPlanningItem(this.assignment, this.reason);
  final Assignment assignment;
  final PlanningReason reason;
}

class PlanningPreview {
  PlanningPreview._(
      this.day,
      this.accountEpoch,
      this.budgetMinutes,
      this.existingMinutes,
      this.remainingMinutes,
      List<PlanningSuggestion> suggested,
      List<ManualPlanningItem> manual,
      List<String> unavailableIds)
      : suggested = List.unmodifiable(suggested),
        manual = List.unmodifiable(manual),
        unavailableIds = List.unmodifiable(unavailableIds);
  final String day;
  final int accountEpoch, budgetMinutes, existingMinutes;

  /// Null means existing unestimated work makes the remainder unknowable.
  final int? remainingMinutes;
  final List<PlanningSuggestion> suggested;
  final List<ManualPlanningItem> manual;
  final List<String> unavailableIds;

  /// Future save callers must also recheck assignment state and obtain consent.
  void ensureCurrentEpoch(int currentEpoch) {
    if (currentEpoch != accountEpoch) throw StateError('账号已变化，请重新生成预览');
  }
}

/// Pure offline calculation: no clock reads, storage, notifications or network.
class RulePlanningService {
  static PlanningPreview preview({
    required List<Assignment> assignments,
    required Set<String> selectedIds,
    required Map<String, int> estimates,
    required List<DailyPlanItem> existingPlans,
    required String day,
    required int budgetMinutes,
    required DateTime now,
    required int accountEpoch,
    Set<String> hiddenIds = const {},
    Set<String> unfollowedCourseKeys = const {},
  }) {
    if (!PersonalWorkspace.validDay(day) ||
        day.compareTo(PersonalWorkspace.dayKey(now)) < 0 ||
        budgetMinutes < 1 ||
        budgetMinutes > 1440) {
      throw ArgumentError('目标日期和总预算无效');
    }
    if (estimates.values.any((v) => v < 0 || v > 1440)) {
      throw ArgumentError('预计耗时应为0至1440分钟，0表示未估算');
    }
    final byId = <String, Assignment>{};
    for (final a in assignments) {
      if (byId.containsKey(a.id)) throw ArgumentError('作业ID重复');
      byId[a.id] = a;
    }
    final existing = <String>{};
    var existingMinutes = 0;
    var unknownExisting = false;
    for (final p in existingPlans.where((p) => p.day == day)) {
      if (!existing.add(p.assignmentId) || p.minutes < 0 || p.minutes > 1440) {
        throw ArgumentError('已有同日计划重复或预计耗时无效');
      }
      if (p.done) continue;
      existingMinutes += p.minutes;
      if (p.minutes == 0) unknownExisting = true;
    }
    var remaining = budgetMinutes - existingMinutes;
    if (remaining < 0) remaining = 0;
    final suggested = <PlanningSuggestion>[];
    final manual = <ManualPlanningItem>[];
    final unavailable =
        selectedIds.where((id) => !byId.containsKey(id)).toList()..sort();
    final candidates = assignments
        .where((a) =>
            selectedIds.contains(a.id) &&
            a.isFormal &&
            !a.isCompleted &&
            !hiddenIds.contains(a.id) &&
            !unfollowedCourseKeys.contains(a.courseKey) &&
            !existing.contains(a.id))
        .toList()
      ..sort((a, b) {
        final x = a.deadlineAt, y = b.deadlineAt;
        final order = x == null
            ? (y == null ? 0 : 1)
            : y == null
                ? -1
                : x.compareTo(y);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
    final targetStart = DateTime.parse('${day}T00:00:00+08:00');
    for (final a in candidates) {
      final d = a.deadlineAt;
      final minutes = estimates[a.id];
      final PlanningReason? reason;
      if (!a.isPendingConfirmed) {
        reason = PlanningReason.statusUnknown;
      } else if (a.deadlineReadFailed) {
        reason = PlanningReason.deadlineReadFailed;
      } else if (!a.deadlineTrusted) {
        reason = PlanningReason.deadlineUntrusted;
      } else if (d == null) {
        reason = PlanningReason.noDeadline;
      } else if (!d.isAfter(now)) {
        reason = PlanningReason.overdue;
      } else if (d.isBefore(targetStart)) {
        reason = PlanningReason.deadlineBeforeTarget;
      } else if (minutes == null || minutes == 0) {
        reason = PlanningReason.missingEstimate;
      } else if (unknownExisting) {
        reason = PlanningReason.existingBudgetUnknown;
      } else if (existingMinutes > budgetMinutes) {
        reason = PlanningReason.existingBudgetExceeded;
      } else if (minutes > remaining) {
        reason = PlanningReason.insufficientBudget;
      } else {
        reason = null;
      }
      if (reason != null) {
        manual.add(ManualPlanningItem(a, reason));
      } else {
        suggested.add(PlanningSuggestion(a, minutes!));
        remaining -= minutes;
      }
    }
    return PlanningPreview._(day, accountEpoch, budgetMinutes, existingMinutes,
        unknownExisting ? null : remaining, suggested, manual, unavailable);
  }
}
