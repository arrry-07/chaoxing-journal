import 'package:flutter/material.dart';

import '../../app/journal.dart';

class ProfileMenuCard extends StatelessWidget {
  const ProfileMenuCard({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1)
                const Divider(height: 1, indent: 56, endIndent: 16),
            ],
          ],
        ),
      );
}

class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.compactSubtitle = false,
    this.trailing = Icons.chevron_right,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool compactSubtitle;
  final IconData trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Journal.ink),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        subtitleTextStyle: compactSubtitle
            ? Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  height: 1.4,
                  color: Journal.muted,
                )
            : null,
        trailing: onTap == null ? null : Icon(trailing, color: Journal.muted),
        onTap: onTap,
      );
}
