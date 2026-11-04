import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/journal.dart';
import '../models/assignment.dart';
import '../models/sync_report.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import '../services/home_sync_presentation.dart';
import 'widgets/assignment_card.dart';

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
  final expanded = <String, bool>{};
  bool allOverdue = false;
  AssignmentStore get store => widget.store;
  Future<void> act(HomeSyncAction action) async {
    switch (action) {
      case HomeSyncAction.read:
      case HomeSyncAction.retry:
        await store.syncAssignments();
      case HomeSyncAction.login:
        if (mounted) {
          await context.push('/login?reauth=1');
        }
      case HomeSyncAction.verify:
        try {
          if (await store.chaoxingClient.verifyInBrowser()) {
            await store.syncAssignments();
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('验证页面未能打开，请到同步详情重试')));
          }
        }
      case HomeSyncAction.settings:
        if (mounted) {
          await context.push('/reminders');
        }
      case HomeSyncAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now(), items = store.visibleAssignments;
        final groups = AssignmentQuery.home(items, now, {});
        final sync = HomeSyncPresentation.from(store.syncReport,
            loading: store.isLoading,
            hasCache: items.isNotEmpty,
            now: now,
            successAt: store.lastSyncAt,
            serviceWarning: store.error != null &&
                store.syncReport.phase == SyncPhase.success);
        Widget card(Assignment a) => AssignmentCard(
            key: ValueKey('assignment-${a.id}'),
            assignment: a,
            now: now,
            onTap: () =>
                context.push('/assignments/${Uri.encodeComponent(a.id)}'));
        List<Widget> timeline(List<Assignment> list) {
          DateTime? previous;
          return [
            for (final a in list) ...[
              if (a.deadlineAt != null &&
                  a.deadlineTrusted &&
                  !a.deadlineReadFailed &&
                  previous != AssignmentQuery.dayKey(a.deadlineAt!))
                dayHeading(
                    previous = AssignmentQuery.dayKey(a.deadlineAt!), now),
              card(a),
            ]
          ];
        }

        Widget heading(String label, int count) => Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Text('$label  $count',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)));
        Widget group(
            String id, String label, List<Assignment> list, bool defaultOpen) {
          return Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                  key: PageStorageKey('home-$id'),
                  initiallyExpanded: expanded[id] ?? defaultOpen,
                  onExpansionChanged: (value) => expanded[id] = value,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  title: Text('$label  ${list.length}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  children: timeline(list)));
        }

        final noUrgent = groups.near.isEmpty && groups.overdue.isEmpty;
        return RefreshIndicator(
            onRefresh: store.syncAssignments,
            child: ListView(
                key: const PageStorageKey('home-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                children: [
                  JournalHeading('课业手记',
                      eyebrow: 'CAMPUS JOURNAL   /   01',
                      bookTitle: true,
                      trailing: IconButton(
                          tooltip: '刷新作业',
                          onPressed: store.isLoading ||
                                  store.syncReport.phase == SyncPhase.running
                              ? null
                              : store.syncAssignments,
                          icon: const Icon(Icons.sync_rounded))),
                  const SizedBox(height: 12),
                  Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(sync.summary,
                            style: const TextStyle(
                                color: Journal.muted, fontSize: 14)),
                        if (sync.actionLabel != null)
                          TextButton(
                              onPressed: () => act(sync.action),
                              child: Text(sync.actionLabel!)),
                        TextButton(
                            onPressed: () => context.push('/sync'),
                            child: const Text('同步详情')),
                      ]),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('待办作业',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    if (noUrgent && groups.noDeadline.isNotEmpty)
                      Text('近期没有明确截止，另有 ${groups.noDeadline.length} 份未设置截止时间',
                          style: const TextStyle(
                              color: Journal.muted, fontSize: 14)),
                    if (noUrgent &&
                        groups.noDeadline.isEmpty &&
                        groups.uncertain.isNotEmpty)
                      Text('有 ${groups.uncertain.length} 份作业需要确认',
                          style: const TextStyle(
                              color: Journal.muted, fontSize: 14)),
                    if (groups.overdue.isNotEmpty) ...[
                      heading('已逾期', groups.overdue.length),
                      ...timeline(groups.overdue
                          .take(allOverdue ? groups.overdue.length : 3)
                          .toList()),
                      if (groups.overdue.length > 3)
                        TextButton(
                            onPressed: () =>
                                setState(() => allOverdue = !allOverdue),
                            child: Text(allOverdue
                                ? '收起逾期作业'
                                : '查看全部 ${groups.overdue.length} 份逾期作业'))
                    ],
                    if (groups.near.isNotEmpty) ...[
                      heading('近期截止', groups.near.length),
                      ...timeline(groups.near)
                    ],
                    if (groups.noDeadline.isNotEmpty)
                      group('undated', '未设置截止时间', groups.noDeadline, noUrgent),
                    if (groups.uncertain.isNotEmpty)
                      group('uncertain', '需要确认', groups.uncertain,
                          noUrgent && groups.noDeadline.isEmpty),
                    if (groups.far.isNotEmpty)
                      group(
                          'far',
                          '30天以后',
                          groups.far,
                          noUrgent &&
                              groups.noDeadline.isEmpty &&
                              groups.uncertain.isEmpty),
                  ] else if (store.assignments.isNotEmpty) ...[
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('本机有已完成、已隐藏、未关注或历史来源的记录，当前首页未显示。')),
                    TextButton(
                        onPressed: () => context.push('/records'),
                        child: const Text('查看全部本地记录')),
                    TextButton(
                        onPressed: () => context.push('/courses'),
                        child: const Text('管理课程')),
                  ] else
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(store.isLoading ||
                                store.syncReport.phase == SyncPhase.running
                            ? '正在读取课程与作业，请稍候。'
                            : store.syncReport.phase == SyncPhase.success
                                ? '暂无作业，已读取的正式作业会显示在这里。'
                                : store.syncReport.phase == SyncPhase.failed
                                    ? '本次尚未取得作业，请使用上方操作继续。'
                                    : '首次读取后，会在这里整理需要处理的作业。')),
                ]));
      });

  Widget dayHeading(DateTime day, DateTime now) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            '${day.year == AssignmentQuery.beijing(now).year ? '' : '${day.year}年'}'
            '${day.month}月${day.day}日  周${'一二三四五六日'[day.weekday - 1]}',
            style: Journal.metadata.copyWith(
                color: Journal.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Divider(height: 1),
      ]));
}
