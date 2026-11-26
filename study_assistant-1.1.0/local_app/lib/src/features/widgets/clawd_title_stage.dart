import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../app/journal_motion.dart';
import '../../services/clawd_companion_controller.dart';
import 'clawd_speech_bubble.dart';
import 'journal_pixel_buddy.dart';

@immutable
class ClawdStageAnchor {
  const ClawdStageAnchor({
    required this.centerX,
    required this.bottomY,
    required this.safeWidth,
  });

  final double centerX;
  final double bottomY;
  final double safeWidth;

  @override
  bool operator ==(Object other) =>
      other is ClawdStageAnchor &&
      (other.centerX - centerX).abs() < 0.25 &&
      (other.bottomY - bottomY).abs() < 0.25 &&
      (other.safeWidth - safeWidth).abs() < 0.25;

  @override
  int get hashCode => Object.hash(
        centerX.round(),
        bottomY.round(),
        safeWidth.round(),
      );
}

enum _StageChoreoKind {
  patrolTop,
  sitDangle,
  napZzz,
  climbEdge,
  hangSlipFlip,
  returnRest,
}

class ClawdTitleStage extends StatefulWidget {
  const ClawdTitleStage({
    super.key,
    required this.title,
    required this.titleStyle,
    required this.controller,
    required this.showBuddy,
    required this.buddySize,
    required this.interactive,
    required this.allowStageMotion,
    required this.snapshotBuilder,
    this.anchorNotifier,
    this.renderBubbleInline = false,
    this.moodOverride,
  });

  final String title;
  final TextStyle titleStyle;
  final ClawdCompanionController controller;
  final bool showBuddy;
  final double buddySize;
  final bool interactive;
  final bool allowStageMotion;
  final ClawdPageContextSnapshot Function() snapshotBuilder;
  final ValueNotifier<ClawdStageAnchor>? anchorNotifier;
  final bool renderBubbleInline;
  final JournalPixelBuddyMood? moodOverride;

  @override
  State<ClawdTitleStage> createState() => _ClawdTitleStageState();
}

class _ClawdTitleStageState extends State<ClawdTitleStage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const SpringDescription _dropSpring = SpringDescription(
    mass: 1.0,
    stiffness: 420.0,
    damping: 24.0,
  );
  static const Tolerance _dropTolerance = JournalMotion.springTolerance;

  late final AnimationController _choreoController;
  late final AnimationController _dropController;

  Timer? _patrolTimer;
  int _choreoStep = 0;
  _StageChoreoKind? _activeChoreo;
  int _activeFacing = 1;

  Offset _currentPos = Offset.zero;
  Offset _choreoStart = Offset.zero;
  Offset _choreoEnd = Offset.zero;
  double _choreoArcHeight = 0.0;

  bool _isDragging = false;
  bool _isPetting = false;
  Offset _dragStart = Offset.zero;
  Offset _dropEnd = Offset.zero;
  Offset _restPos = Offset.zero;
  Rect _glyphRect = Rect.zero;
  double _stageWidth = 200.0;
  double _stageBaseHeight = 44.0;
  bool _hasLayout = false;

  bool _appResumed = true;
  bool _tickerEnabled = true;
  bool _reducedMotion = false;

  bool get _canRunChoreography =>
      mounted &&
      widget.showBuddy &&
      widget.interactive &&
      widget.allowStageMotion &&
      _appResumed &&
      _tickerEnabled &&
      !_reducedMotion &&
      !_isDragging &&
      !_isPetting &&
      widget.controller.transientPose == ClawdTransientPose.none;

  @override
  void initState() {
    super.initState();
    _appResumed =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
            AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _choreoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )
      ..addListener(_onChoreoTick)
      ..addStatusListener(_onChoreoStatus);
    _dropController = AnimationController.unbounded(
      vsync: this,
      value: 0.0,
    )
      ..addListener(_onDropTick)
      ..addStatusListener(_onDropStatus);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reducedMotion = JournalMotion.isReducedMotion(context);
    _reconcileStage(allowNotify: false);
  }

  @override
  void didUpdateWidget(covariant ClawdTitleStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    _reconcileStage(allowNotify: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextResumed = state == AppLifecycleState.resumed;
    if (_appResumed == nextResumed) return;
    _appResumed = nextResumed;
    _reconcileStage(allowNotify: true);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (widget.controller.transientPose != ClawdTransientPose.none) {
      _patrolTimer?.cancel();
      _patrolTimer = null;
    } else {
      _schedulePatrolIfNeeded();
    }
    setState(() {});
  }

  void _reconcileStage({bool allowNotify = true}) {
    if (!mounted) return;
    final motionBlocked = !widget.showBuddy ||
        !widget.allowStageMotion ||
        !_appResumed ||
        !_tickerEnabled ||
        _reducedMotion;
    if (motionBlocked || !widget.interactive) {
      _stopAllMotion(
        resetToRest: true,
        clearTransientPose: motionBlocked,
        allowNotify: allowNotify,
      );
      return;
    }
    _schedulePatrolIfNeeded();
  }

  void _stopAllMotion({
    bool resetToRest = false,
    bool clearTransientPose = false,
    bool allowNotify = true,
  }) {
    _patrolTimer?.cancel();
    _patrolTimer = null;
    _choreoController.stop();
    _dropController.stop();
    _activeChoreo = null;
    _isDragging = false;
    _isPetting = false;
    if (clearTransientPose) {
      final controller = widget.controller;
      final cleared = controller.clearTransientPose(notify: allowNotify);
      if (cleared && !allowNotify) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          controller.notifyListenersIfAlive();
        });
      }
    }
    if (resetToRest && _hasLayout) {
      _currentPos = _restPos;
      _publishAnchorPostFrame();
    }
  }

  void _schedulePatrolIfNeeded() {
    if (!_canRunChoreography ||
        _patrolTimer != null ||
        _choreoController.isAnimating ||
        _dropController.isAnimating) {
      return;
    }
    final delayMs = 2600 + (_choreoStep * 439) % 1901;
    _patrolTimer = Timer(Duration(milliseconds: delayMs), _runNextChoreo);
  }

  double get _hitWidth => math.max(widget.buddySize + 6.0, 44.0);

  double get _hitHalfPad => (_hitWidth - widget.buddySize) * 0.5;

  double _safeMinX(double maxX) =>
      math.min(maxX, _glyphRect.right + _hitHalfPad + 1.0);

  double _safeMaxY() =>
      math.max(_restPos.dy, _stageBaseHeight - widget.buddySize);

  void _runNextChoreo() {
    _patrolTimer = null;
    if (!_canRunChoreography || !_hasLayout) return;

    final step = _choreoStep++;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    final safeMinX = _safeMinX(maxX);
    final restX = _restPos.dx.clamp(safeMinX, maxX);
    final farRightX = maxX;
    final midRightX = ((restX + farRightX) * 0.5).clamp(safeMinX, maxX);
    final highY = (_restPos.dy - 4.0).clamp(-4.0, _restPos.dy);
    final lowY = (_restPos.dy + 2.0).clamp(_restPos.dy, _safeMaxY());
    final clampedStart = Offset(
      _currentPos.dx.clamp(safeMinX, maxX),
      _currentPos.dy.clamp(-6.0, lowY),
    );

    final cycle = step % 6;
    switch (cycle) {
      case 0:
        _activeChoreo = _StageChoreoKind.patrolTop;
        _choreoStart = clampedStart;
        _choreoEnd = Offset(step.isEven ? farRightX : midRightX, _restPos.dy);
        _choreoArcHeight = 6.0;
        _activeFacing = _choreoEnd.dx >= _choreoStart.dx ? 1 : -1;
        _choreoController.duration = const Duration(milliseconds: 560);
      case 1:
        _activeChoreo = _StageChoreoKind.sitDangle;
        _choreoStart = clampedStart;
        _choreoEnd = Offset(farRightX, highY);
        _choreoArcHeight = 5.0;
        _activeFacing = 1;
        _choreoController.duration = const Duration(milliseconds: 760);
      case 2:
        _activeChoreo = _StageChoreoKind.napZzz;
        _choreoStart = clampedStart;
        _choreoEnd = Offset(midRightX, _restPos.dy);
        _choreoArcHeight = 3.0;
        _activeFacing = 1;
        _choreoController.duration = const Duration(milliseconds: 860);
      case 3:
        _activeChoreo = _StageChoreoKind.climbEdge;
        _activeFacing = -1;
        _choreoStart = clampedStart;
        _choreoEnd = Offset(safeMinX, highY);
        _choreoArcHeight = 4.0;
        _choreoController.duration = const Duration(milliseconds: 720);
      case 4:
        _activeChoreo = _StageChoreoKind.hangSlipFlip;
        _choreoStart = clampedStart;
        _choreoEnd = Offset(restX, _restPos.dy);
        _choreoArcHeight = 7.0;
        _activeFacing = 1;
        _choreoController.duration = const Duration(milliseconds: 820);
      default:
        _activeChoreo = _StageChoreoKind.returnRest;
        _choreoStart = clampedStart;
        _choreoEnd = Offset(restX, _restPos.dy);
        _choreoArcHeight = 6.0;
        _activeFacing = _choreoEnd.dx >= _choreoStart.dx ? 1 : -1;
        _choreoController.duration = const Duration(milliseconds: 500);
    }

    _choreoController.forward(from: 0.0);
  }

  void _onChoreoTick() {
    if (!mounted) return;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    final safeMinX = _safeMinX(maxX);
    final t = _choreoController.value.clamp(0.0, 1.0);
    final eased = JournalMotion.easeOut.transform(t);
    final pos = Offset.lerp(_choreoStart, _choreoEnd, eased)!;
    final arc = -_choreoArcHeight * math.sin(math.pi * t);
    setState(() {
      _currentPos = Offset(
        pos.dx.clamp(safeMinX, maxX),
        (pos.dy + arc).clamp(-6.0, _safeMaxY() + 2.0),
      );
    });
    _publishAnchorNow();
  }

  void _onChoreoStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _activeChoreo = null;
      _currentPos = _choreoEnd;
    });
    _publishAnchorNow();
    _schedulePatrolIfNeeded();
  }

  void _onDropTick() {
    if (!mounted) return;
    final t = _dropController.value;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    setState(() {
      _currentPos = Offset(
        (_dragStart.dx + (_dropEnd.dx - _dragStart.dx) * t).clamp(0.0, maxX),
        (_dragStart.dy + (_dropEnd.dy - _dragStart.dy) * t).clamp(-10.0, 28.0),
      );
    });
    _publishAnchorNow();
  }

  void _onDropStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _currentPos = _dropEnd;
    });
    _publishAnchorNow();
    widget.controller.landFromGrab();
    _schedulePatrolIfNeeded();
  }

  void _handleTap() {
    if (!widget.showBuddy) return;
    widget.controller.registerTap(snapshot: widget.snapshotBuilder());
  }

  void _handleLongPressStart(LongPressStartDetails _) {
    if (!widget.showBuddy ||
        !widget.interactive ||
        !widget.allowStageMotion ||
        _reducedMotion) {
      return;
    }
    _patrolTimer?.cancel();
    _patrolTimer = null;
    _choreoController.stop();
    _activeChoreo = null;
    setState(() => _isPetting = true);
    widget.controller.startPet(snapshot: widget.snapshotBuilder());
  }

  void _handleLongPressEnd() {
    if (!_isPetting) return;
    setState(() => _isPetting = false);
    widget.controller.endPet();
    _schedulePatrolIfNeeded();
  }

  void _handlePanStart(DragStartDetails _) {
    if (!widget.showBuddy || !widget.interactive || !widget.allowStageMotion) {
      return;
    }
    _patrolTimer?.cancel();
    _patrolTimer = null;
    _choreoController.stop();
    _dropController.stop();
    _activeChoreo = null;
    setState(() => _isDragging = true);
    widget.controller.startGrab(snapshot: widget.snapshotBuilder());
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    setState(() {
      _currentPos = Offset(
        (_currentPos.dx + details.delta.dx).clamp(0.0, maxX),
        (_currentPos.dy + details.delta.dy).clamp(-10.0, 26.0),
      );
    });
    _publishAnchorNow();
  }

  void _handlePanEndOrCancel() {
    if (!_isDragging) return;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    final safeMinX = _safeMinX(maxX);
    final restX = _restPos.dx.clamp(safeMinX, maxX);
    final midX = ((restX + maxX) * 0.5).clamp(safeMinX, maxX);
    final highY = (_restPos.dy - 4.0).clamp(-4.0, _restPos.dy);

    final candidates = <Offset>[
      Offset(safeMinX, _restPos.dy),
      Offset(restX, _restPos.dy),
      Offset(midX, _restPos.dy),
      Offset(maxX, _restPos.dy),
      Offset(restX, highY),
      Offset(maxX, highY),
    ];
    var best = _restPos;
    var bestDist = double.infinity;
    for (final c in candidates) {
      final d = (c - _currentPos).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        best = c;
      }
    }

    setState(() {
      _isDragging = false;
      _dragStart = _currentPos;
      _dropEnd = best;
    });
    _dropController.animateWith(
      SpringSimulation(
        _dropSpring,
        0.0,
        1.0,
        0.0,
        tolerance: _dropTolerance,
      ),
    );
  }

  JournalPixelBuddyPose _resolvePose() {
    final tp = widget.controller.transientPose;
    if (tp != ClawdTransientPose.none) {
      return switch (tp) {
        ClawdTransientPose.none => JournalPixelBuddyPose.normal,
        ClawdTransientPose.wave => JournalPixelBuddyPose.wave,
        ClawdTransientPose.doubleStar => JournalPixelBuddyPose.doubleStar,
        ClawdTransientPose.tsundere => JournalPixelBuddyPose.tsunderePuff,
        ClawdTransientPose.petting => JournalPixelBuddyPose.petSquint,
        ClawdTransientPose.grabbed => JournalPixelBuddyPose.grabbedFlail,
        ClawdTransientPose.landing => JournalPixelBuddyPose.landing,
        ClawdTransientPose.cheer => JournalPixelBuddyPose.cheer,
      };
    }
    if (_isDragging) return JournalPixelBuddyPose.grabbedFlail;
    if (_isPetting) return JournalPixelBuddyPose.petSquint;
    if (_activeChoreo != null) {
      return switch (_activeChoreo!) {
        _StageChoreoKind.patrolTop => JournalPixelBuddyPose.normal,
        _StageChoreoKind.sitDangle => JournalPixelBuddyPose.sitDangle,
        _StageChoreoKind.napZzz => JournalPixelBuddyPose.napZzz,
        _StageChoreoKind.climbEdge => JournalPixelBuddyPose.climbEdge,
        _StageChoreoKind.hangSlipFlip => JournalPixelBuddyPose.hangSlipFlip,
        _StageChoreoKind.returnRest => JournalPixelBuddyPose.normal,
      };
    }
    return JournalPixelBuddyPose.normal;
  }

  void _publishAnchorNow() {
    final notifier = widget.anchorNotifier;
    if (notifier == null) return;
    final next = ClawdStageAnchor(
      centerX: _currentPos.dx + widget.buddySize * 0.5,
      bottomY: _currentPos.dy + widget.buddySize,
      safeWidth: _stageWidth,
    );
    if (notifier.value != next) {
      notifier.value = next;
    }
  }

  void _publishAnchorPostFrame() {
    final notifier = widget.anchorNotifier;
    if (notifier == null) return;
    final next = ClawdStageAnchor(
      centerX: _currentPos.dx + widget.buddySize * 0.5,
      bottomY: _currentPos.dy + widget.buddySize,
      safeWidth: _stageWidth,
    );
    if (notifier.value == next) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (notifier.value != next) {
        notifier.value = next;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    _patrolTimer?.cancel();
    _patrolTimer = null;
    _choreoController.removeListener(_onChoreoTick);
    _choreoController.removeStatusListener(_onChoreoStatus);
    _choreoController.dispose();
    _dropController.removeListener(_onDropTick);
    _dropController.removeStatusListener(_onDropStatus);
    _dropController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0;
        final reservedTail = widget.showBuddy ? _hitWidth : 0.0;
        final availableTitleW = math.max(40.0, maxW - reservedTail);

        final tp = TextPainter(
          text: TextSpan(text: widget.title, style: widget.titleStyle),
          textDirection: direction,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        final rawW = tp.width.ceilToDouble();
        final rawH = tp.height;
        tp.dispose();

        final scale =
            rawW > availableTitleW && rawW > 0 ? availableTitleW / rawW : 1.0;
        final renderedTitleW = rawW * scale;
        final renderedTitleH = rawH * scale;
        final baseH = math.max(
          renderedTitleH,
          widget.showBuddy ? math.max(widget.buddySize, 44.0) : 0.0,
        );
        final titleTop = (baseH - renderedTitleH) * 0.5;
        final nextGlyphRect =
            Rect.fromLTWH(0.0, titleTop, renderedTitleW, renderedTitleH);
        final restLeadGap = math.max(6.0, _hitHalfPad + 1.0);
        final nextRestPos = Offset(
          (renderedTitleW + restLeadGap)
              .clamp(0.0, math.max(0.0, maxW - widget.buddySize)),
          (baseH - widget.buddySize) * 0.5,
        );

        final geometryChanged = !_hasLayout ||
            (_stageWidth - maxW).abs() > 0.5 ||
            (_restPos - nextRestPos).distance > 0.5;
        _stageWidth = maxW;
        _stageBaseHeight = baseH;
        _glyphRect = nextGlyphRect;
        _restPos = nextRestPos;

        if (!_hasLayout ||
            !widget.allowStageMotion ||
            (!_isDragging &&
                !_choreoController.isAnimating &&
                !_dropController.isAnimating &&
                _activeChoreo == null &&
                geometryChanged)) {
          _currentPos = nextRestPos;
          _hasLayout = true;
        }
        _publishAnchorPostFrame();

        final hitW = math.max(widget.buddySize + 6.0, 44.0);
        final hitH = math.max(widget.buddySize + 6.0, 44.0);
        final hitLeft = (_currentPos.dx + (widget.buddySize - hitW) * 0.5)
            .clamp(0.0, math.max(0.0, maxW - hitW))
            .toDouble();
        final hitTop = _currentPos.dy + (widget.buddySize - hitH) * 0.5;

        final pose = _resolvePose();
        final poseProgress =
            _choreoController.isAnimating ? _choreoController.value : null;
        final enableStageGestures = widget.interactive &&
            widget.allowStageMotion &&
            !_reducedMotion &&
            _appResumed &&
            _tickerEnabled;

        final bubble = widget.controller.activeBubble;
        final showInlineBubble = widget.renderBubbleInline &&
            widget.showBuddy &&
            bubble != null &&
            bubble.tab == ClawdPrimaryTab.home &&
            widget.interactive;

        return SizedBox(
          width: maxW,
          height: _stageBaseHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: availableTitleW),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(widget.title, style: widget.titleStyle),
                  ),
                ),
              ),
              if (widget.showBuddy)
                Positioned(
                  left: hitLeft,
                  top: hitTop,
                  width: hitW,
                  height: hitH,
                  child: Semantics(
                    button: widget.interactive,
                    label: '像素伙伴，轻点或长按互动',
                    onTap: widget.interactive ? _handleTap : null,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.interactive ? _handleTap : null,
                      onLongPressStart:
                          enableStageGestures ? _handleLongPressStart : null,
                      onLongPressEnd: enableStageGestures
                          ? (_) => _handleLongPressEnd()
                          : null,
                      onLongPressCancel:
                          enableStageGestures ? _handleLongPressEnd : null,
                      onPanStart: enableStageGestures ? _handlePanStart : null,
                      onPanUpdate:
                          enableStageGestures ? _handlePanUpdate : null,
                      onPanEnd: enableStageGestures
                          ? (_) => _handlePanEndOrCancel()
                          : null,
                      onPanCancel:
                          enableStageGestures ? _handlePanEndOrCancel : null,
                      child: Center(
                        child: JournalPixelBuddy(
                          key: const ValueKey('home-pixel-buddy'),
                          mood: widget.moodOverride ?? widget.controller.mood,
                          size: widget.buddySize,
                          syncTickListenable: widget.controller.syncTick,
                          displayPrefs: widget.controller.displayPrefs,
                          celebratePulse: widget.controller.celebratePulse,
                          allowTapCombo: widget.interactive,
                          poseOverride: pose,
                          posePulse: widget.controller.transientPulse,
                          poseProgress: poseProgress,
                          facingSign: _activeFacing,
                          enableIdleActions: false,
                          handleGestures: false,
                        ),
                      ),
                    ),
                  ),
                ),
              if (showInlineBubble)
                Positioned(
                  left: 0.0,
                  right: 0.0,
                  top: _currentPos.dy + widget.buddySize + 4.0,
                  height: 120.0,
                  child: ClawdAnchoredSpeechBubble(
                    bubbleKey: const ValueKey('clawd-speech-bubble'),
                    message: bubble,
                    anchorX: _currentPos.dx + widget.buddySize * 0.5,
                    top: 0.0,
                    minLeft: 0.0,
                    safeRight: maxW,
                    maxWidth: math.min(200.0, maxW),
                    pointerDirection: ClawdBubblePointerDirection.up,
                    onTap: widget.controller.onBubbleTapped,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ClawdTabCameo extends StatelessWidget {
  const ClawdTabCameo({
    super.key,
    required this.controller,
    required this.snapshotBuilder,
    this.size,
  });

  final ClawdCompanionController controller;
  final ClawdPageContextSnapshot Function() snapshotBuilder;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ??
        (MediaQuery.textScalerOf(context).scale(14) >= 19.5 ? 20.0 : 25.0);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final pose = switch (controller.transientPose) {
          ClawdTransientPose.none => JournalPixelBuddyPose.normal,
          ClawdTransientPose.wave => JournalPixelBuddyPose.wave,
          ClawdTransientPose.doubleStar => JournalPixelBuddyPose.doubleStar,
          ClawdTransientPose.tsundere => JournalPixelBuddyPose.tsunderePuff,
          ClawdTransientPose.petting => JournalPixelBuddyPose.petSquint,
          ClawdTransientPose.grabbed => JournalPixelBuddyPose.grabbedFlail,
          ClawdTransientPose.landing => JournalPixelBuddyPose.landing,
          ClawdTransientPose.cheer => JournalPixelBuddyPose.cheer,
        };
        final interactive =
            !controller.isSyncing && !controller.hasSyncErrorOrPending;
        return JournalPixelBuddy(
          mood: controller.isSyncing
              ? JournalPixelBuddyMood.syncing
              : controller.mood,
          size: effectiveSize,
          syncTickListenable: controller.syncTick,
          celebratePulse: controller.celebratePulse,
          allowTapCombo: interactive,
          poseOverride: pose,
          posePulse: controller.transientPulse,
          enableIdleActions: true,
          onTap: () => controller.registerTap(snapshot: snapshotBuilder()),
        );
      },
    );
  }
}
