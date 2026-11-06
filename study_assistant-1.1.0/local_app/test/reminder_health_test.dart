import 'review_core_remediation_test.dart' as f;
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      switch (c.method) {
        case 'areNotificationsEnabled':
          return true;
        case 'canScheduleExactNotifications':
          return false;
        case 'getNotificationChannels':
          return [
            {'id': 'assignment_deadlines', 'name': '作业截止提醒', 'importance': 4}
          ];
        case 'pendingNotificationRequests':
          return [
            {'id': 11, 'title': 'sample', 'body': '', 'payload': 'a:sample'},
            {
              'id': 1900000000,
              'title': 'summary',
              'body': '',
              'payload': 'd:summary'
            }
          ];
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        default:
          return true;
      }
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('privacy tightening cancels existing app reminders before replanning',
      () async {
    final s = LocalNotificationService();
    await s.cancelPrivateSchedules();
    final ids = calls
        .where((c) => c.method == 'cancel')
        .map((c) => (c.arguments as Map)['id']);
    expect(ids, containsAll([11, 1900000000]));
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
      if (c.method == 'cancel') throw PlatformException(code: 'blocked');
      return true;
    });
    await expectLater(LocalNotificationService().cancelPrivateSchedules(),
        throwsA(isA<PlatformException>()));
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
  });
  test('summary replaces stable seven IDs and disable only cancels summaries',
      () async {
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
    expect(
        calls
            .where((c) => c.method == 'zonedSchedule')
            .map((c) => (c.arguments as Map)['id']),
        first);
    calls.clear();
    await s.rescheduleSummary([], PersonalWorkspace(), null);
    expect(
        calls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map)['id']),
        [1900000000]);
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
    expect(
        (calls.singleWhere((c) => c.method == 'zonedSchedule').arguments
            as Map)['id'],
        id);
    calls.clear();
    await s.rescheduleManual([]);
    expect(calls.where((c) => c.method == 'cancel'), isEmpty);
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

  test('deleted personal reminder is cancelled even if another schedule fails',
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
        isTrue);
  });
}
