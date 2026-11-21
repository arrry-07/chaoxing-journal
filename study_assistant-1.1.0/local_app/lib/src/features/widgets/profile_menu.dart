import 'package:flutter/material.dart';

import '../../app/journal.dart';
import 'journal_grouped_card.dart';

class ProfileMenuCard extends StatelessWidget {
  const ProfileMenuCard({
    super.key,
    this.title,
    required this.children,
  });

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => JournalGroupedCard(
        title: title,
        dividerIndent: 52,
        children: children,
      );
}

class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.compactSubtitle = false,
    this.trailing = Icons.chevron_right_rounded,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool compactSubtitle;
  final IconData trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => JournalGroupTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: onTap == null
            ? null
            : Icon(trailing, size: 20, color: Journal.of(context).muted),
        onTap: onTap,
      );
}
