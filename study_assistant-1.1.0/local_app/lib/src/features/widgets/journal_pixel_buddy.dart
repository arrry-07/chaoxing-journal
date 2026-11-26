import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../models/assignment_sync_progress.dart';
import '../../models/display_preferences.dart';

enum JournalPixelBuddyMood {
  idle,
  syncing,
  dueToday,
  allClear,
}

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

String journalBuddyTapWhisper({
  required int dueToday,
  required int dueIn3Days,
  required int completedToday,
  required int tapCount,
}) {
  final options = <String>[
    if (dueToday > 0) ...[
      dueToday > 99 ? '今日待办较多，先挑急的' : '今日待办$dueToday项，稳步推进',
      dueToday > 99 ? '先清今日要紧事项吧' : '先清今日这$dueToday项吧',
      if (dueIn3Days > dueToday && dueIn3Days <= 99) '三日内共$dueIn3Days项，提前看',
      '我在盯着截止时间呢',
    ] else if (completedToday > 0) ...[
      '今日已清空，喝口水歇会儿',
      completedToday > 99 ? '今日打卡满满，真棒' : '今日已打卡$completedToday项，真棒',
      if (dueIn3Days > 0)
        dueIn3Days > 99 ? '三日内有多项，提前瞄一眼' : '三日内还有$dueIn3Days项，瞄一眼',
      '今天轻松啦，保持节奏',
    ] else if (dueIn3Days > 0) ...[
      dueIn3Days > 99 ? '三日内有多项，提前瞄一眼' : '三日内还有$dueIn3Days项，瞄一眼',
      '今日暂无急单，先备后续',
      '我在盯着截止时间呢',
    ] else ...[
      '眼前清清爽爽，真好',
      '暂无急单，喝口水歇会儿',
      '有新课业我会盯紧的',
    ],
  ];
  final index = (tapCount < 0 ? -tapCount : tapCount) % options.length;
  return options[index];
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
  });

  final JournalPixelBuddyMood mood;
  final bool mini;
  final double? size;
  final VoidCallback? onTap;
  final ValueListenable<int>? syncTickListenable;
  final DisplayPreferences? displayPrefs;

  @override
  State<JournalPixelBuddy> createState() => _JournalPixelBuddyState();
}

class _JournalPixelBuddyState extends State<JournalPixelBuddy>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  Timer? _idleTimer;
  Timer? _blinkTimer;
  Timer? _syncTimer;
  Timer? _waveTimer;

  bool _appResumed = true;
  bool _tickerEnabled = true;
  bool _reducedMotion = false;
  int _idleStep = 0;
  int _idlePose = 0;
  bool _isBlinking = false;
  bool _isWaving = false;
  int _internalSyncTick = 0;

  bool get _isActive => mounted && _appResumed && _tickerEnabled;

  int get _effectiveSyncTick =>
      widget.syncTickListenable?.value ?? _internalSyncTick;

  @override
  void initState() {
    super.initState();
    _appResumed =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
            AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _jumpController = AnimationController.unbounded(vsync: this, value: 0.0);
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
    if (oldWidget.mood != widget.mood &&
        widget.mood != JournalPixelBuddyMood.syncing) {
      _internalSyncTick = 0;
    }
    _reconcileTimers();
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

  void _reconcileTimers() {
    if (!mounted) return;
    if (!_isActive || _reducedMotion) {
      _cancelAllTimers();
      if (_jumpController.isAnimating || _jumpController.value != 0.0) {
        _jumpController.stop();
        _jumpController.value = 0.0;
      }
      _isBlinking = false;
      _isWaving = false;
      return;
    }

    if (widget.mood == JournalPixelBuddyMood.syncing) {
      _idleTimer?.cancel();
      _idleTimer = null;
      _blinkTimer?.cancel();
      _blinkTimer = null;
      _isBlinking = false;
      if (widget.syncTickListenable == null) {
        _syncTimer ??= Timer.periodic(
          const Duration(milliseconds: 180),
          (_) {
            if (!mounted || !_isActive || _reducedMotion) return;
            setState(() {
              _internalSyncTick = (_internalSyncTick + 1) & 0x3fffffff;
            });
          },
        );
      } else {
        _syncTimer?.cancel();
        _syncTimer = null;
      }
    } else {
      _syncTimer?.cancel();
      _syncTimer = null;
      _scheduleIdleTimerIfNeeded();
    }
  }

  void _scheduleIdleTimerIfNeeded() {
    if (_idleTimer != null ||
        !_isActive ||
        _reducedMotion ||
        widget.mood == JournalPixelBuddyMood.syncing) {
      return;
    }
    final delayMs = 2200 + (_idleStep * 317) % 1201;
    _idleTimer = Timer(Duration(milliseconds: delayMs), _onIdleTick);
  }

  void _onIdleTick() {
    _idleTimer = null;
    if (!mounted ||
        !_isActive ||
        _reducedMotion ||
        widget.mood == JournalPixelBuddyMood.syncing) {
      return;
    }
    _idleStep++;
    final shouldBlink = _idleStep % 3 == 1;
    setState(() {
      _idlePose = _idleStep % 4;
      if (shouldBlink) {
        _isBlinking = true;
      }
    });
    if (shouldBlink) {
      _blinkTimer?.cancel();
      _blinkTimer = Timer(const Duration(milliseconds: 160), () {
        _blinkTimer = null;
        if (!mounted || !_isActive || _reducedMotion) return;
        setState(() => _isBlinking = false);
      });
    }
    _scheduleIdleTimerIfNeeded();
  }

  void _cancelAllTimers() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _waveTimer?.cancel();
    _waveTimer = null;
  }

  void _handleTap() {
    final prefs = widget.displayPrefs;
    if (prefs != null) {
      JournalMotion.tap(prefs);
    }
    if (_isActive && !_reducedMotion) {
      _waveTimer?.cancel();
      setState(() => _isWaving = true);
      _waveTimer = Timer(const Duration(milliseconds: 450), () {
        _waveTimer = null;
        if (!mounted || !_isActive || _reducedMotion) return;
        setState(() => _isWaving = false);
      });
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
    _jumpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final effectiveSize = widget.size ?? (widget.mini ? 19.0 : 26.0);
    final minHitWidth = widget.mini
        ? math.max(effectiveSize + 6.0, 26.0)
        : math.max(effectiveSize + 10.0, 40.0);
    final minHitHeight =
        widget.mini ? math.max(effectiveSize + 6.0, 26.0) : 42.0;

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
            child: SizedBox.square(
              dimension: effectiveSize,
              child: AnimatedBuilder(
                animation: _jumpController,
                builder: (context, _) => CustomPaint(
                  painter: _JournalPixelBuddyPainter(
                    mood: widget.mood,
                    isDark: journal.isDark,
                    accent: journal.accent,
                    idlePose: _reducedMotion ? 0 : _idlePose,
                    isBlinking: !_reducedMotion && _isBlinking,
                    syncTick: _reducedMotion ? 0 : _effectiveSyncTick,
                    isWaving: !_reducedMotion && _isWaving,
                    jumpOffset: _reducedMotion ? 0.0 : _jumpController.value,
                  ),
                ),
              ),
            ),
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
    required this.idlePose,
    required this.isBlinking,
    required this.syncTick,
    required this.isWaving,
    required this.jumpOffset,
  });

  static const int _gridCols = 14;
  static const int _gridRows = 12;

  static const Color _lightBody = Color(0xFFD97757);
  static const Color _lightShadow = Color(0xFFB85D40);
  static const Color _lightHighlight = Color(0xFFEDA083);
  static const Color _lightEye = Color(0xFF1F2328);

  static const Color _darkBody = Color(0xFFE5896B);
  static const Color _darkShadow = Color(0xFFC46B4E);
  static const Color _darkHighlight = Color(0xFFF3AD94);
  static const Color _darkEye = Color(0xFF191816);

  final JournalPixelBuddyMood mood;
  final bool isDark;
  final Color accent;
  final int idlePose;
  final bool isBlinking;
  final int syncTick;
  final bool isWaving;
  final double jumpOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = math.min(size.width / _gridCols, size.height / _gridRows);
    if (cell <= 0) return;

    final originX = (size.width - cell * _gridCols) * 0.5;
    final originY = (size.height - cell * _gridRows) * 0.5 + jumpOffset;

    final bodyColor = isDark ? _darkBody : _lightBody;
    final shadowColor = isDark ? _darkShadow : _lightShadow;
    final highlightColor = isDark ? _darkHighlight : _lightHighlight;
    final eyeColor = isDark ? _darkEye : _lightEye;

    final paint = Paint()..isAntiAlias = false;

    double px(int col) => (originX + col * cell).roundToDouble();
    double py(int row) => (originY + row * cell).roundToDouble();

    void drawCell(int col, int row, Color color) {
      paint.color = color;
      canvas.drawRect(
        Rect.fromLTRB(px(col), py(row), px(col + 1), py(row + 1)),
        paint,
      );
    }

    void drawSquintEye(int col, int row) {
      paint.color = eyeColor;
      final top = py(row) + math.max(1.0, cell * 0.55);
      final bottom = math.min(py(row + 1), top + math.max(1.0, cell * 0.38));
      canvas.drawRect(Rect.fromLTRB(px(col), top, px(col + 1), bottom), paint);
    }

    var dx = 0;
    var dy = 0;
    var torsoBreath = 0;
    var leftArmRow = 5;
    var rightArmRow = 5;
    var leftLegRow = 9;
    var rightLegRow = 9;

    if (mood == JournalPixelBuddyMood.syncing) {
      switch (syncTick % 4) {
        case 0:
          leftArmRow = 4;
          rightArmRow = 6;
          leftLegRow = 9;
          rightLegRow = 8;
        case 1:
          dy = -1;
          leftArmRow = 5;
          rightArmRow = 5;
        case 2:
          leftArmRow = 6;
          rightArmRow = 4;
          leftLegRow = 8;
          rightLegRow = 9;
        default:
          leftArmRow = 5;
          rightArmRow = 5;
      }
    } else if (mood == JournalPixelBuddyMood.allClear) {
      if (!isWaving) {
        dy = -1;
      }
      leftArmRow = 3;
      rightArmRow = 3;
    } else {
      switch (idlePose % 4) {
        case 1:
          torsoBreath = 1;
        case 2:
          dx = -1;
        case 3:
          dx = 1;
        default:
          break;
      }
    }

    if (isWaving) {
      rightArmRow = 3;
    }

    // Top rounded cap (cols 3..10, row 2).
    final topRow = 2 + dy + torsoBreath;
    for (var col = 3; col <= 10; col++) {
      drawCell(col + dx, topRow, highlightColor);
    }

    // Upper & middle torso (cols 2..11).
    for (var row = 3 + dy + torsoBreath; row <= 6 + dy; row++) {
      for (var col = 2; col <= 11; col++) {
        final isTopLeftEdge = row == 3 + dy + torsoBreath && col == 2;
        final isRightShade = col == 11 && row >= 5 + dy;
        final color = isTopLeftEdge
            ? highlightColor
            : isRightShade
                ? shadowColor
                : bodyColor;
        drawCell(col + dx, row, color);
      }
    }

    // Lower torso & bottom shadow edge.
    for (var col = 2; col <= 11; col++) {
      drawCell(
        col + dx,
        7 + dy,
        col == 11 ? shadowColor : bodyColor,
      );
    }
    for (var col = 3; col <= 10; col++) {
      drawCell(col + dx, 8 + dy, shadowColor);
    }

    // Left arm (col 1).
    drawCell(1 + dx, leftArmRow + dy, highlightColor);
    drawCell(1 + dx, leftArmRow + 1 + dy, bodyColor);

    // Right arm (col 12).
    if (isWaving) {
      drawCell(12 + dx, rightArmRow - 1 + dy, highlightColor);
      drawCell(12 + dx, rightArmRow + dy, bodyColor);
    } else {
      drawCell(12 + dx, rightArmRow + dy, bodyColor);
      drawCell(12 + dx, rightArmRow + 1 + dy, shadowColor);
    }

    // Legs (pair at 3..4 and 9..10).
    for (final col in const [3, 4]) {
      drawCell(col + dx, leftLegRow + dy, bodyColor);
      drawCell(col + dx, leftLegRow + 1 + dy, shadowColor);
    }
    for (final col in const [9, 10]) {
      drawCell(col + dx, rightLegRow + dy, bodyColor);
      drawCell(col + dx, rightLegRow + 1 + dy, shadowColor);
    }

    // Eyes (cols 4 and 9, row 4 + dy + torsoBreath).
    final eyeRow = 4 + dy + torsoBreath;
    if (isBlinking) {
      drawSquintEye(4 + dx, eyeRow);
      drawSquintEye(9 + dx, eyeRow);
    } else if (isWaving) {
      drawCell(4 + dx, eyeRow, eyeColor);
      drawSquintEye(9 + dx, eyeRow);
    } else {
      drawCell(4 + dx, eyeRow, eyeColor);
      drawCell(9 + dx, eyeRow, eyeColor);
    }

    // Mood-specific accents using Journal.of(context).accent.
    if (mood == JournalPixelBuddyMood.dueToday) {
      drawCell(12, 0, accent);
      drawCell(11, 1, accent);
      drawCell(12, 1, accent);
      drawCell(13, 1, accent);
      drawCell(12, 2, accent);
    } else if (mood == JournalPixelBuddyMood.allClear) {
      drawCell(1, 0, accent);
      drawCell(0, 1, highlightColor);
      drawCell(1, 1, accent);
      drawCell(12, 0, accent);
      drawCell(12, 1, accent);
      drawCell(13, 1, highlightColor);
    }
  }

  @override
  bool shouldRepaint(_JournalPixelBuddyPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.isDark != isDark ||
      oldDelegate.accent != accent ||
      oldDelegate.idlePose != idlePose ||
      oldDelegate.isBlinking != isBlinking ||
      oldDelegate.syncTick != syncTick ||
      oldDelegate.isWaving != isWaving ||
      oldDelegate.jumpOffset != jumpOffset;
}
