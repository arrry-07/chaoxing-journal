import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../models/display_preferences.dart';

class JournalSwipeAction {
  const JournalSwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.onTrigger,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTrigger;
}

class JournalSwipeTile extends StatefulWidget {
  const JournalSwipeTile({
    super.key,
    required this.child,
    this.displayPrefs = const DisplayPreferences(),
    this.rightAction,
    this.leftAction,
    this.enabled = true,
  });

  final Widget child;
  final DisplayPreferences displayPrefs;
  final JournalSwipeAction? rightAction;
  final JournalSwipeAction? leftAction;
  final bool enabled;

  @override
  State<JournalSwipeTile> createState() => _JournalSwipeTileState();
}

class _JournalSwipeTileState extends State<JournalSwipeTile>
    with SingleTickerProviderStateMixin {
  static const double _rightThreshold = 72.0;
  static const double _leftThreshold = 68.0;
  static const double _maxDrag = 108.0;
  static const double _edgeBackExclusionWidth = 24.0;

  late final AnimationController _snapController;
  // Displayed (rubber-banded) offset and the raw finger travel behind it.
  // Damping is always derived from the raw value; feeding the displayed value
  // back into the damping made the tile creep backwards on slow forward drags.
  double _offset = 0.0;
  double _rawOffset = 0.0;
  bool _crossedRight = false;
  bool _crossedLeft = false;
  bool _ignoredEdgeDrag = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _offset = _snapController.value;
          _rawOffset = _offset;
        });
      });
  }

  @override
  void didUpdateWidget(JournalSwipeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The revealed action may disappear (item completed, pin no longer
    // allowed, tile disabled) while the tile is open: never leave it stuck.
    final lostRight = _offset > 0 && widget.rightAction == null;
    final lostLeft = _offset < 0 && widget.leftAction == null;
    if (!widget.enabled || lostRight || lostLeft) {
      _snapController.stop();
      _offset = 0.0;
      _rawOffset = 0.0;
      _crossedRight = false;
      _crossedLeft = false;
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double _applyRubberBand(double rawDelta, double threshold, double sign) {
    final absVal = rawDelta.abs();
    if (absVal <= threshold) return absVal * sign;
    final excess = absVal - threshold;
    final damped = threshold + (excess * 0.42).clamp(0.0, _maxDrag - threshold);
    return damped * sign;
  }

  double _maxRawFor(double threshold) =>
      threshold + (_maxDrag - threshold) / 0.42;

  double _undoRubberBand(double displayed, double threshold) {
    final absVal = displayed.abs();
    if (absVal <= threshold) return displayed;
    final raw = threshold + (absVal - threshold) / 0.42;
    return displayed.isNegative ? -raw : raw;
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dx = details.globalPosition.dx;
    if (dx < _edgeBackExclusionWidth ||
        dx > screenWidth - _edgeBackExclusionWidth) {
      _ignoredEdgeDrag = true;
      return;
    }
    _ignoredEdgeDrag = false;
    _snapController.stop();
    _rawOffset = _undoRubberBand(
      _offset,
      _offset >= 0 ? _rightThreshold : _leftThreshold,
    );
    _crossedRight = _offset >= _rightThreshold;
    _crossedLeft = _offset <= -_leftThreshold;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _ignoredEdgeDrag) return;
    final delta = details.primaryDelta ?? 0.0;
    final maxRightRaw =
        widget.rightAction == null ? 0.0 : _maxRawFor(_rightThreshold);
    final maxLeftRaw =
        widget.leftAction == null ? 0.0 : _maxRawFor(_leftThreshold);
    final nextRaw = (_rawOffset + delta).clamp(-maxLeftRaw, maxRightRaw);
    _rawOffset = nextRaw;

    final nextOffset = nextRaw >= 0
        ? _applyRubberBand(nextRaw, _rightThreshold, 1.0)
        : _applyRubberBand(nextRaw, _leftThreshold, -1.0);

    if (nextOffset >= _rightThreshold && !_crossedRight) {
      _crossedRight = true;
      JournalMotion.mediumThreshold(widget.displayPrefs);
    } else if (nextOffset < _rightThreshold - 6 && _crossedRight) {
      _crossedRight = false;
      JournalMotion.selectionTick(widget.displayPrefs);
    }

    if (nextOffset <= -_leftThreshold && !_crossedLeft) {
      _crossedLeft = true;
      JournalMotion.selectionTick(widget.displayPrefs);
    } else if (nextOffset > -_leftThreshold + 6 && _crossedLeft) {
      _crossedLeft = false;
    }

    setState(() => _offset = nextOffset);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!widget.enabled || _ignoredEdgeDrag) {
      _ignoredEdgeDrag = false;
      return;
    }
    final velocity = details.primaryVelocity ?? 0.0;
    final triggerRight = widget.rightAction != null &&
        (_offset >= _rightThreshold || (_offset >= 42 && velocity > 750));
    final triggerLeft = widget.leftAction != null &&
        (_offset <= -_leftThreshold || (_offset <= -42 && velocity < -750));

    if (triggerRight) {
      widget.rightAction!.onTrigger();
    } else if (triggerLeft) {
      widget.leftAction!.onTrigger();
    }

    _snapBack(velocity);
  }

  void _snapBack(double velocityPxPerSec) {
    if (!mounted) return;
    _crossedRight = false;
    _crossedLeft = false;
    _rawOffset = 0.0;
    _ignoredEdgeDrag = false;
    if (_offset.abs() < 0.5) {
      setState(() => _offset = 0.0);
      return;
    }
    if (JournalMotion.isReducedMotion(context)) {
      setState(() => _offset = 0.0);
      return;
    }
    _snapController.value = _offset;
    _snapController.animateWith(
      JournalMotion.springFor(
        JournalMotion.snappySpring,
        start: _offset,
        end: 0.0,
        velocity: velocityPxPerSec.clamp(-2400.0, 2400.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled ||
        (widget.rightAction == null && widget.leftAction == null)) {
      return widget.child;
    }
    final journal = Journal.of(context);
    final showingRight = _offset > 1.0 && widget.rightAction != null;
    final showingLeft = _offset < -1.0 && widget.leftAction != null;
    final activeAction = showingRight
        ? widget.rightAction
        : showingLeft
            ? widget.leftAction
            : null;
    final threshold = showingRight ? _rightThreshold : _leftThreshold;
    final progress = (_offset.abs() / threshold).clamp(0.0, 1.0);
    final reached = _offset.abs() >= threshold;
    final reduced = JournalMotion.isReducedMotion(context);
    final iconScale =
        reduced ? 1.0 : (reached ? 1.20 : (0.86 + 0.14 * progress));

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: () => _snapBack(0.0),
      child: ClipRect(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (activeAction != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Color.lerp(
                    journal.sheet,
                    activeAction.backgroundColor,
                    0.45 + 0.55 * progress,
                  )!,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Align(
                      alignment: showingRight
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Opacity(
                        opacity: math.min(1.0, progress * 1.2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showingLeft) ...[
                              Text(
                                activeAction.label,
                                style: journal.pillLabel.copyWith(
                                  color: activeAction.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            AnimatedScale(
                              scale: iconScale,
                              duration: reduced
                                  ? Duration.zero
                                  : Duration(milliseconds: reached ? 160 : 90),
                              curve: reached
                                  ? Curves.easeOutBack
                                  : JournalMotion.easeOut,
                              child: Icon(
                                activeAction.icon,
                                size: 20,
                                color: activeAction.color,
                              ),
                            ),
                            if (showingRight) ...[
                              const SizedBox(width: 8),
                              Text(
                                activeAction.label,
                                style: journal.pillLabel.copyWith(
                                  color: activeAction.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Transform.translate(
              key: const ValueKey('journal-swipe-foreground'),
              offset: Offset(_offset, 0),
              child: ColoredBox(
                color: _offset.abs() > 0.5 ? journal.sheet : Colors.transparent,
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
