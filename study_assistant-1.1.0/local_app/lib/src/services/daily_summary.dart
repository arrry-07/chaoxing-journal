import '../models/assignment.dart';
import '../models/personal_workspace.dart';

class SummaryNotice {
  const SummaryNotice(this.id, this.at, this.body);
  final int id;
  final DateTime at;
  final String body;
}

class DailySummary {
  static const baseId = 1900000000;
  static List<SummaryNotice> build(List<Assignment> rows,
      PersonalWorkspace personal, DateTime now, DateTime? synced) {
    if (!personal.summaryEnabled) return [];
    final beijing = now.toUtc().add(const Duration(hours: 8));
    final result = <SummaryNotice>[];
    for (var i = 0; result.length < 7; i++) {
      final local = DateTime.utc(beijing.year, beijing.month, beijing.day + i,
          personal.summaryHour, personal.summaryMinute);
      final at = local.subtract(const Duration(hours: 8));
      if (!at.isAfter(now)) continue;
      final day = PersonalWorkspace.dayKey(at);
      final due = rows
          .where((a) =>
              !a.isCompleted &&
              a.deadlineTrusted &&
              !a.deadlineReadFailed &&
              a.deadlineAt != null &&
              PersonalWorkspace.dayKey(a.deadlineAt!) == day)
          .length;
      final plans = personal.plans.where((p) => p.day == day && !p.done).length;
      final stamp = synced == null ? '尚未同步' : PersonalWorkspace.dayKey(synced);
      result.add(SummaryNotice(baseId + result.length, at,
          '今日截止 $due 项 · 个人计划 $plans 项。基于 $stamp 本机快照，请打开应用刷新核对。'));
    }
    return result;
  }
}

class ReminderHealth {
  const ReminderHealth(
      {this.notifications,
      this.exact,
      this.channelEnabled,
      this.pending,
      this.summaryPending});
  final bool? notifications, exact, channelEnabled;
  final int? pending, summaryPending;
}
