import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_health_test.dart' as fixture;

class _InvalidSchedulePlugin extends AndroidFlutterLocalNotificationsPlugin {
  final modes = <AndroidScheduleMode>[];

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    AndroidNotificationDetails? notificationDetails, {
    required AndroidScheduleMode scheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    modes.add(scheduleMode);
    if (scheduleMode == AndroidScheduleMode.exactAllowWhileIdle) {
      throw ArgumentError('synthetic invalid schedule');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Android notification plugin behavior', () {
    const notifications =
        MethodChannel('dexterous.com/flutter/local_notifications');
    const permissions = MethodChannel('study_assistant/permissions');
    final calls = <MethodCall>[];
    String? failingQuery;

    setUp(() {
      calls.clear();
      failingQuery = null;
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(permissions, (call) async => 35);
      messenger.setMockMethodCallHandler(notifications, (call) async {
        calls.add(call);
        if (call.method == failingQuery) {
          throw PlatformException(code: 'synthetic_query_error');
        }
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'getNotificationChannels' => [
              fixture.channelRow('assignment_deadlines', '作业截止提醒', 4),
              fixture.channelRow('personal_schedule', '个人待办与考试提醒', 4),
            ],
          'pendingNotificationRequests' || 'getActiveNotifications' => [],
          _ => true,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(notifications, null);
        messenger.setMockMethodCallHandler(permissions, null);
        FlutterLocalNotificationsPlatform.instance =
            AndroidFlutterLocalNotificationsPlugin();
        debugDefaultTargetPlatformOverride = null;
      });
    });

    ManualEntry entry() => ManualEntry(
          id: 'sample',
          title: '合成提醒详情',
          kind: 'todo',
          at: DateTime.now().add(const Duration(days: 1)),
          remind: true,
        );

    test('scheduled details keep private Android lock screen visibility',
        () async {
      final service = LocalNotificationService()..showDetails = true;
      await service.rescheduleManual([entry()]);
      final args = calls
          .singleWhere((call) => call.method == 'zonedSchedule')
          .arguments as Map;
      expect(args['body'], contains('合成提醒详情'));
      expect((args['platformSpecifics'] as Map)['visibility'],
          NotificationVisibility.private.index);
    });

    test('test notification explicitly uses private visibility', () async {
      final service = LocalNotificationService()..showDetails = true;
      expect(await service.showTestNotification(), isTrue);
      final args =
          calls.singleWhere((call) => call.method == 'show').arguments as Map;
      expect((args['platformSpecifics'] as Map)['visibility'],
          NotificationVisibility.private.index);
    });

    test('invalid schedule arguments do not retry with inexact mode', () async {
      final plugin = _InvalidSchedulePlugin();
      FlutterLocalNotificationsPlatform.instance = plugin;
      final service = LocalNotificationService();
      await expectLater(
          service.rescheduleManual([entry()]), throwsArgumentError);
      expect(plugin.modes, [AndroidScheduleMode.exactAllowWhileIdle]);
    });

    test('partial health channel failure is disclosed by reminder explanation',
        () async {
      failingQuery = 'getNotificationChannels';
      final service = LocalNotificationService();
      final health = await service.inspectHealth();
      expect(health.queryErrors, ['通知渠道状态读取失败']);
      final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: service,
        widgetSnapshotService: WidgetSnapshotService(),
        manageBackgroundSchedule: false,
      );
      addTearDown(store.dispose);
      final result =
          await store.explainReminder(kind: 'assignment', id: 'gone');
      expect(result.queryWarnings, contains('通知渠道状态读取失败'));
      expect(result.queryWarnings.join(),
          isNot(contains('synthetic_query_error')));
    });
  });

  test('exam start reminder text never describes a deadline', () {
    expect(
        LocalNotificationService.formatDeadlineRemainingText(90,
            examStart: true),
        '还剩 1 小时 30 分钟开考');
    expect(
        LocalNotificationService.formatDeadlineRemainingText(30,
            examStart: true),
        '还剩 30 分钟开考');
  });
  test('formats deadline remaining text with days hours and minutes', () {
    expect(
      LocalNotificationService.formatDeadlineRemainingText(5945),
      '还剩 4 天 3 小时 5 分钟截止',
    );
    expect(
      LocalNotificationService.formatDeadlineRemainingText(90),
      '还剩 1 小时 30 分钟截止',
    );
    expect(
      LocalNotificationService.formatDeadlineRemainingText(30),
      '还剩 30 分钟截止',
    );
  });

  test('Android notifications default to private lock screen visibility', () {
    final service = File(
      'lib/src/services/local_notification_service.dart',
    ).readAsStringSync();

    expect(service, contains('bool showDetails = false'));
    expect(service, contains('NotificationVisibility.private'));
    expect(service, contains('AndroidNotificationCategory.reminder'));
  });

  test('Darwin notifications are presented immediately', () {
    final service = File(
      'lib/src/services/local_notification_service.dart',
    ).readAsStringSync();

    expect(service, contains('presentBanner: true'));
    expect(service, contains('presentList: true'));
    expect(service, contains('InterruptionLevel.active'));
  });

  test('scheduled assignment notifications use cancellable payload prefix', () {
    final service = File(
      'lib/src/services/local_notification_service.dart',
    ).readAsStringSync();

    expect(service, contains("'a:studyassistant:///assignments/"));
    expect(service, contains("payload?.startsWith('a:')"));
    expect(service, contains('_isPrivatePayload(item.payload)'));
  });

  test('notification taps are wired to route payloads', () {
    final service = File(
      'lib/src/services/local_notification_service.dart',
    ).readAsStringSync();

    expect(service, contains('onDidReceiveNotificationResponse'));
    expect(service, contains('getNotificationAppLaunchDetails'));
  });
}
