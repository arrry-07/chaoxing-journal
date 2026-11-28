import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../app/journal.dart';
import '../../models/assignment.dart';
import '../../models/study_notebook.dart';
import '../../services/assignment_query.dart';
import '../../services/home_manual_timeline.dart';
import '../../services/local_notification_service.dart';
import 'assignment_card.dart';
import 'coursework_status_pill.dart';
import 'journal_buttons.dart';

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
    this.showFullDeadline = false,
    this.compact = false,
    this.countdown = false,
    this.allowUrgentNightBreakthrough = false,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 14),
    this.bouncePulse = 0,
  });

  final ManualEntry entry;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final VoidCallback? onLongPress;
  final Widget? dragHandle;
  final bool inPinnedSection;
  final bool showFullDeadline;
  final bool compact;
  final bool countdown;
  final bool allowUrgentNightBreakthrough;
  final EdgeInsetsGeometry contentPadding;
  final int bouncePulse;

  static final DateFormat _clockFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final at = entry.at;
    final bucket = HomeManualTimeline.manualBucketAt(entry, now);
    final overdue = bucket == AssignmentDeadlineBucket.overdue;
    final largeText = JournalLayout.isLargeText(context);
    final compactLayout = compact && !largeText;
    final titleStyle = journal.entryTitle.copyWith(
      fontSize: compactLayout ? 14.8 : 16.0,
      height: 1.34,
    );
    final metaStyle = journal.metadata.copyWith(
      color: journal.subtle,
      fontSize: compactLayout ? 12.5 : null,
    );
    final bodyGap = compactLayout ? 2.0 : 4.0;
    final railWidth = AssignmentCard.measureRailWidth(
      context,
      inPinnedSection: inPinnedSection,
      showCountdown: !showFullDeadline && !inPinnedSection && countdown,
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
        ? journal.accent
        : at == null
            ? journal.muted
            : overdue
                ? journal.ink
                : today
                    ? journal.accent
                    : journal.ink;
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
        final within24h = !overdue &&
            at.isAfter(now) &&
            at.difference(now) < const Duration(hours: 24);
        if (!showFullDeadline && countdown && within24h) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                clock,
                style: journal.time.copyWith(
                  color: railTextColor,
                  fontWeight: FontWeight.w600,
                  height: 1.22,
                ),
              ),
              Text(
                AssignmentCard.compactRemaining(at, now),
                style: journal.metadata.copyWith(
                  fontSize: 11,
                  height: 1.22,
                  color: today ? journal.accent : journal.subtle,
                ),
              ),
            ],
          );
        }
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
              color: pinUrgent ? journal.accent : journal.subtle,
              fontSize: 11.5,
              height: 1.22,
              fontWeight: pinUrgent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          Text(
            clock,
            style: journal.time.copyWith(
              color: pinUrgent ? journal.accent : journal.ink,
              fontWeight: FontWeight.w600,
              height: 1.22,
            ),
          ),
          if (remaining != dateLabel)
            Text(
              remaining,
              style: journal.metadata.copyWith(
                color: pinUrgent ? journal.accent : journal.subtle,
                fontSize: 11,
                height: 1.22,
              ),
            ),
        ],
      );
    }

    final isExam = entry.kind == ManualEntry.kindExam;
    final typeLabel = isExam ? '考试' : '待办';
    final typePill = CourseworkStatusPill(
      label: typeLabel,
      tone: isExam ? CourseworkPillTone.exam : CourseworkPillTone.todo,
    );
    const sourcePill = CourseworkStatusPill(
      label: '自己添加',
      tone: CourseworkPillTone.neutral,
    );
    final missedWindow =
        LocalNotificationService.isManualReminderWindowMissed(entry, now: now);
    final quietHoursSkipped =
        LocalNotificationService.isManualReminderQuietHoursSkipped(
      entry,
      now: now,
      allowUrgentNightBreakthrough: allowUrgentNightBreakthrough,
    );
    final reminderLabel = !entry.remind || at == null || !at.isAfter(now)
        ? null
        : missedWindow
            ? '不足30分未排提醒'
            : quietHoursSkipped
                ? '夜间静音时段未排期'
                : null;
    final beijingAt = at == null ? null : AssignmentQuery.beijing(at);
    final crossYear = beijingAt != null &&
        beijingAt.year != AssignmentQuery.beijing(now).year;
    final fullDeadlineLine = beijingAt != null &&
            ((showFullDeadline && !inPinnedSection) ||
                (inPinnedSection && crossYear))
        ? DateFormat(
            crossYear ? 'yyyy年M月d日 HH:mm' : 'M月d日 HH:mm',
          ).format(beijingAt)
        : null;
    final auxiliary = <String>[
      if (fullDeadlineLine != null) fullDeadlineLine,
      if (entry.location.trim().isNotEmpty) '地点 ${entry.location.trim()}',
      if (reminderLabel != null) reminderLabel,
      if (entry.attachments.isNotEmpty) '附件 ${entry.attachments.length}',
      if (at == null) '无截止日期',
    ];

    final inlineActions = !largeText;
    final hasInlineDrag = inlineActions && dragHandle != null;
    final dragRightInset = hasInlineDrag ? 8.0 : 2.0;
    final contentRight =
        contentPadding.resolve(Directionality.of(context)).right;
    final topRightReserve = (inlineActions ? 48.0 : 0.0) +
        (hasInlineDrag ? 44.0 : 0.0) +
        (inlineActions ? (dragRightInset + 4.0) : 0.0);
    final titlePadding = EdgeInsets.only(
      right: inlineActions
          ? (topRightReserve - contentRight)
              .clamp(0.0, topRightReserve)
              .toDouble()
          : 0.0,
    );

    Widget completeButton() => Semantics(
          container: true,
          button: !entry.done,
          label: entry.done ? '${entry.title} 已完成' : '标记 ${entry.title} 完成',
          onTap: entry.done ? null : onToggleDone,
          excludeSemantics: true,
          child: Tooltip(
            message: entry.done ? '已完成' : '标记完成',
            child: JournalPressableScale(
              enabled: !entry.done,
              pressScale: 0.92,
              child: IconButton(
                key: ValueKey('complete-manual-${entry.id}'),
                onPressed: entry.done ? null : onToggleDone,
                constraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
                padding: EdgeInsets.zero,
                icon: Icon(
                  entry.done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: entry.done ? journal.accent : journal.muted,
                ),
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
            maxLines: largeText ? null : (compactLayout ? 1 : 2),
            overflow: largeText ? null : TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        SizedBox(height: bodyGap),
        Wrap(
          spacing: 6,
          runSpacing: compactLayout ? 2 : 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (entry.course.trim().isNotEmpty)
              Text(entry.course.trim(), style: metaStyle),
            typePill,
            sourcePill,
            if (overdue)
              CourseworkStatusPill(
                label: overdueLabel,
                tone: CourseworkPillTone.overdue,
              ),
          ],
        ),
        if (auxiliary.isNotEmpty) ...[
          SizedBox(height: bodyGap),
          Text(
            auxiliary.join(' · '),
            maxLines: largeText ? null : 2,
            overflow: largeText ? null : TextOverflow.ellipsis,
            style: metaStyle,
          ),
        ],
        if (entry.note.trim().isNotEmpty)
          Container(
            margin: EdgeInsets.only(top: compactLayout ? 2 : 5),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
            decoration: BoxDecoration(
              color: Color.lerp(
                journal.sheet,
                journal.parchment,
                journal.isDark ? 0.45 : 0.55,
              ),
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(6)),
              border: Border(
                left: BorderSide(color: journal.ruleStrong, width: 2.0),
              ),
            ),
            child: Text(
              entry.note.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: journal.metadata.copyWith(
                color: journal.subtle,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
      ],
    );

    return JournalMicroBounce(
      pulse: bouncePulse,
      child: Stack(
        children: [
          Padding(
            padding: contentPadding,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: inlineActions ? 48 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: [
                      entry.title,
                      if (entry.course.trim().isNotEmpty) entry.course.trim(),
                      typeLabel,
                      if (clock.isNotEmpty) clock,
                      if (reminderLabel != null) reminderLabel,
                      if (entry.attachments.isNotEmpty)
                        '有${entry.attachments.length}个附件',
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
                            vertical: compact ? 5 : 12,
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
                          JournalPressableScale(
                            enabled: !entry.done,
                            pressScale: 0.92,
                            child: OutlinedButton.icon(
                              key: ValueKey('complete-manual-${entry.id}'),
                              onPressed: entry.done ? null : onToggleDone,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                backgroundColor: journal.parchment,
                                disabledBackgroundColor: journal.parchment,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              icon: Icon(
                                entry.done
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 17,
                                color:
                                    entry.done ? journal.accent : journal.muted,
                              ),
                              label: Text(
                                entry.done ? '已完成' : '标记完成',
                                style: journal.metadata.copyWith(
                                  color:
                                      entry.done ? journal.accent : journal.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (dragHandle != null) dragHandle!,
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (inlineActions)
            Positioned(
              top: compact ? 0 : 2,
              right: dragRightInset,
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
    );
  }
}
