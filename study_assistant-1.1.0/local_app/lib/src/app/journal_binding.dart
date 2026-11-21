import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/interaction_feedback_service.dart';

class TapSoundRedirectMessenger extends BinaryMessenger {
  const TapSoundRedirectMessenger(this._inner, {required this.onClick});

  final BinaryMessenger _inner;
  final bool Function() onClick;

  @override
  @Deprecated(
    'Instead of calling this method, use ServicesBinding.instance.channelBuffers.push.',
  )
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) {
    // ignore: deprecated_member_use
    return _inner.handlePlatformMessage(channel, data, callback);
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == 'flutter/platform' && message != null) {
      try {
        final call = const JSONMethodCodec().decodeMethodCall(message);
        if (call.method == 'SystemSound.play' &&
            call.arguments == 'SystemSoundType.click' &&
            onClick()) {
          return Future<ByteData?>.value(
            const JSONMethodCodec().encodeSuccessEnvelope(null),
          );
        }
      } catch (_) {
        // Unhandled or non-JSON platform payloads are forwarded intact.
      }
    }
    return _inner.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    _inner.setMessageHandler(channel, handler);
  }
}

class JournalBinding extends WidgetsFlutterBinding {
  static bool _initialized = false;

  static WidgetsBinding ensureInitialized() {
    if (!_initialized) {
      JournalBinding();
      _initialized = true;
    }
    return WidgetsBinding.instance;
  }

  @override
  BinaryMessenger createBinaryMessenger() => TapSoundRedirectMessenger(
        super.createBinaryMessenger(),
        onClick: () {
          if (InteractionFeedback.systemClickPrefs == null) return false;
          InteractionFeedback.systemClick();
          return true;
        },
      );
}
