import '../../models/display_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/journal.dart';
import '../../models/assignment.dart';
import '../../services/assignment_query.dart';

class AssignmentCard extends StatelessWidget {
  const AssignmentCard(
      {super.key,
      required this.assignment,
      required this.now,
      required this.onTap,
      this.onOpenAssignment,
      this.opening = false,
      this.compact = false,
      this.countdown = false,
      this.showFullDeadline = true});
  final Assignment assignment;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onOpenAssignment;
  final bool opening;
  final bool showFullDeadline;
  final bool compact, countdown;
  @override
  Widget build(BuildContext context) {
    final a = assignment, d = a.deadlineAt;
    final overdue = a.isPendingConfirmed &&
        a.deadlineTrusted &&
        !a.deadlineReadFailed &&
        d != null &&
        d.isBefore(now);
    final today =
        d != null && AssignmentQuery.dayKey(d) == AssignmentQuery.dayKey(now);
    final urgent = overdue
        ? '已逾期${now.difference(d).inDays > 0 ? '${now.difference(d).inDays}天' : ''}'
        : a.isPendingConfirmed &&
                a.deadlineTrusted &&
                !a.deadlineReadFailed &&
                today
            ? '今天截止'
            : null;
    final state = a.statusLabel;
    final deadline = a.deadlineReadFailed
        ? d == null
            ? a.deadlineLabel
            : '截止 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(d))} · ${a.deadlineLabel}'
        : !a.deadlineTrusted
            ? '截止待确认'
            : d == null
                ? '未设置截止时间'
                : countdown
                    ? DisplayPreferences.remaining(d, now)
                    : '截止 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(d))}';
    final color = urgent != null ? Journal.berry : Journal.ink;
    final hasTime = d != null && a.deadlineTrusted && !a.deadlineReadFailed;
    final clock =
        hasTime ? DateFormat('HH:mm').format(AssignmentQuery.beijing(d)) : '—';
    // Measure at the user's text scale: a fixed rail clips times at 2× size.
    final measure = TextPainter(
        text: const TextSpan(text: '00:00', style: Journal.time),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final railWidth = measure.width.ceilToDouble() + 4;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    measure.dispose();
    final metadata = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(state, style: Journal.metadata.copyWith(color: Journal.ink)),
        if (urgent != null)
          Text(urgent,
              style: Journal.metadata
                  .copyWith(color: color, fontWeight: FontWeight.w600)),
        if (showFullDeadline || countdown || !hasTime)
          Text(deadline, style: Journal.metadata),
      ],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
          button: true,
          onTap: onTap,
          label:
              '${a.title}，${a.courseName}，$state，${urgent == null ? '' : '$urgent，'}$deadline',
          excludeSemantics: true,
          child: SizedBox(
              width: double.infinity,
              child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                          padding: EdgeInsets.only(
                              top: compact ? 4 : 12,
                              bottom: onOpenAssignment == null
                                  ? (compact ? 4 : 12)
                                  : 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: railWidth,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(clock, style: Journal.time),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    Text(a.title, style: Journal.entryTitle),
                                    const SizedBox(height: 4),
                                    Text(a.courseName, style: Journal.metadata),
                                    if (onOpenAssignment == null) ...[
                                      const SizedBox(height: 4),
                                      metadata,
                                    ],
                                  ])),
                            ],
                          )))))),
      if (onOpenAssignment != null)
        Padding(
          padding:
              EdgeInsets.only(left: largeText ? 0 : railWidth + 12, bottom: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Padding(
                padding: EdgeInsets.only(left: largeText ? railWidth + 12 : 0),
                child: ExcludeSemantics(
                    child: InkWell(onTap: onTap, child: metadata)),
              ),
              TextButton.icon(
                onPressed: opening ? null : onOpenAssignment,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.launch, size: 18),
                label: Text(opening ? '正在打开…' : '去学习通完成'),
              ),
            ],
          ),
        ),
    ]);
  }
}
