import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
