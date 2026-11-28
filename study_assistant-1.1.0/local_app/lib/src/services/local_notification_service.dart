import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/assignment.dart';
import '../models/local_coursework_state.dart';
import '../models/personal_workspace.dart';
import '../models/reminder_history.dart';
import '../models/study_notebook.dart';
import 'assignment_reminder_planner.dart';
import 'coursework_deadline.dart';
import 'daily_summary.dart';
import 'deadline_quiet_hours_policy.dart';
import 'notification_schedule_policy.dart';
import 'reminder_rule_store.dart';

part 'local_notification_channels.dart';
part 'local_notification_transactions.dart';
part 'local_notification_schedulers.dart';

typedef NotificationPayloadHandler = void Function(String payload);

class NotificationChimePreviewResult {
  const NotificationChimePreviewResult({
    required this.played,
    this.supported = true,
    this.notificationStreamVolume,
    this.notificationStreamMaxVolume,
    this.notificationStreamMuted,
    this.ringerMode,
    this.interruptionFilter,
  });

  final bool played;
  final bool supported;
  final int? notificationStreamVolume;
  final int? notificationStreamMaxVolume;
  final bool? notificationStreamMuted;
  final String? ringerMode;
  final String? interruptionFilter;

  bool get isNotificationVolumeZero =>
      notificationStreamMuted == true || notificationStreamVolume == 0;
  bool get isPhoneMutedOrVibrate =>
      ringerMode == 'silent' || ringerMode == 'vibrate';
  bool get isDoNotDisturbActive =>
      interruptionFilter == 'none' ||
      interruptionFilter == 'alarms' ||
      interruptionFilter == 'priority';
}

class LocalNotificationService {
  LocalNotificationService({
    NotificationPayloadHandler? onPayload,
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? clock,
    tz.Location? location,
  })  : _onPayload = onPayload,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _clock = clock ?? DateTime.now,
        _location = location;

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _clock;
  final tz.Location? _location;
  String? lastWarning;
  String? lastManualNotice;
  List<ReminderScheduleOutcome> lastScheduleOutcomes = const [];
  Set<String> lastQuietHoursSkippedManualIds = const {};
  Set<String> lastMissedWindowManualIds = const {};
  bool showDetails = false;
  bool allowUrgentNightBreakthrough = false;
  LocalCourseworkState courseworkState = const LocalCourseworkState.empty();
  String activeDeadlineChannelId = assignmentV3Channel;
  static const assignmentChannel = NotificationSchedulePolicy.assignmentChannel;
  static const assignmentV2Channel =
      NotificationSchedulePolicy.assignmentV2Channel;
  static const assignmentV3Channel =
      NotificationSchedulePolicy.assignmentV3Channel;
  static const assignmentSilentChannel =
      NotificationSchedulePolicy.assignmentSilentChannel;
  static const assignmentUpdatesChannel =
      NotificationSchedulePolicy.assignmentUpdatesChannel;
  static const assignmentUpdatesV2Channel =
      NotificationSchedulePolicy.assignmentUpdatesV2Channel;
  static const assignmentUpdatesV3Channel =
      NotificationSchedulePolicy.assignmentUpdatesV3Channel;
  static const summaryChannel = NotificationSchedulePolicy.summaryChannel;
  static const summaryV2Channel = NotificationSchedulePolicy.summaryV2Channel;
  static const summaryV3Channel = NotificationSchedulePolicy.summaryV3Channel;
  static const manualChannel = NotificationSchedulePolicy.manualChannel;
  static const manualV2Channel = NotificationSchedulePolicy.manualV2Channel;
  static const manualV3Channel = NotificationSchedulePolicy.manualV3Channel;
  static const chimeSound =
      RawResourceAndroidNotificationSound('journal_chime');
  static final Int64List defaultVibrationPattern =
      Int64List.fromList(const [0, 180, 90, 180]);
  static const _permissionsChannel =
      MethodChannel('study_assistant/permissions');
  static const _legacyMigrationChannel =
      MethodChannel('study_assistant/legacy_assignment_migration');

  static final _androidChannels = _buildAndroidChannels();
  static final _extraChannels = _buildExtraChannels();
  Future<void>? _pluginInitialization;
  final Map<String, Future<void>> _channelCreations = {};
  bool _pluginInitialized = false;
  bool lastDeadlineScheduleFailed = false;
  Timer? _pendingManualTestTimer;
  static Future<void> _scheduleMutationQueue = Future<void>.value();
  static const _scheduleCategories = ['assignments', 'manual', 'summary'];
  static const _scheduleJournalPrefix = 'notification_schedule_v2_journal_';
  static const _scheduleActivePrefix = 'notification_schedule_v2_active_';
  static const _summaryEvidenceKey = 'notification_summary_evidence_v1';
  NotificationPayloadHandler? _onPayload;
  String? _pendingPayload;

  static String? normalizeDeadlineChannelId(String? raw) =>
      NotificationSchedulePolicy.normalizeDeadlineChannelId(raw);

  static bool isManualReminderQuietHoursSkipped(
    ManualEntry entry, {
    required DateTime now,
    bool allowUrgentNightBreakthrough = false,
    tz.Location? location,
  }) =>
      NotificationSchedulePolicy.isManualReminderQuietHoursSkipped(
        entry,
        now: now,
        allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
        location: location,
      );

  static bool isManualReminderWindowMissed(
    ManualEntry entry, {
    required DateTime now,
  }) =>
      NotificationSchedulePolicy.isManualReminderWindowMissed(entry, now: now);

  static String formatDeadlineRemainingText(int offsetMinutes,
          {bool examStart = false}) =>
      NotificationSchedulePolicy.formatDeadlineRemainingText(
        offsetMinutes,
        examStart: examStart,
      );

  void setPayloadHandler(NotificationPayloadHandler? onPayload) =>
      _setPayloadHandler(onPayload);

  Future<void> initializeSafely({NotificationPayloadHandler? onPayload}) =>
      _initializeSafely(onPayload: onPayload);

  Future<void> initialize({NotificationPayloadHandler? onPayload}) =>
      _initialize(onPayload: onPayload);

  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) =>
      _rescheduleAssignments(assignments, offsetsMinutes: offsetsMinutes);

  Future<void> rescheduleManual(List<ManualEntry> entries) =>
      _rescheduleManual(entries);

  Future<void> rescheduleSummary(
    List<Assignment> assignments,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) =>
      _rescheduleSummary(assignments, personal, lastSync);

  Future<bool> showTestManualNotification({Duration delay = Duration.zero}) =>
      _showTestManualNotification(delay: delay);

  Future<bool> showTestNotification() => _showTestNotification();

  Future<String> resolveDefaultDeadlineChannel({String? storedChannelId}) =>
      _resolveDefaultDeadlineChannel(storedChannelId: storedChannelId);

  Future<NotificationChimePreviewResult> previewNotificationChime() =>
      _previewNotificationChime();

  Future<ReminderHealth> inspectHealth() => _inspectHealth();

  Future<bool> requestNotificationsPermission() =>
      _requestNotificationsPermission();

  Future<void> migrateLegacyManualChannelIfNeeded(List<ManualEntry> entries) =>
      _migrateLegacyManualChannelIfNeeded(entries);

  Future<void> migrateLegacySummaryChannelIfNeeded(
    List<Assignment> assignments,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) =>
      _migrateLegacySummaryChannelIfNeeded(assignments, personal, lastSync);

  Future<void> retireLegacyUpdatesAndDeadlineChannelsIfNeeded({
    required bool retireDeadlineV1,
    Future<bool> Function()? beforeRetireDeadlineV1,
  }) =>
      _retireLegacyUpdatesAndDeadlineChannelsIfNeeded(
        retireDeadlineV1: retireDeadlineV1,
        beforeRetireDeadlineV1: beforeRetireDeadlineV1,
      );

  /// Privacy tightening must not retain detailed alarms if replacement fails.
  Future<void> cancelPrivateSchedules() => _cancelPrivateSchedules();

  /// Native-only migration fact. A missing/failed bridge is not evidence of a
  /// completed migration, so callers must keep native reminder activation
  /// paused until this returns true.
  Future<bool> isLegacyAssignmentMigrationComplete() =>
      _isLegacyAssignmentMigrationComplete();

  /// Removes only the legacy plugin-delivered assignment alarms. Personal
  /// reminders and the daily summary retain their existing transaction logs.
  ///
  /// Delivered legacy notifications do not appear in the plugin's pending list
  /// and Android plugin v18 does not return their payload. Ownership is proven
  /// on the native side from the plugin's own click operation and schedule
  /// cache; native notifications that share an id are preserved. This returns
  /// only after that native cleanup (including its cache durability barrier)
  /// completed, so the caller may record a one-time migration marker.
  Future<void> removeLegacyAssignmentSchedules() =>
      _removeLegacyAssignmentSchedules();

  /// Retries durable schedule-batch recovery after an interrupted or failed
  /// replacement. Safe to call repeatedly and after process restart.
  Future<void> recoverPendingSchedules() => _recoverPendingSchedules();

  Future<bool> hasPendingScheduleRecovery() => _hasPendingScheduleRecovery();

  Future<PluginScheduleEvidenceSnapshot> readScheduleEvidence() =>
      _readScheduleEvidence();
}
