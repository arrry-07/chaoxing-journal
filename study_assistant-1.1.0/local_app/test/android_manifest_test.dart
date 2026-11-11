import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android manifest declares internet permission for local Chaoxing login',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.INTERNET'));
    },
  );

  test('Android manifest declares scheduled notification boot recovery', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
  });

  test('Android manifest declares exact alarm permission for timely reminders',
      () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
  });

  test('local notifications prefer exact alarm scheduling', () {
    final service = File(
      'lib/src/services/local_notification_service.dart',
    ).readAsStringSync();

    expect(service, isNot(contains('requestExactAlarmsPermission')));
    final settings = File('lib/src/services/permission_settings_service.dart')
        .readAsStringSync();
    expect(settings, contains('openExactAlarmSettings'));
    expect(service, contains('AndroidScheduleMode.exactAllowWhileIdle'));
  });

  test('Android host exposes reminder permission settings actions', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/studyassistant/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('study_assistant/permissions'));
    expect(mainActivity, contains('openNotificationSettings'));
    expect(mainActivity, contains('openExactAlarmSettings'));
    expect(mainActivity, contains('openLockScreenNotificationSettings'));
    expect(mainActivity, contains('openBatterySettings'));
    expect(mainActivity, contains('getAndroidSdkInt'));
    expect(mainActivity, contains('Build.VERSION.SDK_INT'));
    expect(mainActivity, contains('isNotificationListenerEnabled'));
    expect(mainActivity, contains('openNotificationListenerSettings'));
  });

  test('Android manifest wires native background and listener components', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('AssignmentDeadlineReceiver'));
    expect(manifest, contains('NewAssignmentWindowReceiver'));
    expect(manifest, contains('ReminderClickReceiver'));
    expect(manifest, contains('ReminderClickActivity'));
    expect(manifest, contains('ReminderSystemReceiver'));
    expect(manifest, contains('flutter_deeplinking_enabled'));
    expect(manifest, contains('ChaoxingNotificationListener'));
    expect(
      manifest,
      contains('android.permission.BIND_NOTIFICATION_LISTENER_SERVICE'),
    );
    expect(manifest,
        contains('android.service.notification.NotificationListenerService'));
    expect(manifest, contains('android.intent.action.TIMEZONE_CHANGED'));
    final reminderSystemReceiver = RegExp(
      r'<receiver\s+android:name="\.ReminderSystemReceiver"[\s\S]*?</receiver>',
    ).firstMatch(manifest)?.group(0);
    expect(reminderSystemReceiver, isNotNull);
    expect(
      reminderSystemReceiver,
      contains('android.intent.action.USER_UNLOCKED'),
    );
  });

  test('Android host can open downloaded apk updates', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/studyassistant/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(manifest, contains('androidx.core.content.FileProvider'));
    expect(manifest, contains('@xml/update_file_paths'));
    expect(mainActivity, contains('Intent.ACTION_INSTALL_PACKAGE'));
    expect(mainActivity, contains('application/vnd.android.package-archive'));
    expect(mainActivity, contains('FileProvider.getUriForFile'));
    expect(mainActivity, contains('installApk'));
  });

  test('Android FileProvider exposes update apk cache directory', () {
    final paths = File(
      'android/app/src/main/res/xml/update_file_paths.xml',
    ).readAsStringSync();

    expect(paths, contains('cache-path'));
    expect(paths, contains('updates'));
  });

  test('unsupported 32-bit JNI libraries cannot be packaged', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();

    expect(gradle, contains('lib/armeabi-v7a/**'));
    expect(gradle, isNot(contains('lib/armeabi-v7a/libdartjni.so')));
  });

  test('Android update inspection requires a supported Flutter engine', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/studyassistant/MainActivity.kt',
    ).readAsStringSync();

    expect(
      mainActivity,
      contains('UpdateApkPolicy.hasSupportedFlutterEngine'),
    );
  });

  test('backup allowlists do not contain out-of-scope exclusions', () {
    for (final path in [
      'android/app/src/main/res/xml/backup_rules.xml',
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ]) {
      final rules = File(path).readAsStringSync();
      expect(rules, contains('FlutterSharedPreferences.xml'), reason: path);
      expect(rules, isNot(contains('<exclude')), reason: path);
    }
  });
}
