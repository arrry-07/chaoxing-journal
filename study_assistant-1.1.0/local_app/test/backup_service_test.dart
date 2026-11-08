import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('study_assistant/backup');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('cancelled picker returns null without decrypting', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pick');
      return null;
    });
    expect(await BackupService().pick(), isNull);
  });
  test('empty password and oversized envelope fail before native call',
      () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      called = true;
      return '';
    });
    await expectLater(BackupService().decrypt('{}', ''), throwsArgumentError);
    await expectLater(
        BackupService().decrypt('x' * (12 * 1024 * 1024 + 1), 'password'),
        throwsFormatException);
    expect(called, isFalse);
  });

  test('real crypto round trip preserves legacy rules and backup data',
      () async {
    final dir = await Directory.systemTemp.createTemp('backup-crypto-');
    addTearDown(() => dir.delete(recursive: true));
    final savedFile = File('${dir.path}/synthetic.xxtbackup');
    final crypto = _NativeCompatibleBackupCrypto();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = call.arguments as Map;
      try {
        switch (call.method) {
          case 'encrypt':
            return crypto.encrypt(
              arguments['plaintext'] as String,
              arguments['password'] as String,
            );
          case 'decrypt':
            return crypto.decrypt(
              arguments['envelope'] as String,
              arguments['password'] as String,
            );
          case 'save':
            await savedFile.writeAsString(arguments['content'] as String);
            return true;
          default:
            throw UnsupportedError(call.method);
        }
      } catch (_) {
        throw PlatformException(
          code: 'backup_error',
          message: '备份操作失败',
        );
      }
    });

    const password = 'synthetic-pass-123';
    final legacyRules = [
      for (var value = 1; value <= 32; value++) value,
      400 * 24 * 60,
    ];
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 15,
    });
    final repository = LocalAssignmentRepository();
    await repository.activateAccount('alice');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'reminder_offsets_minutes',
      legacyRules.map((value) => '$value').toList(),
    );
    await prefs.setStringList(
      'unfollowed_courses',
      ['synthetic-course:class'],
    );
    await repository.saveCourses(
      const [
        CourseRef(
          courseId: 'synthetic-course',
          clazzId: 'class',
          name: '合成课程',
        )
      ],
      account: 'alice',
    );
    await repository.mergeAndSave([
      Assignment(
        id: 'cx:work:synthetic-course:class:1',
        courseName: '合成课程',
        title: '合成作业',
        deadlineAt: DateTime.utc(2027, 1, 2, 4),
        requirementsText: '不应出现在备份明文中的说明正文',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026, 11, 8),
      )
    ]);
    final snapshot = await repository.createBackupSnapshot('alice');
    final service = BackupService();

    final envelope = await service.encrypt(snapshot, password);
    expect(envelope, isNot(contains('合成课程')));
    expect(envelope, isNot(contains('合成作业')));
    expect(envelope, isNot(contains('不应出现在备份明文中的说明正文')));
    expect(
      jsonDecode(envelope),
      containsPair('format', 'study-assistant-backup'),
    );
    expect(await service.save(envelope, suggestedName: 'synthetic.xxtbackup'),
        isTrue);
    expect(await savedFile.readAsString(), envelope);

    final restored = await service.decrypt(
      await savedFile.readAsString(),
      password,
    );
    expect(restored.reminderOffsets, unorderedEquals(legacyRules));
    expect(restored.records.single.title, '合成作业');
    expect(restored.records.single.requirementsText, isEmpty);
    expect(restored.courses.single.name, '合成课程');
    expect(restored.unfollowed, {'synthetic-course:class'});
    expect(restored.autoSyncIntervalMinutes, 15);

    await expectLater(
      service.decrypt(envelope, 'wrong-password'),
      throwsA(isA<PlatformException>()),
    );
    final damaged = Map<String, dynamic>.from(
      jsonDecode(envelope) as Map<String, dynamic>,
    );
    final ciphertext = base64Decode(damaged['ciphertext'] as String);
    ciphertext[ciphertext.length - 1] ^= 1;
    damaged['ciphertext'] = base64Encode(ciphertext);
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    await expectLater(
      service.decrypt(jsonEncode(damaged), password),
      throwsA(isA<PlatformException>()),
    );
    final after = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    expect(after, before);
    await expectLater(
      repository.restoreBackupSnapshot(restored, 'bob'),
      throwsStateError,
    );
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
  });
}

/// Mirrors Android BackupCrypto so this MethodChannel integration test can
/// exercise real PBKDF2/AES-GCM without launching a device or JVM process.
class _NativeCompatibleBackupCrypto {
  static const _format = 'study-assistant-backup';
  static const _kdf = 'PBKDF2-HMAC-SHA256';
  static const _cipher = 'AES-256-GCM';
  static const _iterations = 600000;
  static final _aad = utf8.encode(
    '$_format\n1\n$_kdf\n$_iterations\n$_cipher',
  );
  final _aes = AesGcm.with256bits();
  final _pbkdf2 = Pbkdf2.hmacSha256(iterations: _iterations, bits: 256);
  final _random = Random.secure();

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  Future<SecretKey> _key(String password, List<int> salt) =>
      _pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);

  Future<String> encrypt(String plaintext, String password) async {
    final salt = _randomBytes(16), iv = _randomBytes(12);
    final key = await _key(password, salt);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: iv,
      aad: _aad,
    );
    return jsonEncode({
      'format': _format,
      'version': 1,
      'iterations': _iterations,
      'kdf': _kdf,
      'cipher': _cipher,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'ciphertext': base64Encode([...box.cipherText, ...box.mac.bytes]),
    });
  }

  Future<String> decrypt(String envelope, String password) async {
    final json = jsonDecode(envelope);
    if (json is! Map<String, dynamic> ||
        json.length != 8 ||
        json['format'] != _format ||
        json['version'] != 1 ||
        json['iterations'] != _iterations ||
        json['kdf'] != _kdf ||
        json['cipher'] != _cipher) {
      throw const FormatException('unsupported envelope');
    }
    final salt = base64Decode(json['salt'] as String);
    final iv = base64Decode(json['iv'] as String);
    final encrypted = base64Decode(json['ciphertext'] as String);
    if (salt.length != 16 || iv.length != 12 || encrypted.length <= 16) {
      throw const FormatException('invalid envelope');
    }
    final ciphertext = encrypted.sublist(0, encrypted.length - 16);
    final tag = encrypted.sublist(encrypted.length - 16);
    final clear = await _aes.decrypt(
      SecretBox(ciphertext, nonce: iv, mac: Mac(tag)),
      secretKey: await _key(password, salt),
      aad: _aad,
    );
    return utf8.decode(clear);
  }
}
