import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';

void main() {
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

  test('Android notifications are visible on the lock screen', () {
    final service = File(
      'lib/src/services/local_notification_service.dart',
    ).readAsStringSync();

    expect(service, contains('NotificationVisibility.public'));
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
    expect(service, contains("request.payload?.startsWith('a:')"));
  });

  test('notification taps are wired to route payloads', () {
    final service = File(
      'lib/src/services/local_notification_service.dart',
    ).readAsStringSync();

    expect(service, contains('onDidReceiveNotificationResponse'));
    expect(service, contains('getNotificationAppLaunchDetails'));
  });
}
