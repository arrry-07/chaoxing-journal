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
  const homework =
      'https://mooc1.chaoxing.com/mooc-ans/mooc2/work/task?workId=3&enc=a%2Bb';
  for (final appSupported in [true, false]) {
    test(
        'homework only opens Chaoxing and never silently launches browser: $appSupported',
        () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'openChaoxingAssignment' ? appSupported : true;
      });
      final result = await ExternalLinkService().openAssignment(homework);
      expect(
          result,
          appSupported
              ? AssignmentLaunchTarget.chaoxing
              : AssignmentLaunchTarget.unavailable);
      expect(
          calls.map((c) => c.method),
          appSupported
              ? ['openChaoxingAssignment']
              : ['openChaoxingAssignment']);
      expect(calls.every((c) => c.arguments['url'] == homework), isTrue);
    });
  }
}
