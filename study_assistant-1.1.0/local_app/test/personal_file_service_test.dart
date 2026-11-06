import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/personal_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() =>
      messenger.setMockMethodCallHandler(PersonalFileService.channel, null));

  test('cancelled picker leaves no file association', () async {
    messenger.setMockMethodCallHandler(
        PersonalFileService.channel, (_) async => null);
    expect(await PersonalFileService().pick(), isNull);
  });
  test('file reference must be a provider content URI', () async {
    messenger.setMockMethodCallHandler(PersonalFileService.channel,
        (_) async => {'label': 'sample', 'url': 'file:///private/sample'});
    await expectLater(PersonalFileService().pick(), throwsFormatException);
    expect(await PersonalFileService().open('https://example.org'), isFalse);
  });
  test('valid selected document can be opened, revoked grant returns false',
      () async {
    var available = true;
    messenger.setMockMethodCallHandler(PersonalFileService.channel,
        (call) async {
      if (call.method == 'pick') {
        return {'label': 'sample', 'url': 'content://documents/sample'};
      }
      if (!available) throw PlatformException(code: 'unavailable');
      return true;
    });
    final service = PersonalFileService();
    final file = await service.pick();
    expect(file!.label, 'sample');
    expect(await service.open(file.url), isTrue);
    available = false;
    expect(await service.open(file.url), isFalse);
  });
}
