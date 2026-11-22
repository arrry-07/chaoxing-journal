import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/display_preferences.dart';
import '../models/sync_report.dart';

enum InteractionSoundKind { tap, pin, unpin, syncDone, complete }

class InteractionFeedback {
  InteractionFeedback._();

  static const _channel = MethodChannel('study_assistant/interaction_sound');

  static DisplayPreferences Function()? systemClickPrefs;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;
  static DateTime? _last;

  @visibleForTesting
  static void debugReset() {
    _last = null;
    now = DateTime.now;
  }

  static void systemClick() {
    final p = systemClickPrefs?.call();
    if (p != null) trigger(p);
  }

  /// Trigger `syncDone` only after a genuine, clean refresh in the same account epoch.
  static void triggerSyncDoneIfReady({
    required DisplayPreferences prefs,
    required SyncReport before,
    required SyncReport after,
    required int beforeEpoch,
    required int afterEpoch,
    required String? operationError,
  }) {
    if (identical(after, before) ||
        after.phase != SyncPhase.success ||
        operationError != null ||
        beforeEpoch != afterEpoch) {
      return;
    }
    trigger(prefs, kind: InteractionSoundKind.syncDone);
  }

  static void trigger(
    DisplayPreferences prefs, {
    InteractionSoundKind kind = InteractionSoundKind.tap,
    bool preview = false,
  }) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (!prefs.soundEnabled && !prefs.hapticsEnabled) return;
      if (!_shouldEmit(kind, preview)) return;
      unawaited(_optional(_channel.invokeMethod<void>('feedback', {
        'kind': kind.name,
        'sound': prefs.soundEnabled,
        'haptics': prefs.hapticsEnabled,
      })));
      return;
    }
    if (!prefs.hapticsEnabled) return;
    if (!_shouldEmit(kind, preview)) return;
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

  static bool _shouldEmit(InteractionSoundKind kind, bool preview) {
    final current = now();
    if (kind == InteractionSoundKind.tap &&
        !preview &&
        _last != null &&
        current.difference(_last!) < const Duration(milliseconds: 90)) {
      return false;
    }
    _last = current;
    return true;
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
