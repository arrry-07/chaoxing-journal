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

  static const criticalSpring = SpringDescription(
    mass: 1.0,
    stiffness: 420.0,
    damping: 41.0, // damping ratio ~1.00 (no overshoot)
  );

  static const pressSpring = SpringDescription(
    mass: 1.0,
    stiffness: 620.0,
    damping: 42.0, // damping ratio ~0.84
  );

  static const popSpring = SpringDescription(
    mass: 1.0,
    stiffness: 500.0,
    damping: 28.0, // damping ratio ~0.63
  );

  static const springTolerance = Tolerance(distance: 1e-3, velocity: 1e-3);

  static const Curve easeOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Curve easeDrawer = Cubic(0.32, 0.72, 0.0, 1.0);
  static const Curve easeInOut = Cubic(0.77, 0.0, 0.175, 1.0);

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

  static AnimationStyle modalSheetAnimationStyle(BuildContext context) =>
      isReducedMotion(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 280),
              reverseDuration: Duration(milliseconds: 210),
            );

  static SpringSimulation springFor(
    SpringDescription description, {
    required double start,
    required double end,
    double velocity = 0.0,
    Tolerance tolerance = springTolerance,
    bool snapToEnd = true,
  }) =>
      SpringSimulation(
        description,
        start,
        end,
        velocity,
        snapToEnd: snapToEnd,
        tolerance: tolerance,
      );

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
