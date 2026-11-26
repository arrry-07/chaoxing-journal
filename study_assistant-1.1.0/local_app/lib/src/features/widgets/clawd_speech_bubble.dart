import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../services/clawd_companion_controller.dart';

enum ClawdBubblePointerDirection { up, down }

class ClawdSpeechBubble extends StatelessWidget {
  const ClawdSpeechBubble({
    super.key,
    required this.message,
    required this.onTap,
    this.maxWidth = 220.0,
    this.pointerDirection = ClawdBubblePointerDirection.up,
    this.pointerOffsetFromLeft = 24.0,
  });

  final ClawdSpeechMessage message;
  final VoidCallback onTap;
  final double maxWidth;
  final ClawdBubblePointerDirection pointerDirection;
  final double pointerOffsetFromLeft;

  static const double _pointerWidth = 11.0;
  static const double _pointerHeight = 6.0;
  static const double _borderRadius = 11.0;
  static const double _borderWidth = 0.8;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final fillColor =
        Color.lerp(journal.sheetElevated, journal.parchment, 0.22)!;
    final borderColor = message.isTsundere
        ? Color.lerp(journal.ruleStrong, journal.berry, 0.42)!
        : journal.ruleStrong;
    final safeMaxWidth = math.max(96.0, maxWidth);
    final clampedPointerOffset = pointerOffsetFromLeft.clamp(
      14.0,
      math.max(14.0, safeMaxWidth - 14.0),
    );

    final pill = Semantics(
      button: true,
      liveRegion: true,
      label: '${message.text}，点击收起',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: safeMaxWidth,
            minHeight: 30.0,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(_borderRadius),
              border: Border.all(color: borderColor, width: _borderWidth),
              boxShadow: [
                BoxShadow(
                  color: journal.cardShadowContact,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                message.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: journal.metadata.copyWith(
                  fontSize: 12.5,
                  height: 1.32,
                  color: journal.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final tail = IgnorePointer(
      child: CustomPaint(
        size: const Size(_pointerWidth, _pointerHeight),
        painter: _ClawdBubblePointerPainter(
          fillColor: fillColor,
          borderColor: borderColor,
          borderWidth: _borderWidth,
          pointsUp: pointerDirection == ClawdBubblePointerDirection.up,
        ),
      ),
    );

    final composed = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: pointerDirection == ClawdBubblePointerDirection.up
                ? _pointerHeight - 1.0
                : 0.0,
            bottom: pointerDirection == ClawdBubblePointerDirection.down
                ? _pointerHeight - 1.0
                : 0.0,
          ),
          child: pill,
        ),
        Positioned(
          left: (clampedPointerOffset - _pointerWidth * 0.5)
              .clamp(10.0, math.max(10.0, safeMaxWidth - _pointerWidth - 10.0)),
          top: pointerDirection == ClawdBubblePointerDirection.up ? 0.0 : null,
          bottom:
              pointerDirection == ClawdBubblePointerDirection.down ? 0.0 : null,
          child: tail,
        ),
      ],
    );

    final duration = JournalMotion.duration(
      context,
      const Duration(milliseconds: 140),
    );
    if (duration == Duration.zero) {
      return composed;
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(message.id),
      tween: Tween<double>(begin: 0.92, end: 1.0),
      duration: duration,
      curve: JournalMotion.easeOut,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: pointerDirection == ClawdBubblePointerDirection.up
            ? Alignment.topLeft
            : Alignment.bottomLeft,
        child: Opacity(
          opacity: ((scale - 0.92) / 0.08).clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: composed,
    );
  }
}

class _ClawdBubblePointerPainter extends CustomPainter {
  const _ClawdBubblePointerPainter({
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
    required this.pointsUp,
  });

  final Color fillColor;
  final Color borderColor;
  final double borderWidth;
  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPath = Path();
    final strokePath = Path();
    if (pointsUp) {
      fillPath
        ..moveTo(0, size.height)
        ..lineTo(size.width * 0.5, 0)
        ..lineTo(size.width, size.height)
        ..close();
      strokePath
        ..moveTo(0, size.height)
        ..lineTo(size.width * 0.5, 0)
        ..lineTo(size.width, size.height);
    } else {
      fillPath
        ..moveTo(0, 0)
        ..lineTo(size.width * 0.5, size.height)
        ..lineTo(size.width, 0)
        ..close();
      strokePath
        ..moveTo(0, 0)
        ..lineTo(size.width * 0.5, size.height)
        ..lineTo(size.width, 0);
    }
    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      strokePath,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ClawdBubblePointerPainter oldDelegate) =>
      oldDelegate.fillColor != fillColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.pointsUp != pointsUp;
}
