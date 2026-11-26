import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../services/clawd_companion_controller.dart';

enum ClawdBubblePointerDirection { up, down }

/// Mutable holder updated during [CustomSingleChildLayout] positioning so
/// [_ClawdBubblePainter] receives the exact rendered pointer offset on the
/// same frame without triggering an extra build pass.
class ClawdBubblePointerAnchor {
  ClawdBubblePointerAnchor([this.offset]);
  double? offset;
}

class ClawdSpeechBubble extends StatelessWidget {
  const ClawdSpeechBubble({
    super.key,
    required this.message,
    required this.onTap,
    this.maxWidth = 220.0,
    this.pointerDirection = ClawdBubblePointerDirection.up,
    this.pointerOffsetFromLeft,
    this.pointerOffsetFromRight,
    this.pointerAnchor,
    this.pointerAnchorVersion = 0,
  });

  final ClawdSpeechMessage message;
  final VoidCallback onTap;
  final double maxWidth;
  final ClawdBubblePointerDirection pointerDirection;
  final double? pointerOffsetFromLeft;
  final double? pointerOffsetFromRight;
  final ClawdBubblePointerAnchor? pointerAnchor;
  final int pointerAnchorVersion;

  static const double _pointerWidth = 11.0;
  static const double _pointerHeight = 6.0;
  static const double _borderRadius = 11.0;
  static const double _borderWidth = 0.8;

  /// Computes the clamped pointer tip X within `[minCenter, max(minCenter, actualWidth - 14.0)]`.
  static double clampPointerCenterX({
    required double actualWidth,
    double? pointerOffsetFromLeft,
    double? pointerOffsetFromRight,
    double? dynamicOffset,
  }) {
    final double raw;
    if (dynamicOffset != null) {
      raw = dynamicOffset;
    } else if (pointerOffsetFromRight != null) {
      raw = actualWidth - pointerOffsetFromRight;
    } else {
      raw = pointerOffsetFromLeft ?? 24.0;
    }
    final minCenter = math.min(14.0, actualWidth * 0.5);
    final maxCenter = math.max(minCenter, actualWidth - 14.0);
    return raw.clamp(minCenter, maxCenter);
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final fillColor =
        Color.lerp(journal.sheetElevated, journal.parchment, 0.22)!;
    final borderColor = message.isTsundere
        ? Color.lerp(journal.ruleStrong, journal.berry, 0.42)!
        : journal.ruleStrong;
    final safeMaxWidth = math.max(36.0, maxWidth);
    final pointsUp = pointerDirection == ClawdBubblePointerDirection.up;
    final rightAnchored = pointerOffsetFromRight != null;

    final composed = Semantics(
      button: true,
      liveRegion: true,
      label: '${message.text}，点击收起',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CustomPaint(
          painter: _ClawdBubblePainter(
            fillColor: fillColor,
            borderColor: borderColor,
            shadowColor: journal.cardShadowContact,
            borderWidth: _borderWidth,
            borderRadius: _borderRadius,
            pointerWidth: _pointerWidth,
            pointerHeight: _pointerHeight,
            pointsUp: pointsUp,
            pointerOffsetFromLeft: pointerOffsetFromLeft,
            pointerOffsetFromRight: pointerOffsetFromRight,
            pointerAnchor: pointerAnchor,
            layoutVersion: pointerAnchorVersion,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: pointsUp ? _pointerHeight : 0.0,
              bottom: pointsUp ? 0.0 : _pointerHeight,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.min(36.0, safeMaxWidth),
                maxWidth: safeMaxWidth,
                minHeight: 30.0,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
      ),
    );

    final duration = JournalMotion.duration(
      context,
      const Duration(milliseconds: 140),
    );
    if (duration == Duration.zero) {
      return composed;
    }
    final scaleAlignment = switch ((pointsUp, rightAnchored)) {
      (true, true) => Alignment.topRight,
      (true, false) => Alignment.topLeft,
      (false, true) => Alignment.bottomRight,
      (false, false) => Alignment.bottomLeft,
    };
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(message.id),
      tween: Tween<double>(begin: 0.92, end: 1.0),
      duration: duration,
      curve: JournalMotion.easeOut,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: scaleAlignment,
        child: Opacity(
          opacity: ((scale - 0.92) / 0.08).clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: composed,
    );
  }
}

/// Positions [ClawdSpeechBubble] centered around [anchorX] using its actual
/// measured width while clamping strictly inside `[minLeft, safeRight]`, and
/// passes `anchorX - bubbleLeft` directly to the bubble pointer.
class ClawdAnchoredSpeechBubble extends StatelessWidget {
  const ClawdAnchoredSpeechBubble({
    super.key,
    required this.message,
    required this.onTap,
    required this.anchorX,
    required this.top,
    required this.minLeft,
    required this.safeRight,
    this.maxWidth = 210.0,
    this.pointerDirection = ClawdBubblePointerDirection.up,
    this.bubbleKey,
  });

  final ClawdSpeechMessage message;
  final VoidCallback onTap;
  final double anchorX;
  final double top;
  final double minLeft;
  final double safeRight;
  final double maxWidth;
  final ClawdBubblePointerDirection pointerDirection;
  final Key? bubbleKey;

  @override
  Widget build(BuildContext context) {
    final availableWidth = math.max(36.0, safeRight - minLeft);
    final effectiveMaxWidth = math.min(maxWidth, availableWidth);
    final pointerTarget = ClawdBubblePointerAnchor();
    return CustomSingleChildLayout(
      delegate: _ClawdAnchoredBubbleLayoutDelegate(
        anchorX: anchorX,
        top: top,
        minLeft: minLeft,
        safeRight: safeRight,
        maxWidth: effectiveMaxWidth,
        pointerTarget: pointerTarget,
      ),
      child: ClawdSpeechBubble(
        key: bubbleKey,
        message: message,
        maxWidth: effectiveMaxWidth,
        pointerDirection: pointerDirection,
        pointerAnchor: pointerTarget,
        pointerAnchorVersion: Object.hash(
          message.id,
          anchorX.round(),
          minLeft.round(),
          safeRight.round(),
          effectiveMaxWidth.round(),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ClawdAnchoredBubbleLayoutDelegate extends SingleChildLayoutDelegate {
  const _ClawdAnchoredBubbleLayoutDelegate({
    required this.anchorX,
    required this.top,
    required this.minLeft,
    required this.safeRight,
    required this.maxWidth,
    required this.pointerTarget,
  });

  final double anchorX;
  final double top;
  final double minLeft;
  final double safeRight;
  final double maxWidth;
  final ClawdBubblePointerAnchor pointerTarget;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxH = constraints.hasBoundedHeight
        ? math.max(0.0, constraints.maxHeight - top)
        : double.infinity;
    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxH,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = math.max(minLeft, safeRight - childSize.width);
    final bubbleLeft =
        (anchorX - childSize.width * 0.5).clamp(minLeft, maxLeft);
    pointerTarget.offset = anchorX - bubbleLeft;
    return Offset(bubbleLeft, top);
  }

  @override
  bool shouldRelayout(_ClawdAnchoredBubbleLayoutDelegate oldDelegate) =>
      oldDelegate.anchorX != anchorX ||
      oldDelegate.top != top ||
      oldDelegate.minLeft != minLeft ||
      oldDelegate.safeRight != safeRight ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.pointerTarget != pointerTarget;
}

class _ClawdBubblePainter extends CustomPainter {
  const _ClawdBubblePainter({
    required this.fillColor,
    required this.borderColor,
    required this.shadowColor,
    required this.borderWidth,
    required this.borderRadius,
    required this.pointerWidth,
    required this.pointerHeight,
    required this.pointsUp,
    required this.pointerOffsetFromLeft,
    required this.pointerOffsetFromRight,
    required this.pointerAnchor,
    required this.layoutVersion,
  });

  final Color fillColor;
  final Color borderColor;
  final Color shadowColor;
  final double borderWidth;
  final double borderRadius;
  final double pointerWidth;
  final double pointerHeight;
  final bool pointsUp;
  final double? pointerOffsetFromLeft;
  final double? pointerOffsetFromRight;
  final ClawdBubblePointerAnchor? pointerAnchor;
  final int layoutVersion;

  double resolvedPointerCenterX(double actualWidth) =>
      ClawdSpeechBubble.clampPointerCenterX(
        actualWidth: actualWidth,
        pointerOffsetFromLeft: pointerOffsetFromLeft,
        pointerOffsetFromRight: pointerOffsetFromRight,
        dynamicOffset: pointerAnchor?.offset,
      );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= pointerHeight) return;
    final halfStroke = borderWidth * 0.5;
    final pillRect = Rect.fromLTRB(
      halfStroke,
      pointsUp ? pointerHeight : halfStroke,
      size.width - halfStroke,
      pointsUp ? size.height - halfStroke : size.height - pointerHeight,
    );
    final r = math.min(
      borderRadius,
      math.min(pillRect.width * 0.5, pillRect.height * 0.5),
    );
    final pillPath = Path()
      ..addRRect(RRect.fromRectAndRadius(pillRect, Radius.circular(r)));

    final cx = resolvedPointerCenterX(size.width);
    final halfPtr = pointerWidth * 0.5;
    final pointerPath = Path();
    if (pointsUp) {
      final baseY = pointerHeight + 1.0;
      pointerPath
        ..moveTo(cx - halfPtr, baseY)
        ..lineTo(cx, halfStroke)
        ..lineTo(cx + halfPtr, baseY)
        ..close();
    } else {
      final baseY = pillRect.bottom - 1.0;
      pointerPath
        ..moveTo(cx - halfPtr, baseY)
        ..lineTo(cx, size.height - halfStroke)
        ..lineTo(cx + halfPtr, baseY)
        ..close();
    }

    final unifiedPath =
        Path.combine(PathOperation.union, pillPath, pointerPath);

    canvas.drawPath(
      unifiedPath.shift(const Offset(0, 2)),
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawPath(unifiedPath, Paint()..color = fillColor);
    canvas.drawPath(
      unifiedPath,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ClawdBubblePainter oldDelegate) =>
      oldDelegate.fillColor != fillColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.pointerWidth != pointerWidth ||
      oldDelegate.pointerHeight != pointerHeight ||
      oldDelegate.pointsUp != pointsUp ||
      oldDelegate.pointerOffsetFromLeft != pointerOffsetFromLeft ||
      oldDelegate.pointerOffsetFromRight != pointerOffsetFromRight ||
      oldDelegate.layoutVersion != layoutVersion ||
      oldDelegate.pointerAnchor?.offset != pointerAnchor?.offset;
}
