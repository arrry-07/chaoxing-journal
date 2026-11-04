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
      required this.onTap});
  final Assignment assignment;
  final DateTime now;
  final VoidCallback onTap;
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
    final state =
        !a.isPendingConfirmed && !a.isCompleted ? '提交状态待确认' : a.statusLabel;
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
    return Semantics(
        button: true,
        onTap: onTap,
        label: '${a.title}，${a.courseName}，${urgent ?? state}，$deadline',
        excludeSemantics: true,
        child: SizedBox(
            width: double.infinity,
            child: Card(
                elevation: 0,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: Journal.sheet,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(a.title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      height: 1.25)),
                              if (urgent != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(urgent,
                                        style: TextStyle(
                                            color: color,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600))),
                              const SizedBox(height: 4),
                              Text(a.courseName,
                                  style: const TextStyle(
                                      color: Journal.muted,
                                      fontSize: 14,
                                      height: 1.3)),
                              const SizedBox(height: 4),
                              Text('$deadline · $state',
                                  style: TextStyle(
                                      color: color, fontSize: 14, height: 1.3)),
                            ]))))));
  }
}
