import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'journal.dart';
import 'journal_motion.dart';

/// Smooth opaque lateral parallax transition matching the journal paper
/// metaphor:
/// - On non-web Android, permanently mounts a [WidgetsBindingObserver] so
///   Android 14+ predictive back gestures are reachable and transition smoothly
///   between shrinking-card predictive back and commit/cancel completion.
/// - Normal pushes/pops slide in an opaque foreground sheet from the right with
///   a soft left edge shadow while gently receding the underlying route
///   (`Offset(-0.22, 0)`) under a subtle scrim — zero double-text ghosting.
/// - Reduced-motion disables animation cleanly (`child` returned directly) and
///   declines predictive back so system back falls back to instant pop.
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
    final reducedMotion = JournalMotion.isReducedMotion(context);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return _JournalAndroidPredictiveBackHost(
        route: route,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        reducedMotion: reducedMotion,
        child: child,
      );
    }
    if (reducedMotion) {
      return child;
    }

    return _JournalParallaxPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

enum _JournalPredictiveBackPhase {
  idle,
  start,
  update,
  commit,
  cancel,
}

class _JournalAndroidPredictiveBackHost extends StatefulWidget {
  const _JournalAndroidPredictiveBackHost({
    required this.route,
    required this.animation,
    required this.secondaryAnimation,
    required this.reducedMotion,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool reducedMotion;
  final Widget child;

  @override
  State<_JournalAndroidPredictiveBackHost> createState() =>
      _JournalAndroidPredictiveBackHostState();
}

class _JournalAndroidPredictiveBackHostState
    extends State<_JournalAndroidPredictiveBackHost>
    with WidgetsBindingObserver {
  static final ValueNotifier<bool> _neverInProgress =
      ValueNotifier<bool>(false);

  ValueNotifier<bool>? _gestureNotifier;
  bool _gestureActive = false;
  _JournalPredictiveBackPhase _phase = _JournalPredictiveBackPhase.idle;
  PredictiveBackEvent? _startBackEvent;
  PredictiveBackEvent? _currentBackEvent;

  bool get _canStartPredictiveBack {
    if (!mounted || widget.reducedMotion) return false;
    if (JournalMotion.isReducedMotion(context)) return false;
    final route = widget.route;
    final navigator = route.navigator;
    if (navigator == null || !route.isActive || !route.isCurrent) {
      return false;
    }
    if (!route.canPop || route.popDisposition == RoutePopDisposition.doNotPop) {
      return false;
    }
    if (!route.popGestureEnabled) {
      return false;
    }
    if (navigator.userGestureInProgress) {
      return false;
    }
    return true;
  }

  void _attachGestureNotifier() {
    final next = widget.route.navigator?.userGestureInProgressNotifier;
    if (_gestureNotifier == next) return;
    _gestureNotifier?.removeListener(_onUserGestureChanged);
    _gestureNotifier = next;
    _gestureNotifier?.addListener(_onUserGestureChanged);
  }

  void _onUserGestureChanged() {
    final inProgress = _gestureNotifier?.value ?? false;
    if (!inProgress &&
        !_gestureActive &&
        _phase != _JournalPredictiveBackPhase.idle) {
      if (mounted) {
        setState(() => _phase = _JournalPredictiveBackPhase.idle);
      } else {
        _phase = _JournalPredictiveBackPhase.idle;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachGestureNotifier();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachGestureNotifier();
  }

  @override
  void didUpdateWidget(covariant _JournalAndroidPredictiveBackHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) {
      _gestureActive = false;
      _phase = _JournalPredictiveBackPhase.idle;
      _startBackEvent = null;
      _currentBackEvent = null;
    }
    _attachGestureNotifier();
  }

  @override
  void dispose() {
    _gestureNotifier?.removeListener(_onUserGestureChanged);
    _gestureNotifier = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !_canStartPredictiveBack) {
      return false;
    }
    setState(() {
      _gestureActive = true;
      _phase = _JournalPredictiveBackPhase.start;
      _startBackEvent = backEvent;
      _currentBackEvent = backEvent;
    });
    widget.route.handleStartBackGesture(
      progress: clampDouble(1.0 - backEvent.progress, 0.0, 1.0),
    );
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_gestureActive || !mounted || !widget.route.isCurrent) {
      return;
    }
    setState(() {
      _phase = _JournalPredictiveBackPhase.update;
      _currentBackEvent = backEvent;
    });
    widget.route.handleUpdateBackGestureProgress(
      progress: clampDouble(1.0 - backEvent.progress, 0.0, 1.0),
    );
  }

  @override
  void handleCancelBackGesture() {
    if (!_gestureActive) return;
    _gestureActive = false;
    _phase = _JournalPredictiveBackPhase.cancel;
    _startBackEvent = null;
    _currentBackEvent = null;
    widget.route.handleCancelBackGesture();
    if (mounted) {
      if (!(widget.route.navigator?.userGestureInProgress ?? false)) {
        _phase = _JournalPredictiveBackPhase.idle;
      }
      setState(() {});
    }
  }

  @override
  void handleCommitBackGesture() {
    if (!_gestureActive) return;
    _gestureActive = false;
    _phase = _JournalPredictiveBackPhase.commit;
    _startBackEvent = null;
    _currentBackEvent = null;
    widget.route.handleCommitBackGesture();
    if (mounted) {
      if (!(widget.route.navigator?.userGestureInProgress ?? false)) {
        _phase = _JournalPredictiveBackPhase.idle;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reducedMotion) {
      return widget.child;
    }
    final listenable = _gestureNotifier ?? _neverInProgress;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final inPredictiveGesture = widget.route.popGestureInProgress &&
            (_gestureActive || _phase != _JournalPredictiveBackPhase.idle);
        if (inPredictiveGesture) {
          return _JournalPredictiveBackTransition(
            animation: widget.animation,
            phase: _phase,
            startBackEvent: _startBackEvent,
            currentBackEvent: _currentBackEvent,
            child: widget.child,
          );
        }
        return _JournalParallaxPageTransition(
          animation: widget.animation,
          secondaryAnimation: widget.secondaryAnimation,
          child: widget.child,
        );
      },
    );
  }
}

class _JournalPredictiveBackTransition extends StatefulWidget {
  const _JournalPredictiveBackTransition({
    required this.animation,
    required this.phase,
    required this.startBackEvent,
    required this.currentBackEvent,
    required this.child,
  });

  final Animation<double> animation;
  final _JournalPredictiveBackPhase phase;
  final PredictiveBackEvent? startBackEvent;
  final PredictiveBackEvent? currentBackEvent;
  final Widget child;

  @override
  State<_JournalPredictiveBackTransition> createState() =>
      _JournalPredictiveBackTransitionState();
}

class _JournalPredictiveBackTransitionState
    extends State<_JournalPredictiveBackTransition> {
  static const double _kMinScale = 0.90;
  static const double _kDivisionFactor = 20.0;
  static const double _kMargin = 8.0;
  static const double _kYPositionFactor = 0.1;
  static const double _kDeviceBorderRadius = 32.0;
  static const Curve _kCommitCurve = Curves.easeInOutCubicEmphasized;
  static const Interval _kCommitInterval =
      Interval(0.0, 0.8, curve: _kCommitCurve);

  final Tween<double> _borderRadiusTween =
      Tween<double>(begin: 0.0, end: _kDeviceBorderRadius);
  final Tween<double> _opacityTween = Tween<double>(begin: 1.0, end: 0.0);
  final Tween<double> _scaleTween = Tween<double>(begin: 1.0, end: _kMinScale);

  final ProxyAnimation _commitAnimation = ProxyAnimation();
  final ProxyAnimation _bounceAnimation = ProxyAnimation();
  final ProxyAnimation _animation = ProxyAnimation();
  double _lastBounceAnimationValue = 0.0;

  CurvedAnimation? _curvedAnimation;
  CurvedAnimation? _curvedAnimationReversed;
  late Animation<Offset> _positionAnimation;
  Offset _lastDrag = Offset.zero;

  double _getYShiftPosition(double screenHeight) {
    final startTouchY = widget.startBackEvent?.touchOffset?.dy ?? 0.0;
    final currentTouchY = widget.currentBackEvent?.touchOffset?.dy ?? 0.0;
    final yShiftMax = (screenHeight / _kDivisionFactor) - _kMargin;
    final rawYShift = currentTouchY - startTouchY;
    final easedYShift = Curves.easeOut
            .transform(clampDouble(rawYShift.abs() / screenHeight, 0.0, 1.0)) *
        rawYShift.sign *
        yShiftMax;
    return clampDouble(easedYShift, -yShiftMax, yShiftMax);
  }

  void _updateCurvedAnimations() {
    _curvedAnimation?.dispose();
    _curvedAnimationReversed?.dispose();
    _curvedAnimation =
        CurvedAnimation(parent: widget.animation, curve: _kCommitInterval);
    _curvedAnimationReversed = CurvedAnimation(
      parent: ReverseAnimation(widget.animation),
      curve: _kCommitInterval,
    );
  }

  void _updateAnimations(Size screenSize) {
    _animation.parent = switch (widget.phase) {
      _JournalPredictiveBackPhase.commit => _curvedAnimationReversed,
      _ => widget.animation,
    };
    _bounceAnimation.parent = switch (widget.phase) {
      _JournalPredictiveBackPhase.commit => Tween<double>(
          begin: 0.0,
          end: _lastBounceAnimationValue,
        ).animate(_curvedAnimation!),
      _ => ReverseAnimation(widget.animation),
    };
    _commitAnimation.parent = switch (widget.phase) {
      _JournalPredictiveBackPhase.commit => _animation,
      _ => kAlwaysDismissedAnimation,
    };

    final xShift = (screenSize.width / _kDivisionFactor) - _kMargin;
    _positionAnimation = _animation.drive(
      switch (widget.phase) {
        _JournalPredictiveBackPhase.commit => Tween<Offset>(
            begin: _lastDrag,
            end: Offset(screenSize.height * _kYPositionFactor, 0.0),
          ),
        _ => Tween<Offset>(
            begin: switch (widget.currentBackEvent?.swipeEdge) {
              SwipeEdge.left ||
              null =>
                Offset(xShift, _getYShiftPosition(screenSize.height)),
              SwipeEdge.right =>
                Offset(-xShift, _getYShiftPosition(screenSize.height)),
            },
            end: Offset.zero,
          ),
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCurvedAnimations();
    _updateAnimations(MediaQuery.sizeOf(context));
  }

  @override
  void didUpdateWidget(covariant _JournalPredictiveBackTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      _updateCurvedAnimations();
    }
    if (widget.phase != oldWidget.phase ||
        widget.currentBackEvent?.swipeEdge !=
            oldWidget.currentBackEvent?.swipeEdge) {
      _updateAnimations(MediaQuery.sizeOf(context));
    }
  }

  @override
  void dispose() {
    _curvedAnimation?.dispose();
    _curvedAnimationReversed?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        _lastBounceAnimationValue = _bounceAnimation.value;
        return Transform.scale(
          scale: _scaleTween.evaluate(_bounceAnimation),
          child: Transform.translate(
            offset: switch (widget.phase) {
              _JournalPredictiveBackPhase.commit => _positionAnimation.value,
              _ => _lastDrag = Offset(
                  _positionAnimation.value.dx,
                  _getYShiftPosition(MediaQuery.heightOf(context)),
                ),
            },
            child: Opacity(
              opacity: _opacityTween.evaluate(_commitAnimation),
              child: ClipRRect(
                borderRadius: MediaQuery.displayCornerRadiiOf(context) ??
                    BorderRadius.circular(
                      _borderRadiusTween.evaluate(_bounceAnimation),
                    ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
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
