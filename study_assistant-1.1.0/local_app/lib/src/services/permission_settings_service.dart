import 'package:flutter/services.dart';

class PermissionSettingsService {
  const PermissionSettingsService();

  static const _channel = MethodChannel('study_assistant/permissions');

  Future<bool> openNotificationSettings() => _open('openNotificationSettings');

  Future<bool> openExactAlarmSettings() => _open('openExactAlarmSettings');

  Future<bool> openLockScreenNotificationSettings() =>
      _open('openLockScreenNotificationSettings');

  Future<bool> openBatterySettings() => _open('openBatterySettings');

  Future<bool> openAppSettings() => _open('openAppSettings');

  Future<bool> _open(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } catch (_) {
      return false;
    }
  }
}
