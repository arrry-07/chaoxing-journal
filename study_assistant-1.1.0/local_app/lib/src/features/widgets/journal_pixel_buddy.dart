import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../models/assignment_sync_progress.dart';
import '../../models/display_preferences.dart';
import '../../services/clawd_companion_controller.dart';

export '../../services/clawd_companion_controller.dart'
    show JournalPixelBuddyMood, journalBuddyTapWhisper;

const List<String> kJournalSpinnerGlyphs = ['·', '✢', '✳', '✶', '✻', '✽'];

String journalBuddySyncPhrase(AssignmentSyncStage? stage, int tick) {
  switch (stage) {
    case AssignmentSyncStage.courses:
      return '翻阅课表中…';
    case AssignmentSyncStage.workLists:
      return '读取作业中…';
    case AssignmentSyncStage.details:
      return '核对截止中…';
    case AssignmentSyncStage.classroomTasks:
      return '整理课堂中…';
    case AssignmentSyncStage.exams:
      return '核对考试中…';
    case AssignmentSyncStage.saving:
      return '保存手记中…';
    case null:
      return '同步课业中…';
  }
}

enum JournalPixelBuddyPose {
  normal,
  sitDangle,
  napZzz,
  climbEdge,
  hangSlipFlip,
  peekDown,
  hopBounce,
  stretchYawn,
  petSquint,
  grabbedFlail,
  tsunderePuff,
  landing,
  wave,
  doubleStar,
  doubleHeart,
  cheer,
}

enum _BuddyActionKind {
  none,
  idleBreathe,
  idleDoubleBlink,
  idlePeek,
  idleSteps,
  idleWave,
  idleAllClearStar,
  tapWave,
  tapDoubleStar,
  tapDoubleHeart,
  cheer,
  sitDangle,
  napZzz,
  climbEdge,
  hangSlipFlip,
  peekDown,
  hopBounce,
  stretchYawn,
  petSquint,
  grabbedFlail,
  tsunderePuff,
  landing,
}

class JournalPixelBuddy extends StatefulWidget {
  const JournalPixelBuddy({
    super.key,
    this.mood = JournalPixelBuddyMood.idle,
    this.mini = false,
    this.size,
    this.onTap,
    this.syncTickListenable,
    this.displayPrefs,
    this.celebratePulse = 0,
    this.allowTapCombo = true,
    this.poseOverride,
    this.posePulse = 0,
    this.poseProgress,
    this.facingSign = 1,
    this.enableIdleActions = true,
    this.handleGestures = true,
  });

  final JournalPixelBuddyMood mood;
  final bool mini;
  final double? size;
  final VoidCallback? onTap;
  final ValueListenable<int>? syncTickListenable;
  final DisplayPreferences? displayPrefs;
  final int celebratePulse;
  final bool allowTapCombo;
  final JournalPixelBuddyPose? poseOverride;
  final int posePulse;
  final double? poseProgress;
  final int facingSign;
  final bool enableIdleActions;
  final bool handleGestures;

  @override
  State<JournalPixelBuddy> createState() => _JournalPixelBuddyState();
}

class _JournalPixelBuddyState extends State<JournalPixelBuddy>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const SpringDescription _jumpSpring = SpringDescription(
    mass: 1.0,
    stiffness: 500.0,
    damping: 28.0,
  );
  static const Tolerance _jumpTolerance = Tolerance(
    distance: 0.5,
    velocity: 1.0,
  );

  late final AnimationController _jumpController;
  late final AnimationController _actionController;
  Timer? _idleTimer;
  Timer? _syncTimer;

  bool _appResumed = true;
  bool _tickerEnabled = true;
  bool _reducedMotion = false;
  int _idleStep = 0;
  int _peekSign = 1;
  int _internalSyncTick = 0;
  _BuddyActionKind _activeAction = _BuddyActionKind.none;

  bool get _isActive => mounted && _appResumed && _tickerEnabled;

  int get _effectiveSyncTick =>
      widget.syncTickListenable?.value ?? _internalSyncTick;

  bool get _hasPoseOverride =>
      widget.poseOverride != null &&
      widget.poseOverride != JournalPixelBuddyPose.normal;

  @override
  void initState() {
    super.initState();
    _appResumed =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
            AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _jumpController = AnimationController.unbounded(vsync: this, value: 0.0);
    _actionController = AnimationController(
      vsync: this,
      value: 0.0,
      duration: const Duration(milliseconds: 440),
    )..addStatusListener(_onActionStatusChanged);
    _internalSyncTick = widget.syncTickListenable?.value ?? 0;
    widget.syncTickListenable?.addListener(_onExternalSyncTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reducedMotion = JournalMotion.isReducedMotion(context);
    _reconcileTimers();
  }

  @override
  void didUpdateWidget(JournalPixelBuddy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTickListenable != widget.syncTickListenable) {
      oldWidget.syncTickListenable?.removeListener(_onExternalSyncTick);
      widget.syncTickListenable?.addListener(_onExternalSyncTick);
      _internalSyncTick = widget.syncTickListenable?.value ?? 0;
    }
    if (oldWidget.mood != widget.mood) {
      if (widget.mood != JournalPixelBuddyMood.syncing) {
        _internalSyncTick = 0;
      } else {
        _resetActionAndJump();
      }
    }
    final poseChanged = widget.poseOverride != oldWidget.poseOverride ||
        widget.posePulse != oldWidget.posePulse;
    if (poseChanged &&
        _hasPoseOverride &&
        widget.poseProgress == null &&
        _isActive &&
        !_reducedMotion) {
      final mapped = _mapPoseOverride(widget.poseOverride!);
      _startAction(mapped, _durationForAction(mapped));
      if (mapped == _BuddyActionKind.tapWave) {
        _jumpController.animateWith(
          SpringSimulation(
            _jumpSpring,
            _jumpController.value,
            0.0,
            -320.0,
            tolerance: _jumpTolerance,
          ),
        );
      } else if (_jumpController.isAnimating || _jumpController.value != 0.0) {
        _jumpController.stop();
        _jumpController.value = 0.0;
      }
    } else if (oldWidget.poseOverride != widget.poseOverride &&
        !_hasPoseOverride) {
      _resetActionAndJump();
    }
    final celebrated = widget.celebratePulse > oldWidget.celebratePulse;
    _reconcileTimers();
    if (celebrated &&
        !poseChanged &&
        _isActive &&
        !_reducedMotion &&
        widget.mood != JournalPixelBuddyMood.syncing) {
      _triggerCheer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextResumed = state == AppLifecycleState.resumed;
    if (_appResumed == nextResumed) return;
    _appResumed = nextResumed;
    _reconcileTimers();
    if (mounted) {
      setState(() {});
    }
  }

  void _onExternalSyncTick() {
    if (!mounted || !_isActive) return;
    setState(() {
      _internalSyncTick = widget.syncTickListenable?.value ?? _internalSyncTick;
    });
  }

  void _onActionStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    if (_activeAction != _BuddyActionKind.none) {
      setState(() => _activeAction = _BuddyActionKind.none);
    }
    _scheduleIdleTimerIfNeeded();
  }

  void _resetActionAndJump() {
    if (_jumpController.isAnimating || _jumpController.value != 0.0) {
      _jumpController.stop();
      _jumpController.value = 0.0;
    }
    if (_actionController.isAnimating || _actionController.value != 0.0) {
      _actionController.stop();
      _actionController.value = 0.0;
    }
    _activeAction = _BuddyActionKind.none;
  }

  void _reconcileTimers() {
    if (!mounted) return;
    if (!_isActive || _reducedMotion) {
      _cancelAllTimers();
      _resetActionAndJump();
      return;
    }

    if (widget.mood == JournalPixelBuddyMood.syncing) {
      _idleTimer?.cancel();
      _idleTimer = null;
      if (widget.syncTickListenable == null) {
        _syncTimer ??= Timer(
          const Duration(milliseconds: 180),
          _onInternalSyncTick,
        );
      } else {
        _syncTimer?.cancel();
        _syncTimer = null;
      }
    } else {
      _syncTimer?.cancel();
      _syncTimer = null;
      if (widget.enableIdleActions && !_hasPoseOverride) {
        _scheduleIdleTimerIfNeeded();
      } else {
        _idleTimer?.cancel();
        _idleTimer = null;
      }
    }
  }

  void _onInternalSyncTick() {
    _syncTimer = null;
    if (!mounted ||
        !_isActive ||
        _reducedMotion ||
        widget.mood != JournalPixelBuddyMood.syncing ||
        widget.syncTickListenable != null) {
      return;
    }
    setState(() {
      _internalSyncTick = (_internalSyncTick + 1) & 0x3fffffff;
    });
    _syncTimer = Timer(const Duration(milliseconds: 180), _onInternalSyncTick);
  }

  void _scheduleIdleTimerIfNeeded() {
    if (!widget.enableIdleActions ||
        _hasPoseOverride ||
        _idleTimer != null ||
        !_isActive ||
        _reducedMotion ||
        widget.mood == JournalPixelBuddyMood.syncing ||
        _actionController.isAnimating ||
        _activeAction != _BuddyActionKind.none) {
      return;
    }
    final delayMs = 1800 + (_idleStep * 373) % 1401;
    _idleTimer = Timer(Duration(milliseconds: delayMs), _onIdleTick);
  }

  void _onIdleTick() {
    _idleTimer = null;
    if (!mounted ||
        !widget.enableIdleActions ||
        _hasPoseOverride ||
        !_isActive ||
        _reducedMotion ||
        widget.mood == JournalPixelBuddyMood.syncing) {
      return;
    }
    final pool = widget.mood == JournalPixelBuddyMood.allClear
        ? const <_BuddyActionKind>[
            _BuddyActionKind.idleBreathe,
            _BuddyActionKind.idleDoubleBlink,
            _BuddyActionKind.peekDown,
            _BuddyActionKind.hopBounce,
            _BuddyActionKind.idlePeek,
            _BuddyActionKind.idleSteps,
            _BuddyActionKind.stretchYawn,
            _BuddyActionKind.idleWave,
            _BuddyActionKind.idleAllClearStar,
          ]
        : const <_BuddyActionKind>[
            _BuddyActionKind.idleBreathe,
            _BuddyActionKind.idleDoubleBlink,
            _BuddyActionKind.peekDown,
            _BuddyActionKind.hopBounce,
            _BuddyActionKind.idlePeek,
            _BuddyActionKind.idleSteps,
            _BuddyActionKind.stretchYawn,
            _BuddyActionKind.idleWave,
          ];
    final kind = pool[_idleStep % pool.length];
    _idleStep = (_idleStep + 1) & 0x3fffffff;
    if (kind == _BuddyActionKind.idlePeek ||
        kind == _BuddyActionKind.idleSteps) {
      _peekSign = -_peekSign;
    }
    _startAction(kind, _durationForAction(kind));
  }

  _BuddyActionKind _mapPoseOverride(JournalPixelBuddyPose pose) =>
      switch (pose) {
        JournalPixelBuddyPose.normal => _BuddyActionKind.none,
        JournalPixelBuddyPose.sitDangle => _BuddyActionKind.sitDangle,
        JournalPixelBuddyPose.napZzz => _BuddyActionKind.napZzz,
        JournalPixelBuddyPose.climbEdge => _BuddyActionKind.climbEdge,
        JournalPixelBuddyPose.hangSlipFlip => _BuddyActionKind.hangSlipFlip,
        JournalPixelBuddyPose.peekDown => _BuddyActionKind.peekDown,
        JournalPixelBuddyPose.hopBounce => _BuddyActionKind.hopBounce,
        JournalPixelBuddyPose.stretchYawn => _BuddyActionKind.stretchYawn,
        JournalPixelBuddyPose.petSquint => _BuddyActionKind.petSquint,
        JournalPixelBuddyPose.grabbedFlail => _BuddyActionKind.grabbedFlail,
        JournalPixelBuddyPose.tsunderePuff => _BuddyActionKind.tsunderePuff,
        JournalPixelBuddyPose.landing => _BuddyActionKind.landing,
        JournalPixelBuddyPose.wave => _BuddyActionKind.tapWave,
        JournalPixelBuddyPose.doubleStar => _BuddyActionKind.tapDoubleStar,
        JournalPixelBuddyPose.doubleHeart => _BuddyActionKind.tapDoubleHeart,
        JournalPixelBuddyPose.cheer => _BuddyActionKind.cheer,
      };

  Duration _durationForAction(_BuddyActionKind kind) => switch (kind) {
        _BuddyActionKind.none => const Duration(milliseconds: 420),
        _BuddyActionKind.idleBreathe => const Duration(milliseconds: 420),
        _BuddyActionKind.idleDoubleBlink => const Duration(milliseconds: 440),
        _BuddyActionKind.idlePeek => const Duration(milliseconds: 460),
        _BuddyActionKind.idleSteps => const Duration(milliseconds: 440),
        _BuddyActionKind.idleWave => const Duration(milliseconds: 460),
        _BuddyActionKind.idleAllClearStar => const Duration(milliseconds: 460),
        _BuddyActionKind.tapWave => const Duration(milliseconds: 420),
        _BuddyActionKind.tapDoubleStar => const Duration(milliseconds: 460),
        _BuddyActionKind.tapDoubleHeart => const Duration(milliseconds: 480),
        _BuddyActionKind.cheer => const Duration(milliseconds: 440),
        _BuddyActionKind.sitDangle => const Duration(milliseconds: 700),
        _BuddyActionKind.napZzz => const Duration(milliseconds: 850),
        _BuddyActionKind.climbEdge => const Duration(milliseconds: 700),
        _BuddyActionKind.hangSlipFlip => const Duration(milliseconds: 820),
        _BuddyActionKind.peekDown => const Duration(milliseconds: 760),
        _BuddyActionKind.hopBounce => const Duration(milliseconds: 640),
        _BuddyActionKind.stretchYawn => const Duration(milliseconds: 820),
        _BuddyActionKind.petSquint => const Duration(milliseconds: 620),
        _BuddyActionKind.grabbedFlail => const Duration(milliseconds: 560),
        _BuddyActionKind.tsunderePuff => const Duration(milliseconds: 520),
        _BuddyActionKind.landing => const Duration(milliseconds: 280),
      };

  void _startAction(_BuddyActionKind kind, Duration duration) {
    _idleTimer?.cancel();
    _idleTimer = null;
    _activeAction = kind;
    _actionController.duration = duration;
    _actionController.forward(from: 0.0);
  }

  void _triggerCheer() {
    if (_jumpController.isAnimating || _jumpController.value != 0.0) {
      _jumpController.stop();
      _jumpController.value = 0.0;
    }
    _startAction(
        _BuddyActionKind.cheer, _durationForAction(_BuddyActionKind.cheer));
  }

  void _cancelAllTimers() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  void _handleTap() {
    final prefs = widget.displayPrefs;
    if (prefs != null) {
      JournalMotion.tap(prefs);
    }
    if (widget.poseOverride == null &&
        _isActive &&
        !_reducedMotion &&
        widget.mood != JournalPixelBuddyMood.syncing &&
        widget.allowTapCombo) {
      _startAction(
        _BuddyActionKind.tapWave,
        _durationForAction(_BuddyActionKind.tapWave),
      );
      _jumpController.animateWith(
        SpringSimulation(
          _jumpSpring,
          _jumpController.value,
          0.0,
          -320.0,
          tolerance: _jumpTolerance,
        ),
      );
    }
    widget.onTap?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.syncTickListenable?.removeListener(_onExternalSyncTick);
    _cancelAllTimers();
    _actionController.removeStatusListener(_onActionStatusChanged);
    _actionController.dispose();
    _jumpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final effectiveSize = widget.size ?? (widget.mini ? 19.0 : 26.0);
    final minHitWidth = widget.mini
        ? math.max(effectiveSize + 6.0, 26.0)
        : effectiveSize >= 30.0
            ? math.max(effectiveSize + 6.0, 44.0)
            : math.max(effectiveSize + 10.0, 40.0);
    final minHitHeight = widget.mini
        ? math.max(effectiveSize + 6.0, 26.0)
        : effectiveSize >= 30.0
            ? math.max(effectiveSize + 6.0, 44.0)
            : 42.0;

    final effectiveAction = _reducedMotion
        ? _BuddyActionKind.none
        : _hasPoseOverride
            ? _mapPoseOverride(widget.poseOverride!)
            : _activeAction;
    final effectiveProgress = _reducedMotion
        ? 0.0
        : _hasPoseOverride
            ? (widget.poseProgress ??
                (_actionController.isAnimating ? _actionController.value : 0.5))
            : _actionController.value;

    final paintBox = SizedBox.square(
      dimension: effectiveSize,
      child: AnimatedBuilder(
        animation: Listenable.merge([_jumpController, _actionController]),
        builder: (context, _) {
          final currentAction = _reducedMotion
              ? _BuddyActionKind.none
              : _hasPoseOverride
                  ? _mapPoseOverride(widget.poseOverride!)
                  : _activeAction;
          final currentProgress = _reducedMotion
              ? 0.0
              : _hasPoseOverride
                  ? (widget.poseProgress ??
                      (_actionController.isAnimating
                          ? _actionController.value
                          : 0.5))
                  : _actionController.value;
          return CustomPaint(
            painter: _JournalPixelBuddyPainter(
              mood: widget.mood,
              isDark: journal.isDark,
              accent: journal.accent,
              devicePixelRatio: dpr,
              actionKind: currentAction,
              actionProgress: currentAction == _BuddyActionKind.none
                  ? 0.0
                  : currentProgress,
              peekSign: _hasPoseOverride ? widget.facingSign : _peekSign,
              syncTick: _reducedMotion ? 0 : _effectiveSyncTick,
              jumpOffset: _reducedMotion ? 0.0 : _jumpController.value,
            ),
          );
        },
      ),
    );

    if (!widget.handleGestures) {
      return Center(
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: paintBox,
      );
    }

    // Keep reference to effectiveAction/effectiveProgress for clarity when static.
    assert(
        effectiveAction == _BuddyActionKind.none || effectiveProgress >= 0.0);

    return Semantics(
      button: widget.onTap != null,
      label: '像素伙伴，轻点互动',
      onTap: widget.onTap != null ? _handleTap : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minHitWidth,
            minHeight: minHitHeight,
          ),
          child: Center(
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: paintBox,
          ),
        ),
      ),
    );
  }
}

class _JournalPixelBuddyPainter extends CustomPainter {
  const _JournalPixelBuddyPainter({
    required this.mood,
    required this.isDark,
    required this.accent,
    required this.devicePixelRatio,
    required this.actionKind,
    required this.actionProgress,
    required this.peekSign,
    required this.syncTick,
    required this.jumpOffset,
  });

  static const int _gridCols = 14;
  static const int _gridRows = 12;

  static const Color _lightBody = Color(0xFFD97757);
  static const Color _lightShadow = Color(0xFFB85D40);
  static const Color _lightHighlight = Color(0xFFEDA083);
  static const Color _lightEye = Color(0xFF1F2328);
  static const Color _lightHeart = Color(0xFFE25B4B);

  static const Color _darkBody = Color(0xFFE5896B);
  static const Color _darkShadow = Color(0xFFC46B4E);
  static const Color _darkHighlight = Color(0xFFF3AD94);
  static const Color _darkEye = Color(0xFF191816);
  static const Color _darkHeart = Color(0xFFF27B6D);

  final JournalPixelBuddyMood mood;
  final bool isDark;
  final Color accent;
  final double devicePixelRatio;
  final _BuddyActionKind actionKind;
  final double actionProgress;
  final int peekSign;
  final int syncTick;
  final double jumpOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final rawCell = math.min(size.width / _gridCols, size.height / _gridRows);
    if (rawCell <= 0) return;
    final dpr = devicePixelRatio > 0 ? devicePixelRatio : 1.0;
    final physicalCell = (rawCell * dpr).floorToDouble();
    final cell = physicalCell >= 1.0 ? physicalCell / dpr : rawCell;

    double snap(double value) => (value * dpr).roundToDouble() / dpr;

    final originX = snap((size.width - cell * _gridCols) * 0.5);
    final originY = snap((size.height - cell * _gridRows) * 0.5 + jumpOffset);

    final bodyColor = isDark ? _darkBody : _lightBody;
    final shadowColor = isDark ? _darkShadow : _lightShadow;
    final highlightColor = isDark ? _darkHighlight : _lightHighlight;
    final eyeColor = isDark ? _darkEye : _lightEye;
    final heartColor = isDark ? _darkHeart : _lightHeart;

    final paint = Paint()..isAntiAlias = false;

    final t = actionProgress.clamp(0.0, 1.0);
    var dx = 0;
    var dy = 0;
    var eyeDx = 0;
    var eyeDy = 0;
    var leftArmRow = 5;
    var rightArmRow = 5;
    var leg1Row = 9; // col 3
    var leg2Row = 9; // col 5
    var leg3Row = 9; // col 8
    var leg4Row = 9; // col 10
    var bothEyesSquint = false;
    var rightEyeSquint = false;
    var wideEyes = false;
    var blushCheeks = false;
    var scaleX = 1.0;
    var scaleY = 1.0;
    var hopPx = 0.0;
    var leanSkew = 0.0;
    var rotationRad = 0.0;
    var sitDanglePhase = -1;

    if (mood == JournalPixelBuddyMood.syncing) {
      leanSkew = -0.07;
      switch (syncTick % 4) {
        case 0:
          // Diagonal pair (3, 8) lifted; opposite arm swing.
          leg1Row = 8;
          leg3Row = 8;
          leftArmRow = 4;
          rightArmRow = 6;
        case 1:
          dy = -1;
        case 2:
          // Diagonal pair (5, 10) lifted; opposite arm swing.
          leg2Row = 8;
          leg4Row = 8;
          leftArmRow = 6;
          rightArmRow = 4;
        default:
          break;
      }
    } else if (actionKind != _BuddyActionKind.none && t > 0.0 && t < 1.0) {
      switch (actionKind) {
        case _BuddyActionKind.idleBreathe:
          final s = math.sin(math.pi * t);
          scaleX = 1.0 + 0.055 * s;
          scaleY = 1.0 - 0.065 * s;
        case _BuddyActionKind.idleDoubleBlink:
          bothEyesSquint = (t >= 0.0 && t <= 0.22) || (t >= 0.44 && t <= 0.68);
        case _BuddyActionKind.idlePeek:
          if (t >= 0.18 && t <= 0.78) {
            eyeDx = peekSign;
          }
        case _BuddyActionKind.idleSteps:
          if (t < 0.50) {
            dx = peekSign;
            leg1Row = 8;
            leg3Row = 8;
          } else {
            dx = 0;
            leg2Row = 8;
            leg4Row = 8;
          }
        case _BuddyActionKind.idleWave:
          if (t >= 0.12 && t <= 0.88) {
            rightArmRow = (t >= 0.40 && t <= 0.62) ? 4 : 3;
          }
          if (t >= 0.18 && t <= 0.82) {
            rightEyeSquint = true;
          }
        case _BuddyActionKind.idleAllClearStar:
          hopPx = -0.45 * cell * math.sin(math.pi * t);
        case _BuddyActionKind.tapWave:
          if (t >= 0.10 && t <= 0.88) {
            rightArmRow = (t >= 0.40 && t <= 0.62) ? 4 : 3;
          }
          if (t >= 0.16 && t <= 0.82) {
            rightEyeSquint = true;
          }
        case _BuddyActionKind.tapDoubleStar:
        case _BuddyActionKind.tapDoubleHeart:
          if (t < 0.48) {
            hopPx = -1.75 * cell * math.sin(math.pi * (t / 0.48));
          } else {
            hopPx = -1.25 * cell * math.sin(math.pi * ((t - 0.48) / 0.52));
          }
          if (t >= 0.08 && t <= 0.90) {
            leftArmRow = 3;
            rightArmRow = 3;
          }
        case _BuddyActionKind.cheer:
          hopPx = -1.35 * cell * math.sin(math.pi * t);
          if (t >= 0.12 && t <= 0.88) {
            leftArmRow = 3;
            rightArmRow = 3;
          }
        case _BuddyActionKind.sitDangle:
          dy = 1;
          leftArmRow = 6;
          rightArmRow = 6;
          sitDanglePhase = (t * 4).floor() % 2;
        case _BuddyActionKind.napZzz:
          dy = 1;
          scaleX = 1.07;
          scaleY = 0.86;
          bothEyesSquint = true;
          leg1Row = 8;
          leg2Row = 8;
          leg3Row = 8;
          leg4Row = 8;
          leftArmRow = 6;
          rightArmRow = 6;
        case _BuddyActionKind.climbEdge:
          final step = (t * 4).floor() % 2;
          eyeDx = peekSign >= 0 ? 1 : -1;
          if (peekSign >= 0) {
            rightArmRow = step == 0 ? 3 : 4;
            leftArmRow = 5;
          } else {
            leftArmRow = step == 0 ? 3 : 4;
            rightArmRow = 5;
          }
          if (step == 0) {
            leg1Row = 8;
            leg3Row = 8;
          } else {
            leg2Row = 8;
            leg4Row = 8;
          }
          dy = step == 0 ? 0 : -1;
        case _BuddyActionKind.hangSlipFlip:
          if (t < 0.26) {
            final ht = t / 0.26;
            leftArmRow = 2;
            rightArmRow = 2;
            eyeDx = peekSign >= 0 ? 1 : -1;
            hopPx = 0.45 * cell * ht;
          } else if (t < 0.78) {
            final ft = (t - 0.26) / 0.52;
            rotationRad = 2 * math.pi * ft;
            hopPx = -0.95 * cell * math.sin(math.pi * ft);
          } else {
            final rt = (t - 0.78) / 0.22;
            final s = math.sin(math.pi * rt);
            scaleX = 1.0 + 0.10 * s;
            scaleY = 1.0 - 0.12 * s;
          }
        case _BuddyActionKind.peekDown:
          dy = 1;
          eyeDy = 1;
          leftArmRow = 7;
          rightArmRow = 7;
          scaleX = 1.04;
          scaleY = 0.94;
          if (t >= 0.18 && t < 0.48) {
            eyeDx = -1;
          } else if (t >= 0.52 && t <= 0.84) {
            eyeDx = 1;
          }
        case _BuddyActionKind.hopBounce:
          if (t < 0.50) {
            final ht = t / 0.50;
            hopPx = -1.65 * cell * math.sin(math.pi * ht);
            final s = math.sin(math.pi * ht);
            scaleX = 1.0 - 0.05 * s;
            scaleY = 1.0 + 0.07 * s;
          } else {
            final ht = (t - 0.50) / 0.50;
            hopPx = -1.10 * cell * math.sin(math.pi * ht);
            final s = math.sin(math.pi * ht);
            scaleX = 1.0 + 0.05 * (1.0 - s);
            scaleY = 1.0 - 0.05 * (1.0 - s);
          }
          if (t >= 0.08 && t <= 0.90) {
            leftArmRow = 3;
            rightArmRow = 3;
          }
        case _BuddyActionKind.stretchYawn:
          if (t < 0.58) {
            final st = math.sin(math.pi * (t / 0.58) * 0.5);
            scaleX = 1.0 - 0.08 * st;
            scaleY = 1.0 + 0.12 * st;
            leftArmRow = 2;
            rightArmRow = 2;
            bothEyesSquint = t >= 0.18;
          } else {
            final rt = (t - 0.58) / 0.42;
            final s = math.sin(math.pi * rt);
            scaleX = 1.0 + 0.05 * s;
            scaleY = 1.0 - 0.05 * s;
            leftArmRow = 4;
            rightArmRow = 4;
            bothEyesSquint = rt < 0.35;
          }
        case _BuddyActionKind.petSquint:
          final s = math.sin(math.pi * t);
          scaleX = 1.0 + 0.06 * s;
          scaleY = 1.0 - 0.08 * s;
          bothEyesSquint = true;
          blushCheeks = true;
        case _BuddyActionKind.grabbedFlail:
          final flail = (t * 8).floor() % 2;
          wideEyes = true;
          leanSkew = 0.07 * math.sin(t * 4 * math.pi);
          hopPx = -0.4 * cell;
          leftArmRow = flail == 0 ? 3 : 4;
          rightArmRow = flail == 0 ? 4 : 3;
          if (flail == 0) {
            leg1Row = 8;
            leg4Row = 8;
          } else {
            leg2Row = 8;
            leg3Row = 8;
          }
        case _BuddyActionKind.tsunderePuff:
          final s = math.sin(math.pi * t);
          hopPx = -0.55 * cell * s;
          scaleX = 1.0 + 0.05 * s;
          scaleY = 1.0 + 0.04 * s;
          leftArmRow = 4;
          rightArmRow = 4;
          blushCheeks = true;
          eyeDx = -1;
        case _BuddyActionKind.landing:
          final s = math.sin(math.pi * t);
          scaleX = 1.0 + 0.12 * s;
          scaleY = 1.0 - 0.12 * s;
        case _BuddyActionKind.none:
          break;
      }
    }

    final effectiveOriginY = snap(originY + hopPx);

    double px(int col) => snap(originX + col * cell);
    double py(int row) => snap(effectiveOriginY + row * cell);

    void drawCell(int col, int row, Color color) {
      paint.color = color;
      canvas.drawRect(
        Rect.fromLTRB(px(col), py(row), px(col + 1), py(row + 1)),
        paint,
      );
    }

    void drawSquintEye(int col, int row) {
      paint.color = eyeColor;
      final lineTop = snap(py(row) + math.max(1.0 / dpr, cell * 0.25));
      final lineBottom = math.min(
        py(row + 1),
        snap(lineTop + math.max(1.0 / dpr, cell * 0.42)),
      );
      canvas.drawRect(
        Rect.fromLTRB(px(col), lineTop, px(col + 1), lineBottom),
        paint,
      );
    }

    final hasCanvasTransform =
        leanSkew != 0.0 || scaleX != 1.0 || scaleY != 1.0 || rotationRad != 0.0;
    if (hasCanvasTransform) {
      canvas.save();
      final pivotX = originX + _gridCols * cell * 0.5;
      final pivotY = rotationRad != 0.0
          ? effectiveOriginY + 6 * cell
          : effectiveOriginY + 11 * cell;
      canvas.translate(pivotX, pivotY);
      if (rotationRad != 0.0) {
        canvas.rotate(rotationRad);
      }
      if (leanSkew != 0.0) {
        canvas.skew(leanSkew, 0.0);
      }
      if (scaleX != 1.0 || scaleY != 1.0) {
        canvas.scale(scaleX, scaleY);
      }
      canvas.translate(-pivotX, -pivotY);
    }

    // Clawd 10x6 boxy torso (cols 2..11, rows 3..8) with subtle top highlight & bottom edge.
    final topRow = 3 + dy;
    drawCell(2 + dx, topRow, bodyColor);
    for (var col = 3; col <= 10; col++) {
      drawCell(col + dx, topRow, highlightColor);
    }
    drawCell(11 + dx, topRow, bodyColor);

    for (var row = 4 + dy; row <= 7 + dy; row++) {
      for (var col = 2; col <= 11; col++) {
        drawCell(col + dx, row, bodyColor);
      }
    }
    for (var col = 2; col <= 11; col++) {
      drawCell(col + dx, 8 + dy, shadowColor);
    }

    // Side horizontal square ears / arms (col 1 & col 12, resting at rows 5..6).
    drawCell(1 + dx, leftArmRow + dy, highlightColor);
    drawCell(1 + dx, leftArmRow + 1 + dy, bodyColor);

    drawCell(12 + dx, rightArmRow + dy, bodyColor);
    drawCell(12 + dx, rightArmRow + 1 + dy, shadowColor);

    // 4 symmetrical discrete short legs: left pair (3, 5) + center gap (6, 7) + right pair (8, 10).
    void drawLeg(int col, int legRow, {bool dangleExtend = false}) {
      if (dangleExtend) {
        drawCell(col + dx, legRow + dy, bodyColor);
        drawCell(col + dx, legRow + 1 + dy, shadowColor);
      } else if (legRow < 9) {
        // Lifted 1 row: leave Row 10 clear and tint Row 9 shadow.
        drawCell(col + dx, legRow + 1 + dy, shadowColor);
      } else {
        drawCell(col + dx, legRow + dy, bodyColor);
        drawCell(col + dx, legRow + 1 + dy, shadowColor);
      }
    }

    if (sitDanglePhase >= 0) {
      drawLeg(3, 9, dangleExtend: sitDanglePhase == 0);
      drawLeg(5, 8, dangleExtend: sitDanglePhase == 1);
      drawLeg(8, 9, dangleExtend: sitDanglePhase == 0);
      drawLeg(10, 8, dangleExtend: sitDanglePhase == 1);
    } else {
      drawLeg(3, leg1Row);
      drawLeg(5, leg2Row);
      drawLeg(8, leg3Row);
      drawLeg(10, leg4Row);
    }

    // Symmetrical 1x2 eyes at cols 4 and 9, rows 4..5 (shifted by eyeDx/eyeDy).
    final leftEyeCol = 4 + dx + eyeDx;
    final rightEyeCol = 9 + dx + eyeDx;
    final eyeTopRow = 4 + dy + eyeDy;
    final eyeBottomRow = 5 + dy + eyeDy;

    if (bothEyesSquint) {
      drawSquintEye(leftEyeCol, eyeBottomRow);
      drawSquintEye(rightEyeCol, eyeBottomRow);
    } else if (rightEyeSquint) {
      drawCell(leftEyeCol, eyeTopRow, eyeColor);
      drawCell(leftEyeCol, eyeBottomRow, eyeColor);
      drawSquintEye(rightEyeCol, eyeBottomRow);
    } else if (wideEyes) {
      drawCell(leftEyeCol, eyeTopRow, eyeColor);
      drawCell(leftEyeCol, eyeBottomRow, eyeColor);
      drawCell(rightEyeCol, eyeTopRow, eyeColor);
      drawCell(rightEyeCol, eyeBottomRow, eyeColor);
      drawCell(leftEyeCol + 1, eyeTopRow, highlightColor);
      drawCell(rightEyeCol - 1, eyeTopRow, highlightColor);
    } else {
      drawCell(leftEyeCol, eyeTopRow, eyeColor);
      drawCell(leftEyeCol, eyeBottomRow, eyeColor);
      drawCell(rightEyeCol, eyeTopRow, eyeColor);
      drawCell(rightEyeCol, eyeBottomRow, eyeColor);
    }

    if (blushCheeks) {
      final blush = heartColor.withValues(alpha: 0.65);
      drawCell(3 + dx, 6 + dy, blush);
      drawCell(10 + dx, 6 + dy, blush);
    }

    if (hasCanvasTransform) {
      canvas.restore();
    }

    // Floating sky accents in Row 0..1 (Row 2 completely empty above Row 3 head).
    if (mood == JournalPixelBuddyMood.dueToday) {
      drawCell(12, 0, accent);
      drawCell(12, 1, accent);
    } else if (mood == JournalPixelBuddyMood.allClear) {
      drawCell(12, 0, highlightColor);
      drawCell(11, 1, accent);
      drawCell(12, 1, highlightColor);
    }

    // Rising & fading floating particles for combos, cheer, and allClear idle sparkle.
    if (mood != JournalPixelBuddyMood.syncing && t > 0.0 && t < 1.0) {
      final alpha = math.sin(math.pi * t).clamp(0.0, 1.0);
      final maxParticleBottom =
          py(3 + dy) - math.max(1.0 / dpr, snap(cell * 0.25));
      if (actionKind == _BuddyActionKind.tapDoubleStar ||
          actionKind == _BuddyActionKind.cheer ||
          actionKind == _BuddyActionKind.idleAllClearStar) {
        final sCell = math.max(1.0 / dpr, snap(cell * 0.72));
        final starBottomY = math.min(
          maxParticleBottom,
          snap(effectiveOriginY + (2.75 - 1.4 * t) * cell),
        );
        final floatY = snap(starBottomY - 2 * sCell);
        final floatX = snap(originX + 10.5 * cell);
        paint.color = accent.withValues(alpha: alpha);
        canvas.drawRect(
          Rect.fromLTWH(floatX, floatY, sCell, sCell),
          paint,
        );
        paint.color = highlightColor.withValues(alpha: alpha);
        canvas.drawRect(
          Rect.fromLTWH(
              snap(floatX + sCell), snap(floatY - sCell), sCell, sCell),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(
              snap(floatX - sCell), snap(floatY + sCell), sCell, sCell),
          paint,
        );
      } else if (actionKind == _BuddyActionKind.tapDoubleHeart ||
          actionKind == _BuddyActionKind.petSquint) {
        final sub = math.max(1.0 / dpr, snap(cell * 0.55));
        final heartBottomY = math.min(
          maxParticleBottom,
          snap(effectiveOriginY + (2.75 - 1.4 * t) * cell),
        );
        final baseX = snap(originX + 7.0 * cell - sub * 2.5);
        final baseY = snap(heartBottomY - 4 * sub);
        paint.color = heartColor.withValues(alpha: alpha);
        const heartOffsets = <(int, int)>[
          (1, 0),
          (3, 0),
          (0, 1),
          (1, 1),
          (2, 1),
          (3, 1),
          (4, 1),
          (1, 2),
          (2, 2),
          (3, 2),
          (2, 3),
        ];
        for (final (hx, hy) in heartOffsets) {
          canvas.drawRect(
            Rect.fromLTWH(
              snap(baseX + hx * sub),
              snap(baseY + hy * sub),
              sub,
              sub,
            ),
            paint,
          );
        }
      } else if (actionKind == _BuddyActionKind.napZzz) {
        final sub = math.max(1.0 / dpr, snap(cell * 0.55));
        final zBottomY = math.min(
          maxParticleBottom,
          snap(effectiveOriginY + (3.2 - 1.5 * t) * cell),
        );
        final baseX = snap(originX + 10.0 * cell);
        final baseY = snap(zBottomY - 3 * sub);
        paint.color = accent.withValues(alpha: alpha);
        const zOffsets = <(int, int)>[
          (0, 0),
          (1, 0),
          (2, 0),
          (1, 1),
          (0, 2),
          (1, 2),
          (2, 2),
        ];
        for (final (zx, zy) in zOffsets) {
          canvas.drawRect(
            Rect.fromLTWH(
              snap(baseX + zx * sub),
              snap(baseY + zy * sub),
              sub,
              sub,
            ),
            paint,
          );
        }
      } else if (actionKind == _BuddyActionKind.tsunderePuff) {
        final sub = math.max(1.0 / dpr, snap(cell * 0.6));
        final puffBottomY = math.min(
          maxParticleBottom,
          snap(effectiveOriginY + (2.6 - 0.8 * t) * cell),
        );
        final baseX = snap(originX + 10.0 * cell);
        final baseY = snap(puffBottomY - 3 * sub);
        paint.color = heartColor.withValues(alpha: alpha);
        const puffOffsets = <(int, int)>[
          (0, 0),
          (2, 0),
          (1, 1),
          (0, 2),
          (2, 2),
        ];
        for (final (pxOffset, pyOffset) in puffOffsets) {
          canvas.drawRect(
            Rect.fromLTWH(
              snap(baseX + pxOffset * sub),
              snap(baseY + pyOffset * sub),
              sub,
              sub,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_JournalPixelBuddyPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.isDark != isDark ||
      oldDelegate.accent != accent ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      oldDelegate.actionKind != actionKind ||
      oldDelegate.actionProgress != actionProgress ||
      oldDelegate.peekSign != peekSign ||
      oldDelegate.syncTick != syncTick ||
      oldDelegate.jumpOffset != jumpOffset;
}
