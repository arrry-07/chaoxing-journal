import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'review_core_remediation_test.dart' as f;
import 'reminder_health_test.dart' as h;

// Keep the real show/cleanup queue and Store identity transitions. Unrelated
// schedule creation is covered by reminder_health_test, not this race fixture.
class _Notifications extends LocalNotificationService {
  @override
  Future<void> rescheduleAssignments(List<Assignment> items,
      {List<int>? offsetsMinutes}) async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}
  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace workspace, DateTime? lastSync) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<Map<String, Object?>> active, pending;
  late List<String> events;
  Completer<void>? showing, release;
  late bool failShow, failCancel;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    active = [];
    pending = [];
    events = [];
    showing = release = null;
    failShow = failCancel = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('study_assistant/permissions'),
            (call) async => call.method == 'getAndroidSdkInt' ? 35 : true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'areNotificationsEnabled':
        case 'canScheduleExactNotifications':
          return true;
        case 'getNotificationChannels':
          return [
            for (final id in [
              'assignment_deadlines',
              'daily_summary',
              'personal_schedule'
            ])
              h.channelRow(id, id, 4)
          ];
        case 'pendingNotificationRequests':
          return pending.toList();
        case 'getActiveNotifications':
          return active.toList();
        case 'zonedSchedule':
          final args = call.arguments as Map;
          pending.add({
            'id': args['id'],
            'title': args['title'],
            'body': args['body'],
            'payload': args['payload']
          });
          return true;
        case 'show':
          events.add('show-start');
          showing?.complete();
          if (release != null) {
            await release!.future;
          }
          if (failShow) {
            throw PlatformException(code: 'synthetic-show-failure');
          }
          final args = call.arguments as Map;
          active.removeWhere((n) => n['id'] == args['id']);
          // v18 Android getActiveNotifications returns channelId/tag, NOT
          // payload. Keep this seam faithful to the shipped native plugin.
          active.add({
            'id': args['id'],
            'channelId': 'assignment_deadlines',
            'tag': null
          });
          events.add('show-done');
          return true;
        case 'cancel':
          if (failCancel) {
            throw PlatformException(code: 'synthetic-cancel-failure');
          }
          final id = (call.arguments as Map)['id'];
          active.removeWhere((n) => n['id'] == id);
          pending.removeWhere((n) => n['id'] == id);
          events.add('cancel');
          return true;
        default:
          return true;
      }
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('study_assistant/permissions'), null);
  });
  for (final switching in [false, true]) {
    test(
        'in-flight platform show is retired before ${switching ? 'switch' : 'logout'} completes',
        () async {
      final service = _Notifications();
      final store = AssignmentStore(
          sessionStore: f.Session(),
          notificationService: service,
          widgetSnapshotService: f.WidgetService(),
          chaoxingClient: f.Client());
      addTearDown(store.dispose);
      await store.restoreSession();
      pending.add({
        'id': 730123,
        'title': 'synthetic',
        'body': '',
        'payload': 'a:synthetic'
      });
      showing = Completer<void>();
      release = Completer<void>();
      final oldRequest = service.showTestNotification();
      await showing!.future.timeout(const Duration(seconds: 3));
      var ended = false;
      final transition = (switching
              ? store.loginChaoxing(
                  account: 'B', password: 'dummy', agreementAccepted: true)
              : store.logout())
          .then((_) {
        ended = true;
        events.add('identity-done');
      });
      await Future<void>.delayed(Duration.zero);
      expect(ended, false);
      release!.complete();
      expect(await oldRequest, true);
      await transition;
      expect(active, isEmpty);
      expect(pending, isEmpty);
      expect(events.indexOf('show-done'),
          lessThan(events.indexOf('identity-done')));
      expect(store.account, switching ? 'B' : null);
      if (switching) {
        showing = release = null;
        expect(await service.showTestNotification(), true);
        expect(active.single['id'], 1900000008);
        await service.cancelPrivateSchedules();
      }
    });
  }
  test('show failure reports false without poisoning later show or cleanup',
      () async {
    final service = _Notifications();
    failShow = true;
    expect(await service.showTestNotification(), false);
    expect(active, isEmpty);
    failShow = false;
    expect(await service.showTestNotification(), true);
    await service.cancelPrivateSchedules();
    expect(active, isEmpty);
  });
  test(
      'deleting a delivered manual reminder uses native channel ownership without payload',
      () async {
    final service = LocalNotificationService();
    await service.rescheduleManual([
      ManualEntry(
          id: 'qa-manual',
          title: 'QA',
          kind: 'exam',
          at: DateTime.now().add(const Duration(hours: 1)),
          remind: true)
    ]);
    final id = pending.single['id'];
    pending.clear();
    active.add({'id': id, 'channelId': 'personal_schedule', 'tag': null});
    await service.rescheduleManual([]);
    expect(active, isEmpty);
    expect(pending, isEmpty);
    expect(await service.hasPendingScheduleRecovery(), false);
  });
  for (final category in ['assignments', 'summary']) {
    test('retiring delivered $category uses native channel ownership',
        () async {
      final service = LocalNotificationService();
      if (category == 'assignments') {
        await service.rescheduleAssignments([
          f
              .sample('shared')
              .copyWith(deadlineAt: DateTime.now().add(const Duration(days: 2)))
        ], offsetsMinutes: [
          30
        ]);
      } else {
        await service.rescheduleSummary([f.sample('shared')],
            PersonalWorkspace(summaryEnabled: true), DateTime.now());
      }
      expect(pending, isNotEmpty);
      final first = pending.removeAt(0);
      active.add({
        'id': first['id'],
        'channelId': category == 'assignments'
            ? 'assignment_deadlines'
            : 'daily_summary',
        'tag': null
      });
      if (category == 'assignments') {
        await service.rescheduleAssignments([], offsetsMinutes: [30]);
      } else {
        await service
            .rescheduleSummary([], PersonalWorkspace(), DateTime.now());
      }
      expect(active, isEmpty);
      expect(pending, isEmpty);
      expect(await service.hasPendingScheduleRecovery(), false);
    });
  }
  for (final evidence in [
    {'channelId': 'assignment_deadlines', 'tag': null},
    {'channelId': 'unknown-channel', 'tag': null},
    {'channelId': 'personal_schedule', 'tag': 'foreign-tag'},
    {
      'channelId': 'assignment_deadlines',
      'tag': null,
      'payload': 'p:qa-manual'
    },
  ]) {
    test('v2 manual recovery rejects conflicting native evidence $evidence',
        () async {
      final service = LocalNotificationService();
      await service.rescheduleManual([
        ManualEntry(
            id: 'qa-manual',
            title: 'QA',
            kind: 'exam',
            at: DateTime.now().add(const Duration(hours: 1)),
            remind: true)
      ]);
      final id = pending.single['id'];
      pending.clear();
      active.add({'id': id, ...evidence});
      await expectLater(service.rescheduleManual([]), throwsFormatException);
      expect(active.single['id'], id);
      expect(await service.hasPendingScheduleRecovery(), true);
    });
  }
  test(
      'native delivered channels are cleaned while unrelated or tagged notices remain',
      () async {
    final service = _Notifications();
    active.addAll([
      for (var i = 0; i < 3; i++)
        {
          'id': 700 + i,
          'channelId': [
            'assignment_deadlines',
            'daily_summary',
            'personal_schedule'
          ][i],
          'tag': null
        },
      {'id': 800, 'channelId': 'unrelated', 'tag': null},
      {'id': 801, 'channelId': 'assignment_deadlines', 'tag': 'unrelated-tag'},
    ]);
    await service.cancelPrivateSchedules();
    expect(active.map((n) => n['id']), [800, 801]);
  });
  test('cancel failure is visible and retry clears both pending and delivered',
      () async {
    final service = _Notifications();
    expect(await service.showTestNotification(), true);
    pending.add({
      'id': 730124,
      'title': 'synthetic',
      'body': '',
      'payload': 'a:synthetic'
    });
    failCancel = true;
    await expectLater(service.cancelPrivateSchedules(), throwsStateError);
    expect(service.lastWarning, contains('清理未完成'));
    expect(active, isNotEmpty);
    expect(pending, isNotEmpty);
    failCancel = false;
    await service.cancelPrivateSchedules();
    expect(active, isEmpty);
    expect(pending, isEmpty);
    expect(service.lastWarning, isNull);
  });
}
