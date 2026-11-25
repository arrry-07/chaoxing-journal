import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'journal.dart';
import 'journal_motion.dart';

/// Smooth opaque lateral parallax transition matching the journal paper
/// metaphor:
/// - In-progress Android 14+ predictive back gestures delegate cleanly to
///   [PredictiveBackPageTransitionsBuilder].
/// - Normal pushes/pops slide in an opaque foreground sheet from the right with
///   a soft left edge shadow while gently receding the underlying route
///   (`Offset(-0.22, 0)`) under a subtle scrim — zero double-text ghosting.
/// - Reduced-motion disables animation cleanly (`child` returned directly).
class JournalPageTransitionsBuilder extends PageTransitionsBuilder {
  const JournalPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (JournalMotion.isReducedMotion(context)) {
      return child;
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        route.popGestureInProgress) {
      return const PredictiveBackPageTransitionsBuilder().buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    return _JournalParallaxPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _JournalParallaxPageTransition extends StatefulWidget {
  const _JournalParallaxPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<_JournalParallaxPageTransition> createState() =>
      _JournalParallaxPageTransitionState();
}

class _JournalParallaxPageTransitionState
    extends State<_JournalParallaxPageTransition> {
  late CurvedAnimation _primary;
  late CurvedAnimation _secondary;

  @override
  void initState() {
    super.initState();
    _primary = _createCurve(widget.animation);
    _secondary = _createCurve(widget.secondaryAnimation);
  }

  @override
  void didUpdateWidget(covariant _JournalParallaxPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _primary.dispose();
      _primary = _createCurve(widget.animation);
    }
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _secondary.dispose();
      _secondary = _createCurve(widget.secondaryAnimation);
    }
  }

  CurvedAnimation _createCurve(Animation<double> parent) => CurvedAnimation(
        parent: parent,
        curve: JournalMotion.easeDrawer,
        reverseCurve: JournalMotion.easeOut,
      );

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final incomingSlide = _primary.drive(
      Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ),
    );
    final outgoingSlide = _secondary.drive(
      Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.22, 0.0),
      ),
    );

    return SlideTransition(
      position: outgoingSlide,
      child: AnimatedBuilder(
        animation: _secondary,
        child: SlideTransition(
          position: incomingSlide,
          child: AnimatedBuilder(
            animation: _primary,
            child: widget.child,
            builder: (context, child) {
              final raw = widget.animation.value;
              final active =
                  widget.animation.status != AnimationStatus.completed &&
                      raw > 0.0 &&
                      raw < 1.0;
              if (!active) return child!;
              return DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: (journal.isDark ? 0.24 : 0.10) * _primary.value,
                      ),
                      blurRadius: 16,
                      offset: const Offset(-4, 0),
                    ),
                  ],
                ),
                child: child,
              );
            },
          ),
        ),
        builder: (context, child) {
          final covered = widget.secondaryAnimation.value;
          if (covered <= 0.0) return child!;
          return Stack(
            fit: StackFit.passthrough,
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(
                      alpha: (journal.isDark ? 0.16 : 0.08) * _secondary.value,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
