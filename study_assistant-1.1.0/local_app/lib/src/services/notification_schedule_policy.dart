import 'package:timezone/timezone.dart' as tz;

import '../models/study_notebook.dart';
import 'deadline_quiet_hours_policy.dart';

/// Pure rules shared by notification scheduling, migration and recovery.
class NotificationSchedulePolicy {
  const NotificationSchedulePolicy._();

  // Shared wire IDs for platform registration and journal ownership checks.
  static const assignmentChannel = 'assignment_deadlines';
  static const assignmentV2Channel = 'assignment_deadlines_v2';
  static const assignmentV3Channel = 'assignment_deadlines_v3';
  static const assignmentSilentChannel = 'assignment_silent';
  static const assignmentUpdatesChannel = 'assignment_updates';
  static const assignmentUpdatesV2Channel = 'assignment_updates_v2';
  static const assignmentUpdatesV3Channel = 'assignment_updates_v3';
  static const summaryChannel = 'daily_summary';
  static const summaryV2Channel = 'daily_summary_v2';
  static const summaryV3Channel = 'daily_summary_v3';
  static const manualChannel = 'personal_schedule';
  static const manualV2Channel = 'personal_schedule_v2';
  static const manualV3Channel = 'personal_schedule_v3';

  static String? normalizeDeadlineChannelId(String? raw) {
    switch (raw?.trim()) {
      case assignmentChannel:
        return assignmentChannel;
      case assignmentV2Channel:
        return assignmentV2Channel;
      case assignmentV3Channel:
        return assignmentV3Channel;
      default:
        return null;
    }
  }

  static String channelNameForId(String channelId) => switch (channelId) {
        manualV3Channel || manualV2Channel || manualChannel => '待办与考试提醒',
        assignmentUpdatesV3Channel || assignmentUpdatesV2Channel => '新增作业提醒',
        assignmentUpdatesChannel => '作业变化提醒',
        summaryV3Channel || summaryV2Channel || summaryChannel => '每日课业摘要',
        _ => '作业截止提醒',
      };

  static bool isManualReminderQuietHoursSkipped(
    ManualEntry entry, {
    required DateTime now,
    bool allowUrgentNightBreakthrough = false,
    tz.Location? location,
  }) {
    if (entry.done || !entry.remind || entry.at == null) return false;
    final rawAt = entry.at!.subtract(const Duration(minutes: 30));
    if (!rawAt.isAfter(now)) return false;
    return DeadlineQuietHoursPolicy.adjustManualCandidate(
          candidateAt: rawAt,
          eventAt: entry.at!,
          now: now,
          allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
          location: location,
        ) ==
        null;
  }

  static bool isManualReminderWindowMissed(
    ManualEntry entry, {
    required DateTime now,
  }) {
    if (entry.done || !entry.remind || entry.at == null) return false;
    final rawAt = entry.at!.subtract(const Duration(minutes: 30));
    return !rawAt.isAfter(now);
  }

  static String formatDeadlineRemainingText(int offsetMinutes,
      {bool examStart = false}) {
    final safeMinutes = offsetMinutes < 0 ? 0 : offsetMinutes;
    final days = safeMinutes ~/ 1440;
    final hours = (safeMinutes % 1440) ~/ 60;
    final minutes = safeMinutes % 60;
    final parts = <String>[
      if (days > 0) '$days 天',
      if (hours > 0) '$hours 小时',
      if (minutes > 0 || (days == 0 && hours == 0)) '$minutes 分钟',
    ];
    return '还剩 ${parts.join(' ')}${examStart ? '开考' : '截止'}';
  }

  static bool isPrivatePayload(String? payload) =>
      payload?.startsWith('a:') == true ||
      payload?.startsWith('p:') == true ||
      payload?.startsWith('d:') == true ||
      // The health-check notification is private too. It is not a scheduled
      // transaction, so it is cleaned by payload/active scanning rather than
      // being assigned to a category journal.
      payload?.startsWith('t:') == true;

  static String? scheduleCategoryForPayload(String? payload) {
    if (payload?.startsWith('a:') == true) return 'assignments';
    if (payload?.startsWith('p:') == true) return 'manual';
    if (payload?.startsWith('d:') == true) return 'summary';
    return null;
  }

  static bool isValidManualPayload(String? payload) {
    if (payload == null || !payload.startsWith('p:')) return false;
    final id = payload.substring(2);
    return id.isNotEmpty &&
        id.length <= 100 &&
        !id.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
  }

  static String? scheduleCategoryForChannel(String? channel) =>
      switch (channel) {
        assignmentChannel => 'assignments',
        assignmentV2Channel => 'assignments',
        assignmentV3Channel => 'assignments',
        assignmentSilentChannel => 'assignments',
        assignmentUpdatesChannel => 'assignments',
        assignmentUpdatesV2Channel => 'assignments',
        assignmentUpdatesV3Channel => 'assignments',
        manualChannel => 'manual',
        manualV2Channel => 'manual',
        manualV3Channel => 'manual',
        summaryChannel => 'summary',
        summaryV2Channel => 'summary',
        summaryV3Channel => 'summary',
        _ => null,
      };

  static String appendWarning(String? current, String next) =>
      current == null || current.isEmpty ? next : '$next；$current';

  /// Allocates unique IDs outside the legacy notification namespaces.
  ///
  /// [nextInt] returns an offset in [0, upperBound). The caller supplies
  /// randomness, and [reserved] remains unchanged.
  static List<int> allocateNotificationIds(
    int count,
    Set<int> reserved, {
    required int Function(int upperBound) nextInt,
  }) {
    const firstTransactionalId = 2000000000;
    final result = <int>{};
    while (result.length < count) {
      final candidate =
          firstTransactionalId + nextInt(0x7fffffff - firstTransactionalId);
      if (!reserved.contains(candidate)) result.add(candidate);
    }
    return result.toList();
  }
}
