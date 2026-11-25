import 'package:flutter/material.dart';
import '../../app/journal.dart';

enum CourseworkPillTone {
  overdue,
  urgentToday,
  unconfirmed,
  exam,
  todo,
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
    final journal = Journal.of(context);
    final palette = switch (tone) {
      CourseworkPillTone.overdue => (
          fg: journal.overdueAmber,
          bg: journal.overdueAmberBg,
          border: null,
          defaultIcon: null,
        ),
      CourseworkPillTone.urgentToday => (
          fg: journal.accent,
          bg: journal.slateBg,
          border: journal.sageBorder,
          defaultIcon: Icons.schedule_rounded,
        ),
      CourseworkPillTone.unconfirmed => (
          fg: journal.ochre,
          bg: journal.ochreBg,
          border: null,
          defaultIcon: Icons.help_outline_rounded,
        ),
      CourseworkPillTone.exam => (
          fg: journal.examOrange,
          bg: journal.examOrangeBg,
          border: journal.examOrangeBorder,
          defaultIcon: Icons.school_outlined,
        ),
      CourseworkPillTone.todo => (
          fg: journal.todoGreen,
          bg: journal.todoGreenBg,
          border: null,
          defaultIcon: null,
        ),
      CourseworkPillTone.completed => (
          fg: journal.ink,
          bg: journal.sage,
          border: null,
          defaultIcon: Icons.check_circle_outline_rounded,
        ),
      CourseworkPillTone.neutral => (
          fg: journal.muted,
          bg: journal.parchment,
          border: null,
          defaultIcon: null,
        ),
    };
    final effectiveIcon = icon ?? palette.defaultIcon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(6),
        border: palette.border == null
            ? null
            : Border.all(color: palette.border!, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (effectiveIcon != null) ...[
            Icon(effectiveIcon, size: 12.5, color: palette.fg),
            const SizedBox(width: 3.5),
          ],
          Flexible(
            child: Text(
              label,
              style: journal.metadata.copyWith(
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
