import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';

void main() {
  const store = BackgroundCheckSettingsStore();

  test('new installs default to enabled four-hour checks', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await store.loadAndMigrate();
    expect(settings.enabled, isTrue);
    expect(settings.intervalMinutes, 240);
    expect(settings.notificationListenerEnabled, isFalse);
    expect(settings.newAssignmentReminderEnabled, isTrue);
  });

  test('legacy disabled remains disabled', () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final settings = await store.loadAndMigrate();
    expect(settings.enabled, isFalse);
    expect(settings.intervalMinutes, 240);
  });

  test('legacy 120, 240 and 360 minutes are preserved', () async {
    for (final legacy in [120, 240, 360]) {
      SharedPreferences.setMockInitialValues(
          {'auto_sync_interval_minutes': legacy});
      final settings =
          await const BackgroundCheckSettingsStore().loadAndMigrate();
      expect(settings.enabled, isTrue);
      expect(settings.intervalMinutes, legacy);
    }
  });

  test('other positive legacy intervals migrate to four hours', () async {
    for (final legacy in [1, 15, 30, 60, 180, 1440]) {
      SharedPreferences.setMockInitialValues(
          {'auto_sync_interval_minutes': legacy});
      final settings =
          await const BackgroundCheckSettingsStore().loadAndMigrate();
      expect(settings.enabled, isTrue);
      expect(settings.intervalMinutes, 240);
    }
  });

  test('listener and new-reminder settings are independent', () async {
    SharedPreferences.setMockInitialValues({});
    final initial = await store.loadAndMigrate();
    await store.save(initial.copyWith(
      notificationListenerEnabled: true,
      newAssignmentReminderEnabled: false,
    ));

    final loaded = await store.loadAndMigrate();
    expect(loaded.enabled, isTrue);
    expect(loaded.notificationListenerEnabled, isTrue);
    expect(loaded.newAssignmentReminderEnabled, isFalse);
  });
}
