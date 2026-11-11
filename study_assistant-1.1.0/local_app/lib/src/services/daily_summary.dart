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

enum ReminderChannelStatus {
  enabled,
  disabled,
  missing,
  unsupported,
  queryFailed,
}

class ReminderChannelHealth {
  const ReminderChannelHealth(this.status, {this.importance});

  final ReminderChannelStatus status;
  final int? importance;

  bool? get enabled => switch (status) {
        ReminderChannelStatus.enabled => true,
        ReminderChannelStatus.disabled => false,
        _ => null,
      };

  String get label => switch (status) {
        ReminderChannelStatus.enabled => switch (importance) {
            1 => '已开启（最低重要性）',
            2 => '已开启（低重要性）',
            3 => '已开启（默认重要性）',
            4 => '已开启（高重要性）',
            5 => '已开启（最高重要性）',
            _ => '已开启',
          },
        ReminderChannelStatus.disabled => '已关闭（系统设置）',
        ReminderChannelStatus.missing => '渠道未创建（请重新初始化提醒）',
        ReminderChannelStatus.unsupported => '系统不支持通知渠道',
        ReminderChannelStatus.queryFailed => '读取失败，请重新体检',
      };
}

class ReminderHealth {
  const ReminderHealth(
      {this.notifications,
      this.exact,
      this.assignmentChannel,
      this.assignmentUpdatesChannel,
      this.summaryChannel,
      this.manualChannel,
      this.pending,
      this.summaryPending,
      this.manualPending,
      this.scheduleRecoveryPending = false});

  final bool? notifications, exact;
  final ReminderChannelHealth? assignmentChannel,
      assignmentUpdatesChannel,
      summaryChannel,
      manualChannel;
  final int? pending, summaryPending, manualPending;
  final bool scheduleRecoveryPending;

  // Missing, unsupported and failed channel checks must not collapse to false.
  bool? get channelEnabled => assignmentChannel?.enabled;
  bool? get assignmentUpdatesChannelEnabled =>
      assignmentUpdatesChannel?.enabled;
  bool? get summaryChannelEnabled => summaryChannel?.enabled;
  bool? get manualChannelEnabled => manualChannel?.enabled;
}
