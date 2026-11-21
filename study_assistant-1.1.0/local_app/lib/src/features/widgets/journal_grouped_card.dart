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

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final hasHeader = title != null ||
        trailing != null ||
        (infoItems != null && infoItems!.isNotEmpty);
    final headerFill = Color.lerp(
      journal.sheet,
      journal.sage,
      journal.isDark ? 0.24 : 0.30,
    )!;

    return Material(
      color: backgroundColor ?? journal.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: journal.cardBorder, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Container(
              color: headerFill,
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
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
              Text(
                trailingText!,
                style: journal.metadata.copyWith(fontSize: 13),
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
