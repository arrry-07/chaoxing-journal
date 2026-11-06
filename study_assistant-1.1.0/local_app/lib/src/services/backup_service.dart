import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/backup_snapshot.dart';

class BackupService {
  static const _channel = MethodChannel('study_assistant/backup');
  static const maxEnvelopeBytes = 12 * 1024 * 1024;
  void _password(String password) {
    if (password.isEmpty || password.length > 1024) {
      throw ArgumentError('请填写备份口令（最多1024个字符）');
    }
  }

  void _envelope(String value) {
    if (value.length > maxEnvelopeBytes ||
        utf8.encode(value).length > maxEnvelopeBytes) {
      throw const FormatException('备份文件超过12 MiB上限');
    }
  }

  Future<String> encrypt(BackupSnapshot snapshot, String password) async {
    _password(password);
    final plaintext = snapshot.encode();
    if (utf8.encode(plaintext).length > BackupSnapshot.maxPlaintextBytes) {
      throw const FormatException('备份数据超过8 MiB上限');
    }
    final result = await _channel.invokeMethod<String>(
        'encrypt', {'plaintext': plaintext, 'password': password});
    if (result == null) throw StateError('未能加密备份');
    _envelope(result);
    return result;
  }

  Future<BackupSnapshot> decrypt(String envelope, String password) async {
    _password(password);
    _envelope(envelope);
    final plaintext = await _channel.invokeMethod<String>(
        'decrypt', {'envelope': envelope, 'password': password});
    if (plaintext == null) throw const FormatException('未能解密备份');
    return BackupSnapshot.decode(plaintext);
  }

  Future<String?> pick() async {
    final result = await _channel.invokeMethod<String>('pick');
    if (result != null) _envelope(result);
    return result;
  }

  Future<bool> save(String content, {required String suggestedName}) async {
    _envelope(content);
    return await _channel.invokeMethod<bool>(
            'save', {'content': content, 'suggestedName': suggestedName}) ??
        false;
  }
}
