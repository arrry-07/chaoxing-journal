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

    expect(service, contains('requestExactAlarmsPermission'));
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
}
