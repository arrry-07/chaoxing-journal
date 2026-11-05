import 'package:flutter/material.dart';
import '../app/journal.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/assignment_store.dart';

class AssignmentDetailScreen extends StatelessWidget {
  const AssignmentDetailScreen({
    super.key,
    required this.store,
    required this.assignmentId,
  });

  final AssignmentStore store;
  final String assignmentId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final assignment = store.findAssignment(assignmentId);
        if (assignment == null) {
          return Center(
            child: FilledButton.icon(
              onPressed: () => context.go('/assignments'),
              icon: const Icon(Icons.home_outlined),
              label: const Text('返回主页'),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/assignments'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              assignment.courseName,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              assignment.title,
              style: const TextStyle(
                  fontSize: 26,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Journal.ink),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.event_available),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        assignment.deadlineAt == null
                            ? assignment.deadlineLabel
                            : DateFormat(
                                'yyyy年M月d日 HH:mm',
                                'zh_CN',
                              ).format(assignment.deadlineAt!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(assignment.statusLabel),
                      if (!assignment.deadlineTrusted &&
                          assignment.deadlineAt != null)
                        const Text('历史截止时间待确认，不参与日历和提醒'),
                      if (assignment.deadlineRawText != null)
                        Text(assignment.deadlineRawText!),
                      if (assignment.deadlineReadFailed &&
                          assignment.deadlineAt != null)
                        Text(assignment.deadlineLabel),
                      if (assignment.requirementsText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(assignment.requirementsText)
                      ]
                    ]),
              ),
            ),
            const SizedBox(height: 20),
            if (!assignment.isCompleted)
              FilledButton.icon(
                onPressed: () async {
                  await store.updateCompletion(assignment.id, true);
                  if (context.mounted) {
                    context.go('/assignments');
                  }
                },
                icon: const Icon(Icons.visibility_off_outlined),
                label: const Text('在本机隐藏此作业'),
              ),
          ],
        );
      },
    );
  }
}
