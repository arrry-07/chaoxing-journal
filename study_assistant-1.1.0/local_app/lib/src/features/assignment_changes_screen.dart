import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../models/assignment_change.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_info_popover.dart';

class AssignmentChangesScreen extends StatelessWidget {
  const AssignmentChangesScreen({super.key, required this.store});
  final AssignmentStore store;

  String _deadline(String raw) {
    final at = DateTime.tryParse(raw);
    return at == null
        ? '未设置截止'
        : DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(at));
  }

  ({String label, IconData icon, Color color, Color pillBg}) _meta(
    AssignmentChangeKind kind,
    JournalPalette journal,
  ) {
    return switch (kind) {
      AssignmentChangeKind.published => (
          label: '新增作业',
          icon: Icons.add_circle_outline_rounded,
          color: journal.accent,
          pillBg: journal.sage,
        ),
      AssignmentChangeKind.deadline => (
          label: '截止调整',
          icon: Icons.event_outlined,
          color: journal.berry,
          pillBg: journal.berryBg,
        ),
      AssignmentChangeKind.status => (
          label: '状态变更',
          icon: Icons.task_alt_rounded,
          color: journal.ink,
          pillBg: journal.parchment,
        ),
    };
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final journal = Journal.of(context);
          final events = store.changes;
          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              leading: IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  final router = GoRouter.maybeOf(context);
                  if (router != null && router.canPop()) {
                    router.pop();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    router?.go('/profile/records');
                  }
                },
              ),
              title: const Text('作业变化'),
              actions: const [
                JournalInfoButton(
                  title: '变化记录说明',
                  items: [
                    '保留最近 200 条本机课业变化记录。',
                    '首次完整同步会建立基线；同步读取失败不代表没有作业。',
                  ],
                ),
                SizedBox(width: 4),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                if (events.isEmpty)
                  JournalGroupedCard(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        '暂无变化记录。下次同步后，有新增作业或可信时间、提交状态变化时会显示在这里。',
                        style: journal.metadata,
                      ),
                    ],
                  )
                else
                  JournalGroupedCard(
                    dividerIndent: 52,
                    children: [
                      for (final event in events)
                        _buildEventTile(context, journal, event),
                    ],
                  ),
              ],
            ),
          );
        },
      );

  Widget _buildEventTile(
    BuildContext context,
    JournalPalette journal,
    AssignmentChange event,
  ) {
    final meta = _meta(event.kind, journal);
    final summary = switch (event.kind) {
      AssignmentChangeKind.published => event.after,
      AssignmentChangeKind.deadline =>
        '截止：${_deadline(event.before)} → ${_deadline(event.after)}',
      AssignmentChangeKind.status => '${event.before} → ${event.after}',
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => GoRouter.maybeOf(context)?.push(
          '/assignments/${Uri.encodeComponent(event.assignmentId)}',
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(meta.icon, color: meta.color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: meta.pillBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            meta.label,
                            style: journal.pillLabel.copyWith(
                              fontSize: 12,
                              color: meta.color,
                            ),
                          ),
                        ),
                        Text(
                          DateFormat('M月d日 HH:mm').format(
                            AssignmentQuery.beijing(event.at),
                          ),
                          style: journal.metadata,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(event.title, style: journal.entryTitle),
                    if (event.courseName.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(event.courseName, style: journal.metadata),
                    ],
                    if (summary.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        style: journal.metadata.copyWith(color: journal.ink),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: journal.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
