import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../app/journal.dart';
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
    double? stageBottomY,
  }) : stageBottomY = stageBottomY ?? bottomY;

  final double centerX;
  final double bottomY;
  final double safeWidth;
  final double stageBottomY;

  @override
  bool operator ==(Object other) =>
      other is ClawdStageAnchor &&
      (other.centerX - centerX).abs() < 0.25 &&
      (other.bottomY - bottomY).abs() < 0.25 &&
      (other.safeWidth - safeWidth).abs() < 0.25 &&
      (other.stageBottomY - stageBottomY).abs() < 0.25;

  @override
  int get hashCode => Object.hash(
        centerX.round(),
        bottomY.round(),
        safeWidth.round(),
        stageBottomY.round(),
      );
}

enum _StageChoreoKind {
  climbRoof,
  patrolRoof,
  peekDown,
  hopBounce,
  stretchYawn,
  sitDangle,
  napZzz,
  hangSlipFlip,
  returnRest,
}

@immutable
class _TitleMetricsKey {
  const _TitleMetricsKey({
    required this.title,
    required this.titleStyle,
    required this.direction,
    required this.textScaler,
    required this.availableTitleW,
  });

  final String title;
  final TextStyle titleStyle;
  final TextDirection direction;
  final TextScaler textScaler;
  final double availableTitleW;

  @override
  bool operator ==(Object other) =>
      other is _TitleMetricsKey &&
      other.title == title &&
      other.titleStyle == titleStyle &&
      other.direction == direction &&
      other.textScaler == textScaler &&
      other.availableTitleW == availableTitleW;

  @override
  int get hashCode => Object.hash(
        title,
        titleStyle,
        direction,
        textScaler,
        availableTitleW,
      );
}

@immutable
class _TitleMetrics {
  const _TitleMetrics({
    required this.key,
    required this.rawW,
    required this.rawH,
    required this.scale,
    required this.charCenters,
  });

  final _TitleMetricsKey key;
  final double rawW;
  final double rawH;
  final double scale;
  final List<double> charCenters;
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

  static int debugTitleMetricsComputeCountForTesting = 0;

  static double resolvedBuddySize(BuildContext context, {double? maxWidth}) {
    if (JournalLayout.isLargeText(context)) return 24.0;
    final width = maxWidth ?? MediaQuery.sizeOf(context).width;
    if (width < 350.0) return 30.0;
    return 34.0;
  }

  static double roofHeadroomFor({
    required bool allowStageMotion,
    required double buddySize,
  }) {
    if (!allowStageMotion) return 0.0;
    return buddySize >= 32.0 ? 31.0 : 28.0;
  }

  /// Samples an L-shaped outer-contour stage path so Clawd never crosses
  /// through title glyphs or leaves the positive-coordinate hit box (`dy >= 0`).
  static Offset sampleStagePath({
    required Offset start,
    required Offset end,
    required double t,
    required double arcHeight,
    required double roofY,
    required double safeMinX,
    required double maxX,
    required double maxY,
    required bool allowRoof,
  }) {
    final clampedT = t.clamp(0.0, 1.0);
    final effectiveRoofY = math.max(0.0, roofY);
    final effectiveMaxY = math.max(effectiveRoofY, maxY);
    final effectiveSafeMinX = safeMinX.clamp(0.0, maxX).toDouble();

    Offset clampSafe(Offset raw) {
      final minX = allowRoof ? 0.0 : effectiveSafeMinX;
      final x = raw.dx.clamp(minX, maxX).toDouble();
      final inGlyphZone = allowRoof && x < effectiveSafeMinX - 0.01;
      final yUpper = inGlyphZone ? effectiveRoofY : effectiveMaxY;
      final y = raw.dy.clamp(0.0, math.max(0.0, yUpper)).toDouble();
      return Offset(x, y);
    }

    final startOnRoof = allowRoof && start.dx < effectiveSafeMinX - 0.5;
    final endOnRoof = allowRoof && end.dx < effectiveSafeMinX - 0.5;

    if (!startOnRoof && endOnRoof) {
      const climbSplit = 0.42;
      if (clampedT <= climbSplit) {
        final u = JournalMotion.easeOut.transform(clampedT / climbSplit);
        final x = lerpDouble(
          math.max(start.dx, effectiveSafeMinX),
          effectiveSafeMinX,
          u,
        )!;
        final y = lerpDouble(start.dy, effectiveRoofY, u)!;
        return clampSafe(Offset(x, y));
      }
      final segT = (clampedT - climbSplit) / (1.0 - climbSplit);
      final u = JournalMotion.easeOut.transform(segT);
      final x = lerpDouble(effectiveSafeMinX, end.dx, u)!;
      final arc = -arcHeight * math.sin(math.pi * segT);
      return clampSafe(Offset(x, effectiveRoofY + arc));
    }

    if (startOnRoof && !endOnRoof) {
      const slideSplit = 0.45;
      if (clampedT <= slideSplit) {
        final segT = clampedT / slideSplit;
        final u = JournalMotion.easeOut.transform(segT);
        final x = lerpDouble(start.dx, effectiveSafeMinX, u)!;
        final arc = -(arcHeight * 0.45) * math.sin(math.pi * segT);
        return clampSafe(Offset(x, effectiveRoofY + arc));
      }
      final segT = (clampedT - slideSplit) / (1.0 - slideSplit);
      final u = JournalMotion.easeOut.transform(segT);
      final x = lerpDouble(
        effectiveSafeMinX,
        math.max(end.dx, effectiveSafeMinX),
        u,
      )!;
      final y = lerpDouble(effectiveRoofY, end.dy, u)!;
      final arc = -arcHeight * math.sin(math.pi * segT);
      return clampSafe(Offset(x, y + arc));
    }

    final eased = JournalMotion.easeOut.transform(clampedT);
    final pos = Offset.lerp(start, end, eased)!;
    final arc = -arcHeight * math.sin(math.pi * clampedT);
    if (!startOnRoof && !endOnRoof) {
      return clampSafe(
        Offset(math.max(pos.dx, effectiveSafeMinX), pos.dy + arc),
      );
    }
    return clampSafe(Offset(pos.dx, math.min(effectiveRoofY, pos.dy + arc)));
  }

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
  double _roofHeadroom = 0.0;
  double _roofY = 0.0;
  double _glyphRoofY = 0.0;
  List<double> _roofCharCentersX = const [];
  double _stageWidth = 200.0;
  double _stageBaseHeight = 44.0;
  bool _hasLayout = false;
  _TitleMetrics? _titleMetricsCache;

  bool _appResumed = true;
  bool _tickerEnabled = true;
  bool _reducedMotion = false;

  bool get _hasRoofTrack =>
      widget.showBuddy && widget.allowStageMotion && _roofHeadroom > 0.0;

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
    final delayMs = 2400 + (_choreoStep * 439) % 1801;
    _patrolTimer = Timer(Duration(milliseconds: delayMs), _runNextChoreo);
  }

  double get _hitWidth => math.max(widget.buddySize + 6.0, 44.0);

  double get _hitHalfPad => (_hitWidth - widget.buddySize) * 0.5;

  double _safeMinX(double maxX) =>
      math.min(maxX, _glyphRect.right + _hitHalfPad + 1.0);

  double _safeMaxY() =>
      math.max(_restPos.dy, _stageBaseHeight - widget.buddySize);

  Offset _clampSafePosition(Offset raw) {
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    final safeMinX = _safeMinX(maxX);
    final minX = _hasRoofTrack ? 0.0 : safeMinX;
    final x = raw.dx.clamp(minX, maxX).toDouble();
    final inGlyphZone = _hasRoofTrack && x < safeMinX - 0.01;
    final maxY = inGlyphZone ? _roofY : _safeMaxY();
    final y = raw.dy.clamp(0.0, math.max(0.0, maxY)).toDouble();
    return Offset(x, y);
  }

  List<Offset> _roofLandingSpots(double maxX) {
    if (!_hasRoofTrack || _roofCharCentersX.isEmpty) return const [];
    return [
      for (final cx in _roofCharCentersX)
        Offset(
          (cx - widget.buddySize * 0.5).clamp(0.0, maxX).toDouble(),
          _roofY,
        ),
    ];
  }

  void _runNextChoreo() {
    _patrolTimer = null;
    if (!_canRunChoreography || !_hasLayout) return;

    final step = _choreoStep++;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    final safeMinX = _safeMinX(maxX);
    final restX = _restPos.dx.clamp(safeMinX, maxX).toDouble();
    final farRightX = maxX;
    final midRightX = ((restX + farRightX) * 0.5).clamp(safeMinX, maxX);
    final roofSpots = _roofLandingSpots(maxX);
    final hasRoofSpots = roofSpots.isNotEmpty;
    final startPos = _clampSafePosition(_currentPos);

    Offset spotAt(int idx) => roofSpots[idx.clamp(0, roofSpots.length - 1)];

    final cycle = step % 9;
    switch (cycle) {
      case 0:
        if (hasRoofSpots) {
          _activeChoreo = _StageChoreoKind.climbRoof;
          _choreoStart = startPos;
          _choreoEnd = spotAt(roofSpots.length - 1);
          _choreoArcHeight = 5.0;
          _activeFacing = -1;
          _choreoController.duration = const Duration(milliseconds: 780);
        } else {
          _activeChoreo = _StageChoreoKind.hopBounce;
          _choreoStart = startPos;
          _choreoEnd = Offset(midRightX, _restPos.dy);
          _choreoArcHeight = 5.0;
          _activeFacing = 1;
          _choreoController.duration = const Duration(milliseconds: 640);
        }
      case 1:
        _activeChoreo = _StageChoreoKind.patrolRoof;
        _choreoStart = startPos;
        _choreoEnd = hasRoofSpots
            ? spotAt(step.isEven ? 1 : 0)
            : Offset(farRightX, _restPos.dy);
        _choreoArcHeight = 5.0;
        _activeFacing = _choreoEnd.dx >= _choreoStart.dx ? 1 : -1;
        _choreoController.duration = const Duration(milliseconds: 640);
      case 2:
        _activeChoreo = _StageChoreoKind.peekDown;
        _choreoStart = startPos;
        _choreoEnd = hasRoofSpots
            ? spotAt(math.min(2, roofSpots.length - 1))
            : Offset(midRightX, _restPos.dy);
        _choreoArcHeight = 2.0;
        _activeFacing = 1;
        _choreoController.duration = const Duration(milliseconds: 780);
      case 3:
        _activeChoreo = _StageChoreoKind.hopBounce;
        _choreoStart = startPos;
        _choreoEnd = hasRoofSpots
            ? spotAt((step ~/ 2) % roofSpots.length)
            : Offset(restX, _restPos.dy);
        _choreoArcHeight = 4.0;
        _activeFacing = _choreoEnd.dx >= _choreoStart.dx ? 1 : -1;
        _choreoController.duration = const Duration(milliseconds: 660);
      case 4:
        _activeChoreo = _StageChoreoKind.stretchYawn;
        _choreoStart = startPos;
        _choreoEnd = startPos;
        _choreoArcHeight = 0.0;
        _activeFacing = 1;
        _choreoController.duration = const Duration(milliseconds: 820);
      case 5:
        _activeChoreo = _StageChoreoKind.sitDangle;
        _choreoStart = startPos;
        _choreoEnd = hasRoofSpots
            ? spotAt(roofSpots.length - 1)
            : Offset(farRightX, _restPos.dy);
        _choreoArcHeight = 3.0;
        _activeFacing = 1;
        _choreoController.duration = const Duration(milliseconds: 760);
      case 6:
        _activeChoreo = _StageChoreoKind.hangSlipFlip;
        _choreoStart = startPos;
        _choreoEnd = Offset(restX, _restPos.dy);
        _choreoArcHeight = 6.0;
        _activeFacing = 1;
        _choreoController.duration = const Duration(milliseconds: 860);
      case 7:
        _activeChoreo = _StageChoreoKind.napZzz;
        _choreoStart = startPos;
        _choreoEnd = Offset(midRightX, _restPos.dy);
        _choreoArcHeight = 2.0;
        _activeFacing = 1;
        _choreoController.duration = const Duration(milliseconds: 860);
      default:
        _activeChoreo = _StageChoreoKind.returnRest;
        _choreoStart = startPos;
        _choreoEnd = Offset(restX, _restPos.dy);
        _choreoArcHeight = 4.0;
        _activeFacing = _choreoEnd.dx >= _choreoStart.dx ? 1 : -1;
        _choreoController.duration = const Duration(milliseconds: 520);
    }

    _choreoController.forward(from: 0.0);
  }

  void _onChoreoTick() {
    if (!mounted) return;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    final safeMinX = _safeMinX(maxX);
    final nextPos = ClawdTitleStage.sampleStagePath(
      start: _choreoStart,
      end: _choreoEnd,
      t: _choreoController.value,
      arcHeight: _choreoArcHeight,
      roofY: _roofY,
      safeMinX: safeMinX,
      maxX: maxX,
      maxY: _safeMaxY(),
      allowRoof: _hasRoofTrack,
    );
    setState(() {
      _currentPos = nextPos;
    });
    _publishAnchorNow();
  }

  void _onChoreoStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _activeChoreo = null;
      _currentPos = _clampSafePosition(_choreoEnd);
    });
    _publishAnchorNow();
    _schedulePatrolIfNeeded();
  }

  void _onDropTick() {
    if (!mounted) return;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    final safeMinX = _safeMinX(maxX);
    final t = _dropController.value;
    final startOnRoof = _hasRoofTrack && _dragStart.dx < safeMinX - 0.5;
    final endOnRoof = _hasRoofTrack && _dropEnd.dx < safeMinX - 0.5;
    final Offset nextPos;
    if (startOnRoof != endOnRoof) {
      nextPos = ClawdTitleStage.sampleStagePath(
        start: _dragStart,
        end: _dropEnd,
        t: t.clamp(0.0, 1.0),
        arcHeight: 3.0,
        roofY: _roofY,
        safeMinX: safeMinX,
        maxX: maxX,
        maxY: _safeMaxY(),
        allowRoof: _hasRoofTrack,
      );
    } else {
      final raw = Offset(
        _dragStart.dx + (_dropEnd.dx - _dragStart.dx) * t,
        _dragStart.dy + (_dropEnd.dy - _dragStart.dy) * t,
      );
      nextPos = _clampSafePosition(raw);
    }
    setState(() {
      _currentPos = nextPos;
    });
    _publishAnchorNow();
  }

  void _onDropStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _currentPos = _clampSafePosition(_dropEnd);
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
    setState(() {
      _currentPos = _clampSafePosition(_currentPos + details.delta);
    });
    _publishAnchorNow();
  }

  void _handlePanEndOrCancel() {
    if (!_isDragging) return;
    final maxX = math.max(0.0, _stageWidth - widget.buddySize);
    final safeMinX = _safeMinX(maxX);
    final restX = _restPos.dx.clamp(safeMinX, maxX).toDouble();
    final midX = ((restX + maxX) * 0.5).clamp(safeMinX, maxX).toDouble();

    final candidates = <Offset>[
      ..._roofLandingSpots(maxX),
      Offset(safeMinX, _restPos.dy),
      Offset(restX, _restPos.dy),
      Offset(midX, _restPos.dy),
      Offset(maxX, _restPos.dy),
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
      _dropEnd = _clampSafePosition(best);
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
        _StageChoreoKind.climbRoof => JournalPixelBuddyPose.climbEdge,
        _StageChoreoKind.patrolRoof => JournalPixelBuddyPose.hopBounce,
        _StageChoreoKind.peekDown => JournalPixelBuddyPose.peekDown,
        _StageChoreoKind.hopBounce => JournalPixelBuddyPose.hopBounce,
        _StageChoreoKind.stretchYawn => JournalPixelBuddyPose.stretchYawn,
        _StageChoreoKind.sitDangle => JournalPixelBuddyPose.sitDangle,
        _StageChoreoKind.napZzz => JournalPixelBuddyPose.napZzz,
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
      stageBottomY: _stageBaseHeight,
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
      stageBottomY: _stageBaseHeight,
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
    _titleMetricsCache = null;
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

  _TitleMetrics _resolveTitleMetrics({
    required String title,
    required TextStyle titleStyle,
    required TextDirection direction,
    required TextScaler textScaler,
    required double availableTitleW,
  }) {
    final key = _TitleMetricsKey(
      title: title,
      titleStyle: titleStyle,
      direction: direction,
      textScaler: textScaler,
      availableTitleW: availableTitleW,
    );
    final cached = _titleMetricsCache;
    if (cached != null && cached.key == key) {
      return cached;
    }

    final tp = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    ClawdTitleStage.debugTitleMetricsComputeCountForTesting++;
    final rawW = tp.width.ceilToDouble();
    final rawH = tp.height;
    final scale =
        rawW > availableTitleW && rawW > 0 ? availableTitleW / rawW : 1.0;

    final centers = <double>[];
    if (title.isNotEmpty) {
      for (var i = 0; i < title.length; i++) {
        final boxes = tp.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
        );
        if (boxes.isNotEmpty) {
          final box = boxes.first;
          centers.add(((box.left + box.right) * 0.5) * scale);
        }
      }
      if (centers.isEmpty && rawW > 0) {
        final stepW = (rawW * scale) / title.length;
        for (var i = 0; i < title.length; i++) {
          centers.add((i + 0.5) * stepW);
        }
      }
    }
    tp.dispose();

    final metrics = _TitleMetrics(
      key: key,
      rawW: rawW,
      rawH: rawH,
      scale: scale,
      charCenters: List<double>.unmodifiable(centers),
    );
    _titleMetricsCache = metrics;
    return metrics;
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

        final metrics = _resolveTitleMetrics(
          title: widget.title,
          titleStyle: widget.titleStyle,
          direction: direction,
          textScaler: textScaler,
          availableTitleW: availableTitleW,
        );
        final rawW = metrics.rawW;
        final rawH = metrics.rawH;
        final scale = metrics.scale;
        final charCenters = metrics.charCenters;

        final renderedTitleW = rawW * scale;
        final renderedTitleH = rawH * scale;
        final textBandHeight = math.max(
          renderedTitleH,
          widget.showBuddy ? math.max(widget.buddySize, 44.0) : 0.0,
        );
        final titleOffsetInBand = (textBandHeight - renderedTitleH) * 0.5;
        final allowRoof = widget.showBuddy && widget.allowStageMotion;
        final baseRoofHeadroom = ClawdTitleStage.roofHeadroomFor(
          allowStageMotion: allowRoof,
          buddySize: widget.buddySize,
        );
        final effectiveRoofHeadroom = allowRoof
            ? math.max(
                baseRoofHeadroom,
                widget.buddySize - titleOffsetInBand,
              )
            : 0.0;
        final stageHeight = effectiveRoofHeadroom + textBandHeight;
        final titleTop = effectiveRoofHeadroom + titleOffsetInBand;
        final nextGlyphRoofY = titleTop;
        final nextRoofY = allowRoof
            ? (nextGlyphRoofY - widget.buddySize)
                .clamp(0.0, math.max(0.0, titleTop))
                .toDouble()
            : 0.0;
        final nextGlyphRect =
            Rect.fromLTWH(0.0, titleTop, renderedTitleW, renderedTitleH);
        final restLeadGap = math.max(6.0, _hitHalfPad + 1.0);
        final nextRestPos = Offset(
          (renderedTitleW + restLeadGap)
              .clamp(0.0, math.max(0.0, maxW - widget.buddySize))
              .toDouble(),
          effectiveRoofHeadroom + (textBandHeight - widget.buddySize) * 0.5,
        );

        final geometryChanged = !_hasLayout ||
            (_stageWidth - maxW).abs() > 0.5 ||
            (_stageBaseHeight - stageHeight).abs() > 0.5 ||
            (_restPos - nextRestPos).distance > 0.5;
        _stageWidth = maxW;
        _stageBaseHeight = stageHeight;
        _roofHeadroom = effectiveRoofHeadroom;
        _glyphRoofY = nextGlyphRoofY;
        _roofY = nextRoofY;
        _roofCharCentersX = charCenters;
        _glyphRect = nextGlyphRect;
        _restPos = nextRestPos;

        assert(!allowRoof ||
            (_roofY >= 0.0 && _roofY + widget.buddySize <= _glyphRoofY + 1.0));

        if (!_hasLayout ||
            !widget.allowStageMotion ||
            (!_isDragging &&
                !_choreoController.isAnimating &&
                !_dropController.isAnimating &&
                _activeChoreo == null &&
                geometryChanged)) {
          _currentPos = nextRestPos;
          _hasLayout = true;
        } else {
          _currentPos = _clampSafePosition(_currentPos);
        }
        _publishAnchorPostFrame();

        final hitW = math.max(widget.buddySize + 6.0, 44.0);
        final hitH = math.max(widget.buddySize + 6.0, 44.0);
        final hitLeft = (_currentPos.dx + (widget.buddySize - hitW) * 0.5)
            .clamp(0.0, math.max(0.0, maxW - hitW))
            .toDouble();
        final hitTop = (_currentPos.dy + (widget.buddySize - hitH) * 0.5)
            .clamp(0.0, math.max(0.0, _stageBaseHeight - hitH))
            .toDouble();

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
            alignment: Alignment.topLeft,
            children: [
              Positioned(
                left: 0.0,
                top: effectiveRoofHeadroom,
                height: textBandHeight,
                child: Align(
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
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: _currentPos.dx - hitLeft,
                            top: _currentPos.dy - hitTop,
                            width: widget.buddySize,
                            height: widget.buddySize,
                            child: JournalPixelBuddy(
                              key: const ValueKey('home-pixel-buddy'),
                              mood:
                                  widget.moodOverride ?? widget.controller.mood,
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
                        ],
                      ),
                    ),
                  ),
                ),
              if (showInlineBubble)
                Positioned(
                  left: 0.0,
                  right: 0.0,
                  top: math.max(
                          _currentPos.dy + widget.buddySize, _stageBaseHeight) +
                      4.0,
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
    final effectiveSize = size ?? ClawdTitleStage.resolvedBuddySize(context);
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
