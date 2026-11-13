import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/permission_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('study_assistant/permissions');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('battery settings report each actual destination', () async {
    var response = 'appDetailsFallback';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => response);
    const service = PermissionSettingsService();
    for (final entry in {
      'appDetailsFallback': SettingsOpenResult.appDetailsFallback,
      'listFallback': SettingsOpenResult.listFallback,
      'unavailable': SettingsOpenResult.unavailable,
    }.entries) {
      response = entry.key;
      expect(await service.openBatterySettingsResult(), entry.value);
    }
  });

  test('structured settings calls map fixed native strings explicitly',
      () async {
    final responses = {
      'openNotificationSettingsResult': 'direct',
      'openExactAlarmSettingsResult': 'listFallback',
      'openNotificationChannelSettingsResult': 'appDetailsFallback',
      'openBatterySettingsResult': 'unavailable',
      'openAppSettingsResult': 'direct',
      'openNotificationListenerSettingsResult': 'listFallback',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return responses[call.method];
    });
    const service = PermissionSettingsService();

    expect(
      await service.openNotificationSettingsResult(),
      SettingsOpenResult.direct,
    );
    expect(
      await service.openExactAlarmSettingsResult(),
      SettingsOpenResult.listFallback,
    );
    expect(
      await service.openNotificationChannelSettingsResult(
        'assignment_updates',
      ),
      SettingsOpenResult.appDetailsFallback,
    );
    expect(
      await service.openBatterySettingsResult(),
      SettingsOpenResult.unavailable,
    );
    expect(
      await service.openAppSettingsResult(),
      SettingsOpenResult.direct,
    );
    expect(
      await service.openNotificationListenerSettingsResult(),
      SettingsOpenResult.listFallback,
    );

    final channelCall = calls.singleWhere(
      (call) => call.method == 'openNotificationChannelSettingsResult',
    );
    expect(channelCall.arguments, {'channelId': 'assignment_updates'});
  });

  test('lock screen compatibility result targets the deadline channel',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'direct';
    });
    const service = PermissionSettingsService();

    expect(
      await service.openLockScreenNotificationSettingsResult(),
      SettingsOpenResult.direct,
    );
    expect(
      calls.single.arguments,
      {'channelId': 'assignment_deadlines'},
    );
  });

  test('unknown, missing, mistyped and exceptional results are unavailable',
      () async {
    var mode = 'unknown';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (mode) {
        case 'unknown':
          return 'futureValue';
        case 'missing':
          return null;
        case 'mistyped':
          return false;
        case 'exception':
          throw PlatformException(code: 'activity_missing');
      }
      return null;
    });
    const service = PermissionSettingsService();

    for (final current in ['unknown', 'missing', 'mistyped', 'exception']) {
      mode = current;
      expect(
        await service.openNotificationSettingsResult(),
        SettingsOpenResult.unavailable,
        reason: current,
      );
    }
  });

  test('legacy bool methods still use the original bool channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'openExactAlarmSettings') return true;
      if (call.method == 'openBatterySettings') return false;
      throw PlatformException(code: 'missing_setting_activity');
    });
    const service = PermissionSettingsService();

    expect(await service.openExactAlarmSettings(), isTrue);
    expect(await service.openBatterySettings(), isFalse);
    expect(await service.openNotificationSettings(), isFalse);
    expect(
      calls.map((call) => call.method),
      [
        'openExactAlarmSettings',
        'openBatterySettings',
        'openNotificationSettings',
      ],
    );
  });

  test('empty channel IDs fail locally without invoking the platform',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'direct';
    });
    const service = PermissionSettingsService();

    expect(
      await service.openNotificationChannelSettingsResult('  '),
      SettingsOpenResult.unavailable,
    );
    expect(calls, isEmpty);
  });

  test('Android listener detail extra is a flattened ComponentName string', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/studyassistant/MainActivity.kt',
    ).readAsStringSync();

    expect(
      mainActivity,
      contains('Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS'),
    );
    expect(
      mainActivity,
      contains('Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME'),
    );
    expect(
      mainActivity,
      contains('ChaoxingNotificationListener::class.java'),
    );
    expect(mainActivity, contains('.flattenToString()'));
    expect(
      mainActivity,
      contains('Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS'),
    );
  });

  test('battery settings prefer app details and retain list fallback', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/studyassistant/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      mainActivity,
      contains('Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS'),
    );
    final batteryMethod = mainActivity.substring(
      mainActivity.indexOf('private fun openBatterySettings()'),
      mainActivity.indexOf('private fun openNotificationListenerSettings()'),
    );
    expect(
        batteryMethod.indexOf('openAppDetailsSettings()'),
        lessThan(batteryMethod
            .indexOf('ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS')));
    expect(batteryMethod, contains('SettingsOpenOutcome.APP_DETAILS_FALLBACK'));
    expect(batteryMethod, contains('SettingsOpenOutcome.LIST_FALLBACK'));
    expect(batteryMethod, contains('SettingsOpenOutcome.UNAVAILABLE'));
    expect(batteryMethod, isNot(contains('SettingsOpenOutcome.DIRECT')));
    expect(
      mainActivity,
      isNot(contains('Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')),
    );
    expect(
      manifest,
      isNot(contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')),
    );
    expect(manifest, contains('android:label="学习通课业手记"'));
  });

  test('legacy settings bool does not report app-details fallback as success',
      () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/studyassistant/MainActivity.kt',
    ).readAsStringSync();

    expect(
      mainActivity,
      contains('outcome == SettingsOpenOutcome.DIRECT ||'),
    );
    expect(
      mainActivity,
      contains('outcome == SettingsOpenOutcome.LIST_FALLBACK'),
    );
    expect(
      mainActivity,
      isNot(contains('outcome != SettingsOpenOutcome.UNAVAILABLE')),
    );
  });
}
