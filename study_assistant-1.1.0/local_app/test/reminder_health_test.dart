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
}
