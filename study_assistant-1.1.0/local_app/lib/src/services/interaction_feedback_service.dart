import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/display_preferences.dart';

enum InteractionSoundKind { tap, pin, unpin, syncDone, complete }

class InteractionFeedback {
  InteractionFeedback._();

  static const _channel = MethodChannel('study_assistant/interaction_sound');

  static void trigger(
    DisplayPreferences prefs, {
    InteractionSoundKind kind = InteractionSoundKind.tap,
  }) {
    if (prefs.hapticsEnabled) {
      final vibration = switch (kind) {
        InteractionSoundKind.tap => HapticFeedback.selectionClick(),
        InteractionSoundKind.pin ||
        InteractionSoundKind.unpin ||
        InteractionSoundKind.syncDone =>
          HapticFeedback.lightImpact(),
        InteractionSoundKind.complete => HapticFeedback.mediumImpact(),
      };
      unawaited(_optional(vibration));
    }
    if (prefs.soundEnabled &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_optional(
        _channel.invokeMethod<void>('play', {'kind': kind.name}),
      ));
    }
  }

  static Future<void> _optional(Future<void> feedback) async {
    try {
      await feedback;
    } on MissingPluginException {
      // Feedback can be unavailable on another host.
    } on PlatformException {
      // A feedback error must not interrupt the completed interaction.
    }
  }
}
