import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../models/assignment.dart';
import '../services/assignment_store.dart';

class AssignmentListScreen extends StatelessWidget {
  const AssignmentListScreen({super.key, required this.store});
  final AssignmentStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final now = DateTime.now();
          final sorted = [...store.visibleAssignments]
            ..sort(Assignment.compareByDeadline);
          final next = sorted
              .where((a) => a.deadlineAt?.isBefore(now) == false)
              .firstOrNull;
          final groups = <DateTime?, List<Assignment>>{};
          for (final item in sorted) {
            final date = item.deadlineAt;
            groups
                .putIfAbsent(
                    date == null ? null : DateUtils.dateOnly(date), () => [])
                .add(item);
          }
          final labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
          return RefreshIndicator(
            onRefresh: store.syncAssignments,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: JournalHeading(
                        '课业手记',
                        eyebrow: 'CAMPUS JOURNAL   /   01',
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新作业',
                      onPressed: store.isLoading ? null : store.syncAssignments,
                      icon: const Icon(Icons.sync_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                    store.lastSyncAt == null
                        ? '尚无成功同步记录'
                        : '最近成功同步 ${DateFormat('M月d日 HH:mm').format(store.lastSyncAt!)}',
                    style: const TextStyle(color: Journal.muted)),
                const SizedBox(height: 12),
                if (store.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      store.error!,
                      style: const TextStyle(color: Journal.berry),
                    ),
                  ),
                if (next != null)
                  InkWell(
                    onTap: () => context.push(
                      '/assignments/${Uri.encodeComponent(next.id)}',
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: Journal.sage,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bookmark_border_rounded, size: 18),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '下一份要交',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            next.title,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${next.courseName}　·　${DateFormat('M月d日 HH:mm').format(next.deadlineAt!)}',
                          ),
                          if (next.deadlineReadFailed) Text(next.deadlineLabel),
                        ],
                      ),
                    ),
                  ),
                if (sorted.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Text('手帐里暂时没有待交作业。下拉可以同步。'),
                  ),
                for (final group in groups.entries) ...[
                  const SizedBox(height: 22),
                  Text(
                    group.key == null
                        ? '暂无截止时间'
                        : '${DateFormat(group.key!.year == now.year ? 'M月d日' : 'yyyy年M月d日').format(group.key!)}　${labels[group.key!.weekday - 1]}',
                    style: Journal.section,
                  ),
                  const Divider(),
                  for (final item in group.value)
                    InkWell(
                      key: ValueKey('assignment-${item.id}'),
                      onTap: () => context.push(
                        '/assignments/${Uri.encodeComponent(item.id)}',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.deadlineAt != null)
                              Text(
                                DateFormat('HH:mm').format(item.deadlineAt!),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 17,
                                  color: Journal.ink,
                                ),
                              ),
                            if (item.deadlineAt != null)
                              const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.courseName,
                                    style:
                                        const TextStyle(color: Journal.muted),
                                  ),
                                  if (item.status == 'returned' ||
                                      item.status == 'unknown')
                                    Text(item.statusLabel),
                                  if (item.deadlineReadFailed)
                                    Text(item.deadlineLabel),
                                  if (item.isOverdue ||
                                      DateUtils.isSameDay(now, item.deadlineAt))
                                    Text(
                                      item.isOverdue ? '已逾期' : '今天截止',
                                      style: const TextStyle(
                                        color: Journal.berry,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      );
}
