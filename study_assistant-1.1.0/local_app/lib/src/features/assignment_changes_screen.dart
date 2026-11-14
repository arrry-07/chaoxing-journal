import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/assignment_change.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';

class AssignmentChangesScreen extends StatelessWidget {
  const AssignmentChangesScreen({super.key, required this.store});
  final AssignmentStore store;
  String deadline(String raw) {
    final at = DateTime.tryParse(raw);
    return at == null
        ? '未设置截止'
        : DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(at));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final events = store.changes;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回'))),
          Text('作业变化', style: Theme.of(context).textTheme.headlineMedium),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('保留最近200条本机变化。首次完整同步建立基线；读取失败不代表没有作业。')),
          if (events.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('暂无变化记录。下次同步后，有新增作业或可信时间、提交状态变化时会显示在这里。')),
          for (final event in events)
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (event.kind) {
                  AssignmentChangeKind.published => Icons.add_circle_outline,
                  AssignmentChangeKind.deadline => Icons.event_outlined,
                  AssignmentChangeKind.status => Icons.task_alt
                }),
                title: Text(event.title),
                subtitle: Text('${event.courseName}\n${switch (event.kind) {
                  AssignmentChangeKind.published => event.after,
                  AssignmentChangeKind.deadline =>
                    '截止：${deadline(event.before)} → ${deadline(event.after)}',
                  AssignmentChangeKind.status =>
                    '${event.before} → ${event.after}',
                }}\n${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(event.at))}'),
                isThreeLine: true,
                onTap: () => context.push(
                    '/assignments/${Uri.encodeComponent(event.assignmentId)}')),
        ]);
      });
}
