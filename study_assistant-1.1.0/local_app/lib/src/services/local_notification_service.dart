import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/assignment.dart';
import 'reminder_rule_store.dart';
import 'daily_summary.dart';
import '../models/personal_workspace.dart';
import '../models/study_notebook.dart';

typedef NotificationPayloadHandler = void Function(String payload);

class LocalNotificationService {
  LocalNotificationService(
      {NotificationPayloadHandler? onPayload,
      FlutterLocalNotificationsPlugin? plugin})
      : _onPayload = onPayload,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  String? lastWarning;
  bool showDetails = false;

  /// Privacy tightening must not retain detailed alarms if replacement fails.
  Future<void> cancelPrivateSchedules() async {
    final pending = await _plugin.pendingNotificationRequests();
    Object? failure;
    for (final item in pending) {
      final payload = item.payload ?? '';
      if (!['a:', 'p:', 'd:'].any(payload.startsWith)) continue;
      try {
        await _plugin.cancel(item.id);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  NotificationPayloadHandler? _onPayload;
  String? _pendingPayload;
  static const summaryChannel = 'daily_summary';
  Future<void> rescheduleManual(List<ManualEntry> entries) async {
    final active = await _plugin.pendingNotificationRequests();
    final desired = <int>{};
    final schedules = <(ManualEntry, DateTime, int)>[];
    var collision = false;
    for (final e in entries.where((e) => !e.done && e.remind && e.at != null)) {
      final at = e.at!.subtract(const Duration(minutes: 30));
      if (!at.isAfter(DateTime.now())) continue;
      final id = 1800000000 + (_notificationId(e.id, 30) % 10000000);
      if (!desired.add(id)) collision = true;
      schedules.add((e, at, id));
    }
    // Removal is independent of whether another entry can be scheduled today.
    Object? cancellationError;
    for (final n in active.where((n) => n.payload?.startsWith('p:') ?? false)) {
      if (!desired.contains(n.id)) {
        try {
          await _plugin.cancel(n.id);
        } catch (error) {
          cancellationError ??= error;
        }
      }
    }
    if (cancellationError != null) throw cancellationError;
    if (collision) throw StateError('个人提醒标识冲突，请修改后重试');
    for (final (e, at, id) in schedules) {
      await _zonedSchedule(
          id: id,
          channelId: 'personal_schedule',
          title: e.kind == 'exam' ? '个人考试提醒' : '个人待办提醒',
          body: showDetails
              ? '${e.title} · 30分钟后到时，请核对个人安排'
              : '有个人安排即将到时，请打开课业手记查看',
          notifyAt: at,
          payload: 'p:${e.id}');
    }
  }

  Future<ReminderHealth> inspectHealth() async {
    AndroidFlutterLocalNotificationsPlugin? android;
    try {
      android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
    } catch (_) {}
    bool? allowed, exact, channel;
    int? pending, summary, manual;
    try {
      allowed = await android?.areNotificationsEnabled();
    } catch (_) {}
    try {
      exact = await android?.canScheduleExactNotifications();
    } catch (_) {}
    try {
      final channels = await android?.getNotificationChannels();
      final c =
          channels?.where((c) => c.id == 'assignment_deadlines').firstOrNull;
      channel = c == null ? null : c.importance != Importance.none;
    } catch (_) {}
    try {
      final list = await _plugin.pendingNotificationRequests();
      pending = list.where((n) => n.payload?.startsWith('a:') ?? false).length;
      summary = list.where((n) => n.payload == 'd:summary').length;
      manual = list.where((n) => n.payload?.startsWith('p:') ?? false).length;
    } catch (_) {}
    return ReminderHealth(
        notifications: allowed,
        exact: exact,
        channelEnabled: channel,
        pending: pending,
        summaryPending: summary,
        manualPending: manual);
  }

  Future<bool> showTestNotification() async {
    try {
      final health = await inspectHealth();
      if (health.notifications != true || health.channelEnabled == false) {
        return false;
      }
      await _plugin.show(
          DailySummary.baseId + 8,
          '课业手记测试通知',
          '如果看到了这条通知，当前显示链路可用；不代表未来后台提醒一定送达。',
          const NotificationDetails(
              android: AndroidNotificationDetails(
                  'assignment_deadlines', '作业截止提醒',
                  importance: Importance.high, priority: Priority.high)),
          payload: 'd:summary');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> rescheduleSummary(List<Assignment> assignments,
      PersonalWorkspace personal, DateTime? lastSync) async {
    final desired =
        DailySummary.build(assignments, personal, DateTime.now(), lastSync);
    if (desired.isEmpty) {
      // Only query/cancel when supported; fake/test platforms may have no plugin.
      final active = await _plugin.pendingNotificationRequests();
      for (final n in active.where((n) => n.payload == 'd:summary')) {
        await _plugin.cancel(n.id);
      }
      return;
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
            summaryChannel, '每日课业摘要',
            description: '基于最近一次本机快照的课业摘要',
            importance: Importance.defaultImportance));
    for (final n in desired) {
      await _plugin.zonedSchedule(
          n.id,
          '今日课业摘要',
          showDetails ? n.body : '今日课业摘要已准备好，请打开课业手记查看',
          tz.TZDateTime.from(n.at, tz.local),
          NotificationDetails(
              android: AndroidNotificationDetails(summaryChannel, '每日课业摘要',
                  importance: Importance.defaultImportance,
                  visibility: NotificationVisibility.private)),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'd:summary');
    }
  }

  static String formatDeadlineRemainingText(int offsetMinutes) {
    final safeMinutes = offsetMinutes < 0 ? 0 : offsetMinutes;
    final days = safeMinutes ~/ 1440;
    final hours = (safeMinutes % 1440) ~/ 60;
    final minutes = safeMinutes % 60;
    final parts = <String>[
      if (days > 0) '$days 天',
      if (hours > 0) '$hours 小时',
      if (minutes > 0 || (days == 0 && hours == 0)) '$minutes 分钟',
    ];
    return '还剩 ${parts.join(' ')}截止';
  }

  void setPayloadHandler(NotificationPayloadHandler? onPayload) {
    _onPayload = onPayload;
    final pendingPayload = _pendingPayload;
    if (onPayload != null && pendingPayload != null) {
      _pendingPayload = null;
      onPayload(pendingPayload);
    }
  }

  Future<void> initializeSafely({NotificationPayloadHandler? onPayload}) async {
    try {
      await initialize(onPayload: onPayload);
    } catch (_) {
      lastWarning = '提醒初始化失败，请检查系统通知设置';
    }
  }

  Future<void> initialize({NotificationPayloadHandler? onPayload}) async {
    if (onPayload != null) {
      setPayloadHandler(onPayload);
    }
    timezone_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const android = AndroidInitializationSettings('@drawable/app_icon');
    const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false);
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _handleNotificationResponse(launchResponse);
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'assignment_deadlines',
          '作业截止提醒',
          description: '学习通作业截止前提醒',
          importance: Importance.high,
        ));
  }

  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    lastWarning = null;
    try {
      final active = await _plugin.pendingNotificationRequests();
      final desiredIds = <int>{};
      final offsets = ReminderRuleStore.normalizeOffsets(offsetsMinutes);
      // Replace matching IDs first. Keep previous schedules if replacement fails.
      for (final assignment in assignments.where((item) =>
          !item.isCompleted &&
          item.deadlineTrusted &&
          !item.deadlineReadFailed)) {
        for (final offset in offsets) {
          final at = assignment.deadlineAt?.subtract(Duration(minutes: offset));
          if (at == null || !at.isAfter(DateTime.now())) continue;
          desiredIds.add(_notificationId(assignment.id, offset));
          await _scheduleAssignmentReminder(assignment, offset);
        }
      }
      for (final request in active) {
        if ((request.payload?.startsWith('a:') ?? false) &&
            !desiredIds.contains(request.id)) {
          await _plugin.cancel(request.id);
        }
      }
    } catch (_) {
      lastWarning = '部分提醒未能更新，旧提醒可能仍有效；请检查通知权限后重试';
    }
  }

  static int _notificationId(String assignmentId, int offset) {
    // Object.hash is seeded per process, so it cannot identify persisted alarms.
    var hash = 2166136261;
    for (final code in '$assignmentId:$offset'.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0x7fffffff;
    }
    // Reserve disjoint spaces for personal (1.8b) and summary (1.9b) IDs.
    // Replanning cancels legacy a: IDs after successful replacement.
    return hash % 1700000000;
  }

  Future<void> _scheduleAssignmentReminder(
    Assignment assignment,
    int offset,
  ) async {
    final notifyAt = assignment.deadlineAt?.subtract(Duration(minutes: offset));
    if (notifyAt == null || notifyAt.difference(DateTime.now()).isNegative) {
      return;
    }
    await _zonedSchedule(
      id: _notificationId(assignment.id, offset),
      channelId: 'assignment_deadlines',
      title: '作业即将截止',
      body: showDetails
          ? '${assignment.courseName} · ${assignment.title}，${formatDeadlineRemainingText(offset)}'
          : '有作业即将截止，请打开课业手记查看',
      notifyAt: notifyAt,
      payload:
          'a:studyassistant:///assignments/${Uri.encodeComponent(assignment.id)}',
    );
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    final routePayload =
        payload.startsWith('a:') ? payload.substring(2) : payload;
    final handler = _onPayload;
    if (handler == null) {
      _pendingPayload = routePayload;
      return;
    }
    handler(routePayload);
  }

  Future<void> _zonedSchedule({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required DateTime notifyAt,
    required String payload,
  }) async {
    await _trySchedule(
      id: id,
      channelId: channelId,
      title: title,
      body: body,
      notifyAt: notifyAt,
      payload: payload,
      mode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> _trySchedule({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required DateTime notifyAt,
    required String payload,
    required AndroidScheduleMode mode,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(notifyAt, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelId == 'personal_schedule' ? '个人待办与考试提醒' : '作业截止提醒',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: showDetails
                ? NotificationVisibility.public
                : NotificationVisibility.private,
            ticker: title,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (_) {
      if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
        await _trySchedule(
          id: id,
          channelId: channelId,
          title: title,
          body: body,
          notifyAt: notifyAt,
          payload: payload,
          mode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        lastWarning = '精确提醒不可用，已改为系统允许的近似时间提醒';
      } else {
        rethrow;
      }
    }
  }
}
