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

  late final AnimationController _snapController;
  double _offset = 0.0;
  bool _crossedRight = false;
  bool _crossedLeft = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (!mounted) return;
        setState(() => _offset = _snapController.value);
      });
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

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _snapController.stop();
    _crossedRight = false;
    _crossedLeft = false;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final delta = details.primaryDelta ?? 0.0;
    var nextRaw = _offset + delta;
    if (nextRaw > 0 && widget.rightAction == null) nextRaw = 0;
    if (nextRaw < 0 && widget.leftAction == null) nextRaw = 0;

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
    if (!widget.enabled) return;
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

    _snapBack(velocity / 300.0);
  }

  void _snapBack(double velocity) {
    _crossedRight = false;
    _crossedLeft = false;
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
        velocity: velocity.clamp(-12.0, 12.0),
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
    final iconScale = reached ? 1.18 : (0.84 + 0.16 * progress);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: () => _snapBack(0.0),
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
                          Transform.scale(
                            scale: iconScale,
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
            offset: Offset(_offset, 0),
            child: ColoredBox(
              color: _offset.abs() > 0.5 ? journal.sheet : Colors.transparent,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
