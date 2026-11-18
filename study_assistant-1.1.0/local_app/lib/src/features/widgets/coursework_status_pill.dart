import 'package:flutter/material.dart';
import '../../app/journal.dart';

enum CourseworkPillTone {
  overdue,
  urgentToday,
  unconfirmed,
  exam,
  completed,
  neutral,
}

class CourseworkStatusPill extends StatelessWidget {
  const CourseworkStatusPill({
    super.key,
    required this.label,
    this.tone = CourseworkPillTone.neutral,
    this.icon,
  });

  final String label;
  final CourseworkPillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = switch (tone) {
      CourseworkPillTone.overdue => (
          fg: Journal.berry,
          bg: Journal.berryBg,
          border: Journal.berryBorder,
          defaultIcon: Icons.warning_amber_rounded,
        ),
      CourseworkPillTone.urgentToday => (
          fg: Journal.berry,
          bg: Journal.berryBg,
          border: Journal.berryBorder,
          defaultIcon: Icons.schedule_rounded,
        ),
      CourseworkPillTone.unconfirmed => (
          fg: Journal.ochre,
          bg: Journal.ochreBg,
          border: Journal.ochreBorder,
          defaultIcon: Icons.help_outline_rounded,
        ),
      CourseworkPillTone.exam => (
          fg: Journal.slate,
          bg: Journal.slateBg,
          border: Journal.slateBorder,
          defaultIcon: Icons.school_outlined,
        ),
      CourseworkPillTone.completed => (
          fg: Journal.ink,
          bg: Journal.sage,
          border: Journal.sageBorder,
          defaultIcon: Icons.check_circle_outline_rounded,
        ),
      CourseworkPillTone.neutral => (
          fg: Journal.ink,
          bg: Journal.parchment,
          border: Journal.rule,
          defaultIcon: null,
        ),
    };
    final effectiveIcon = icon ?? palette.defaultIcon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (effectiveIcon != null) ...[
            Icon(effectiveIcon, size: 13, color: palette.fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: Journal.metadata.copyWith(
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: palette.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
