import 'package:flutter/services.dart';

enum SettingsOpenResult {
  direct,
  listFallback,
  appDetailsFallback,
  unavailable,
}

class PermissionSettingsService {
  const PermissionSettingsService();

  static const _channel = MethodChannel('study_assistant/permissions');
  static const _assignmentDeadlineChannelId = 'assignment_deadlines';

  Future<SettingsOpenResult> openNotificationSettingsResult() =>
      _openResult('openNotificationSettingsResult');

  Future<SettingsOpenResult> openExactAlarmSettingsResult() =>
      _openResult('openExactAlarmSettingsResult');

  Future<SettingsOpenResult> openLockScreenNotificationSettingsResult() =>
      openNotificationChannelSettingsResult(_assignmentDeadlineChannelId);

  Future<SettingsOpenResult> openNotificationChannelSettingsResult(
    String channelId,
  ) {
    final normalized = channelId.trim();
    if (normalized.isEmpty) {
      return Future.value(SettingsOpenResult.unavailable);
    }
    return _openResult(
      'openNotificationChannelSettingsResult',
      arguments: {'channelId': normalized},
    );
  }

  Future<SettingsOpenResult> openBatterySettingsResult() =>
      _openResult('openBatterySettingsResult');

  Future<SettingsOpenResult> openAppSettingsResult() =>
      _openResult('openAppSettingsResult');

  Future<SettingsOpenResult> openNotificationListenerSettingsResult() =>
      _openResult('openNotificationListenerSettingsResult');

  Future<bool> openNotificationSettings() => _open('openNotificationSettings');

  Future<bool> openExactAlarmSettings() => _open('openExactAlarmSettings');

  Future<bool> openLockScreenNotificationSettings() =>
      _open('openLockScreenNotificationSettings');

  Future<bool> openBatterySettings() => _open('openBatterySettings');

  Future<bool> openAppSettings() => _open('openAppSettings');

  Future<bool> openNotificationListenerSettings() =>
      _open('openNotificationListenerSettings');

  Future<bool> isNotificationListenerEnabled() async {
    try {
      return await _channel
              .invokeMethod<bool>('isNotificationListenerEnabled') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _open(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<SettingsOpenResult> _openResult(
    String method, {
    Object? arguments,
  }) async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        method,
        arguments,
      );
      return switch (value) {
        'direct' => SettingsOpenResult.direct,
        'listFallback' => SettingsOpenResult.listFallback,
        'appDetailsFallback' => SettingsOpenResult.appDetailsFallback,
        'unavailable' => SettingsOpenResult.unavailable,
        _ => SettingsOpenResult.unavailable,
      };
    } catch (_) {
      return SettingsOpenResult.unavailable;
    }
  }
}
