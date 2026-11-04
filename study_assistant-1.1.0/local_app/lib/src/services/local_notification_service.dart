import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/assignment.dart';
import 'reminder_rule_store.dart';

typedef NotificationPayloadHandler = void Function(String payload);

class LocalNotificationService {
  LocalNotificationService({NotificationPayloadHandler? onPayload})
      : _onPayload = onPayload;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  NotificationPayloadHandler? _onPayload;
  String? _pendingPayload;

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
    } catch (_) {}
  }

  Future<void> initialize({NotificationPayloadHandler? onPayload}) async {
    if (onPayload != null) {
      setPayloadHandler(onPayload);
    }
    timezone_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const android = AndroidInitializationSettings('@drawable/app_icon');
    const ios = DarwinInitializationSettings();
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
    await _requestNotificationPermission();
    await _requestExactAlarmPermission();
  }

  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    try {
      await _requestNotificationPermission();
      await _cancelAssignments();
      final offsets = ReminderRuleStore.normalizeOffsets(offsetsMinutes);
      for (final assignment in assignments.where((item) => !item.isCompleted)) {
        for (final offset in offsets) {
          await _scheduleAssignmentReminder(assignment, offset);
        }
      }
    } catch (_) {}
  }

  Future<void> _cancelAssignments() async {
    final active = await _plugin.pendingNotificationRequests();
    for (final request in active) {
      if (request.payload?.startsWith('a:') ?? false) {
        await _plugin.cancel(request.id);
      }
    }
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
      id: Object.hash('a', assignment.id, offset),
      channelId: 'assignment_deadlines',
      title: '作业即将截止',
      body:
          '${assignment.courseName} · ${assignment.title}，${formatDeadlineRemainingText(offset)}',
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

  Future<void> _requestNotificationPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _requestExactAlarmPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
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
            '作业截止提醒',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
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
      }
    }
  }
}
