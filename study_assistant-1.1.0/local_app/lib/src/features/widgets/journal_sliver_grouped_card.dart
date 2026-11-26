import 'package:flutter/material.dart';

import '../../app/journal.dart';

class JournalSliverGroupedCard extends StatelessWidget {
  const JournalSliverGroupedCard({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.dividerIndent = 16.0,
    this.findChildIndexCallback,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double dividerIndent;
  final ChildIndexGetter? findChildIndexCallback;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final edge = BorderSide(color: journal.cardBorder, width: 0.8);
    const corner = Radius.circular(16);
    final findIndex = findChildIndexCallback;
    return DecoratedSliver(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: journal.cardShadowContact,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: journal.cardShadowAmbient,
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      sliver: SliverList.builder(
        itemCount: itemCount,
        findChildIndexCallback: findIndex == null
            ? null
            : (key) => key is ValueKey<Key> ? findIndex(key.value) : null,
        itemBuilder: (context, index) {
          final item = itemBuilder(context, index);
          final itemKey = item.key;
          final first = index == 0;
          final last = index == itemCount - 1;
          final radius = BorderRadius.vertical(
            top: first ? corner : Radius.zero,
            bottom: last ? corner : Radius.zero,
          );
          final body = CustomPaint(
            foregroundPainter: first
                ? _SliverTopHighlightPainter(
                    highlightColor: journal.cardTopHighlight,
                    radius: 16.0,
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!first)
                  Divider(
                    height: 0.6,
                    thickness: 0.6,
                    indent: dividerIndent,
                    endIndent: 16,
                    color: journal.divider,
                  ),
                item,
              ],
            ),
          );
          return Material(
            // Keep the item's key for its subtree and pass it back to the
            // caller's index lookup when the sliver moves a row.
            key: itemKey == null ? null : ValueKey<Key>(itemKey),
            color: journal.sheet,
            shape: RoundedRectangleBorder(borderRadius: radius),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border(
                  top: first ? edge : BorderSide.none,
                  right: edge,
                  bottom: last ? edge : BorderSide.none,
                  left: edge,
                ),
              ),
              child: body,
            ),
          );
        },
      ),
    );
  }
}

class _SliverTopHighlightPainter extends CustomPainter {
  const _SliverTopHighlightPainter({
    required this.highlightColor,
    required this.radius,
  });

  static const double _highlightWidth = 0.8;
  static const double _highlightInset = 1.2;

  final Color highlightColor;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cornerRadius = radius.clamp(0.0, size.shortestSide / 2).toDouble();
    const inset = _highlightInset;
    final arcRadius = cornerRadius > inset ? cornerRadius - inset : 0.0;
    final path = Path()..moveTo(inset, inset + arcRadius);
    if (arcRadius > 0) {
      path.arcToPoint(
        Offset(inset + arcRadius, inset),
        radius: Radius.circular(arcRadius),
        clockwise: true,
      );
    }
    path.lineTo(size.width - inset - arcRadius, inset);
    if (arcRadius > 0) {
      path.arcToPoint(
        Offset(size.width - inset, inset + arcRadius),
        radius: Radius.circular(arcRadius),
        clockwise: true,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _highlightWidth
        ..strokeCap = StrokeCap.round
        ..color = highlightColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SliverTopHighlightPainter oldDelegate) =>
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.radius != radius;
}
