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
    final state = !a.isPendingConfirmed && !a.isCompleted
        ? '提交状态待确认'
        : a.deadlineTrusted &&
                a.isPendingConfirmed &&
                d != null &&
                d.isBefore(now)
            ? '已逾期 · ${a.statusLabel}'
            : a.statusLabel;
    final deadline = !a.deadlineTrusted && d != null
        ? '截止待确认 · 历史时间 ${DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(d))}'
        : d == null
            ? a.deadlineLabel
            : DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(d));
    return Semantics(
        button: true,
        onTap: onTap,
        label: '${a.title}，${a.courseName}，$state，$deadline',
        excludeSemantics: true,
        child: Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Journal.rule)),
            child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title,
                              style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                              '${a.courseName}${a.clazzId == null ? '' : ' · 班级 ${a.clazzId}'}',
                              style: const TextStyle(color: Journal.muted)),
                          const SizedBox(height: 6),
                          Text(state,
                              style: const TextStyle(color: Journal.berry)),
                          Text(deadline),
                          if (a.deadlineReadFailed && d != null)
                            Text(a.deadlineLabel),
                        ])))));
  }
}
