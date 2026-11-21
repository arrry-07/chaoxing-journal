import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/display_preferences.dart';
import '../services/interaction_feedback_service.dart';

class JournalMotion {
  const JournalMotion._();

  static const interactiveSpring = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 33.5, // damping ratio ~0.86
  );

  static const snappySpring = SpringDescription(
    mass: 1.0,
    stiffness: 520.0,
    damping: 37.4, // damping ratio ~0.82
  );

  static const gentleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 35.8, // critically damped (~1.0)
  );

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeSheet = Curves.easeOutQuart;

  static bool isReducedMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration duration(
    BuildContext context, [
    Duration normal = const Duration(milliseconds: 220),
  ]) =>
      isReducedMotion(context) ? Duration.zero : normal;

  static Duration themeTransitionDuration(BuildContext context) =>
      isReducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 220);

  static SpringSimulation springFor(
    SpringDescription description, {
    required double start,
    required double end,
    double velocity = 0.0,
  }) =>
      SpringSimulation(description, start, end, velocity);

  static void tap(DisplayPreferences prefs) {
    InteractionFeedback.trigger(prefs, kind: InteractionSoundKind.tap);
  }

  static void pin(DisplayPreferences prefs, {required bool pinned}) {
    InteractionFeedback.trigger(
      prefs,
      kind: pinned ? InteractionSoundKind.pin : InteractionSoundKind.unpin,
    );
  }

  static void complete(DisplayPreferences prefs) {
    InteractionFeedback.trigger(prefs, kind: InteractionSoundKind.complete);
  }

  static void selectionTick(DisplayPreferences prefs) {
    if (!prefs.hapticsEnabled) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      InteractionFeedback.trigger(
        prefs.copyWith(soundEnabled: false),
        kind: InteractionSoundKind.tap,
        preview: true,
      );
      return;
    }
    unawaited(_optionalHaptic(HapticFeedback.selectionClick()));
  }

  static void mediumThreshold(DisplayPreferences prefs) {
    if (!prefs.hapticsEnabled) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      InteractionFeedback.trigger(
        prefs.copyWith(soundEnabled: false),
        kind: InteractionSoundKind.complete,
        preview: true,
      );
      return;
    }
    unawaited(_optionalHaptic(HapticFeedback.mediumImpact()));
  }

  static Future<void> _optionalHaptic(Future<void> feedback) async {
    try {
      await feedback;
    } on MissingPluginException {
      // Haptics can be unavailable on test or desktop hosts.
    } on PlatformException {
      // Never allow haptic channel failure to disrupt an interaction.
    }
  }
}
