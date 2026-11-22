import 'package:shared_preferences/shared_preferences.dart';

import 'daytime_check_policy.dart';

class BackgroundCheckSettings {
  const BackgroundCheckSettings({
    required this.enabled,
    required this.intervalMinutes,
    required this.notificationListenerEnabled,
    required this.newAssignmentReminderEnabled,
    required this.migratedFromLegacy,
  });

  final bool enabled;
  final int intervalMinutes;
  final bool notificationListenerEnabled;
  final bool newAssignmentReminderEnabled;
  final bool migratedFromLegacy;

  BackgroundCheckSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    bool? notificationListenerEnabled,
    bool? newAssignmentReminderEnabled,
    bool? migratedFromLegacy,
  }) =>
      BackgroundCheckSettings(
        enabled: enabled ?? this.enabled,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        notificationListenerEnabled:
            notificationListenerEnabled ?? this.notificationListenerEnabled,
        newAssignmentReminderEnabled:
            newAssignmentReminderEnabled ?? this.newAssignmentReminderEnabled,
        migratedFromLegacy: migratedFromLegacy ?? this.migratedFromLegacy,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'intervalMinutes': intervalMinutes,
        'notificationListenerEnabled': notificationListenerEnabled,
        'newAssignmentReminderEnabled': newAssignmentReminderEnabled,
      };
}

class BackgroundCheckSettingsStore {
  static const _enabledKey = 'background_check_enabled_v1';
  static const _intervalKey = 'background_check_interval_minutes_v1';
  static const _listenerKey = 'notification_listener_enabled_v1';
  static const _newAssignmentKey = 'new_assignment_reminder_enabled_v1';
  static const legacyIntervalKey = 'auto_sync_interval_minutes';
  static const legacyMigrationKey = 'background_check_legacy_migration_v1';

  const BackgroundCheckSettingsStore();

  Future<BackgroundCheckSettings> loadAndMigrate({
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    if (prefs == null) await p.reload();
    final migrated = p.getBool(legacyMigrationKey) == true;
    final hasNewInterval = p.containsKey(_intervalKey);

    if (!migrated || !hasNewInterval) {
      final legacy = p.getInt(legacyIntervalKey);
      final enabled = legacy != 0;
      final interval = _migrateLegacyInterval(legacy);
      await _writeVerified(p, _enabledKey, enabled);
      await _writeVerified(p, _intervalKey, interval);
      if (!p.containsKey(_listenerKey)) {
        await _writeVerified(p, _listenerKey, false);
      }
      if (!p.containsKey(_newAssignmentKey)) {
        await _writeVerified(p, _newAssignmentKey, true);
      }
      await _writeVerified(p, legacyMigrationKey, true);
      // Keep the legacy value for backup/older-client compatibility.
      await _writeVerified(p, legacyIntervalKey, enabled ? interval : 0);
      return BackgroundCheckSettings(
        enabled: enabled,
        intervalMinutes: interval,
        notificationListenerEnabled: p.getBool(_listenerKey) ?? false,
        newAssignmentReminderEnabled: p.getBool(_newAssignmentKey) ?? true,
        migratedFromLegacy: !migrated,
      );
    }

    return BackgroundCheckSettings(
      enabled: p.getBool(_enabledKey) ?? true,
      intervalMinutes: DaytimeCheckPolicy.normalizeIntervalMinutes(
        p.getInt(_intervalKey) ?? DaytimeCheckPolicy.defaultIntervalMinutes,
      ),
      notificationListenerEnabled: p.getBool(_listenerKey) ?? false,
      newAssignmentReminderEnabled: p.getBool(_newAssignmentKey) ?? true,
      migratedFromLegacy: false,
    );
  }

  Future<void> save(
    BackgroundCheckSettings settings, {
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final interval =
        DaytimeCheckPolicy.normalizeIntervalMinutes(settings.intervalMinutes);
    await _writeVerified(p, _enabledKey, settings.enabled);
    await _writeVerified(p, _intervalKey, interval);
    await _writeVerified(p, _listenerKey, settings.notificationListenerEnabled);
    await _writeVerified(
        p, _newAssignmentKey, settings.newAssignmentReminderEnabled);
    await _writeVerified(p, legacyMigrationKey, true);
    await _writeVerified(p, legacyIntervalKey, settings.enabled ? interval : 0);
  }

  static int _migrateLegacyInterval(int? legacy) {
    if (legacy == 0) return DaytimeCheckPolicy.defaultIntervalMinutes;
    if (DaytimeCheckPolicy.allowedIntervalsMinutes.contains(legacy)) {
      return legacy!;
    }
    return DaytimeCheckPolicy.defaultIntervalMinutes;
  }

  static Future<void> _writeVerified(
    SharedPreferences prefs,
    String key,
    Object value,
  ) async {
    bool saved;
    try {
      saved = switch (value) {
        bool item => await prefs.setBool(key, item),
        int item => await prefs.setInt(key, item),
        _ => throw ArgumentError.value(value, 'value'),
      };
    } catch (_) {
      saved = false;
    }
    if (saved) return;
    await prefs.reload();
    final durable = prefs.get(key);
    if (durable != value) {
      throw StateError('后台检查设置未能保存，请重试');
    }
  }
}
