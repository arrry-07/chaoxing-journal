import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/journal.dart';
import '../models/assignment.dart';
import '../models/sync_report.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import '../services/home_sync_presentation.dart';
import '../services/assignment_web_link.dart';
import '../services/external_link_service.dart';
import 'widgets/assignment_card.dart';

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
  bool _refreshing = false;
  final _openingAssignments = <String>{};
  AssignmentStore get store => widget.store;

  Future<void> openAssignment(String id) async {
    if (_openingAssignments.contains(id)) return;
    final assignment = store.findAssignment(id);
    final url =
        assignment == null ? null : AssignmentWebLink.validatedUrl(assignment);
    if (url == null) {
      feedback('作业链接暂不可用，请刷新作业信息');
      return;
    }
    setState(() => _openingAssignments.add(id));
    store.beginAssignmentVisit(id);
    final target = await ExternalLinkService().openAssignment(url);
    if (target == AssignmentLaunchTarget.unavailable) {
      store.cancelAssignmentVisit(id);
    }
    if (!mounted) return;
    setState(() => _openingAssignments.remove(id));
    feedback(target.message);
  }

  void feedback(String message, {bool details = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Journal.ink,
          content: Text(message,
              style: Journal.metadata.copyWith(color: Journal.sheet)),
          action: details
              ? SnackBarAction(
                  label: '查看详情',
                  textColor: Journal.sheet,
                  onPressed: () {
                    if (mounted) context.push('/sync');
                  })
              : null));
  }

  Future<bool> act(HomeSyncAction action) async {
    switch (action) {
      case HomeSyncAction.read:
      case HomeSyncAction.retry:
        await store.syncAssignments();
        return true;
      case HomeSyncAction.login:
        if (mounted) {
          feedback('需要重新登录，登录后将继续读取作业');
          await context.push('/login?reauth=1');
        }
        return false;
      case HomeSyncAction.verify:
        try {
          feedback('请先完成安全验证，完成后将继续刷新');
          if (await store.chaoxingClient.verifyInBrowser()) {
            await store.syncAssignments();
            return true;
          }
          feedback('验证尚未完成，请在同步详情继续', details: true);
        } catch (_) {
          feedback('验证页面未能打开，请到同步详情重试', details: true);
        }
        return false;
      case HomeSyncAction.settings:
        if (mounted) {
          await context.push('/reminders');
        }
        return false;
      case HomeSyncAction.none:
        return false;
    }
  }

  Future<void> refresh(HomeSyncAction action) async {
    // The store queues operations; give feedback and reject repeated taps even
    // before it emits its first loading notification.
    if (_refreshing ||
        store.isLoading ||
        store.syncReport.phase == SyncPhase.running) {
      return;
    }
    setState(() => _refreshing = true);
    final before = store.syncReport;
    try {
      final attempted = await act(action);
      if (!mounted || !attempted) return;
      final report = store.syncReport;
      if (identical(report, before) ||
          report.phase == SyncPhase.idle ||
          report.phase == SyncPhase.running) {
        feedback('刷新未完成，请查看同步详情', details: true);
      } else if (report.phase == SyncPhase.success) {
        feedback(store.error == null ? '作业已更新' : '作业已更新，本机服务需要处理',
            details: store.error != null);
      } else if (report.phase == SyncPhase.partial) {
        final detailOnly = report.issues.isNotEmpty &&
            report.issues.every((issue) => issue.stage == 'detail');
        feedback(detailOnly ? '作业已更新，部分截止时间待确认' : report.summary,
            details: true);
      } else {
        feedback(store.assignments.isEmpty ? '刷新失败，请查看同步详情' : '更新失败，已保留上次记录',
            details: true);
      }
    } catch (_) {
      feedback('刷新未完成，请查看同步详情', details: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final busy = _refreshing ||
            store.isLoading ||
            store.syncReport.phase == SyncPhase.running;
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
            onOpenAssignment: AssignmentWebLink.validatedUrl(a) == null
                ? null
                : () => openAssignment(a.id),
            opening: _openingAssignments.contains(a.id),
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
                        onPressed: busy
                            ? null
                            : () => refresh(
                                sync.action == HomeSyncAction.login ||
                                        sync.action == HomeSyncAction.verify
                                    ? sync.action
                                    : HomeSyncAction.retry),
                        icon: busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Journal.ink))
                            : const Icon(Icons.sync_rounded)),
                    IconButton(
                        tooltip: '同步详情',
                        onPressed: () => context.push('/sync'),
                        icon: const Icon(Icons.more_horiz_rounded)),
                  ])),
              const SizedBox(height: 20),
              if (busy)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                        liveRegion: true,
                        child: const Text('正在刷新作业…', style: Journal.metadata))),
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
