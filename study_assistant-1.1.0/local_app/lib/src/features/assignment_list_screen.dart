import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/journal.dart';
import '../models/assignment.dart';
import '../models/sync_report.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import 'widgets/assignment_card.dart';

class AssignmentListScreen extends StatelessWidget {
  const AssignmentListScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now(),
            g = AssignmentQuery.home(
                store.visibleAssignments, DateTime.now(), {});
        Widget card(Assignment a) => AssignmentCard(
            key: ValueKey('assignment-${a.id}'),
            assignment: a,
            now: now,
            onTap: () =>
                context.push('/assignments/${Uri.encodeComponent(a.id)}'));
        Widget folded(String name, List<Assignment> list) => ExpansionTile(
            title: Text('$name（${list.length}）'),
            children: list.map(card).toList());
        return RefreshIndicator(
            onRefresh: store.syncAssignments,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                children: [
                  Row(children: [
                    const Expanded(
                        child: JournalHeading('学习通课业手记',
                            eyebrow: 'CAMPUS JOURNAL   /   01')),
                    IconButton(
                        tooltip: '刷新作业',
                        onPressed:
                            store.isLoading ? null : store.syncAssignments,
                        icon: const Icon(Icons.sync_rounded))
                  ]),
                  const SizedBox(height: 16),
                  Text(store.syncSummary,
                      style: TextStyle(
                          color: store.error == null
                              ? Journal.muted
                              : Journal.berry)),
                  if (store.visibleAssignments.isNotEmpty &&
                      (store.error != null || store.lastSyncAt == null))
                    const Text('显示上次记录'),
                  TextButton(
                      onPressed: () => context.push('/sync'),
                      child: const Text('查看同步详情 / 重试')),
                  if (g.near.isNotEmpty) ...[
                    const Text('下一份要交', style: Journal.section),
                    card(g.near.first)
                  ],
                  const SizedBox(height: 18),
                  const Text('近期待交', style: Journal.section),
                  if (g.near.isEmpty)
                    Text(store.syncReport.phase == SyncPhase.failed &&
                            store.assignments.isNotEmpty
                        ? '本次读取失败，可查看本机记录与待确认作业。'
                        : store.syncReport.lastDataSuccessAt == null &&
                                store.lastSyncAt == null &&
                                store.assignments.isEmpty
                            ? '尚未获取作业，请先同步。'
                            : '未来30天暂无确认待交作业。'),
                  for (final a in g.near.skip(g.near.isEmpty ? 0 : 1)) card(a),
                  if (store.assignments.isNotEmpty &&
                      store.visibleAssignments.isEmpty) ...[
                    const Text('本机有历史、已完成或未关注的记录，当前筛选未显示。'),
                    TextButton(
                        onPressed: () => context.push('/records'),
                        child: const Text('查看全部本地记录')),
                  ],
                  if (g.far.isNotEmpty) folded('更远期待交', g.far),
                  if (g.uncertain.isNotEmpty) folded('截止 / 提交待确认', g.uncertain),
                  if (g.overdue.isNotEmpty) folded('已逾期', g.overdue),
                ]));
      });
}
