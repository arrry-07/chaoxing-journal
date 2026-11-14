import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/journal.dart';
import '../models/assignment.dart';
import '../models/assignment_sync_progress.dart';
import '../models/home_filters.dart';
import '../models/sync_report.dart';
import '../models/personal_workspace.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import '../services/home_sync_presentation.dart';
import '../services/assignment_web_link.dart';
import '../services/external_link_service.dart';
import 'widgets/assignment_card.dart';

/// A calendar recovery view. It is carried in the route query, never in
/// [HomeFilters], so opening or leaving it cannot rewrite saved preferences.
enum AssignmentRecoveryScope {
  noDeadline('noDeadline', '无截止日期'),
  deadlinePending('deadlinePending', '截止待确认');

  const AssignmentRecoveryScope(this.queryValue, this.label);

  static const queryParameter = 'scope';

  final String queryValue;
  final String label;

  static AssignmentRecoveryScope? fromQueryValue(String? value) {
    for (final scope in values) {
      if (scope.queryValue == value) return scope;
    }
    return null;
  }

  /// Retained historical dates remain visible here even though the trusted
  /// calendar grid excludes them.
  bool matches(Assignment assignment, DateTime now) => switch (this) {
        noDeadline => assignment.deadlineBucketAt(now) ==
            AssignmentDeadlineBucket.confirmedNoDeadline,
        deadlinePending => assignment.deadlineBucketAt(now) ==
            AssignmentDeadlineBucket.unconfirmed,
      };
}

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
  // Keep both the label and icon button inside a narrow screen while allowing
  // a larger tap target and readable text.
  static const _compactFilterTextThreshold = 18.0;

  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  bool _refreshing = false;
  String? get _courseKey => store.homeFilters.courseKey;
  String get _query => store.homeFilters.query;
  AssignmentDeadlineFilter get _deadlineFilter => store.homeFilters.deadline;
  HomeSortOrder get _sortOrder => store.homeFilters.sortOrder;
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

  AssignmentRecoveryScope? _recoveryScope(BuildContext context) {
    if (GoRouter.maybeOf(context) == null) return null;
    try {
      final value = GoRouterState.of(context)
          .uri
          .queryParameters[AssignmentRecoveryScope.queryParameter];
      return AssignmentRecoveryScope.fromQueryValue(value);
    } on GoError {
      // The screen is also embedded in plain test hosts without a page state.
      return null;
    }
  }

  void _exitRecoveryScope(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      context.go('/assignments');
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final busy = _refreshing ||
            store.isLoading ||
            store.syncReport.phase == SyncPhase.running;
        final recoveryScope = _recoveryScope(context);
        final displayAssignments = store.homeDisplayAssignments;
        final options = <String, String>{
          for (final a in displayAssignments)
            if (a.courseKey case final key?) key: a.courseName
        };
        if (_courseKey != null && !options.containsKey(_courseKey)) {
          options[_courseKey!] = '已选课程（当前无可显示作业）';
        }
        final now = DateTime.now();
        // Recovery views are route-scoped. They deliberately bypass the saved
        // query/course/deadline filters without ever writing them back.
        final items = recoveryScope == null
            ? AssignmentQuery.filterHome(
                displayAssignments,
                query: _query,
                courseKey: _courseKey,
                deadline: _deadlineFilter,
                now: now,
              )
            : displayAssignments
                .where((assignment) => recoveryScope.matches(assignment, now))
                .toList();
        final sortOrder = _sortOrder;
        final sortedItems = sortOrder == HomeSortOrder.grouped
            ? items
            : AssignmentQuery.sortHome(items, sortOrder, now: now);
        final groups = sortOrder == HomeSortOrder.grouped
            ? AssignmentQuery.home(items, now, {})
            : null;
        final sync = HomeSyncPresentation.from(store.syncReport,
            loading: store.isLoading,
            hasCache: displayAssignments.isNotEmpty,
            now: now,
            successAt: store.lastSyncAt,
            serviceWarning: store.error != null &&
                store.syncReport.phase == SyncPhase.success);
        final freshness = _freshnessLabel(sync.summary,
            store.syncReport.lastDataSuccessAt ?? store.lastSyncAt, now);
        final filtersActive = _query.trim().isNotEmpty ||
            _courseKey != null ||
            _deadlineFilter != AssignmentDeadlineFilter.all;
        final compactFilterAction = MediaQuery.textScalerOf(context).scale(14) >
            _compactFilterTextThreshold;
        Widget card(Assignment a) => AssignmentCard(
            key: ValueKey('assignment-${a.id}'),
            assignment: a,
            now: now,
            showFullDeadline: false,
            compact: store.display.compact,
            countdown: store.display.countdown,
            deadlinePending: store.isHomeDeadlinePending(a.id),
            previewOnly: store.isHomeAssignmentPreviewOnly(a.id),
            previewSaving:
                store.homeSyncProgress?.stage == AssignmentSyncStage.saving,
            onOpenAssignment: AssignmentWebLink.validatedUrl(a) == null
                ? null
                : () => openAssignment(a.id),
            opening: _openingAssignments.contains(a.id),
            onTap: () =>
                context.push('/assignments/${Uri.encodeComponent(a.id)}'));
        Widget filterAction() => compactFilterAction
            ? IconButton(
                tooltip: filtersActive ? '已筛选，打开搜索与期限筛选' : '搜索与筛选',
                onPressed: () => _openFilters(options),
                icon: Badge(
                    isLabelVisible: filtersActive,
                    child: const Icon(Icons.filter_list)),
              )
            : TextButton.icon(
                onPressed: () => _openFilters(options),
                icon: const Icon(Icons.filter_list, size: 18),
                label: Text(filtersActive ? '已筛选' : '搜索与筛选'),
              );
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
            key: PageStorageKey(recoveryScope == null
                ? 'home-list'
                : 'home-recovery-${recoveryScope.queryValue}'),
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
              if (recoveryScope != null) ...[
                _recoveryHeader(context, recoveryScope, items.length),
                const SizedBox(height: 12),
              ],
              Builder(builder: (context) {
                final today = PersonalWorkspace.dayKey(now);
                final plans =
                    store.personal.plans.where((p) => p.day == today).toList();
                final minutes = plans
                    .where((p) => !p.done)
                    .fold<int>(0, (v, p) => v + p.minutes);
                return Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.checklist),
                        title: const Text('今日计划'),
                        subtitle: Text(plans.isEmpty
                            ? '选两三份作业，安排今天要做的事'
                            : '${plans.where((p) => p.done).length}/${plans.length} 项已勾选 · 预计剩余 $minutes 分钟'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/plan')));
              }),
              const Divider(height: 24),
              Row(children: [
                const Icon(Icons.schedule, size: 16, color: Journal.muted),
                const SizedBox(width: 6),
                Expanded(
                    child: Semantics(
                  liveRegion: true,
                  label: '数据新鲜度',
                  child: Row(children: [
                    Flexible(child: Text(freshness, style: Journal.metadata)),
                    if (sync.showCached) ...[
                      const SizedBox(width: 6),
                      const Text('上次记录', style: Journal.metadata),
                    ],
                  ]),
                )),
                if (recoveryScope == null) filterAction(),
              ]),
              if (recoveryScope == null && sortOrder != HomeSortOrder.grouped)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort, size: 16, color: Journal.muted),
                        const SizedBox(width: 6),
                        Text(
                          _sortLabel(sortOrder),
                          key: const ValueKey('current-home-sort'),
                          style: Journal.metadata,
                        ),
                      ],
                    ),
                  ),
                ),
              if (busy)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                        liveRegion: true,
                        child: Text(_syncProgressLabel(store),
                            style: Journal.metadata))),
              if (recoveryScope == null &&
                  _courseKey != null &&
                  !displayAssignments.any((a) => a.courseKey == _courseKey))
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('已保留课程筛选，当前没有可显示的作业。可在搜索与筛选中更改条件。',
                        style: Journal.metadata)),
              if (sortedItems.isNotEmpty) ...[
                if (groups != null) ...[
                  ...timeline([...groups.near, ...groups.far]),
                  if (groups.noDeadline.isNotEmpty) ...[
                    note('未设置截止时间'),
                    ...timeline(groups.noDeadline),
                  ],
                  if (groups.uncertain.isNotEmpty) ...[
                    note('状态或截止待确认'),
                    ...timeline(groups.uncertain),
                  ],
                  ...timeline(groups.overdue),
                ] else
                  ...timeline(sortedItems),
              ] else if (recoveryScope != null) ...[
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('这个临时范围当前没有作业，可能已随同步更新。',
                        style: Journal.metadata)),
              ] else if (filtersActive &&
                  (displayAssignments.isNotEmpty ||
                      store.assignments.isNotEmpty)) ...[
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('没有符合搜索或期限条件的作业')),
                TextButton(
                    onPressed: () => _saveFilters(
                          HomeFilters(sortOrder: _sortOrder),
                          store.accountEpoch,
                          store.account,
                        ),
                    child: const Text('清除搜索与期限条件')),
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
            '${day.month}月${day.day}日 周${'一二三四五六日'[day.weekday - 1]}',
            style: Journal.metadata.copyWith(
                color: Journal.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Divider(height: 1),
      ]));

  Widget _recoveryHeader(
          BuildContext context, AssignmentRecoveryScope scope, int count) =>
      Card(
        key: const ValueKey('assignment-recovery-scope'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.filter_alt_outlined,
                    size: 18, color: Journal.muted),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('临时范围 · ${scope.label}',
                        style: Journal.entryTitle)),
              ]),
              const SizedBox(height: 4),
              Text(
                '共 $count 项。不受已保存的搜索、课程和期限筛选影响，返回后原偏好保留。',
                style: Journal.metadata,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _exitRecoveryScope(context),
                  child: const Text('退出临时范围'),
                ),
              ),
            ],
          ),
        ),
      );

  String _deadlineLabel(AssignmentDeadlineFilter filter) => switch (filter) {
        AssignmentDeadlineFilter.all => '全部',
        AssignmentDeadlineFilter.next7Days => '7天内',
        AssignmentDeadlineFilter.next30Days => '30天内',
        AssignmentDeadlineFilter.overdue => '已逾期',
        AssignmentDeadlineFilter.uncertain => '期限待确认',
        AssignmentDeadlineFilter.noDeadline => '无截止日期',
        AssignmentDeadlineFilter.notExpired => '未截止',
      };

  String _sortLabel(HomeSortOrder order) => switch (order) {
        HomeSortOrder.grouped => '默认分组',
        HomeSortOrder.deadlineAsc => '截止时间：近到远',
        HomeSortOrder.deadlineDesc => '截止时间：远到近',
        HomeSortOrder.courseName => '课程名称',
        HomeSortOrder.title => '作业名称',
      };

  String _syncProgressLabel(AssignmentStore store) {
    final progress = store.homeSyncProgress;
    if (progress == null) return '正在刷新作业…';
    if (progress.stage == AssignmentSyncStage.details &&
        progress.attemptedCount > 0) {
      return '${progress.stageLabel}，已处理 ${progress.resolvedCount} 项详情';
    }
    return progress.stageLabel;
  }

  String _freshnessLabel(String summary, DateTime? updatedAt, DateTime now) {
    if (updatedAt != null &&
        now.difference(updatedAt) >= const Duration(hours: 24)) {
      return '$summary · 超过24小时未更新';
    }
    return summary;
  }

  Future<void> _saveFilters(
      HomeFilters filters, int epoch, String? expectedAccount) async {
    if (store.accountEpoch != epoch || store.account != expectedAccount) {
      return;
    }
    final saved = await store.saveHomeFilters(filters, epoch);
    if (!mounted ||
        epoch != store.accountEpoch ||
        store.account != expectedAccount) {
      return;
    }
    if (!saved) feedback('搜索、筛选与排序未能保存，请重试；原偏好已保留');
  }

  Future<void> _openFilters(Map<String, String> courseOptions) async {
    final openingEpoch = store.accountEpoch;
    final openingAccount = store.account;
    final controller = TextEditingController(text: _query);
    var query = _query;
    var courseKey = _courseKey;
    var deadline = _deadlineFilter;
    var sortOrder = _sortOrder;
    final selection = await showModalBottomSheet<_HomeFilterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('搜索、筛选与排序', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: _query.isNotEmpty,
                  onChanged: (value) => setSheetState(() => query = value),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: '搜索作业或课程',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in homeDeadlineFilterChoices)
                      ChoiceChip(
                        key: ValueKey('deadline-${filter.name}'),
                        selected: deadline == filter,
                        onSelected: (_) =>
                            setSheetState(() => deadline = filter),
                        label: Text(_deadlineLabel(filter)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: courseKey ?? '',
                  key: ValueKey(
                      'course-${store.accountEpoch}-${courseKey ?? "all"}'),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '课程筛选'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部课程')),
                    for (final entry in courseOptions.entries)
                      DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                              '${entry.value}${courseOptions.values.where((v) => v == entry.value).length > 1 ? '（${courseOptions.keys.toList().indexOf(entry.key) + 1}班）' : ''}',
                              overflow: TextOverflow.ellipsis))
                  ],
                  onChanged: (value) => setSheetState(
                      () => courseKey = value == '' ? null : value),
                ),
                const SizedBox(height: 16),
                Text('排序', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                RadioGroup<HomeSortOrder>(
                  groupValue: sortOrder,
                  onChanged: (value) {
                    if (value != null) {
                      setSheetState(() => sortOrder = value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final order in HomeSortOrder.values)
                        RadioListTile<HomeSortOrder>(
                          key: ValueKey('sort-${order.name}'),
                          value: order,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(_sortLabel(order)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                OverflowBar(
                    spacing: 8,
                    overflowSpacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setSheetState(() {
                          query = '';
                          courseKey = null;
                          deadline = AssignmentDeadlineFilter.all;
                          controller.clear();
                        }),
                        child: const Text('清空筛选'),
                      ),
                      TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('取消')),
                      FilledButton(
                        onPressed: () => Navigator.pop(
                            sheetContext,
                            _HomeFilterSelection(
                                query: query,
                                courseKey: courseKey,
                                deadline: deadline,
                                sortOrder: sortOrder)),
                        child: const Text('应用'),
                      ),
                    ]),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (!mounted ||
        selection == null ||
        store.accountEpoch != openingEpoch ||
        store.account != openingAccount) {
      return;
    }
    await _saveFilters(
        HomeFilters(
            query: selection.query.trim(),
            courseKey: selection.courseKey,
            deadline: selection.deadline,
            sortOrder: selection.sortOrder),
        openingEpoch,
        openingAccount);
  }
}

class _HomeFilterSelection {
  const _HomeFilterSelection({
    required this.query,
    required this.courseKey,
    required this.deadline,
    required this.sortOrder,
  });

  final String query;
  final String? courseKey;
  final AssignmentDeadlineFilter deadline;
  final HomeSortOrder sortOrder;
}
