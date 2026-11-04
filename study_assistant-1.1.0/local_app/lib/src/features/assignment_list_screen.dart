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
            showFullDeadline: false,
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

        Widget note(String label) => Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Text(label, style: Journal.metadata));
        return ListView(
            key: const PageStorageKey('home-list'),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
            children: [
              JournalHeading('课业手记',
                  eyebrow: 'CAMPUS JOURNAL   /   01',
                  bookTitle: true,
                  trailingWidth: 96,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: '刷新作业',
                        onPressed: store.isLoading ||
                                store.syncReport.phase == SyncPhase.running
                            ? null
                            : () => act(sync.action == HomeSyncAction.login ||
                                    sync.action == HomeSyncAction.verify
                                ? sync.action
                                : HomeSyncAction.retry),
                        icon: const Icon(Icons.sync_rounded)),
                    IconButton(
                        tooltip: '同步详情',
                        onPressed: () => context.push('/sync'),
                        icon: const Icon(Icons.more_horiz_rounded)),
                  ])),
              const SizedBox(height: 20),
              if (items.isNotEmpty) ...[
                ...timeline([...groups.near, ...groups.far]),
                if (groups.noDeadline.isNotEmpty) ...[
                  note('未设置截止时间'),
                  ...timeline(groups.noDeadline),
                ],
                if (groups.uncertain.isNotEmpty) ...[
                  note('需要确认'),
                  ...timeline(groups.uncertain),
                ],
                ...timeline(groups.overdue),
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
                                ? '本次尚未取得作业，请点击右上角刷新继续。'
                                : '点击右上角刷新，开始整理这本课业手记。')),
            ]);
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
