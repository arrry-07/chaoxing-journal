import 'package:flutter/material.dart';

import '../../app/journal.dart';
import 'journal_info_popover.dart';

class JournalGroupedCard extends StatelessWidget {
  const JournalGroupedCard({
    super.key,
    required this.children,
    this.title,
    this.trailing,
    this.infoTitle,
    this.infoItems,
    this.dividerIndent = 16.0,
    this.borderRadius = 16.0,
    this.backgroundColor,
    this.padding = EdgeInsets.zero,
    this.emphasized = false,
  });

  final List<Widget> children;
  final String? title;
  final Widget? trailing;
  final String? infoTitle;
  final List<String>? infoItems;
  final double dividerIndent;
  final double borderRadius;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final hasHeader = title != null ||
        trailing != null ||
        (infoItems != null && infoItems!.isNotEmpty);
    final compactTrailingHeader =
        trailing != null && (infoItems == null || infoItems!.isEmpty);
    final headerFill = journal.sectionHeaderFill;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
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
      child: Material(
        color: backgroundColor ?? journal.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(
            color: emphasized ? journal.sageBorder : journal.cardBorder,
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: emphasized
              ? _JournalCardEmphasisTintPainter(
                  startColor: journal.cardEmphasisTintStart,
                  endColor: journal.cardEmphasisTintEnd,
                )
              : null,
          foregroundPainter: _JournalCardEdgePainter(
            highlightColor: journal.cardTopHighlight,
            radius: borderRadius,
            barColor: emphasized ? journal.cardEmphasisBar : null,
            barGlowColor: emphasized ? journal.cardEmphasisBarGlow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasHeader)
                Container(
                  constraints: compactTrailingHeader
                      ? const BoxConstraints(minHeight: 43)
                      : null,
                  decoration: BoxDecoration(
                    color: headerFill,
                    border: Border(
                      bottom: BorderSide(color: journal.divider, width: 0.6),
                    ),
                  ),
                  padding: compactTrailingHeader
                      ? const EdgeInsets.fromLTRB(16, 2, 8, 2)
                      : const EdgeInsets.fromLTRB(16, 12, 12, 10),
                  child: Row(
                    children: [
                      if (title != null)
                        Expanded(
                          child: Text(
                            title!,
                            style: journal.section.copyWith(fontSize: 15.5),
                          ),
                        )
                      else
                        const Spacer(),
                      if (trailing != null) trailing!,
                      if (infoItems != null && infoItems!.isNotEmpty)
                        JournalInfoButton(
                          title: infoTitle ?? title ?? '说明',
                          items: infoItems!,
                        ),
                    ],
                  ),
                ),
              if (padding == EdgeInsets.zero)
                ..._withDividers(journal)
              else
                Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: _withDividers(journal),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _withDividers(JournalPalette journal) {
    if (children.isEmpty) return const [];
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i != children.length - 1) {
        out.add(Divider(
          height: 0.6,
          thickness: 0.6,
          indent: dividerIndent,
          endIndent: 16,
          color: journal.divider,
        ));
      }
    }
    return out;
  }
}

/// Very light cobalt wash from the top-left to the bottom-right of a card that
/// carries the "today" / pinned emphasis.
class _JournalCardEmphasisTintPainter extends CustomPainter {
  const _JournalCardEmphasisTintPainter({
    required this.startColor,
    required this.endColor,
  });

  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [startColor, endColor],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _JournalCardEmphasisTintPainter oldDelegate) =>
      oldDelegate.startColor != startColor || oldDelegate.endColor != endColor;
}

/// Paints the inset top hairline highlight and, for emphasized cards, the 3dp
/// soft cobalt bar along the left edge. Both are clipped by the hosting
/// [Material] rounded rectangle, so the painter never needs to round corners.
class _JournalCardEdgePainter extends CustomPainter {
  const _JournalCardEdgePainter({
    required this.highlightColor,
    required this.radius,
    this.barColor,
    this.barGlowColor,
  });

  static const double _highlightWidth = 0.8;
  // Sits just inside the 0.8dp border, which Material paints on top.
  static const double _highlightInset = 1.2;
  static const double _barInset = 0.8;
  static const double _barWidth = 3.0;
  static const double _barGlowWidth = 5.0;

  final Color highlightColor;
  final double radius;
  final Color? barColor;
  final Color? barGlowColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cornerRadius = radius.clamp(0.0, size.shortestSide / 2).toDouble();
    _paintTopHighlight(canvas, size, cornerRadius);
    _paintEmphasisBar(canvas, size);
  }

  void _paintTopHighlight(Canvas canvas, Size size, double cornerRadius) {
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

  void _paintEmphasisBar(Canvas canvas, Size size) {
    final glow = barGlowColor;
    if (glow != null) {
      final glowRect = Rect.fromLTWH(_barInset, 0, _barGlowWidth, size.height);
      canvas.drawRect(
        glowRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [glow, glow.withValues(alpha: 0)],
          ).createShader(glowRect),
      );
    }
    final bar = barColor;
    if (bar == null) return;
    canvas.drawRect(
      Rect.fromLTWH(_barInset, 0, _barWidth, size.height),
      Paint()..color = bar,
    );
  }

  @override
  bool shouldRepaint(covariant _JournalCardEdgePainter oldDelegate) =>
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.barColor != barColor ||
      oldDelegate.barGlowColor != barGlowColor ||
      oldDelegate.radius != radius;
}

class JournalGroupTile extends StatelessWidget {
  const JournalGroupTile({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.showChevron = true,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final effectiveIconColor = iconColor ?? journal.ink;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (icon != null) ...[
              SizedBox(
                width: 24,
                child: Icon(icon, size: 21, color: effectiveIconColor),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: journal.entryTitle),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: journal.metadata.copyWith(fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null && trailingText!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  trailingText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: journal.metadata.copyWith(fontSize: 13),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null && showChevron) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: journal.muted,
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
