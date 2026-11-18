import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../models/assignment_change.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';

class AssignmentChangesScreen extends StatelessWidget {
  const AssignmentChangesScreen({super.key, required this.store});
  final AssignmentStore store;

  String _deadline(String raw) {
    final at = DateTime.tryParse(raw);
    return at == null
        ? '未设置截止'
        : DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(at));
  }

  ({String label, IconData icon, Color color}) _meta(
      AssignmentChangeKind kind) {
    return switch (kind) {
      AssignmentChangeKind.published => (
          label: '新增作业',
          icon: Icons.add_circle_outline,
          color: Journal.ink,
        ),
      AssignmentChangeKind.deadline => (
          label: '截止调整',
          icon: Icons.event_outlined,
          color: Journal.berry,
        ),
      AssignmentChangeKind.status => (
          label: '状态变更',
          icon: Icons.task_alt,
          color: Journal.ink,
        ),
    };
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final events = store.changes;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('/profile/records'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回'),
                ),
              ),
              const SizedBox(height: 4),
              const JournalHeading(
                '作业变化',
                eyebrow: 'CAMPUS JOURNAL   /   CHANGES',
              ),
              const SizedBox(height: 8),
              const Text(
                '保留最近200条本机变化。首次完整同步建立基线；读取失败不代表没有作业。',
                style: Journal.metadata,
              ),
              const SizedBox(height: 14),
              if (events.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '暂无变化记录。下次同步后，有新增作业或可信时间、提交状态变化时会显示在这里。',
                      style: Journal.metadata,
                    ),
                  ),
                ),
              for (final event in events)
                Builder(
                  builder: (context) {
                    final meta = _meta(event.kind);
                    final summary = switch (event.kind) {
                      AssignmentChangeKind.published => event.after,
                      AssignmentChangeKind.deadline =>
                        '截止：${_deadline(event.before)} → ${_deadline(event.after)}',
                      AssignmentChangeKind.status =>
                        '${event.before} → ${event.after}',
                    };
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => GoRouter.maybeOf(context)?.push(
                            '/assignments/${Uri.encodeComponent(event.assignmentId)}',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(meta.icon, color: meta.color, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Journal.paper,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Journal.rule,
                                              ),
                                            ),
                                            child: Text(
                                              meta.label,
                                              style: Journal.metadata.copyWith(
                                                fontSize: 12,
                                                color: meta.color,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            DateFormat('M月d日 HH:mm').format(
                                              AssignmentQuery.beijing(event.at),
                                            ),
                                            style: Journal.metadata,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        event.title,
                                        style: Journal.entryTitle,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        event.courseName,
                                        style: Journal.metadata,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        summary,
                                        style: Journal.metadata.copyWith(
                                          color: Journal.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      );
}
