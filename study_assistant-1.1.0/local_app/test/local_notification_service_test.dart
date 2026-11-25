import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
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
              fixture.channelRow('assignment_deadlines_v2', '作业截止提醒', 4),
              fixture.channelRow('personal_schedule_v2', '待办与考试提醒', 4),
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
          at: DateTime(2030, 11, 6, 18, 0),
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

    test(
        'manual and assignment schedules obey quiet hours and night breakthrough',
        () async {
      timezone_data.initializeTimeZones();
      final shanghai = tz.getLocation('Asia/Shanghai');
      final now = tz.TZDateTime(shanghai, 2030, 11, 20, 20, 0);
      final service = LocalNotificationService(
        clock: () => now,
        location: shanghai,
      )..showDetails = true;

      await service.rescheduleManual([
        ManualEntry(
          id: 'night-todo',
          title: '凌晨待办',
          kind: 'todo',
          at: tz.TZDateTime(shanghai, 2030, 11, 21, 0, 45),
          remind: true,
        ),
        ManualEntry(
          id: 'shiftable-todo',
          title: '八点待办',
          kind: 'todo',
          at: tz.TZDateTime(shanghai, 2030, 11, 21, 7, 50),
          remind: true,
        ),
      ]);
      var scheduledTimes = calls
          .where((call) => call.method == 'zonedSchedule')
          .map((call) => DateTime.parse(
              (call.arguments as Map)['scheduledDateTime'] as String))
          .toList();
      expect(scheduledTimes, hasLength(1));
      // The plugin receives wall-clock time; compare it without assuming the
      // host process timezone matches Asia/Shanghai.
      expect(scheduledTimes.single, DateTime(2030, 11, 21, 7, 30));

      calls.clear();
      service.allowUrgentNightBreakthrough = true;
      await service.rescheduleManual([
        ManualEntry(
          id: 'night-todo',
          title: '凌晨待办',
          kind: 'todo',
          at: tz.TZDateTime(shanghai, 2030, 11, 21, 0, 45),
          remind: true,
        ),
      ]);
      scheduledTimes = calls
          .where((call) => call.method == 'zonedSchedule')
          .map((call) => DateTime.parse(
              (call.arguments as Map)['scheduledDateTime'] as String))
          .toList();
      expect(scheduledTimes.single, DateTime(2030, 11, 21, 0, 15));

      calls.clear();
      await service.rescheduleAssignments([
        Assignment(
          id: 'cx:work:1:2:night',
          courseName: '计算机网络',
          title: '实验报告',
          deadlineAt: tz.TZDateTime(shanghai, 2030, 11, 21, 0, 30),
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
          deadlineTrusted: true,
        ),
      ], offsetsMinutes: [
        30
      ]);
      scheduledTimes = calls
          .where((call) => call.method == 'zonedSchedule')
          .map((call) => DateTime.parse(
              (call.arguments as Map)['scheduledDateTime'] as String))
          .toList();
      expect(scheduledTimes, [
        DateTime(2030, 11, 20, 22, 30),
        DateTime(2030, 11, 21, 0, 0),
      ]);
    });

    test(
        'resolveDefaultDeadlineChannel defaults to v2 and honors explicit stored selection',
        () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var channels = <Map<String, Object?>>[];
      var failChannelQuery = false;
      messenger.setMockMethodCallHandler(notifications, (call) async {
        calls.add(call);
        if (call.method == 'getNotificationChannels') {
          if (failChannelQuery) {
            throw PlatformException(code: 'channels_unavailable');
          }
          return channels;
        }
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'pendingNotificationRequests' || 'getActiveNotifications' => [],
          _ => true,
        };
      });

      SharedPreferences.setMockInitialValues({});
      final freshService = LocalNotificationService();
      await freshService.initializeSafely();
      channels = [
        fixture.channelRow('assignment_deadlines', '作业截止提醒', 4),
      ];
      expect(
        await freshService.resolveDefaultDeadlineChannel(),
        LocalNotificationService.assignmentV2Channel,
      );

      SharedPreferences.setMockInitialValues({});
      channels = [
        fixture.channelRow('assignment_deadlines', '作业截止提醒', 4),
      ];
      final upgradeByChannel = LocalNotificationService();
      await upgradeByChannel.initializeSafely();
      expect(
        await upgradeByChannel.resolveDefaultDeadlineChannel(),
        LocalNotificationService.assignmentV2Channel,
      );
      expect(
        await upgradeByChannel.resolveDefaultDeadlineChannel(
          storedChannelId: LocalNotificationService.assignmentChannel,
        ),
        LocalNotificationService.assignmentChannel,
      );
      expect(
        await upgradeByChannel.resolveDefaultDeadlineChannel(
          storedChannelId: LocalNotificationService.assignmentV2Channel,
        ),
        LocalNotificationService.assignmentV2Channel,
      );

      SharedPreferences.setMockInitialValues(
          {'notification_details_v1': false});
      channels = <Map<String, Object?>>[];
      final upgradeByLegacyKey = LocalNotificationService();
      await upgradeByLegacyKey.initializeSafely();
      expect(
        await upgradeByLegacyKey.resolveDefaultDeadlineChannel(),
        LocalNotificationService.assignmentV2Channel,
      );

      SharedPreferences.setMockInitialValues({});
      failChannelQuery = true;
      expect(
        await LocalNotificationService().resolveDefaultDeadlineChannel(),
        LocalNotificationService.assignmentV2Channel,
      );

      final failedInit = LocalNotificationService();
      await failedInit.initializeSafely();
      expect(
        await failedInit.resolveDefaultDeadlineChannel(),
        LocalNotificationService.assignmentV2Channel,
      );

      failChannelQuery = false;
      SharedPreferences.setMockInitialValues({
        'deadline_channel_install_default_v1':
            LocalNotificationService.assignmentV2Channel,
      });
      messenger.setMockMethodCallHandler(permissions, (call) async {
        throw MissingPluginException('missing permissions in worker');
      });
      expect(
        await LocalNotificationService().resolveDefaultDeadlineChannel(),
        LocalNotificationService.assignmentV2Channel,
      );
      messenger.setMockMethodCallHandler(permissions, (call) async => 35);
    });

    test(
        'inspectHealth merges native channel details silently without polluting queryErrors',
        () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(permissions, (call) async {
        if (call.method == 'getAndroidSdkInt') return 35;
        if (call.method == 'inspectNotificationHealthDetails') {
          return {
            'channels': {
              'assignment_deadlines': {
                'exists': true,
                'importance': 4,
                'soundMuted': true,
                'customSound': false,
                'vibrationEnabled': false,
                'lockscreenVisibility': 0,
              },
              'assignment_deadlines_v2': {
                'exists': true,
                'importance': 4,
                'soundMuted': false,
                'customSound': true,
                'vibrationEnabled': true,
                'lockscreenVisibility': 1,
              },
              'assignment_silent': {
                'exists': true,
                'importance': 2,
                'soundMuted': true,
                'customSound': false,
                'vibrationEnabled': false,
                'lockscreenVisibility': 0,
              },
            },
            'ignoringBatteryOptimizations': false,
            'lockscreenShowNotifications': true,
            'lockscreenAllowPrivateNotifications': false,
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(notifications, (call) async {
        calls.add(call);
        return switch (call.method) {
          'getNotificationChannels' => [
              fixture.channelRow('assignment_deadlines', '作业截止提醒', 4),
              fixture.channelRow('assignment_deadlines_v2', '作业截止提醒（增强有声）', 4),
              fixture.channelRow('assignment_silent', '静默作业通知', 2),
              fixture.channelRow('assignment_updates_v2', '新增作业提醒', 4),
              fixture.channelRow('daily_summary_v2', '每日课业摘要', 4),
              fixture.channelRow('personal_schedule_v2', '待办与考试提醒', 4),
            ],
          'areNotificationsEnabled' || 'canScheduleExactNotifications' => true,
          'pendingNotificationRequests' || 'getActiveNotifications' => [],
          _ => true,
        };
      });

      final service = LocalNotificationService()
        ..activeDeadlineChannelId =
            LocalNotificationService.assignmentV2Channel;
      final health = await service.inspectHealth();
      expect(health.queryErrors, isEmpty);
      expect(health.activeDeadlineChannelId,
          LocalNotificationService.assignmentV2Channel);
      expect(health.assignmentChannel?.channelId,
          LocalNotificationService.assignmentV2Channel);
      expect(health.assignmentChannel?.customSound, isTrue);
      expect(health.legacyDeadlineChannel?.soundMuted, isTrue);
      expect(health.legacyDeadlineChannel?.vibrationEnabled, isFalse);
      expect(health.silentChannel?.importance, 2);
      expect(health.ignoringBatteryOptimizations, isFalse);
      expect(health.lockscreenShowNotifications, isTrue);
      expect(health.lockscreenAllowPrivateNotifications, isFalse);

      messenger.setMockMethodCallHandler(permissions, (call) async {
        if (call.method == 'getAndroidSdkInt') return 35;
        if (call.method == 'inspectNotificationHealthDetails') {
          throw MissingPluginException('missing details handler');
        }
        return null;
      });
      final fallbackHealth = await service.inspectHealth();
      expect(fallbackHealth.queryErrors, isEmpty);
      expect(fallbackHealth.assignmentChannel?.status,
          ReminderChannelStatus.enabled);
    });

    test(
        'showTestNotification uses activeDeadlineChannelId and keeps private visibility',
        () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channelList = <Map<String, Object?>>[
        fixture.channelRow('assignment_deadlines', '作业截止提醒', 4),
        fixture.channelRow('personal_schedule_v2', '待办与考试提醒', 4),
      ];
      messenger.setMockMethodCallHandler(notifications, (call) async {
        calls.add(call);
        if (call.method == 'createNotificationChannel') {
          final args = call.arguments as Map;
          final id = args['id'] as String;
          if (!channelList.any((item) => item['id'] == id)) {
            channelList.add(
              fixture.channelRow(
                id,
                args['name'] as String? ?? '',
                args['importance'] as int? ?? 4,
              ),
            );
          }
          return null;
        }
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'getNotificationChannels' => channelList,
          'pendingNotificationRequests' || 'getActiveNotifications' => [],
          _ => true,
        };
      });

      final service = LocalNotificationService()
        ..activeDeadlineChannelId =
            LocalNotificationService.assignmentV2Channel;
      expect(await service.showTestNotification(), isTrue);

      final createdChannels = calls
          .where((call) => call.method == 'createNotificationChannel')
          .map((call) => (call.arguments as Map)['id'])
          .toList();
      expect(createdChannels,
          contains(LocalNotificationService.assignmentV2Channel));
      final showArgs =
          calls.singleWhere((call) => call.method == 'show').arguments as Map;
      final specifics = showArgs['platformSpecifics'] as Map;
      expect(
          specifics['channelId'], LocalNotificationService.assignmentV2Channel);
      expect(specifics['visibility'], NotificationVisibility.private.index);
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
