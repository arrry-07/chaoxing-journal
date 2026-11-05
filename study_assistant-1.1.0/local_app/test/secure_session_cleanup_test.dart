import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('study_assistant/external_links');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  for (final failCleanup in [false, true]) {
    test(
        'logout deletes credentials and requests website cleanup (native failure: $failCleanup)',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'chaoxingAccount': 'synthetic',
        'chaoxingPassword': 'synthetic-only'
      });
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (failCleanup) {
          throw PlatformException(code: 'web_storage_unavailable');
        }
        return true;
      });
      await SecureSessionStore().clear();
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
      expect(calls, ['clearWebSession']);
    });
  }
}
