import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../app/journal.dart';
import '../../models/assignment.dart';
import '../../models/display_preferences.dart';
import '../../models/study_notebook.dart';
import '../../services/assignment_query.dart';
import '../../services/home_manual_timeline.dart';
import 'assignment_card.dart';
import 'coursework_status_pill.dart';

/// Local manual entry rendered in the same grouped timeline as coursework.
///
/// The rail width and compact countdown deliberately reuse [AssignmentCard] so
/// mixed rows stay pixel-aligned and do not grow parallel formatting rules.
class ManualHomeCard extends StatelessWidget {
  const ManualHomeCard({
    super.key,
    required this.entry,
    required this.now,
    required this.onTap,
    required this.onToggleDone,
    this.onLongPress,
    this.dragHandle,
    this.inPinnedSection = false,
    this.compact = false,
    this.countdown = false,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 14),
  });

  final ManualEntry entry;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final VoidCallback? onLongPress;
  final Widget? dragHandle;
  final bool inPinnedSection;
  final bool compact;
  final bool countdown;
  final EdgeInsetsGeometry contentPadding;

  static final DateFormat _clockFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final at = entry.at;
    final bucket = HomeManualTimeline.manualBucketAt(entry, now);
    final overdue = bucket == AssignmentDeadlineBucket.overdue;
    final largeText = JournalLayout.isLargeText(context);
    final railWidth = AssignmentCard.measureRailWidth(
      context,
      inPinnedSection: inPinnedSection,
    );
    final today =
        at != null && AssignmentQuery.dayKey(at) == AssignmentQuery.dayKey(now);
    final pinUrgent = inPinnedSection &&
        !overdue &&
        at != null &&
        (today || at.difference(now) <= const Duration(hours: 48));
    final clock =
        at == null ? '' : _clockFormat.format(AssignmentQuery.beijing(at));
    final railTextColor = pinUrgent
        ? journal.berry
        : at == null
            ? journal.muted
            : overdue
                ? journal.muted
                : today
                    ? journal.berry
                    : journal.ink.withValues(alpha: 0.88);
    final overdueDays = overdue ? now.difference(at!).inDays : 0;
    final overdueLabel = overdueDays > 0 ? '已逾期$overdueDays天' : '已逾期';

    Widget buildRail() {
      if (at == null) {
        return Text(
          '—',
          style: journal.time.copyWith(
            color: railTextColor,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        );
      }
      if (!inPinnedSection) {
        return Text(
          clock,
          style: journal.time.copyWith(
            color: railTextColor,
            fontWeight: FontWeight.w600,
          ),
        );
      }
      final beijingAt = AssignmentQuery.beijing(at);
      final todayDay = AssignmentQuery.dayKey(now);
      final tomorrowDay =
          DateTime(todayDay.year, todayDay.month, todayDay.day + 1);
      final dueDay = AssignmentQuery.dayKey(at);
      final dateLabel = dueDay == todayDay
          ? '今天'
          : dueDay == tomorrowDay
              ? '明天'
              : '${beijingAt.month}/${beijingAt.day}';
      final remaining =
          overdue ? overdueLabel : AssignmentCard.compactRemaining(at, now);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateLabel,
            style: journal.metadata.copyWith(
              color: pinUrgent ? journal.berry : journal.muted,
              fontSize: 11.5,
              height: 1.22,
              fontWeight: pinUrgent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          Text(
            clock,
            style: journal.time.copyWith(
              color: pinUrgent
                  ? journal.berry
                  : overdue
                      ? journal.muted
                      : journal.ink,
              fontWeight: FontWeight.w600,
              height: 1.22,
            ),
          ),
          Text(
            remaining,
            style: journal.metadata.copyWith(
              color: pinUrgent ? journal.berry : journal.muted,
              fontSize: 11,
              height: 1.22,
            ),
          ),
        ],
      );
    }

    final isExam = entry.kind == ManualEntry.kindExam;
    final typeLabel = isExam ? '手动考试' : '手动待办';
    final typePill = isExam
        ? const CourseworkStatusPill(
            label: '手动考试',
            tone: CourseworkPillTone.exam,
          )
        : const CourseworkStatusPill(
            label: '手动待办',
            tone: CourseworkPillTone.neutral,
            icon: Icons.edit_note_rounded,
          );
    final auxiliary = <String>[
      if (entry.location.trim().isNotEmpty) '地点 ${entry.location.trim()}',
      if (entry.remind && at != null && at.isAfter(now)) '提前30分提醒',
      if (countdown && !inPinnedSection && at != null && !overdue)
        DisplayPreferences.remaining(at, now),
      if (at == null) '无截止日期',
    ];

    final inlineActions = !largeText;
    final contentRight =
        contentPadding.resolve(Directionality.of(context)).right;
    final topRightReserve = (inlineActions ? 48.0 : 0.0) +
        (inlineActions && dragHandle != null ? 34.0 : 0.0) +
        ((inlineActions && dragHandle != null) ? 6.0 : 0.0);
    final titlePadding = EdgeInsets.only(
      right: inlineActions
          ? (topRightReserve - contentRight)
              .clamp(0.0, topRightReserve)
              .toDouble()
          : 0.0,
    );

    Widget completeButton() => Semantics(
          container: true,
          button: true,
          label: '标记 ${entry.title} 完成',
          onTap: onToggleDone,
          excludeSemantics: true,
          child: Tooltip(
            message: '标记完成',
            child: IconButton(
              key: ValueKey('complete-manual-${entry.id}'),
              onPressed: onToggleDone,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.radio_button_unchecked_rounded,
                size: 20,
                color: journal.muted,
              ),
            ),
          ),
        );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: titlePadding,
          child: Text(
            entry.title.trim(),
            maxLines: largeText ? null : 2,
            overflow: largeText ? null : TextOverflow.ellipsis,
            style: overdue
                ? journal.entryTitle.copyWith(
                    color: journal.isDark ? journal.muted : journal.ochre,
                  )
                : journal.entryTitle,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (entry.course.trim().isNotEmpty)
              Text(entry.course.trim(), style: journal.metadata),
            typePill,
            if (overdue)
              CourseworkStatusPill(
                label: overdueLabel,
                tone: CourseworkPillTone.overdue,
              ),
          ],
        ),
        if (auxiliary.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (final line in auxiliary) Text(line, style: journal.metadata),
        ],
      ],
    );

    return Padding(
      padding: contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Semantics(
                button: true,
                label: [
                  entry.title,
                  if (entry.course.trim().isNotEmpty) entry.course.trim(),
                  typeLabel,
                  if (overdue) overdueLabel,
                  if (at == null) '无截止日期',
                ].join('，'),
                onTap: onTap,
                excludeSemantics: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    onLongPress: onLongPress,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: compact ? 8.5 : 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: railWidth, child: buildRail()),
                          const SizedBox(width: 10),
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (inlineActions)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      completeButton(),
                      if (dragHandle != null) dragHandle!,
                    ],
                  ),
                ),
            ],
          ),
          if (largeText)
            Padding(
              padding: EdgeInsets.only(
                left: railWidth + 10,
                bottom: 8,
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: ValueKey('complete-manual-${entry.id}'),
                    onPressed: onToggleDone,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      backgroundColor: journal.parchment,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: Icon(
                      Icons.radio_button_unchecked_rounded,
                      size: 17,
                      color: journal.muted,
                    ),
                    label: Text(
                      '标记完成',
                      style: journal.metadata.copyWith(
                        color: journal.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (dragHandle != null) dragHandle!,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
