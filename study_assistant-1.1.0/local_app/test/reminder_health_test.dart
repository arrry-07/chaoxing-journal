import 'dart:async';
import 'dart:convert';
import 'review_core_remediation_test.dart' as f;
import 'package:flutter/material.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/features/reminder_health_screen.dart';
import 'package:study_assistant_mobile/src/services/permission_settings_service.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';

class InspectableNotifications extends f.Notifications {
  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;
}

class ThrowingHealthNotifications extends f.Notifications {
  @override
  Future<ReminderHealth> inspectHealth() async =>
      throw StateError('synthetic health inspection failure');
}

class PendingRecoveryNotifications extends f.Notifications {
  final recoveryStarted = Completer<void>();
  final recoveryFinish = Completer<void>();
  bool failAfterFinish = false;

  @override
  Future<ReminderHealth> inspectHealth() async =>
      const ReminderHealth(scheduleRecoveryPending: true);

  @override
  Future<void> recoverPendingSchedules() async {
    recoveryStarted.complete();
    await recoveryFinish.future;
    if (failAfterFinish) throw StateError('synthetic recovery failure');
  }
}

class CountingHealthNotifications extends InspectableNotifications {
  int inspections = 0;

  @override
  Future<ReminderHealth> inspectHealth() async {
    inspections++;
    return const ReminderHealth(
      notifications: true,
      exact: true,
    );
  }
}

class _HealthPermissionSettingsService extends PermissionSettingsService {
  _HealthPermissionSettingsService({
    this.channelResult = SettingsOpenResult.direct,
  });

  final SettingsOpenResult channelResult;
  String? requestedChannelId;

  @override
  Future<SettingsOpenResult> openNotificationChannelSettingsResult(
    String channelId,
  ) async {
    requestedChannelId = channelId;
    return channelResult;
  }
}

class _HealthGateway extends BackgroundReminderGateway {
  _HealthGateway({this.available = true});

  bool available;
  bool failInspections = false;
  Object failure = TimeoutException('synthetic native health timeout');
  BackgroundReminderHealth nextHealth = nativeHealth();
  int inspections = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<int> ensureActiveAccount(String accountHash) async => 1;

  @override
  Future<int> clearActiveAccount(String accountHash) async => 1;

  @override
  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
  }) async {}

  @override
  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
  }) async {}

  @override
  Future<void> cancelAssignmentDeliveryKeepEvents(String accountHash) async {}

  @override
  Future<ReminderPlanState> loadPlanState({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      ReminderPlanState(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
        baselineCompleted: true,
        knownAssignmentIds: const {},
        sentNewAssignmentIds: const {},
        lastAttemptAt: null,
        lastFullSuccessAt: null,
        pendingUpdate: false,
        mutationVersion: 0,
      );

  @override
  Future<ReminderPlanApplyResult> applyPlan({
    required String accountHash,
    required int sessionEpoch,
    required AssignmentReminderPlan plan,
    required DateTime completedAt,
    required String? failure,
    required bool syncCompleted,
    required int expectedMutationVersion,
  }) async =>
      const ReminderPlanApplyResult(
        scheduledDeadlineCount: 0,
        pendingNewCount: 0,
        warning: null,
      );

  @override
  Future<bool> acquireWriteLease(String owner) async => true;

  @override
  Future<void> releaseWriteLease(String owner) async {}

  @override
  Future<BackgroundReminderHealth> inspectHealth({
    required String accountHash,
    required int sessionEpoch,
  }) async {
    inspections++;
    if (failInspections) throw failure;
    return nextHealth;
  }
}

BackgroundReminderHealth nativeHealth({
  bool notificationListenerEnabled = true,
  bool notificationListenerGranted = true,
  int pendingDeadlineCount = 0,
  int pendingNewCount = 0,
  bool baselineCompleted = true,
}) =>
    BackgroundReminderHealth(
      backgroundEnabled: true,
      intervalMinutes: 60,
      newAssignmentReminderEnabled: true,
      notificationListenerEnabled: notificationListenerEnabled,
      notificationListenerGranted: notificationListenerGranted,
      nextCheckAt: null,
      pendingNewCount: pendingNewCount,
      pendingDeadlineCount: pendingDeadlineCount,
      baselineCompleted: baselineCompleted,
      pendingSignalCount: 0,
      migrationPending: false,
      lastFailure: null,
    );

AssignmentStore _nativeHealthStore(LocalNotificationService notifications,
        BackgroundReminderGateway gateway) =>
    AssignmentStore(
      sessionStore: f.Session(),
      notificationService: notifications,
      widgetSnapshotService: f.WidgetService(),
      chaoxingClient: f.Client(),
      backgroundReminderGateway: gateway,
      nativeReminderDeliveryEnabled: true,
      manageBackgroundSchedule: false,
    );

class _FlakyHealthNotifications extends f.Notifications {
  bool fail = true;

  @override
  Future<ReminderHealth> inspectHealth() async {
    if (fail) throw TimeoutException('synthetic notification health timeout');
    return const ReminderHealth(
      notifications: true,
      exact: true,
      pending: 0,
      summaryPending: 0,
      manualPending: 0,
    );
  }
}

Map<String, Object?> channelRow(String id, String name, int importance) => {
      'id': id,
      'name': name,
      'description': '',
      'groupId': null,
      'showBadge': true,
      'importance': importance,
      'sound': null,
      'playSound': false,
      'enableLights': false,
      'enableVibration': false,
      'vibrationPattern': null,
      'ledColor': 0,
      'audioAttributesUsage': 5,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const permissionsChannel = MethodChannel('study_assistant/permissions');
  final calls = <MethodCall>[];
  final permissionCalls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    calls.clear();
    permissionCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      switch (c.method) {
        case 'areNotificationsEnabled':
          return true;
        case 'canScheduleExactNotifications':
          return false;
        case 'getNotificationChannels':
          return [channelRow('assignment_deadlines', '作业截止提醒', 4)];
        case 'pendingNotificationRequests':
          return [
            {'id': 11, 'title': 'sample', 'body': '', 'payload': 'a:sample'},
            {
              'id': 1900000000,
              'title': 'summary',
              'body': '',
              'payload': 'd:summary'
            },
            {
              'id': 1900000008,
              'title': 'test',
              'body': '',
              'payload': 't:notification-test'
            }
          ];
        case 'getActiveNotifications':
          return [];
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        default:
          return true;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async {
      permissionCalls.add(call);
      if (call.method == 'getAndroidSdkInt') return 35;
      return false;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, null);
  });
  test('privacy tightening cancels existing app reminders before replanning',
      () async {
    final s = LocalNotificationService();
    await s.cancelPrivateSchedules();
    final ids = calls
        .where((c) => c.method == 'cancel')
        .map((c) => (c.arguments as Map)['id']);
    expect(ids, containsAll([11, 1900000000, 1900000008]));
  });
  test('privacy cancellation failure is propagated instead of claiming hidden',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'pendingNotificationRequests') {
        return [
          {'id': 11, 'title': 'sample', 'body': '', 'payload': 'a:sample'}
        ];
      }
      if (c.method == 'getActiveNotifications') return [];
      if (c.method == 'cancel') throw PlatformException(code: 'blocked');
      if (c.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });
    await expectLater(LocalNotificationService().cancelPrivateSchedules(),
        throwsA(isA<StateError>()));
  });
  test('initialization and background rescheduling never request permissions',
      () async {
    final s = LocalNotificationService();
    await s.initialize();
    await s.rescheduleAssignments([]);
    expect(calls.where((c) => c.method.startsWith('request')), isEmpty);
  });
  test(
      'private reminders hide personal titles by default and allow explicit detail',
      () async {
    final s = LocalNotificationService();
    await s.initialize();
    calls.clear();
    final now = DateTime.now();
    final item = ManualEntry(
        id: 'private',
        title: 'PRIVATE TITLE',
        kind: 'exam',
        at: now.add(const Duration(hours: 2)),
        remind: true);
    await s.rescheduleManual([item]);
    final hidden =
        calls.firstWhere((c) => c.method == 'zonedSchedule').arguments as Map;
    expect(hidden['body'].toString(), isNot(contains('PRIVATE TITLE')));
    s.showDetails = true;
    calls.clear();
    await s.rescheduleManual([item]);
    final detail =
        calls.firstWhere((c) => c.method == 'zonedSchedule').arguments as Map;
    expect(detail['body'], contains('PRIVATE TITLE'));
  });
  test(
      'manual scheduling warns when notifications or exact alarms are unavailable',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'areNotificationsEnabled') return false;
      if (call.method == 'canScheduleExactNotifications') return false;
      if (call.method == 'getNotificationChannels') {
        return [
          channelRow('assignment_deadlines', '作业截止提醒', 4),
          channelRow('daily_summary', '每日课业摘要', 3),
          channelRow('personal_schedule', '个人待办与考试提醒', 4),
        ];
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });
    final service = LocalNotificationService();
    final entry = ManualEntry(
      id: 'permission-warning',
      title: '个人安排',
      kind: 'todo',
      at: DateTime.now().add(const Duration(hours: 2)),
      remind: true,
    );

    await service.rescheduleManual([entry]);

    expect(calls.any((call) => call.method == 'zonedSchedule'), isTrue,
        reason: 'saving an arrangement still attempts to retain its schedule');
    expect(service.lastWarning, contains('系统通知权限已关闭'));
    expect(service.lastWarning, contains('精确闹钟权限'));
    expect(calls.any((call) => call.method.startsWith('request')), isFalse);
  });
  test(
      'manual scheduling warns when the personal notification channel is disabled',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'areNotificationsEnabled') return true;
      if (call.method == 'canScheduleExactNotifications') return true;
      if (call.method == 'getNotificationChannels') {
        return [
          channelRow('assignment_deadlines', '作业截止提醒', 4),
          channelRow('daily_summary', '每日课业摘要', 3),
          channelRow('personal_schedule', '个人待办与考试提醒', 0),
        ];
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });
    final service = LocalNotificationService();
    final entry = ManualEntry(
      id: 'channel-warning',
      title: '个人安排',
      kind: 'todo',
      at: DateTime.now().add(const Duration(hours: 2)),
      remind: true,
    );

    await service.rescheduleManual([entry]);

    expect(service.lastWarning, contains('个人日程通知渠道已被系统关闭'));
  });
  test('manual reminder whose 30-minute lead time has passed is reported',
      () async {
    final service = LocalNotificationService();
    await service.rescheduleManual([
      ManualEntry(
        id: 'too-soon',
        title: '即将开始的考试',
        kind: 'exam',
        at: DateTime.now().add(const Duration(minutes: 15)),
        remind: true,
      )
    ]);

    expect(service.lastWarning, contains('提前30分钟提醒时间已过'));
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
  });
  test('manual inexact fallback preserves permission and channel warnings',
      () async {
    var scheduleAttempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') {
        return [channelRow('assignment_deadlines', '作业截止提醒', 4)];
      }
      if (call.method == 'areNotificationsEnabled') return true;
      if (call.method == 'canScheduleExactNotifications') return false;
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        scheduleAttempts++;
        if (scheduleAttempts == 1) {
          throw PlatformException(code: 'exact_alarm_unavailable');
        }
        return null;
      }
      return true;
    });
    final service = LocalNotificationService();
    await service.rescheduleManual([
      ManualEntry(
        id: 'fallback',
        title: '期末考试',
        kind: 'exam',
        at: DateTime.now().add(const Duration(hours: 2)),
        remind: true,
      )
    ]);

    expect(scheduleAttempts, 2,
        reason: 'the exact failure should retry with an inexact alarm');
    expect(service.lastWarning, contains('无法确认个人日程通知渠道状态'));
    expect(service.lastWarning, contains('系统未授予精确闹钟权限'));
    expect(service.lastWarning, contains('近似时间提醒'));
  });
  test(
      'health inspects without permission prompts and test notification is explicit',
      () async {
    final s = LocalNotificationService();
    final h = await s.inspectHealth();
    expect(h.notifications, isTrue);
    expect(h.exact, isFalse);
    expect(h.pending, 1);
    expect(h.summaryPending, 1);
    expect(calls.any((c) => c.method.startsWith('request')), isFalse);
    expect(await s.showTestNotification(), isTrue);
    expect(calls.where((c) => c.method == 'show').length, 1);
    expect(h.assignmentChannel?.status, ReminderChannelStatus.enabled);
    expect(h.summaryChannel?.status, ReminderChannelStatus.missing);
    expect(h.manualChannel?.status, ReminderChannelStatus.missing);
    expect(h.summaryChannelEnabled, isNull);
    expect(h.manualChannelEnabled, isNull);
  });
  test('privacy cleanup waits for an in-flight test notification', () async {
    final healthStarted = Completer<void>();
    final releaseHealth = Completer<void>();
    final events = <String>[];
    final visible = <Map<String, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'getNotificationChannels':
          return [channelRow('assignment_deadlines', '作业截止提醒', 4)];
        case 'areNotificationsEnabled':
          healthStarted.complete();
          await releaseHealth.future;
          return true;
        case 'canScheduleExactNotifications':
          return false;
        case 'pendingNotificationRequests':
          return [];
        case 'getActiveNotifications':
          return visible.toList();
        case 'show':
          final args = call.arguments as Map;
          events.add('show');
          visible.add({
            'id': args['id'],
            'title': args['title'],
            'body': args['body'],
            'payload': args['payload'],
          });
          return true;
        case 'cancel':
          events.add('cancel');
          final id = (call.arguments as Map)['id'];
          visible.removeWhere((item) => item['id'] == id);
          return true;
        default:
          return true;
      }
    });
    final service = LocalNotificationService();
    final showing = service.showTestNotification();
    await healthStarted.future;
    final cleaning = service.cancelPrivateSchedules().then((_) {
      events.add('cleanup-complete');
    });
    // Let an unqueued cleanup finish while the earlier show is still blocked.
    // A correctly serialized cleanup stays pending until releaseHealth completes.
    await Future<void>.delayed(Duration.zero);
    releaseHealth.complete();
    expect(await showing, isTrue);
    await cleaning;
    expect(visible, isEmpty,
        reason: 'an earlier test notification must not appear after cleanup');
    expect(events, ['show', 'cancel', 'cleanup-complete']);
  });
  test('health inspects deadline, summary and personal channels independently',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      if (c.method == 'getNotificationChannels') {
        return [
          channelRow('assignment_deadlines', '作业截止提醒', 4),
          channelRow('daily_summary', '每日课业摘要', 0),
          channelRow('personal_schedule', '个人待办与考试提醒', 2)
        ];
      }
      if (c.method == 'areNotificationsEnabled') return true;
      if (c.method == 'canScheduleExactNotifications') return false;
      if (c.method == 'pendingNotificationRequests') return [];
      return true;
    });
    final health = await LocalNotificationService().inspectHealth();
    expect(health.assignmentChannel?.status, ReminderChannelStatus.enabled);
    expect(health.assignmentChannel?.importance, 4);
    expect(health.summaryChannel?.status, ReminderChannelStatus.disabled);
    expect(health.manualChannel?.status, ReminderChannelStatus.enabled);
    expect(health.manualChannel?.importance, 2);
    expect(
        calls.where((c) => c.method == 'createNotificationChannel'), isEmpty);
  });
  test('initialization provisions all four Android channels in stable order',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'getNotificationChannels') return [];
      return true;
    });
    await LocalNotificationService().initialize();
    expect(
        calls
            .where((call) => call.method == 'createNotificationChannel')
            .map((call) => (call.arguments as Map)['id']),
        [
          'assignment_deadlines',
          'assignment_updates',
          'daily_summary',
          'personal_schedule'
        ]);
    final channels = calls
        .where((call) => call.method == 'createNotificationChannel')
        .map((call) => call.arguments as Map)
        .toList();
    expect(channels.map((channel) => channel['importance']), [4, 3, 3, 4]);
    expect(channels.map((channel) => channel['name']),
        ['作业截止提醒', '作业变化提醒', '每日课业摘要', '个人待办与考试提醒']);
    final initializeIndex =
        calls.indexWhere((call) => call.method == 'initialize');
    final launchIndex = calls
        .indexWhere((call) => call.method == 'getNotificationAppLaunchDetails');
    final channelIndex =
        calls.indexWhere((call) => call.method == 'createNotificationChannel');
    expect(launchIndex, greaterThan(initializeIndex));
    expect(channelIndex, greaterThan(launchIndex));
  });
  test('all schedule entry points provision channels before scheduling',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      return true;
    });
    final service = LocalNotificationService();

    await service.rescheduleAssignments(
        [f.sample('assignment-channel').copyWith(deadlineTrusted: true)],
        offsetsMinutes: [30]);
    var createIndex = calls
        .lastIndexWhere((call) => call.method == 'createNotificationChannel');
    var scheduleIndex =
        calls.indexWhere((call) => call.method == 'zonedSchedule');
    expect(scheduleIndex, greaterThan(createIndex));
    expect(
        calls
            .where((call) => call.method == 'createNotificationChannel')
            .map((call) => (call.arguments as Map)['id']),
        ['assignment_deadlines']);

    calls.clear();
    await service.rescheduleSummary(
        [], PersonalWorkspace(summaryEnabled: true), DateTime.now());
    createIndex = calls
        .lastIndexWhere((call) => call.method == 'createNotificationChannel');
    scheduleIndex = calls.indexWhere((call) => call.method == 'zonedSchedule');
    expect(scheduleIndex, greaterThan(createIndex));
    expect(
        calls
            .where((call) => call.method == 'createNotificationChannel')
            .map((call) => (call.arguments as Map)['id']),
        ['daily_summary']);

    calls.clear();
    await service.rescheduleManual([
      ManualEntry(
          id: 'manual-channel',
          title: '个人安排',
          kind: 'todo',
          at: DateTime.now().add(const Duration(days: 2)),
          remind: true)
    ]);
    createIndex = calls
        .lastIndexWhere((call) => call.method == 'createNotificationChannel');
    scheduleIndex = calls.indexWhere((call) => call.method == 'zonedSchedule');
    expect(scheduleIndex, greaterThan(createIndex));
    expect(
        calls
            .where((call) => call.method == 'createNotificationChannel')
            .map((call) => (call.arguments as Map)['id']),
        ['personal_schedule']);
  });
  test('empty replacement still cancels old reminders without channel creation',
      () async {
    final service = LocalNotificationService();
    await service.initialize();
    calls.clear();
    await service.rescheduleAssignments([], offsetsMinutes: []);
    await service.rescheduleManual([]);
    await service.rescheduleSummary([], PersonalWorkspace(), null);
    expect(calls.where((call) => call.method == 'createNotificationChannel'),
        isEmpty);
    expect(
        calls
            .where((call) => call.method == 'cancel')
            .map((call) => (call.arguments as Map)['id']),
        containsAll([11, 1900000000]));
  });
  test('repeated initialization is safe and retains the same channel IDs',
      () async {
    final created = <String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationChannels') {
        return created
            .map((id) => channelRow(id, id, 4))
            .toList(growable: false);
      }
      if (call.method == 'createNotificationChannel') {
        created.add((call.arguments as Map)['id'] as String);
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'getNotificationChannels') return [];
      return true;
    });
    final service = LocalNotificationService();
    await service.initialize();
    expect(calls.where((call) => call.method == 'createNotificationChannel'),
        hasLength(4));
    calls.clear();
    await service.initialize();
    expect(calls.where((call) => call.method == 'initialize'), isEmpty);
    expect(
        calls
            .where((call) => call.method == 'createNotificationChannel')
            .length,
        0);
    expect(calls.where((call) => call.method == 'deleteNotificationChannel'),
        isEmpty);
  });
  test('concurrent initialization shares plugin and per-channel futures',
      () async {
    final created = <String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationChannels') {
        return created
            .map((id) => channelRow(id, id, 4))
            .toList(growable: false);
      }
      if (call.method == 'createNotificationChannel') {
        created.add((call.arguments as Map)['id'] as String);
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'getNotificationChannels') return [];
      return true;
    });
    final service = LocalNotificationService();
    await Future.wait([service.initialize(), service.initialize()]);
    expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
    expect(calls.where((call) => call.method == 'createNotificationChannel'),
        hasLength(4));
  });
  test('existing channels are not re-registered over user preferences',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationChannels') {
        return [
          channelRow('assignment_deadlines', '用户自定义作业名', 0),
          channelRow('assignment_updates', '用户自定义作业变化名', 1),
          channelRow('daily_summary', '用户自定义摘要名', 2),
          channelRow('personal_schedule', '用户自定义日程名', 1),
        ];
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'areNotificationsEnabled') return true;
      if (call.method == 'canScheduleExactNotifications') return true;
      return true;
    });
    final service = LocalNotificationService();
    await service.initialize();
    expect(calls.where((call) => call.method == 'createNotificationChannel'),
        isEmpty);
    final health = await service.inspectHealth();
    expect(health.assignmentChannel?.status, ReminderChannelStatus.disabled);
    expect(health.summaryChannel?.importance, 2);
    expect(health.manualChannel?.importance, 1);
  });
  test('a new service instance recreates channels after an app restart',
      () async {
    final created = <String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationChannels') {
        return created
            .map((id) => channelRow(id, id, 4))
            .toList(growable: false);
      }
      if (call.method == 'createNotificationChannel') {
        created.add((call.arguments as Map)['id'] as String);
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'getNotificationChannels') return [];
      return true;
    });
    await LocalNotificationService().initialize();
    calls.clear();
    await LocalNotificationService().initialize();
    expect(calls.where((call) => call.method == 'initialize').length, 1);
    expect(calls.where((call) => call.method == 'createNotificationChannel'),
        isEmpty);
  });
  test('channel creation failure blocks scheduling and is retryable', () async {
    var fail = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'createNotificationChannel' &&
          (call.arguments as Map)['id'] == 'personal_schedule' &&
          fail) {
        throw PlatformException(code: 'channel_create_failed');
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      return true;
    });
    final service = LocalNotificationService();
    final entry = ManualEntry(
        id: 'manual-retry',
        title: '重试',
        kind: 'todo',
        at: DateTime.now().add(const Duration(days: 2)),
        remind: true);
    await expectLater(
        service.rescheduleManual([entry]), throwsA(isA<PlatformException>()));
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    fail = false;
    await service.rescheduleManual([entry]);
    expect(calls.where((call) => call.method == 'zonedSchedule'), hasLength(1));
    expect(
        calls
            .where((call) => call.method == 'createNotificationChannel')
            .map((call) => (call.arguments as Map)['id']),
        ['personal_schedule', 'personal_schedule']);
  });
  test('initialization attempts every channel even when one creation fails',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'createNotificationChannel' &&
          (call.arguments as Map)['id'] == 'daily_summary') {
        throw PlatformException(code: 'summary_channel_failed');
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      return true;
    });
    await expectLater(
        LocalNotificationService().initialize(), throwsA(isA<StateError>()));
    expect(
        calls
            .where((call) => call.method == 'createNotificationChannel')
            .map((call) => (call.arguments as Map)['id']),
        [
          'assignment_deadlines',
          'assignment_updates',
          'daily_summary',
          'personal_schedule'
        ]);
  });
  test('a channel failure does not block other reminder categories', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'createNotificationChannel' &&
          (call.arguments as Map)['id'] == 'assignment_deadlines') {
        throw PlatformException(code: 'assignment_channel_failed');
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      return true;
    });
    final service = LocalNotificationService();
    await service.rescheduleAssignments(
        [f.sample('assignment-fails').copyWith(deadlineTrusted: true)],
        offsetsMinutes: [30]);
    expect(service.lastWarning, isNotNull);
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);

    await service.rescheduleSummary(
        [], PersonalWorkspace(summaryEnabled: true), DateTime.now());
    await service.rescheduleManual([
      ManualEntry(
          id: 'manual-survives',
          title: '个人提醒',
          kind: 'todo',
          at: DateTime.now().add(const Duration(days: 2)),
          remind: true)
    ]);
    expect(
        calls
            .where((call) => call.method == 'createNotificationChannel')
            .map((call) => (call.arguments as Map)['id']),
        ['assignment_deadlines', 'daily_summary', 'personal_schedule']);
    expect(calls.where((call) => call.method == 'zonedSchedule'), hasLength(8));
  });
  test('channel query failure blocks replacement but preserves old reminders',
      () async {
    final old = {
      'id': 123,
      'title': '旧提醒',
      'body': 'old',
      'payload': 'a:old',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [old];
      if (call.method == 'getNotificationChannels') {
        throw PlatformException(code: 'channel_list_unavailable');
      }
      return true;
    });
    final service = LocalNotificationService();
    await service.rescheduleAssignments(
        [f.sample('assignment-channel').copyWith(deadlineTrusted: true)],
        offsetsMinutes: [30]);
    expect(service.lastWarning, isNotNull);
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    expect(calls.where((call) => call.method == 'cancel'), isEmpty);
    expect(calls.where((call) => call.method == 'createNotificationChannel'),
        isEmpty);
  });
  test('plugin initialization failure is retryable without duplicate state',
      () async {
    var fail = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize' && fail) {
        throw PlatformException(code: 'initialize_failed');
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      return true;
    });
    final service = LocalNotificationService();
    await expectLater(service.initialize(), throwsA(isA<PlatformException>()));
    expect(calls.where((call) => call.method == 'createNotificationChannel'),
        isEmpty);
    fail = false;
    await service.initialize();
    expect(calls.where((call) => call.method == 'initialize'), hasLength(2));
    expect(calls.where((call) => call.method == 'createNotificationChannel'),
        hasLength(4));
  });
  test('Android 7.1 reports notification channels unsupported, not missing',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async {
      permissionCalls.add(call);
      if (call.method == 'getAndroidSdkInt') return 25;
      return false;
    });
    final health = await LocalNotificationService().inspectHealth();
    expect(health.assignmentChannel?.status, ReminderChannelStatus.unsupported);
    expect(health.summaryChannel?.status, ReminderChannelStatus.unsupported);
    expect(health.manualChannel?.status, ReminderChannelStatus.unsupported);
    expect(
        calls.any((call) => call.method == 'getNotificationChannels'), isFalse);
    expect(await LocalNotificationService().showTestNotification(), isTrue);
  });
  test('channel query errors are reported separately from missing channels',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationChannels') {
        throw PlatformException(code: 'channel_query_failed');
      }
      if (call.method == 'pendingNotificationRequests') return [];
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async {
      permissionCalls.add(call);
      if (call.method == 'getAndroidSdkInt') return 35;
      return false;
    });
    final health = await LocalNotificationService().inspectHealth();
    expect(health.assignmentChannel?.status, ReminderChannelStatus.queryFailed);
    expect(health.summaryChannel?.status, ReminderChannelStatus.queryFailed);
    expect(health.manualChannel?.status, ReminderChannelStatus.queryFailed);
  });
  test('Android SDK query errors are reported as channel query failures',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async {
      permissionCalls.add(call);
      throw PlatformException(code: 'sdk_query_failed');
    });
    final health = await LocalNotificationService().inspectHealth();
    expect(health.assignmentChannel?.status, ReminderChannelStatus.queryFailed);
    expect(health.summaryChannel?.status, ReminderChannelStatus.queryFailed);
    expect(health.manualChannel?.status, ReminderChannelStatus.queryFailed);
    expect(
        calls.any((call) => call.method == 'getNotificationChannels'), isFalse);
  });
  test('non-Android platforms report notification channels unsupported',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final health = await LocalNotificationService().inspectHealth();
    expect(health.assignmentChannel?.status, ReminderChannelStatus.unsupported);
    expect(health.summaryChannel?.status, ReminderChannelStatus.unsupported);
    expect(health.manualChannel?.status, ReminderChannelStatus.unsupported);
    expect(permissionCalls.any((call) => call.method == 'getAndroidSdkInt'),
        isFalse);
  });
  testWidgets('health page displays the three channel states separately',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      if (c.method == 'getNotificationChannels') {
        return [
          channelRow('assignment_deadlines', '作业截止提醒', 4),
          channelRow('daily_summary', '每日课业摘要', 0),
          channelRow('personal_schedule', '个人待办与考试提醒', 2)
        ];
      }
      if (c.method == 'areNotificationsEnabled') return true;
      if (c.method == 'canScheduleExactNotifications') return true;
      if (c.method == 'pendingNotificationRequests') return [];
      return true;
    });
    final store =
        f.makeStore(f.Session(), notifications: InspectableNotifications());
    addTearDown(store.dispose);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    await store.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final deadline =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '截止提醒通知渠道'));
    final summary =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '每日摘要通知渠道'));
    final personal =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '个人日程通知渠道'));
    expect((deadline.subtitle as Text).data, '已开启（高重要性）');
    expect((summary.subtitle as Text).data, '已关闭（系统设置）');
    expect((personal.subtitle as Text).data, '已开启（低重要性）');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('health page explains a missing channel list fallback',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      if (c.method == 'getNotificationChannels') {
        return [
          channelRow('assignment_updates', '作业变化提醒', 3),
          channelRow('assignment_deadlines', '作业截止提醒', 4),
        ];
      }
      if (c.method == 'areNotificationsEnabled') return true;
      if (c.method == 'canScheduleExactNotifications') return true;
      if (c.method == 'pendingNotificationRequests') return [];
      return true;
    });
    final store =
        f.makeStore(f.Session(), notifications: InspectableNotifications());
    addTearDown(store.dispose);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    await store.restoreSession();
    final permissions = _HealthPermissionSettingsService(
      channelResult: SettingsOpenResult.listFallback,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderHealthScreen(
          store: store,
          permissionSettingsService: permissions,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tile = find.widgetWithText(ListTile, '作业变化通知渠道');
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(permissions.requestedChannelId, 'assignment_updates');
    expect(find.textContaining('已打开相关系统设置列表'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('health page refreshes after returning to the foreground',
      (tester) async {
    final notifications = CountingHealthNotifications();
    final store = f.makeStore(f.Session(), notifications: notifications);
    addTearDown(store.dispose);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    await store.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(notifications.inspections, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(notifications.inspections, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('health refresh clears busy state when inspection throws',
      (tester) async {
    final store =
        f.makeStore(f.Session(), notifications: ThrowingHealthNotifications());
    addTearDown(store.dispose);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    await store.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.scrollUntilVisible(find.text('重新体检'), 200);
    final refresh = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '重新体检'));
    expect(refresh.onPressed, isNotNull,
        reason: 'inspection failure must not leave the page busy');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('nativeHealthFailureNeverFabricatesZeroCounts', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'legacy_assignment_schedule_cleanup_v2': true,
    });
    final gateway = _HealthGateway()..failInspections = true;
    final store = _nativeHealthStore(InspectableNotifications(), gateway);
    addTearDown(store.dispose);
    await store.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('原生后台提醒状态暂时无法读取，可重试'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('学习通通知使用权'), 200);
    final listener =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '学习通通知使用权'));
    expect((listener.subtitle as Text).data, '暂时无法读取，可重试',
        reason: '读取失败不能被显示成“默认关闭”');
    await tester.scrollUntilVisible(find.textContaining('原生作业截止事件'), 200);
    expect(find.textContaining('原生作业截止事件：暂时无法读取，可重试'), findsOneWidget);
    expect(find.textContaining('待处理新增作业事件：暂时无法读取，可重试'), findsOneWidget);
    expect(find.textContaining('原生作业截止事件：0 条'), findsNothing);
    expect(find.textContaining('待处理新增作业事件：0 条'), findsNothing);
    expect(find.textContaining('当前平台不适用'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('healthInspectionTimeoutKeepsLastResultAndIsRetryable',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'legacy_assignment_schedule_cleanup_v2': true,
    });
    final gateway = _HealthGateway()
      ..nextHealth = nativeHealth(pendingDeadlineCount: 3, pendingNewCount: 1);
    final store = _nativeHealthStore(InspectableNotifications(), gateway);
    addTearDown(store.dispose);
    await store.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.scrollUntilVisible(find.textContaining('原生作业截止事件'), 200);
    expect(find.textContaining('原生作业截止事件：3 条'), findsOneWidget);

    gateway.failInspections = true;
    await tester.scrollUntilVisible(find.text('重新体检'), 200);
    await tester.tap(find.text('重新体检'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.scrollUntilVisible(
        find.textContaining('原生作业截止事件：3 条（上次结果）'), -200);
    expect(find.textContaining('原生作业截止事件：3 条（上次结果）'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('以下标注“上次结果”'), -200);
    expect(find.textContaining('原生后台提醒状态暂时无法读取，可重试'), findsOneWidget);

    gateway.failInspections = false;
    gateway.nextHealth = nativeHealth(pendingDeadlineCount: 2);
    await tester.scrollUntilVisible(find.text('重新体检'), 200);
    await tester.tap(find.text('重新体检'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.scrollUntilVisible(find.textContaining('原生作业截止事件'), -200);
    expect(find.textContaining('原生作业截止事件：2 条'), findsOneWidget);
    expect(find.textContaining('原生作业截止事件：2 条（上次结果）'), findsNothing);
    expect(find.textContaining('上次结果'), findsNothing);
    await tester.scrollUntilVisible(find.text('先确认提醒能到达'), -200);
    expect(find.textContaining('暂时无法读取，可重试'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('unsupportedPlatformDiffersFromInspectionFailure',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'legacy_assignment_schedule_cleanup_v2': true,
    });
    final unsupportedGateway = _HealthGateway(available: false);
    final unsupported =
        _nativeHealthStore(InspectableNotifications(), unsupportedGateway);
    addTearDown(unsupported.dispose);
    await unsupported.restoreSession();
    await tester.pumpWidget(
        MaterialApp(home: ReminderHealthScreen(store: unsupported)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('暂时无法读取，可重试'), findsNothing);
    expect(unsupportedGateway.inspections, 0);
    await tester.scrollUntilVisible(find.text('学习通通知使用权'), 200);
    final listener =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '学习通通知使用权'));
    expect((listener.subtitle as Text).data, '当前平台不适用');
    await tester.scrollUntilVisible(find.textContaining('原生作业截止事件'), 200);
    expect(find.textContaining('原生作业截止事件：当前平台不适用'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    final failingGateway = _HealthGateway()..failInspections = true;
    final failing =
        _nativeHealthStore(InspectableNotifications(), failingGateway);
    addTearDown(failing.dispose);
    await failing.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: failing)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('原生后台提醒状态暂时无法读取，可重试'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('学习通通知使用权'), 200);
    final failingListener =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '学习通通知使用权'));
    expect((failingListener.subtitle as Text).data, '暂时无法读取，可重试');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('successfulRetryClearsStaleError', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'legacy_assignment_schedule_cleanup_v2': true,
    });
    final notifications = _FlakyHealthNotifications();
    final store = _nativeHealthStore(notifications, _HealthGateway());
    addTearDown(store.dispose);
    await store.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('系统通知与排期体检暂时无法读取，可重试'), findsOneWidget);

    notifications.fail = false;
    await tester.scrollUntilVisible(find.text('重新体检'), 200);
    await tester.tap(find.text('重新体检'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.scrollUntilVisible(find.textContaining('已安排摘要'), 200);
    expect(find.textContaining('已安排摘要：0 条'), findsOneWidget);
    expect(find.textContaining('原生作业截止事件：0 条'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('先确认提醒能到达'), -200);
    expect(find.textContaining('暂时无法读取，可重试'), findsNothing);
    expect(find.textContaining('上次结果'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
      'reminder recovery finishing after dispose causes no state update',
      (tester) async {
    final notifications = PendingRecoveryNotifications();
    final store = f.makeStore(f.Session(), notifications: notifications);
    addTearDown(store.dispose);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    await store.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.scrollUntilVisible(find.text('重试提醒恢复'), 200);
    await tester.tap(find.text('重试提醒恢复'));
    await notifications.recoveryStarted.future;
    await tester.pumpWidget(const SizedBox.shrink());
    notifications.recoveryFinish.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('failed reminder recovery after dispose causes no state update',
      (tester) async {
    final notifications = PendingRecoveryNotifications()
      ..failAfterFinish = true;
    final store = f.makeStore(f.Session(), notifications: notifications);
    addTearDown(store.dispose);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    await store.restoreSession();
    await tester
        .pumpWidget(MaterialApp(home: ReminderHealthScreen(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.scrollUntilVisible(find.text('重试提醒恢复'), 200);
    await tester.tap(find.text('重试提醒恢复'));
    await notifications.recoveryStarted.future;
    await tester.pumpWidget(const SizedBox.shrink());
    notifications.recoveryFinish.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
  test('summary stages a new seven-ID batch before retiring the old batch',
      () async {
    final active = <int, Map>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = call.arguments as Map;
        active[args['id'] as int] = Map.from(args);
        return null;
      }
      if (call.method == 'cancel') {
        active.remove((call.arguments as Map)['id']);
        return null;
      }
      return true;
    });
    final s = LocalNotificationService();
    await s.initialize();
    calls.clear();
    await s.rescheduleSummary(
        [], PersonalWorkspace(summaryEnabled: true), DateTime.now());
    final first = calls
        .where((c) => c.method == 'zonedSchedule')
        .map((c) => (c.arguments as Map)['id'])
        .toList();
    expect(first.length, 7);
    calls.clear();
    await s.rescheduleSummary(
        [], PersonalWorkspace(summaryEnabled: true), DateTime.now());
    final second = calls
        .where((c) => c.method == 'zonedSchedule')
        .map((c) => (c.arguments as Map)['id'])
        .toList();
    expect(second, hasLength(7));
    expect(second.toSet().intersection(first.toSet()), isEmpty);
    expect(active.keys.toSet(), second.toSet());
    expect(
        calls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map)['id'])
            .toSet(),
        first.toSet());
    calls.clear();
    await s.rescheduleSummary([], PersonalWorkspace(), null);
    expect(
        calls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map)['id'])
            .toSet(),
        second.toSet());
    expect(active, isEmpty);
  });
  test('personal reminder schedules only future unfinished opted-in entries',
      () async {
    final s = LocalNotificationService();
    await s.initialize();
    calls.clear();
    final at = DateTime.now().toUtc().add(const Duration(days: 2));
    final entry = ManualEntry(
        id: 'm1', title: 'exam', kind: 'exam', at: at, remind: true);
    await s.rescheduleManual([
      entry,
      entry.completed(true),
      const ManualEntry(id: 'none', title: 'none', kind: 'todo')
    ]);
    final scheduled = calls.where((c) => c.method == 'zonedSchedule').single;
    expect((scheduled.arguments as Map)['payload'], 'p:m1');
    final id = (scheduled.arguments as Map)['id'];
    calls.clear();
    await s.rescheduleManual([entry]);
    final replacementId = (calls
        .singleWhere((c) => c.method == 'zonedSchedule')
        .arguments as Map)['id'];
    expect(replacementId, isNot(id));
    expect(
        calls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map)['id']),
        contains(id));
    calls.clear();
    await s.rescheduleManual([]);
    expect(
        calls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map)['id']),
        contains(replacementId));
  });
  test('personal IDs cannot overwrite homework IDs with known colliding inputs',
      () async {
    final s = LocalNotificationService();
    await s.initialize();
    calls.clear();
    await s.rescheduleAssignments([f.sample('106040')], offsetsMinutes: [30]);
    final workId = (calls
        .singleWhere((c) => c.method == 'zonedSchedule')
        .arguments as Map)['id'];
    calls.clear();
    await s.rescheduleManual([
      ManualEntry(
          id: 'm1800000000086842',
          title: 'personal',
          kind: 'todo',
          at: DateTime.utc(2030),
          remind: true)
    ]);
    final manualId = (calls
        .singleWhere((c) => c.method == 'zonedSchedule')
        .arguments as Map)['id'];
    expect(manualId, isNot(workId));
  });

  test('failed personal batch preserves removed and existing reminders',
      () async {
    final service = LocalNotificationService();
    await service.initialize();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      if (c.method == 'pendingNotificationRequests') {
        return [
          {
            'id': 1800000001,
            'title': 'removed',
            'body': '',
            'payload': 'p:removed'
          }
        ];
      }
      if (c.method == 'zonedSchedule') {
        throw PlatformException(code: 'schedule_failed');
      }
      if (c.method == 'getNotificationChannels') return [];
      return true;
    });
    await expectLater(
        service.rescheduleManual([
          ManualEntry(
              id: 'other',
              title: 'other',
              kind: 'todo',
              at: DateTime.utc(2030),
              remind: true)
        ]),
        throwsA(isA<PlatformException>()));
    expect(
        calls.any((c) =>
            c.method == 'cancel' && (c.arguments as Map)['id'] == 1800000001),
        isFalse,
        reason: 'the old batch is retained until the replacement commits');
  });
  test(
      'privacy cancellation also clears delivered IDs from the active manifest',
      () async {
    final active = <int, Map>{};
    final visible = <Map<String, Object?>>[];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        active[args['id'] as int] = args;
        return null;
      }
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        active.remove(id);
        return null;
      }
      return true;
    });
    final service = LocalNotificationService();
    await service.rescheduleManual([
      ManualEntry(
          id: 'delivered-private',
          title: '已送达的个人事项',
          kind: 'todo',
          at: DateTime.now().add(const Duration(days: 2)),
          remind: true)
    ]);
    final deliveredId = active.keys.single;
    visible
        .addAll(active.values.map((item) => Map<String, Object?>.from(item)));
    active.clear(); // The OS has delivered it; it is no longer pending.
    calls.clear();
    // The delivered notification remains visible to NotificationManager.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return visible;
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        visible.removeWhere((item) => item['id'] == id);
        return null;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });
    await service.cancelPrivateSchedules();
    expect(cancelled, contains(deliveredId));
    expect(active, isEmpty);
  });
  test(
      'privacy cleanup cancels known notifications despite a damaged channel manifest',
      () async {
    const deliveredManualId = 1800000091;
    const journalOldId = 1800000092;
    const journalNewId = 2000000092;
    final pending = <Map<String, Object?>>[
      {'id': 901, 'title': '作业', 'body': 'private', 'payload': 'a:work'},
      {'id': 902, 'title': '个人事项', 'body': 'private', 'payload': 'p:todo'},
      {'id': 903, 'title': '摘要', 'body': 'private', 'payload': 'd:summary'},
      {'id': 904, 'title': 'other', 'body': '', 'payload': 'external:other'},
    ];
    final cancelled = <int>[];
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_assignments': ['not-an-id'],
      'notification_schedule_v2_journal_assignments': '{broken-json',
      'notification_schedule_v2_active_manual': ['$deliveredManualId'],
      'notification_schedule_v2_journal_summary': jsonEncode({
        'version': 1,
        'phase': 'committed',
        'oldIds': [journalOldId],
        'newIds': [journalNewId],
      }),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') return pending;
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.cancelPrivateSchedules(), throwsStateError);

    expect(
        cancelled,
        containsAll(
            [901, 902, 903, deliveredManualId, journalOldId, journalNewId]));
    expect(cancelled, isNot(contains(904)),
        reason: 'non-app notifications must not be cancelled');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getStringList('notification_schedule_v2_active_assignments'),
        ['not-an-id'],
        reason: 'damaged metadata must remain visible for manual recovery');
    expect(prefs.getString('notification_schedule_v2_journal_assignments'),
        '{broken-json',
        reason:
            'damaged transaction metadata must remain visible for recovery');
    expect(prefs.getStringList('notification_schedule_v2_active_manual'), []);
    expect(prefs.getString('notification_schedule_v2_journal_summary'), isNull);
    expect(await service.hasPendingScheduleRecovery(), isTrue);
    expect(service.lastWarning, contains('无法确认'));
  });
  test(
      'privacy cleanup repairs a damaged active manifest when its journal is valid',
      () async {
    const oldId = 1800000101;
    const newId = 2000000101;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_assignments': ['not-an-id'],
      'notification_schedule_v2_journal_assignments': jsonEncode({
        'version': 1,
        'phase': 'committed',
        'oldIds': [oldId],
        'newIds': [newId],
      }),
    });
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await service.cancelPrivateSchedules();

    expect(cancelled, containsAll([oldId, newId]));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
        prefs.getStringList('notification_schedule_v2_active_assignments'), []);
    expect(prefs.getString('notification_schedule_v2_journal_assignments'),
        isNull);
    expect(await service.hasPendingScheduleRecovery(), isFalse);
  });
  test(
      'privacy cleanup cancels pending private notifications despite a corrupt journal',
      () async {
    const pendingAssignmentId = 911;
    const deliveredManualId = 1800000093;
    const activeDeliveredId = 916;
    const summaryJournalOldId = 1900000094;
    const summaryJournalNewId = 2000000095;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_journal_assignments': '{broken-json',
      'notification_schedule_v2_active_manual': ['$deliveredManualId'],
      'notification_schedule_v2_journal_summary': jsonEncode({
        'version': 1,
        'phase': 'committed',
        'oldIds': [summaryJournalOldId],
        'newIds': [summaryJournalNewId],
      }),
    });
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pendingNotificationRequests') {
        return [
          {
            'id': pendingAssignmentId,
            'title': '作业',
            'body': 'private',
            'payload': 'a:work',
          },
          {
            'id': 912,
            'title': '其他',
            'body': '',
            'payload': 'external:other',
          },
        ];
      }
      if (call.method == 'getActiveNotifications') {
        return [
          {
            'id': activeDeliveredId,
            'title': '个人安排',
            'body': 'private',
            'payload': 'p:delivered',
          },
        ];
      }
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.cancelPrivateSchedules(), throwsStateError);

    expect(
        cancelled,
        containsAll([
          pendingAssignmentId,
          deliveredManualId,
          activeDeliveredId,
          summaryJournalOldId,
          summaryJournalNewId,
        ]));
    expect(cancelled, isNot(contains(912)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('notification_schedule_v2_journal_assignments'),
        '{broken-json',
        reason: 'damaged journal must remain visible for recovery');
    expect(prefs.getStringList('notification_schedule_v2_active_manual'), []);
    expect(prefs.getString('notification_schedule_v2_journal_summary'), isNull);
    expect(service.lastWarning, contains('无法确认'));
  });
  test(
      'privacy cleanup cancels visible private notifications when manifests are missing',
      () async {
    const deliveredId = 917;
    SharedPreferences.setMockInitialValues({});
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') {
        return [
          {
            'id': deliveredId,
            'title': '私人提醒',
            'body': 'private',
            'payload': 'p:visible',
          },
        ];
      }
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });

    final service = LocalNotificationService();
    await service.cancelPrivateSchedules();

    expect(cancelled, [deliveredId]);
    expect(service.lastWarning, isNull);
  });
  test(
      'startup detects and cancels transactional IDs orphaned from a missing journal',
      () async {
    const oldId = 701;
    const orphanId = 2000000702;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_assignments': ['$oldId'],
    });
    final pending = <Map<String, Object?>>[
      {'id': oldId, 'title': 'old', 'body': '', 'payload': 'a:old'},
      {'id': orphanId, 'title': 'new', 'body': '', 'payload': 'a:new'},
    ];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return pending;
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        pending.removeWhere((item) => item['id'] == id);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    expect(await service.hasPendingScheduleRecovery(), isTrue);
    await service.recoverPendingSchedules();

    expect(cancelled, [orphanId]);
    expect(pending.map((item) => item['id']), contains(oldId));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('notification_schedule_v2_journal_assignments'),
        isNull);
    expect(prefs.getStringList('notification_schedule_v2_active_assignments'),
        ['$oldId']);
    expect(await service.hasPendingScheduleRecovery(), isFalse);
  });
  test('startup preserves orphan IDs when the active manifest is also missing',
      () async {
    const orphanId = 2000000712;
    SharedPreferences.setMockInitialValues({});
    final pending = <Map<String, Object?>>[
      {'id': orphanId, 'title': 'new', 'body': '', 'payload': 'p:new'},
    ];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return pending;
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.recoverPendingSchedules(), throwsStateError);

    expect(cancelled, isEmpty,
        reason:
            'without a manifest recovery cannot distinguish old and new batches');
    expect(pending, hasLength(1));
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });
  test('startup refuses a v2 journal copied into another notification category',
      () async {
    const oldManualId = 718;
    const newManualId = 2000000719;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_manual': ['$oldManualId'],
      'notification_schedule_v2_journal_assignments': jsonEncode({
        'version': 2,
        'category': 'manual',
        'phase': 'committed',
        'oldIds': [oldManualId],
        'newIds': [newManualId],
      }),
    });
    final pending = <Map<String, Object?>>[
      {'id': oldManualId, 'title': 'old', 'body': '', 'payload': 'p:old'},
      {'id': newManualId, 'title': 'new', 'body': '', 'payload': 'p:new'},
    ];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return pending;
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.recoverPendingSchedules(), throwsStateError);

    expect(cancelled, isEmpty,
        reason: 'the assignment recovery path must not cancel manual IDs');
    expect(pending, hasLength(2));
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });
  test('startup refuses v2 IDs recorded in another category manifest',
      () async {
    const oldForeignId = 730;
    const newForeignId = 2000000731;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_manual': [
        '$oldForeignId',
        '$newForeignId',
      ],
      'notification_schedule_v2_journal_assignments': jsonEncode({
        'version': 2,
        'category': 'assignments',
        'phase': 'committed',
        'oldIds': [oldForeignId],
        'newIds': [newForeignId],
      }),
    });
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.recoverPendingSchedules(), throwsStateError);

    expect(cancelled, isEmpty,
        reason: 'a foreign manifest disproves the v2 category ownership');
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });
  test('startup refuses v2 IDs proven foreign by pending or active payload',
      () async {
    const oldForeignId = 732;
    const newForeignId = 2000000733;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_journal_assignments': jsonEncode({
        'version': 2,
        'category': 'assignments',
        'phase': 'committed',
        'oldIds': [oldForeignId],
        'newIds': [newForeignId],
      }),
    });
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') {
        return [
          {
            'id': newForeignId,
            'title': 'manual new',
            'body': '',
            'payload': 'p:new',
          },
        ];
      }
      if (call.method == 'getActiveNotifications') {
        return [
          {
            'id': oldForeignId,
            'title': 'manual old',
            'body': '',
            'payload': 'p:old',
          },
        ];
      }
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.recoverPendingSchedules(), throwsStateError);

    expect(cancelled, isEmpty);
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });
  test('startup refuses visible v2 IDs without category evidence', () async {
    const oldId = 734;
    const newId = 2000000735;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_journal_assignments': jsonEncode({
        'version': 2,
        'category': 'assignments',
        'phase': 'committed',
        'oldIds': [oldId],
        'newIds': [newId],
      }),
    });
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') {
        return [
          {'id': oldId, 'title': 'unknown', 'body': '', 'payload': null},
        ];
      }
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.recoverPendingSchedules(), throwsStateError);

    expect(cancelled, isEmpty);
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });
  test(
      'startup refuses a legacy v1 journal whose IDs belong to another category',
      () async {
    const oldAssignmentId = 720;
    const oldManualId = 721;
    const newAssignmentId = 2000000720;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_assignments': ['$oldAssignmentId'],
      'notification_schedule_v2_active_manual': ['$oldManualId'],
      'notification_schedule_v2_journal_manual': jsonEncode({
        'version': 1,
        'phase': 'committed',
        'oldIds': [oldAssignmentId],
        'newIds': [newAssignmentId],
      }),
    });
    final pending = <Map<String, Object?>>[
      {
        'id': oldAssignmentId,
        'title': '作业旧提醒',
        'body': '',
        'payload': 'a:old',
      },
      {
        'id': newAssignmentId,
        'title': '作业新提醒',
        'body': '',
        'payload': 'a:new',
      },
      {
        'id': oldManualId,
        'title': '个人旧提醒',
        'body': '',
        'payload': 'p:old',
      },
    ];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return pending;
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.recoverPendingSchedules(), throwsStateError);

    expect(cancelled, isEmpty,
        reason: 'v1 journal ownership cannot be inferred from its key alone');
    expect(pending, hasLength(3));
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });
  test('startup does not trust a v1 journal copied with its active manifest',
      () async {
    const oldId = 724;
    const newId = 2000000725;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_manual': ['$newId'],
      'notification_schedule_v2_journal_manual': jsonEncode({
        'version': 1,
        'phase': 'committed',
        'oldIds': [oldId],
        'newIds': [newId],
      }),
    });
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.recoverPendingSchedules(), throwsStateError);

    expect(cancelled, isEmpty,
        reason:
            'the journal and adjacent manifest are not independent ownership evidence');
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });
  test(
      'startup recovers a delivered orphan transaction from active notifications',
      () async {
    const oldId = 722;
    const deliveredOrphanId = 2000000723;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_assignments': ['$oldId'],
    });
    final pending = <Map<String, Object?>>[
      {'id': oldId, 'title': 'old', 'body': '', 'payload': 'a:old'},
    ];
    final active = <Map<String, Object?>>[
      {
        'id': deliveredOrphanId,
        'title': 'new delivered',
        'body': '',
        'payload': 'a:new',
      },
    ];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return pending;
      if (call.method == 'getActiveNotifications') return active;
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        active.removeWhere((item) => item['id'] == id);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    expect(await service.hasPendingScheduleRecovery(), isTrue);
    await service.recoverPendingSchedules();

    expect(cancelled, [deliveredOrphanId]);
    expect(active, isEmpty);
    expect(pending.map((item) => item['id']), [oldId]);
    expect(await service.hasPendingScheduleRecovery(), isFalse);
  });
  test(
      'privacy cleanup continues cancelling after one notification cancel fails',
      () async {
    const failedId = 913;
    const succeedingId = 914;
    const pendingId = 915;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_manual': ['$failedId', '$succeedingId'],
    });
    final attempted = <int>[];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pendingNotificationRequests') {
        return [
          {'id': pendingId, 'title': '个人', 'body': '', 'payload': 'p:todo'},
        ];
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        attempted.add(id);
        if (id == failedId) throw PlatformException(code: 'blocked');
        cancelled.add(id);
        return null;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return true;
    });

    final service = LocalNotificationService();
    await expectLater(service.cancelPrivateSchedules(), throwsStateError);

    expect(attempted, containsAll([failedId, succeedingId, pendingId]));
    expect(cancelled, containsAll([succeedingId, pendingId]));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getStringList('notification_schedule_v2_active_manual'),
        containsAll(['$failedId', '$succeedingId']),
        reason:
            'metadata stays available for retry after any cancellation failure');
  });
  test('the Nth assignment schedule failure compensates staged IDs only',
      () async {
    final active = <int, Map>{
      701: {'id': 701, 'title': 'old', 'body': '', 'payload': 'a:old'},
    };
    final cancelled = <int>[];
    int? failedId;
    int? firstId;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        final id = args['id'] as int;
        if (firstId == null) {
          firstId = id;
        } else if (id != firstId) {
          failedId ??= id;
        }
        if (id == failedId) {
          throw PlatformException(code: 'nth_schedule_failed');
        }
        active[id] = args;
        return null;
      }
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        active.remove(id);
        return null;
      }
      return true;
    });
    final service = LocalNotificationService();
    await service.rescheduleAssignments([
      f.sample('batch-a').copyWith(deadlineTrusted: true),
      f.sample('batch-b').copyWith(deadlineTrusted: true),
    ], offsetsMinutes: [
      30
    ]);
    expect(service.lastWarning, contains('未能完整更新'));
    expect(active.keys, [701]);
    expect(cancelled, hasLength(2),
        reason: 'compensation cancels the scheduled and not-yet-scheduled IDs');
    expect(await service.hasPendingScheduleRecovery(), isFalse);
  });
  test('compensation cancellation failure persists and startup retries it',
      () async {
    final active = <int, Map>{
      702: {'id': 702, 'title': 'old', 'body': '', 'payload': 'a:old'},
    };
    int? failedId;
    int? firstId;
    var failCompensation = true;
    var failedNewId = -1;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        final id = args['id'] as int;
        if (firstId == null) {
          firstId = id;
        } else if (id != firstId) {
          failedId ??= id;
        }
        if (id == failedId) {
          throw PlatformException(code: 'nth_schedule_failed');
        }
        failedNewId = id;
        active[failedNewId] = args;
        return null;
      }
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        if (id == failedNewId && failCompensation) {
          throw PlatformException(code: 'compensation_failed');
        }
        active.remove(id);
        return null;
      }
      return true;
    });
    final service = LocalNotificationService();
    await service.rescheduleAssignments([
      f.sample('compensate-a').copyWith(deadlineTrusted: true),
      f.sample('compensate-b').copyWith(deadlineTrusted: true),
    ], offsetsMinutes: [
      30
    ]);
    expect(service.lastWarning, contains('临时提醒'));
    expect(active.keys, containsAll([702, failedNewId]));
    expect(await service.hasPendingScheduleRecovery(), isTrue);

    failCompensation = false;
    final restarted = LocalNotificationService();
    await restarted.initialize();
    expect(active.keys, [702]);
    expect(await restarted.hasPendingScheduleRecovery(), isFalse);
  });
  test('old-batch cancellation failure keeps committed journal for retry',
      () async {
    final active = <int, Map>{
      703: {'id': 703, 'title': 'old', 'body': '', 'payload': 'a:old'},
    };
    var failOldCancellation = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        active[args['id'] as int] = args;
        return null;
      }
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        if (id == 703 && failOldCancellation) {
          throw PlatformException(code: 'old_cancel_failed');
        }
        active.remove(id);
        return null;
      }
      return true;
    });
    final service = LocalNotificationService();
    await service.rescheduleAssignments(
        [f.sample('committed').copyWith(deadlineTrusted: true)],
        offsetsMinutes: [30]);
    expect(service.lastWarning, contains('旧通知清理失败'));
    expect(active.length, 2,
        reason: 'new batch is committed while old cancellation is pending');
    expect(await service.hasPendingScheduleRecovery(), isTrue);

    failOldCancellation = false;
    await LocalNotificationService().initialize();
    expect(active.length, 1);
    expect(active.values.single['payload'], startsWith('a:'));
    expect(await service.hasPendingScheduleRecovery(), isFalse);
  });

  test('commit journal write that throws after durable write keeps new batch',
      () async {
    final store = _NotificationJournalStore()..throwAfterCommitWrite = true;
    SharedPreferencesStorePlatform.instance = store;
    final active = <int, Map>{
      804: {'id': 804, 'title': 'old', 'body': '', 'payload': 'a:old'},
    };
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        active[args['id'] as int] = args;
        return null;
      }
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        active.remove(id);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await service.rescheduleAssignments(
        [f.sample('commit-ack-lost').copyWith(deadlineTrusted: true)],
        offsetsMinutes: [30]);

    expect(active.length, 1,
        reason: 'read-back must recognize the committed marker as durable');
    expect(active.values.single['payload'], contains('commit-ack-lost'));
    expect(cancelled, contains(804));
    expect(await service.hasPendingScheduleRecovery(), isFalse);
  });

  test('commit journal write rejected before persistence compensates new IDs',
      () async {
    final store = _NotificationJournalStore()..rejectCommitWrite = true;
    SharedPreferencesStorePlatform.instance = store;
    final active = <int, Map>{
      805: {'id': 805, 'title': 'old', 'body': '', 'payload': 'a:old'},
    };
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        active[args['id'] as int] = args;
        return null;
      }
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        active.remove(id);
        return null;
      }
      return true;
    });

    final service = LocalNotificationService();
    await service.rescheduleAssignments(
        [f.sample('commit-write-failed').copyWith(deadlineTrusted: true)],
        offsetsMinutes: [30]);

    expect(service.lastWarning, contains('未能完整更新'));
    expect(active.keys, [805]);
    expect(cancelled, isNotEmpty);
    expect(await service.hasPendingScheduleRecovery(), isFalse);
  });
  test(
      'missing commit journal and failed repair are recovered from orphan pending IDs',
      () async {
    final store = _NotificationJournalStore()
      ..loseStagingBeforeCommit = true
      ..rejectStagingRepair = true;
    await store.setValue('StringList',
        'flutter.notification_schedule_v2_active_assignments', ['808']);
    SharedPreferencesStorePlatform.instance = store;
    final active = <int, Map>{
      808: {'id': 808, 'title': 'old', 'body': '', 'payload': 'a:old'},
    };
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        active[args['id'] as int] = args;
        return null;
      }
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        active.remove(id);
        return null;
      }
      return true;
    });

    final firstProcess = LocalNotificationService();
    await firstProcess.rescheduleAssignments(
        [f.sample('orphaned-commit').copyWith(deadlineTrusted: true)],
        offsetsMinutes: [30]);

    expect(firstProcess.lastWarning, contains('无法重建恢复记录'));
    expect(active.length, 2,
        reason:
            'the failed repair must not guess which batch is authoritative');
    expect(await firstProcess.hasPendingScheduleRecovery(), isTrue,
        reason: 'an unmanifested transactional ID is visible as recovery work');

    final restarted = LocalNotificationService();
    await restarted.initialize();

    expect(active.keys, [808]);
    expect(cancelled, hasLength(1));
    expect(cancelled.single, isNot(808));
    expect(await restarted.hasPendingScheduleRecovery(), isFalse);
  });

  test('corrupt assignment journal is visible and does not block summary',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_journal_assignments': '{broken-json',
    });
    final active = <int, Map>{
      806: {'id': 806, 'title': 'old', 'body': '', 'payload': 'a:old'},
    };
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        active[args['id'] as int] = args;
        return null;
      }
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        active.remove(id);
        return null;
      }
      return true;
    });
    final service = LocalNotificationService();
    await expectLater(service.initialize(), throwsStateError);
    expect(await service.hasPendingScheduleRecovery(), isTrue);
    await expectLater(service.recoverPendingSchedules(), throwsStateError);

    await service.rescheduleSummary(
        [], PersonalWorkspace(summaryEnabled: true), DateTime.now());

    expect(active.containsKey(806), isTrue,
        reason: 'corrupt assignment journal must not cancel old homework');
    expect(active.values.where((item) => item['payload'] == 'd:summary'),
        hasLength(7),
        reason: 'a damaged assignment journal must not block summary channel');
    expect(cancelled, isEmpty);
    expect(service.lastWarning, contains('assignments'));
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });

  test('startup rolls back a staging batch left by process termination',
      () async {
    const oldId = 807;
    const stagedId = 2000000807;
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_assignments': ['$oldId'],
      'notification_schedule_v2_journal_assignments': jsonEncode({
        'version': 1,
        'phase': 'staging',
        'oldIds': [oldId],
        'newIds': [stagedId],
      }),
    });
    final active = <int, Map>{
      oldId: {'id': oldId, 'title': 'old', 'body': '', 'payload': 'a:old'},
      stagedId: {
        'id': stagedId,
        'title': 'staged',
        'body': '',
        'payload': 'a:staged'
      },
    };
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        cancelled.add(id);
        active.remove(id);
        return null;
      }
      return true;
    });

    final restarted = LocalNotificationService();
    await restarted.initialize();

    expect(active.keys, [oldId]);
    expect(cancelled, [stagedId]);
    expect(await restarted.hasPendingScheduleRecovery(), isFalse);
  });

  test('damaged active manifest is visible and recovery cannot claim success',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_schedule_v2_active_assignments': ['not-an-id'],
    });
    final service = LocalNotificationService();
    expect(await service.hasPendingScheduleRecovery(), isTrue);
    await expectLater(service.recoverPendingSchedules(), throwsStateError);
    expect(await service.hasPendingScheduleRecovery(), isTrue);
  });

  test('concurrent assignment reschedules serialize into one active batch',
      () async {
    final active = <int, Map>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'getNotificationChannels') return [];
      if (call.method == 'pendingNotificationRequests') {
        return active.values.toList();
      }
      if (call.method == 'getActiveNotifications') return [];
      if (call.method == 'zonedSchedule') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        active[args['id'] as int] = args;
        return null;
      }
      if (call.method == 'cancel') {
        active.remove((call.arguments as Map)['id'] as int);
        return null;
      }
      return true;
    });
    final service = LocalNotificationService();
    await Future.wait([
      service.rescheduleAssignments(
          [f.sample('concurrent-first').copyWith(deadlineTrusted: true)],
          offsetsMinutes: [30]),
      service.rescheduleAssignments(
          [f.sample('concurrent-second').copyWith(deadlineTrusted: true)],
          offsetsMinutes: [30]),
    ]);
    expect(active, hasLength(1));
    expect(active.values.single['payload'], contains('concurrent-second'));
    expect(await service.hasPendingScheduleRecovery(), isFalse);
  });
}

class _NotificationJournalStore extends InMemorySharedPreferencesStore {
  _NotificationJournalStore() : super.withData({});

  bool throwAfterCommitWrite = false;
  bool rejectCommitWrite = false;
  bool loseStagingBeforeCommit = false;
  bool rejectStagingRepair = false;
  int _stagingWrites = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.notification_schedule_v2_journal_assignments' &&
        value is String) {
      final phase = jsonDecode(value)['phase'];
      if (phase == 'staging') {
        _stagingWrites++;
        if (rejectStagingRepair && _stagingWrites > 1) return false;
      }
      if (phase == 'committed') {
        if (loseStagingBeforeCommit) {
          await super.remove(key);
          return false;
        }
        if (rejectCommitWrite) return false;
        if (throwAfterCommitWrite) {
          await super.setValue(valueType, key, value);
          throw PlatformException(code: 'commit_ack_lost');
        }
      }
    }
    return super.setValue(valueType, key, value);
  }
}
