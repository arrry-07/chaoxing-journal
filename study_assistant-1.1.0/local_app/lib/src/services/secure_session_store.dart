import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

class SecureSessionStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    await _storage.write(key: 'chaoxingAccount', value: account);
    await _storage.write(key: 'chaoxingPassword', value: password);
    if (displayName == null || displayName.trim().isEmpty) {
      await _storage.delete(key: 'chaoxingDisplayName');
    } else {
      await _storage.write(
        key: 'chaoxingDisplayName',
        value: displayName.trim(),
      );
    }
    if (avatarUrl == null || avatarUrl.trim().isEmpty) {
      await _storage.delete(key: 'chaoxingAvatarUrl');
    } else {
      await _storage.write(
        key: 'chaoxingAvatarUrl',
        value: avatarUrl.trim(),
      );
    }
  }

  Future<String?> readChaoxingAccount() async {
    // Older installations may still hold credentials for the retired provider.
    for (final key in const [
      'shuniZuilingSchoolUserLocalId',
      'shuniZuilingPassword',
      'shuniZuilingSchoolCode',
    ]) {
      await _storage.delete(key: key);
    }
    return _storage.read(key: 'chaoxingAccount');
  }

  Future<String?> readChaoxingPassword() =>
      _storage.read(key: 'chaoxingPassword');

  Future<String?> readChaoxingDisplayName() =>
      _storage.read(key: 'chaoxingDisplayName');

  Future<String?> readChaoxingAvatarUrl() =>
      _storage.read(key: 'chaoxingAvatarUrl');

  /// WebView storage is shared across this application's verification sessions.
  /// A missing platform host or a cleanup failure must not retain credentials.
  Future<void> clearWebSession() async {
    try {
      await const MethodChannel('study_assistant/external_links')
          .invokeMethod<bool>('clearWebSession');
    } on PlatformException {
      // Logout must still remove secure storage if WebView is unavailable.
    } on MissingPluginException {
      // Desktop/test hosts have no Android verification WebView.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.deleteAll();
    } finally {
      await clearWebSession();
    }
  }
}
