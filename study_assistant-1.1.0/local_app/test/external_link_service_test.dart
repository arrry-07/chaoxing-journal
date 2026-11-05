import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/external_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('study_assistant/external_links');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('external platform errors produce a recoverable false result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'no_handler');
    });
    expect(
        await ExternalLinkService().openUrl('https://chaoxing.com/'), isFalse);
  });
}
