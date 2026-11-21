import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/journal_binding.dart';

class _RecordingMessenger extends BinaryMessenger {
  final List<(String channel, ByteData? message)> sent = [];

  @override
  @Deprecated('Unused in test fake')
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {}

  @override
  Future<ByteData?>? send(String channel, ByteData? message) async {
    sent.add((channel, message));
    return null;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}
}

void main() {
  test('TapSoundRedirectMessenger intercepts SystemSound.play click', () async {
    final inner = _RecordingMessenger();
    var clicks = 0;
    final messenger = TapSoundRedirectMessenger(
      inner,
      onClick: () {
        clicks++;
        return true;
      },
    );

    final clickPayload = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('SystemSound.play', 'SystemSoundType.click'),
    );
    final response = await messenger.send('flutter/platform', clickPayload);

    expect(clicks, 1);
    expect(inner.sent, isEmpty);
    expect(const JSONMethodCodec().decodeEnvelope(response!), isNull);
  });

  test('TapSoundRedirectMessenger forwards when onClick returns false',
      () async {
    final inner = _RecordingMessenger();
    var clicks = 0;
    final messenger = TapSoundRedirectMessenger(
      inner,
      onClick: () {
        clicks++;
        return false;
      },
    );

    final clickPayload = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('SystemSound.play', 'SystemSoundType.click'),
    );
    await messenger.send('flutter/platform', clickPayload);

    expect(clicks, 1);
    expect(inner.sent, [('flutter/platform', clickPayload)]);
  });

  test('TapSoundRedirectMessenger forwards other methods and channels',
      () async {
    final inner = _RecordingMessenger();
    var clicks = 0;
    final messenger = TapSoundRedirectMessenger(
      inner,
      onClick: () {
        clicks++;
        return true;
      },
    );

    final hapticPayload = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('HapticFeedback.vibrate', 'HapticFeedbackType.vibrate'),
    );
    final alertPayload = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('SystemSound.play', 'SystemSoundType.alert'),
    );
    final otherChannelPayload = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('feedback', {'kind': 'tap'}),
    );
    final invalidPlatformPayload = ByteData(2);

    await messenger.send('flutter/platform', hapticPayload);
    await messenger.send('flutter/platform', alertPayload);
    await messenger.send(
        'study_assistant/interaction_sound', otherChannelPayload);
    await messenger.send('flutter/platform', invalidPlatformPayload);

    expect(clicks, 0);
    expect(inner.sent, [
      ('flutter/platform', hapticPayload),
      ('flutter/platform', alertPayload),
      ('study_assistant/interaction_sound', otherChannelPayload),
      ('flutter/platform', invalidPlatformPayload),
    ]);
  });
}
