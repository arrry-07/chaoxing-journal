import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import '../models/personal_workspace.dart';
import 'assignment_reminder_planner.dart';
import 'coursework_deadline.dart';

class SummaryNotice {
  const SummaryNotice(this.id, this.at, this.body);
  final int id;
  final DateTime at;
  final String body;
}

class DailySummary {
  static const baseId = 1900000000;
  static List<SummaryNotice> build(
    List<Assignment> rows,
    PersonalWorkspace personal,
    DateTime now,
    DateTime? synced, {
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
    if (!personal.summaryEnabled) return [];
    final beijing = now.toUtc().add(const Duration(hours: 8));
    final result = <SummaryNotice>[];
    for (var i = 0; result.length < 7; i++) {
      final local = DateTime.utc(beijing.year, beijing.month, beijing.day + i,
          personal.summaryHour, personal.summaryMinute);
      final at = local.subtract(const Duration(hours: 8)).toLocal();
      if (!at.isAfter(now)) continue;
      final day = PersonalWorkspace.dayKey(at);
      final due = rows.where((a) {
        if (a.isExam) return false;
        final entry = CourseworkDeadline.entryFor(a, coursework);
        final bucket = CourseworkDeadline.bucketAt(a, now, entry: entry);
        final resolved = CourseworkDeadline.resolveEntry(a, entry);
        return bucket == AssignmentDeadlineBucket.notExpiredWithDeadline &&
            resolved != null &&
            PersonalWorkspace.dayKey(resolved.at) == day;
      }).length;
      final exams = rows
          .where((a) =>
              a.isExam &&
              AssignmentReminderSnapshot(
                      assignment: a, hidden: false, followed: true)
                  .eligibleAt(at) &&
              PersonalWorkspace.dayKey(a.reminderAnchorAt!) == day)
          .length;
      final examText = exams == 0 ? '' : ' · 今日开考 $exams 项';
      final plans = personal.plans.where((p) => p.day == day && !p.done).length;
      final stamp = synced == null ? '尚未同步' : PersonalWorkspace.dayKey(synced);
      result.add(SummaryNotice(baseId + result.length, at,
          '今日截止 $due 项$examText · 个人计划 $plans 项。基于 $stamp 本机快照，请打开应用刷新核对。'));
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
  const ReminderChannelHealth(
    this.status, {
    this.importance,
    this.channelId,
    this.soundMuted,
    this.customSound,
    this.vibrationEnabled,
    this.lockscreenVisibility,
  });

  final ReminderChannelStatus status;
  final int? importance;
  final String? channelId;
  final bool? soundMuted;
  final bool? customSound;
  final bool? vibrationEnabled;
  final int? lockscreenVisibility;

  bool? get enabled => switch (status) {
        ReminderChannelStatus.enabled => true,
        ReminderChannelStatus.disabled => false,
        _ => null,
      };

  String get label {
    final base = switch (status) {
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
    if (status != ReminderChannelStatus.enabled) return base;
    final traits = <String>[
      if (soundMuted == true) '系统已静音' else if (customSound == true) '已自定义铃声',
      if (vibrationEnabled == false) '振动已关闭',
    ];
    if (traits.isEmpty) return base;
    return '$base · ${traits.join(' · ')}';
  }
}

class ReminderHealth {
  const ReminderHealth(
      {this.notifications,
      this.exact,
      this.assignmentChannel,
      this.assignmentUpdatesChannel,
      this.summaryChannel,
      this.manualChannel,
      this.activeDeadlineChannelId,
      this.legacyDeadlineChannel,
      this.v2DeadlineChannel,
      this.v3DeadlineChannel,
      this.silentChannel,
      this.ignoringBatteryOptimizations,
      this.lockscreenShowNotifications,
      this.lockscreenAllowPrivateNotifications,
      this.ringerMode,
      this.interruptionFilter,
      this.notificationStreamVolume,
      this.notificationStreamMaxVolume,
      this.notificationStreamMuted,
      this.pending,
      this.summaryPending,
      this.manualPending,
      this.scheduleRecoveryPending = false,
      this.queryErrors = const []});

  final bool? notifications, exact;
  final ReminderChannelHealth? assignmentChannel,
      assignmentUpdatesChannel,
      summaryChannel,
      manualChannel,
      legacyDeadlineChannel,
      v2DeadlineChannel,
      v3DeadlineChannel,
      silentChannel;
  final String? activeDeadlineChannelId;
  final bool? ignoringBatteryOptimizations,
      lockscreenShowNotifications,
      lockscreenAllowPrivateNotifications,
      notificationStreamMuted;
  final String? ringerMode, interruptionFilter;
  final int? notificationStreamVolume, notificationStreamMaxVolume;
  final int? pending, summaryPending, manualPending;
  final bool scheduleRecoveryPending;
  final List<String> queryErrors;

  bool get isPhoneMutedOrVibrate =>
      ringerMode == 'silent' || ringerMode == 'vibrate';
  bool get isNotificationVolumeZero =>
      notificationStreamMuted == true || notificationStreamVolume == 0;
  bool get isDndActive =>
      interruptionFilter == 'priority' ||
      interruptionFilter == 'none' ||
      interruptionFilter == 'alarms';

  // Missing, unsupported and failed channel checks must not collapse to false.
  bool? get channelEnabled => assignmentChannel?.enabled;
  bool? get assignmentUpdatesChannelEnabled =>
      assignmentUpdatesChannel?.enabled;
  bool? get summaryChannelEnabled => summaryChannel?.enabled;
  bool? get manualChannelEnabled => manualChannel?.enabled;
}
