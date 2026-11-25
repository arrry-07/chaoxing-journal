import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/reminder_settings_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/permission_settings_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

import 'reminder_health_test.dart' as lns_fixture;

class _TestSession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-m7';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _FakeNotifications extends LocalNotificationService {
  _FakeNotifications(this.health);

  ReminderHealth health;
  int manualTestCalls = 0;

  @override
  Future<ReminderHealth> inspectHealth() async => health;

  @override
  Future<bool> showTestManualNotification({
    Duration delay = Duration.zero,
  }) async {
    manualTestCalls++;
    return true;
  }

  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> items,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}

  @override
  Future<void> migrateLegacyManualChannelIfNeeded(
    List<ManualEntry> entries,
  ) async {}

  @override
  Future<void> migrateLegacySummaryChannelIfNeeded(
    List<Assignment> assignments,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}

  @override
  Future<void> retireLegacyUpdatesAndDeadlineChannelsIfNeeded({
    required bool retireDeadlineV1,
    Future<bool> Function()? beforeRetireDeadlineV1,
  }) async {}
}

class _NoopSnapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _RecordingPermissions extends PermissionSettingsService {
  const _RecordingPermissions(this.events);

  final List<String> events;

  @override
  Future<bool> isNotificationListenerEnabled() async => true;

  @override
  Future<SettingsOpenResult> openNotificationSettingsResult() async {
    events.add('openNotificationSettings');
    return SettingsOpenResult.direct;
  }

  @override
  Future<SettingsOpenResult> openNotificationChannelSettingsResult(
    String channelId,
  ) async {
    events.add('channel:$channelId');
    return SettingsOpenResult.direct;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));

  test(
      'M7: ReminderHealth exposes ringer mute/vibrate and DND flags accurately',
      () {
    expect(const ReminderHealth().isPhoneMutedOrVibrate, isFalse);
    expect(const ReminderHealth().isDndActive, isFalse);
    expect(
      const ReminderHealth(ringerMode: 'normal', interruptionFilter: 'all')
          .isPhoneMutedOrVibrate,
      isFalse,
    );
    expect(
      const ReminderHealth(ringerMode: 'normal', interruptionFilter: 'all')
          .isDndActive,
      isFalse,
    );
    expect(
      const ReminderHealth(ringerMode: 'silent').isPhoneMutedOrVibrate,
      isTrue,
    );
    expect(
      const ReminderHealth(ringerMode: 'vibrate').isPhoneMutedOrVibrate,
      isTrue,
    );
    expect(
      const ReminderHealth(interruptionFilter: 'priority').isDndActive,
      isTrue,
    );
    expect(
      const ReminderHealth(interruptionFilter: 'none').isDndActive,
      isTrue,
    );
    expect(
      const ReminderHealth(interruptionFilter: 'alarms').isDndActive,
      isTrue,
    );
  });

  group(
      'M7 Android personal_schedule_v2 migration, ringer health and test notification',
      () {
    const notifications =
        MethodChannel('dexterous.com/flutter/local_notifications');
    const permissions = MethodChannel('study_assistant/permissions');
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(notifications, null);
      messenger.setMockMethodCallHandler(permissions, null);
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      debugDefaultTargetPlatformOverride = null;
    });

    test(
        'initialize creates personal_schedule_v2 first without dropping legacy alarms, then migrateLegacyManualChannelIfNeeded reschedules onto v2 before retiring personal_schedule and survives errors',
        () async {
      SharedPreferences.setMockInitialValues({
        'notification_schedule_v2_active_manual': ['2000000101'],
      });
      final calls = <MethodCall>[];
      final events = <String>[];
      var throwOnDelete = true;
      final channels = <Map<String, Object?>>[
        lns_fixture.channelRow('assignment_deadlines', '作业截止提醒', 4),
        lns_fixture.channelRow('assignment_updates_v2', '新增作业提醒', 4),
        lns_fixture.channelRow('daily_summary_v2', '每日课业摘要', 4),
        lns_fixture.channelRow('personal_schedule', '个人待办与考试提醒', 4),
      ];
      final pendingRequests = <Map<String, Object?>>[
        {
          'id': 2000000101,
          'title': '旧待办',
          'body': '旧内容',
          'payload': 'p:m1',
        },
      ];
      messenger.setMockMethodCallHandler(permissions, (call) async => 35);
      messenger.setMockMethodCallHandler(notifications, (call) async {
        calls.add(call);
        if (call.method == 'deleteNotificationChannel') {
          events.add('delete:${call.arguments}');
          if (throwOnDelete) {
            throw PlatformException(code: 'legacy_delete_error');
          }
          channels.removeWhere((c) => c['id'] == call.arguments);
          return null;
        }
        if (call.method == 'createNotificationChannel') {
          final args = Map<String, Object?>.from(call.arguments as Map);
          events.add('create:${args['id']}');
          channels.add(lns_fixture.channelRow(
            args['id'] as String,
            args['name'] as String,
            args['importance'] as int,
          ));
          return null;
        }
        if (call.method == 'zonedSchedule') {
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          final details =
              Map<Object?, Object?>.from(args['platformSpecifics'] as Map);
          events.add('schedule:${args['payload']}@${details['channelId']}');
          return null;
        }
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'getNotificationChannels' => channels,
          'pendingNotificationRequests' => pendingRequests,
          'getActiveNotifications' => [],
          _ => true,
        };
      });

      final service = LocalNotificationService(
        clock: () => DateTime(2030, 11, 20, 10, 0),
      );
      await service.initialize();

      // initialize MUST NOT delete legacy channel before notebook entries are rescheduled.
      expect(
        calls.where((c) => c.method == 'deleteNotificationChannel'),
        isEmpty,
      );
      final v2Create = calls
          .where((c) => c.method == 'createNotificationChannel')
          .map((c) => Map<String, Object?>.from(c.arguments as Map))
          .firstWhere(
              (c) => c['id'] == LocalNotificationService.manualV2Channel);
      expect(v2Create['name'], '待办与考试提醒');
      expect(v2Create['importance'], 4);
      expect(v2Create['playSound'], isTrue);
      expect(v2Create['enableVibration'], isTrue);

      final entry = ManualEntry(
        id: 'm1',
        title: '高数交作业',
        kind: ManualEntry.kindTodo,
        at: DateTime(2030, 11, 20, 14, 0),
        remind: true,
      );
      await service.migrateLegacyManualChannelIfNeeded([entry]);
      expect(
        events,
        containsAllInOrder([
          'create:personal_schedule_v2',
          'schedule:p:m1@personal_schedule_v2',
          'delete:personal_schedule',
        ]),
      );

      throwOnDelete = false;
      await service.migrateLegacyManualChannelIfNeeded([entry]);
      expect(
        channels.any((c) => c['id'] == LocalNotificationService.manualChannel),
        isFalse,
      );
    });

    test('showTestManualNotification handles StateError cleanly', () async {
      messenger.setMockMethodCallHandler(permissions, (call) async => 35);
      messenger.setMockMethodCallHandler(notifications, (call) async {
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'getNotificationChannels' => null,
          'pendingNotificationRequests' || 'getActiveNotifications' => [],
          _ => true,
        };
      });
      final service = LocalNotificationService();
      expect(await service.showTestManualNotification(), isFalse);
    });

    test(
        'inspectHealth reads ringerMode & interruptionFilter and showTestManualNotification targets personal_schedule_v2',
        () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(permissions, (call) async {
        if (call.method == 'getAndroidSdkInt') return 35;
        if (call.method == 'inspectNotificationHealthDetails') {
          return {
            'channels': {
              'assignment_deadlines': {'exists': true, 'importance': 4},
              'personal_schedule_v2': {
                'exists': true,
                'importance': 4,
                'soundMuted': false,
                'vibrationEnabled': true,
                'lockscreenVisibility': 1,
              },
            },
            'ringerMode': 'vibrate',
            'interruptionFilter': 'priority',
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(notifications, (call) async {
        calls.add(call);
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'getNotificationChannels' => [
              lns_fixture.channelRow('assignment_deadlines', '作业截止提醒', 4),
              lns_fixture.channelRow('personal_schedule_v2', '待办与考试提醒', 4),
            ],
          'pendingNotificationRequests' || 'getActiveNotifications' => [],
          'areNotificationsEnabled' || 'canScheduleExactNotifications' => true,
          _ => true,
        };
      });

      final service = LocalNotificationService();
      final health = await service.inspectHealth();
      expect(health.ringerMode, 'vibrate');
      expect(health.interruptionFilter, 'priority');
      expect(health.isPhoneMutedOrVibrate, isTrue);
      expect(health.isDndActive, isTrue);
      expect(health.manualChannel?.channelId,
          LocalNotificationService.manualV2Channel);

      final shown = await service.showTestManualNotification();
      expect(shown, isTrue);
      final showArgs = Map<String, Object?>.from(
        calls.singleWhere((c) => c.method == 'show').arguments as Map,
      );
      expect(showArgs['payload'], 't:manual-notification-test');
      final platformDetails =
          Map<String, Object?>.from(showArgs['platformSpecifics'] as Map);
      expect(platformDetails['channelId'],
          LocalNotificationService.manualV2Channel);
      expect(platformDetails['channelName'], '待办与考试提醒');
      expect(platformDetails['playSound'], isTrue);
      expect(platformDetails['enableVibration'], isTrue);
    });
  });

  testWidgets(
      'M7: ReminderSettingsScreen surfaces ringer/DND warnings, test manual reminder & system settings buttons at 320dp@2x across themes',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    for (final dark in [false, true]) {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      FlutterSecureStorage.setMockInitialValues({});
      final events = <String>[];
      final fakeNotif = _FakeNotifications(
        const ReminderHealth(
          notifications: true,
          exact: true,
          assignmentChannel:
              ReminderChannelHealth(ReminderChannelStatus.enabled),
          assignmentUpdatesChannel:
              ReminderChannelHealth(ReminderChannelStatus.enabled),
          summaryChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
          manualChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
          ringerMode: 'vibrate',
          interruptionFilter: 'priority',
        ),
      );
      final store = AssignmentStore(
        sessionStore: _TestSession(),
        notificationService: fakeNotif,
        widgetSnapshotService: _NoopSnapshot(),
      );
      addTearDown(store.dispose);
      await store.restoreSession();

      await tester.pumpWidget(MaterialApp(
        theme: dark ? StudyAssistantTheme.dark : StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: ReminderSettingsScreen(
          key: ValueKey('m7-settings-$dark'),
          assignmentStore: store,
          permissionSettingsService: _RecordingPermissions(events),
          initialExpandHealth: true,
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'dark=$dark');

      expect(
        find.byKey(const ValueKey('reminder-health-ringer-warning')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reminder-health-dnd-warning')),
        findsOneWidget,
      );

      final testManualBtn =
          find.byKey(const ValueKey('send-test-manual-notification-button'));
      await Scrollable.ensureVisible(
        tester.element(testManualBtn),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(testManualBtn);
      await tester.pumpAndSettle();
      expect(fakeNotif.manualTestCalls, 1);

      final sysBtn =
          find.byKey(const ValueKey('open-system-notification-settings'));
      await Scrollable.ensureVisible(tester.element(sysBtn), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(sysBtn);
      await tester.pumpAndSettle();
      expect(events, contains('openNotificationSettings'));

      final manualTile = find.widgetWithText(ListTile, '个人日程通知渠道');
      await Scrollable.ensureVisible(
        tester.element(manualTile),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(manualTile);
      await tester.pumpAndSettle();
      expect(events, contains('channel:personal_schedule_v2'));
    }
  });

  testWidgets(
      'M7 Gate 1: ReminderSettingsScreen flags muted manualChannel audio/vibration and catches test manual notification errors',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    FlutterSecureStorage.setMockInitialValues({});
    final fakeNotif = _ThrowingTestManualNotifications(
      const ReminderHealth(
        notifications: true,
        exact: true,
        assignmentChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
        assignmentUpdatesChannel:
            ReminderChannelHealth(ReminderChannelStatus.enabled),
        summaryChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
        manualChannel: ReminderChannelHealth(
          ReminderChannelStatus.enabled,
          soundMuted: true,
          vibrationEnabled: false,
        ),
      ),
    );
    final store = AssignmentStore(
      sessionStore: _TestSession(),
      notificationService: fakeNotif,
      widgetSnapshotService: _NoopSnapshot(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: ReminderSettingsScreen(
        assignmentStore: store,
        initialExpandHealth: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('个人日程渠道在系统中已静音'), findsOneWidget);
    expect(find.textContaining('个人日程渠道振动已关闭'), findsOneWidget);

    final btn =
        find.byKey(const ValueKey('send-test-manual-notification-button'));
    await Scrollable.ensureVisible(tester.element(btn), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('未能发送待办测试提醒'), findsOneWidget);
  });
}

class _ThrowingTestManualNotifications extends _FakeNotifications {
  _ThrowingTestManualNotifications(super.health);

  @override
  Future<bool> showTestManualNotification({
    Duration delay = Duration.zero,
  }) async {
    throw StateError('channel unreadable');
  }
}
