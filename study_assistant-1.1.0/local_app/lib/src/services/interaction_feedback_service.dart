import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/display_preferences.dart';
import '../models/sync_report.dart';

enum InteractionSoundKind {
  tap,
  pin,
  unpin,
  syncDone,
  complete,
  clawdJump,
  clawdCombo2,
  clawdCombo3,
  clawdPet,
  clawdGrab,
  clawdLand,
  clawdCheer,
  clawdSyncTick,
}

class InteractionFeedback {
  InteractionFeedback._();

  static const _channel = MethodChannel('study_assistant/interaction_sound');

  static DisplayPreferences Function()? systemClickPrefs;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;
  static DateTime? _lastTap;
  static DateTime? _lastSyncTick;

  @visibleForTesting
  static void debugReset() {
    _lastTap = null;
    _lastSyncTick = null;
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
    final allowHaptics =
        prefs.hapticsEnabled && kind != InteractionSoundKind.clawdSyncTick;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (!prefs.soundEnabled && !allowHaptics) return;
      if (!_shouldEmit(kind, preview)) return;
      unawaited(_optional(_channel.invokeMethod<void>('feedback', {
        'kind': kind.name,
        'sound': prefs.soundEnabled,
        'haptics': allowHaptics,
      })));
      return;
    }
    if (!allowHaptics) return;
    if (!_shouldEmit(kind, preview)) return;
    final Future<void>? vibration = switch (kind) {
      InteractionSoundKind.tap => HapticFeedback.selectionClick(),
      InteractionSoundKind.pin ||
      InteractionSoundKind.unpin ||
      InteractionSoundKind.syncDone ||
      InteractionSoundKind.clawdJump ||
      InteractionSoundKind.clawdCombo2 ||
      InteractionSoundKind.clawdPet =>
        HapticFeedback.lightImpact(),
      InteractionSoundKind.complete ||
      InteractionSoundKind.clawdCombo3 ||
      InteractionSoundKind.clawdGrab ||
      InteractionSoundKind.clawdLand ||
      InteractionSoundKind.clawdCheer =>
        HapticFeedback.mediumImpact(),
      InteractionSoundKind.clawdSyncTick => null,
    };
    if (vibration != null) {
      unawaited(_optional(vibration));
    }
  }

  static bool _shouldEmit(InteractionSoundKind kind, bool preview) {
    if (preview) return true;
    final current = now();
    if (kind == InteractionSoundKind.tap) {
      if (_lastTap != null) {
        final elapsed = current.difference(_lastTap!);
        if (!elapsed.isNegative && elapsed < const Duration(milliseconds: 90)) {
          return false;
        }
      }
      _lastTap = current;
      return true;
    }
    if (kind == InteractionSoundKind.clawdSyncTick) {
      if (_lastSyncTick != null) {
        final elapsed = current.difference(_lastSyncTick!);
        if (!elapsed.isNegative &&
            elapsed < const Duration(milliseconds: 320)) {
          return false;
        }
      }
      _lastSyncTick = current;
      return true;
    }
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
