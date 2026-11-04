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
      this.showFullDeadline = true});
  final Assignment assignment;
  final DateTime now;
  final VoidCallback onTap;
  final bool showFullDeadline;
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
    measure.dispose();
    return Semantics(
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
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                                  const SizedBox(height: 4),
                                  Text(state,
                                      style: Journal.metadata
                                          .copyWith(color: Journal.ink)),
                                  if (urgent != null)
                                    Text(urgent,
                                        style: Journal.metadata.copyWith(
                                            color: color,
                                            fontWeight: FontWeight.w600)),
                                  if (showFullDeadline || !hasTime)
                                    Text(deadline, style: Journal.metadata),
                                ])),
                          ],
                        ))))));
  }
}
