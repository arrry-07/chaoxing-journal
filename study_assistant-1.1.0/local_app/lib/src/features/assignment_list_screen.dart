import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/journal.dart';
import '../app/transient_feedback.dart';
import '../local/chaoxing_local_client.dart';
import '../models/assignment.dart';
import '../models/assignment_sync_progress.dart';
import '../models/home_filters.dart';
import '../models/sync_report.dart';
import '../models/personal_workspace.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import '../services/exam_schedule_presentation.dart';
import '../services/home_course_filter.dart';
import '../services/home_sync_presentation.dart';
import '../services/assignment_web_link.dart';
import '../services/external_link_service.dart';
import 'widgets/assignment_card.dart';

/// A calendar recovery view. It is carried in the route query, never in
/// [HomeFilters], so opening or leaving it cannot rewrite saved preferences.
enum AssignmentRecoveryScope {
  noDeadline('noDeadline', '无截止日期'),
  deadlinePending('deadlinePending', '截止时间未知'),
  examUnknown('examUnknown', '考试');

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
  bool matches(Assignment assignment, DateTime now) {
    if (AssignmentQuery.isArchivedPastTerm(assignment, now)) return false;
    if (assignment.isExam) {
      return this == examUnknown &&
          !AssignmentQuery.isExamEnded(assignment, now) &&
          !assignment.isCompleted;
    }
    if (AssignmentQuery.isArchivedClassroomPractice(assignment, now)) {
      return false;
    }
    return switch (this) {
      noDeadline => AssignmentQuery.timelineBucketAt(assignment, now) ==
          AssignmentDeadlineBucket.confirmedNoDeadline,
      examUnknown => false,
      deadlinePending => AssignmentQuery.timelineBucketAt(assignment, now) ==
          AssignmentDeadlineBucket.unconfirmed,
    };
  }
}

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen>
    with WidgetsBindingObserver {
  Timer? _clock;
  final _feedback = TransientFeedbackController();
  late int _feedbackEpoch;
  String? _feedbackAccount;

  void _checkFeedbackAccount() {
    if (_feedbackEpoch != store.accountEpoch ||
        _feedbackAccount != store.account) {
      _feedback.dismiss();
      _feedbackEpoch = store.accountEpoch;
      _feedbackAccount = store.account;
    }
  }

  @override
  void didUpdateWidget(covariant AssignmentListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != store) {
      oldWidget.store.removeListener(_checkFeedbackAccount);
      _feedback.dismiss();
      _feedbackEpoch = store.accountEpoch;
      _feedbackAccount = store.account;
      store.addListener(_checkFeedbackAccount);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _feedbackEpoch = store.accountEpoch;
    _feedbackAccount = store.account;
    store.addListener(_checkFeedbackAccount);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_checkFeedbackAccount);
    _feedback.dispose();
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  bool _refreshing = false;
  String? get _courseKey => store.homeFilters.courseKey;
  String get _query => store.homeFilters.query;
  AssignmentDeadlineFilter get _deadlineFilter => store.homeFilters.deadline;
  HomeSortOrder get _sortOrder =>
      normalizedHomeSort(store.homeFilters.sortOrder);
  AssignmentTypeFilter get _typeFilter =>
      normalizedHomeType(store.homeFilters.type);
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
    _feedback.show(
        context,
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Journal.ink,
          content: Text(message,
              style: Journal.metadata.copyWith(color: Journal.sheet)),
          action: details
              ? SnackBarAction(
                  label: '查看详情',
                  textColor: Journal.sheet,
                  onPressed: () {
                    _feedback.dismiss();
                    if (mounted) context.push('/sync?expand=issues');
                  },
                )
              : null,
        ));
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
        } on VerificationTargetUnavailable {
          feedback('请先刷新作业数据，再完成安全验证', details: true);
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
        final now = DateTime.now();
        final filtersActive = _query.trim().isNotEmpty ||
            _typeFilter != AssignmentTypeFilter.all ||
            _courseKey != null ||
            _deadlineFilter != AssignmentDeadlineFilter.all;
        final catalogAssignments = store.homeCatalogAssignments;
        final examSources = catalogAssignments;
        final displayIndex = store.homeDisplayIndex;
        final displayAssignments = AssignmentQuery.currentDisplay(
            catalogAssignments, now,
            index: displayIndex);
        final options = buildHomeCourseFilterOptions(
          assignments: displayAssignments,
          catalog: store.courses,
          records: [
            for (final group in store.localRecordGroups) ...group.sources,
          ],
          selectedCourseKey: _courseKey,
        );
        // The home list shows unfinished work only; filters intersect the same
        // unfinished catalog so all = homework union exam stays true. Completed
        // and ended history lives in local records and statistics. Recovery
        // views are route-scoped and never write saved preferences back.
        final items = recoveryScope == null
            ? AssignmentQuery.filterHome(
                catalogAssignments,
                query: _query,
                courseKey: _courseKey,
                deadline: _deadlineFilter,
                type: _typeFilter,
                includeHistorical: false,
                index: displayIndex,
                now: now,
              )
            : displayAssignments
                .where((assignment) => recoveryScope.matches(assignment, now))
                .toList();
        final sortOrder = _sortOrder;
        final sortedItems = AssignmentQuery.sortHome(
          items,
          sortOrder,
          now: now,
          sourceRecords: catalogAssignments,
          displayIndex: displayIndex,
        );
        final today = PersonalWorkspace.dayKey(now);
        final plans =
            store.personal.plans.where((p) => p.day == today).toList();
        final sync = HomeSyncPresentation.from(store.syncReport,
            loading: store.isLoading,
            hasCache:
                catalogAssignments.isNotEmpty || displayAssignments.isNotEmpty,
            now: now,
            successAt: store.lastSyncAt,
            serviceWarning: store.error != null &&
                store.syncReport.phase == SyncPhase.success);
        final freshness = _freshnessLabel(sync.summary,
            store.syncReport.lastDataSuccessAt ?? store.lastSyncAt, now);
        final statusText = sync.showCached ? '$freshness · 显示上次记录' : freshness;
        Widget card(Assignment a) => AssignmentCard(
            key: ValueKey('assignment-${a.id}'),
            assignment: a,
            examSources: examSources,
            displayIndex: displayIndex,
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
        List<Widget> timeline(List<Assignment> list) {
          String? previous;
          var overdueTierAnnounced = false;
          final todayDay = AssignmentQuery.dayKey(now);
          final widgets = <Widget>[];
          for (final a in list) {
            final bucket = AssignmentQuery.timelineBucketAt(a, now);
            final isOverdue = bucket == AssignmentDeadlineBucket.overdue;
            var isTodayGroup = false;
            String? key;
            String? heading;
            if (a.isExam) {
              final stamp = ExamSchedulePresentation.build(a,
                      records: examSources, index: displayIndex)
                  .timeline;
              key = stamp?.key;
              heading = stamp?.heading;
              if (!isOverdue &&
                  a.timelineAt != null &&
                  AssignmentQuery.dayKey(a.timelineAt!) == todayDay) {
                isTodayGroup = true;
              }
            } else if (a.timelineAt != null &&
                a.timelineTrusted &&
                !a.deadlineReadFailed) {
              final day = AssignmentQuery.dayKey(a.timelineAt!);
              isTodayGroup = !isOverdue && day == todayDay;
              key = '${day.year}:${day.month}:${day.day}';
              heading = '${day.year}年${day.month}月${day.day}日 '
                  '周${'一二三四五六日'[day.weekday - 1]}';
            }
            if (heading == null && recoveryScope == null) {
              key = 'undated';
              heading = '无日期与待确认';
            }
            final effectiveKey = isOverdue ? 'overdue:$key' : key;
            if (heading != null && effectiveKey != previous) {
              String? tierBadge;
              var tone = _DayHeadingTone.normal;
              if (isOverdue) {
                tone = _DayHeadingTone.overdue;
                if (!overdueTierAnnounced && recoveryScope == null) {
                  tierBadge = '已逾期置底';
                  overdueTierAnnounced = true;
                }
              } else if (key == 'undated') {
                tone = _DayHeadingTone.undated;
              } else if (isTodayGroup) {
                tone = _DayHeadingTone.today;
                tierBadge = '今天';
              }
              widgets.add(dayHeading(
                heading,
                top: widgets.isEmpty ? 10 : 14,
                tone: tone,
                badge: tierBadge,
              ));
            }
            previous = effectiveKey;
            final row = card(a);
            widgets.add(widgets.isEmpty
                ? Padding(padding: const EdgeInsets.only(top: 8), child: row)
                : row);
          }
          return widgets;
        }

        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final syncAction = sync.action == HomeSyncAction.login ||
                sync.action == HomeSyncAction.verify
            ? sync.action
            : HomeSyncAction.retry;

        // Scrolling must never trigger an implicit remote sync; keep explicit
        // refresh on the header button only.
        return ListView(
          key: PageStorageKey(recoveryScope == null
              ? 'home-list'
              : 'home-recovery-${recoveryScope.queryValue}'),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
          children: [
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('课业手记', style: Journal.display),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (plans.isEmpty)
                      IconButton(
                          key: const ValueKey('home-plan-entry'),
                          tooltip: '今日计划',
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: () => context.push('/plan'),
                          icon: const Icon(Icons.checklist_rounded)),
                    IconButton(
                        tooltip: '刷新作业',
                        onPressed: busy ? null : () => refresh(syncAction),
                        icon: busy
                            ? reduceMotion
                                ? const Icon(Icons.hourglass_top_rounded,
                                    size: 20, color: Journal.ink)
                                : const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Journal.ink))
                            : const Icon(Icons.sync_rounded)),
                    IconButton(
                        tooltip: '同步详情',
                        onPressed: () => context.push('/sync'),
                        icon: const Icon(Icons.more_horiz_rounded)),
                  ]),
                ]),
            const SizedBox(height: 8),
            if (recoveryScope != null) ...[
              _recoveryHeader(context, recoveryScope, items.length),
              const SizedBox(height: 12),
            ],
            if (plans.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Journal.sage.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: const ValueKey('home-plan-summary'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => context.push('/plan'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(children: [
                            const Icon(Icons.checklist_rounded,
                                size: 18, color: Journal.ink),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '今日计划 · 已完成${plans.where((p) => p.done).length}/${plans.length}',
                                style: Journal.metadata.copyWith(
                                  color: Journal.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: Journal.muted),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const ValueKey('home-sync-status'),
                onTap: sync.action == HomeSyncAction.none
                    ? null
                    : () => context.push('/sync?expand=issues'),
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Semantics(
                    liveRegion: true,
                    button: sync.action != HomeSyncAction.none,
                    label: statusText,
                    child: Row(children: [
                      Icon(
                        store.syncReport.phase == SyncPhase.failed
                            ? Icons.error_outline_rounded
                            : store.syncReport.phase == SyncPhase.partial
                                ? Icons.info_outline_rounded
                                : Icons.schedule_rounded,
                        size: 15,
                        color: store.syncReport.phase == SyncPhase.failed
                            ? Journal.berry
                            : store.syncReport.phase == SyncPhase.partial
                                ? Journal.ochre
                                : Journal.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                          child: ExcludeSemantics(
                              child:
                                  Text(statusText, style: Journal.metadata))),
                      if (sync.action != HomeSyncAction.none)
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: Journal.muted),
                    ]),
                  ),
                ),
              ),
            ),
            if (recoveryScope == null) ...[
              const SizedBox(height: 8),
              _homeActions(context, options, filtersActive, sortOrder),
              AnimatedSize(
                duration: JournalLayout.motionDuration(context),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: filtersActive
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _activeFilterSummaryBar(options),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
            if (busy)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: reduceMotion
                          ? Container(height: 3, color: Journal.sageBorder)
                          : const LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Journal.parchment,
                              color: Journal.ink,
                            ),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _syncProgressLabel(store),
                        style: Journal.metadata.copyWith(color: Journal.ink),
                      ),
                    ),
                  ],
                ),
              ),
            if (recoveryScope == null &&
                _courseKey != null &&
                !displayAssignments.any((a) => a.courseKey == _courseKey))
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('已保留课程筛选，当前没有可显示的作业。可在搜索与筛选中更改条件。',
                      style: Journal.metadata)),
            if (sortedItems.isNotEmpty) ...[
              ...timeline(sortedItems),
            ] else if (recoveryScope != null) ...[
              _emptyStateCard(
                icon: Icons.event_available_outlined,
                message: '当前范围没有课业',
              ),
            ] else if (filtersActive &&
                (displayAssignments.isNotEmpty ||
                    store.assignments.isNotEmpty)) ...[
              _emptyStateCard(
                icon: Icons.filter_alt_off_outlined,
                message: '没有符合搜索、类型或期限条件的记录',
                actions: [
                  FilledButton.tonal(
                    onPressed: () => _saveFilters(
                      HomeFilters(sortOrder: _sortOrder),
                      store.accountEpoch,
                      store.account,
                    ),
                    child: const Text('清除搜索与筛选条件'),
                  ),
                ],
              ),
            ] else if (store.assignments.isNotEmpty) ...[
              _emptyStateCard(
                icon: Icons.inventory_2_outlined,
                message: '本机有已完成、已结束、已隐藏、未关注、历史课堂练习或非课业来源的记录，可在本地记录查看。',
                actions: [
                  FilledButton.tonal(
                    onPressed: () => context.push('/records'),
                    child: const Text('查看全部本地记录'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push('/courses'),
                    child: const Text('管理课程'),
                  ),
                ],
              ),
            ] else
              _emptyStateCard(
                icon: busy
                    ? Icons.hourglass_top_rounded
                    : store.syncReport.phase == SyncPhase.success
                        ? Icons.task_alt_rounded
                        : Icons.menu_book_rounded,
                message: store.isLoading ||
                        store.syncReport.phase == SyncPhase.running
                    ? '正在读取课程与作业，请稍候。'
                    : store.syncReport.phase == SyncPhase.success
                        ? '暂无待办，已读取的作业、任务与考试会显示在这里。'
                        : store.syncReport.phase == SyncPhase.failed
                            ? '本次尚未取得作业，请点击右上角刷新继续。'
                            : '点击右上角刷新，开始整理这本课业手记。',
              ),
          ],
        );
      });

  Widget _emptyStateCard({
    required IconData icon,
    required String message,
    List<Widget> actions = const [],
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Journal.parchment,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: Journal.muted),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Journal.metadata.copyWith(
                color: Journal.ink,
                fontSize: 14.5,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
      );

  Widget _activeFilterSummaryBar(List<HomeCourseFilterOption> options) {
    final epoch = store.accountEpoch;
    final account = store.account;
    Widget removableTag(String text, VoidCallback onRemove) => Semantics(
          container: true,
          button: true,
          label: '移除筛选：$text',
          onTap: onRemove,
          excludeSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onRemove,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Journal.sage,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Journal.metadata.copyWith(
                              fontSize: 12,
                              color: Journal.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.close_rounded,
                            size: 14, color: Journal.ink),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_query.trim().isNotEmpty)
          removableTag(
            '关键词：${_query.trim()}',
            () => _saveFilters(
              HomeFilters(
                query: '',
                courseKey: _courseKey,
                deadline: _deadlineFilter,
                type: _typeFilter,
                sortOrder: _sortOrder,
              ),
              epoch,
              account,
            ),
          ),
        if (_typeFilter != AssignmentTypeFilter.all)
          removableTag(
            '类型：${_typeFilter.label}',
            () => _saveFilters(
              HomeFilters(
                query: _query,
                courseKey: _courseKey,
                deadline: _deadlineFilter,
                type: AssignmentTypeFilter.all,
                sortOrder: _sortOrder,
              ),
              epoch,
              account,
            ),
          ),
        if (_deadlineFilter != AssignmentDeadlineFilter.all)
          removableTag(
            '期限：${_deadlineLabel(_deadlineFilter)}',
            () => _saveFilters(
              HomeFilters(
                query: _query,
                courseKey: _courseKey,
                deadline: AssignmentDeadlineFilter.all,
                type: _typeFilter,
                sortOrder: _sortOrder,
              ),
              epoch,
              account,
            ),
          ),
        if (_courseKey != null)
          removableTag(
            '课程：${options.where((option) => option.courseKey == _courseKey).firstOrNull?.label ?? "已选课程"}',
            () => _saveFilters(
              HomeFilters(
                query: _query,
                courseKey: null,
                deadline: _deadlineFilter,
                type: _typeFilter,
                sortOrder: _sortOrder,
              ),
              epoch,
              account,
            ),
          ),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
            foregroundColor: Journal.muted,
          ),
          onPressed: () => _saveFilters(
            HomeFilters(sortOrder: _sortOrder),
            epoch,
            account,
          ),
          child: const Text('重置条件'),
        ),
      ],
    );
  }

  Widget dayHeading(
    String label, {
    double top = 12,
    _DayHeadingTone tone = _DayHeadingTone.normal,
    String? badge,
  }) {
    final textColor = switch (tone) {
      _DayHeadingTone.overdue => Journal.berry,
      _DayHeadingTone.undated => Journal.ochre,
      _DayHeadingTone.today => Journal.ink,
      _DayHeadingTone.normal => Journal.muted,
    };
    final baseStyle = Journal.dayHeading.copyWith(
      color: textColor,
      fontSize: 14.5,
    );
    final date = RegExp(r'^(\d{4}年)?(\d{1,2}月\d{1,2}日)(.*)$').firstMatch(label);
    final Widget labelWidget = date == null
        ? Text(label, style: baseStyle)
        : Text.rich(
            TextSpan(children: [
              if (date[1] != null)
                TextSpan(
                  text: date[1],
                  style: baseStyle.copyWith(fontWeight: FontWeight.w500),
                ),
              TextSpan(
                text: date[2],
                style: baseStyle.copyWith(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: date[3],
                style: baseStyle.copyWith(fontWeight: FontWeight.w400),
              ),
            ]),
            style: baseStyle,
          );
    return Padding(
      padding: EdgeInsets.only(top: top + 6, bottom: 2),
      child: Row(
        children: [
          Flexible(
            child: labelWidget,
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: tone == _DayHeadingTone.overdue
                    ? Journal.berryBg
                    : Journal.sage,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: Journal.metadata.copyWith(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: tone == _DayHeadingTone.overdue
                      ? Journal.berry
                      : Journal.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

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
                Expanded(child: Text(scope.label, style: Journal.entryTitle)),
              ]),
              const SizedBox(height: 4),
              Text(
                '共 $count 项',
                style: Journal.metadata,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _exitRecoveryScope(context),
                  child: const Text('返回全部'),
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
        AssignmentDeadlineFilter.notExpired => '未逾期',
      };

  String _shortSortLabel(HomeSortOrder order) =>
      switch (normalizedHomeSort(order)) {
        HomeSortOrder.deadlineDesc => '时间远到近',
        HomeSortOrder.courseName => '按课程',
        _ => '时间近到远',
      };

  Widget _homeActions(
      BuildContext context,
      List<HomeCourseFilterOption> options,
      bool filtersActive,
      HomeSortOrder sortOrder) {
    final actionColor = Theme.of(context).colorScheme.primary;
    final filterStyle = Journal.metadata.copyWith(
      color: actionColor,
      fontWeight: FontWeight.w500,
    );
    final sortStyle = Journal.metadata.copyWith(
      color: Journal.muted,
      fontWeight: FontWeight.w500,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final filterLabel = filtersActive ? '已筛选' : '搜索与筛选';
    final sortLabel = _shortSortLabel(sortOrder);
    double labelWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    final filterWidth = 18 + 8 + labelWidth(filterLabel, filterStyle) + 28;
    final sortWidth = 16 + 6 + labelWidth(sortLabel, sortStyle) + 16;

    Widget buildFilterPill({bool fullWidth = false}) {
      final message = filtersActive ? '已筛选，打开搜索与期限筛选' : '搜索与筛选';
      void onTap() => _openFilters(options);
      return Semantics(
        button: true,
        label: message,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Tooltip(
            message: message,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 48,
                    minWidth: fullWidth ? double.infinity : 0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: fullWidth ? null : 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: filtersActive ? Journal.sage : Journal.parchment,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        mainAxisSize:
                            fullWidth ? MainAxisSize.max : MainAxisSize.min,
                        children: [
                          Icon(
                            filtersActive
                                ? Icons.tune_rounded
                                : Icons.search_rounded,
                            size: 17,
                            color: actionColor,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(filterLabel, style: filterStyle),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildSortButton({double horizontalPad = 6}) {
      final message = '当前排序：$sortLabel，打开搜索、筛选与排序';
      void onTap() => _openFilters(options);
      return Semantics(
        button: true,
        label: message,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Tooltip(
            message: message,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.swap_vert_rounded,
                          size: 17, color: Journal.muted),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          sortLabel,
                          key: const ValueKey('current-home-sort'),
                          style: sortStyle,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      if (filterWidth + sortWidth + 12 <= constraints.maxWidth) {
        return Row(children: [
          Flexible(child: buildFilterPill(fullWidth: true)),
          const SizedBox(width: 12),
          buildSortButton(),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildFilterPill(),
          buildSortButton(horizontalPad: 14),
        ],
      );
    });
  }

  String _sortLabel(HomeSortOrder order) => switch (order) {
        HomeSortOrder.grouped => '默认分组',
        HomeSortOrder.deadlineAsc => '时间：近到远（考试按开考）',
        HomeSortOrder.deadlineDesc => '时间：远到近（考试按开考）',
        HomeSortOrder.courseName => '按课程',
        HomeSortOrder.title => '名称',
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

  Future<void> _openFilters(List<HomeCourseFilterOption> courseOptions) async {
    final openingEpoch = store.accountEpoch;
    final openingAccount = store.account;
    final controller = TextEditingController(text: _query);
    var query = _query;
    var courseKey = _courseKey;
    var deadline = _deadlineFilter;
    var type = _typeFilter;
    var sortOrder = _sortOrder;
    final selection = await showModalBottomSheet<_HomeFilterSelection>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Journal.ruleStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('搜索、筛选与排序', style: Journal.section),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: _query.isNotEmpty,
                  onChanged: (value) => setSheetState(() => query = value),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: '搜索作业、任务、考试或课程',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                Text('类型', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in homeTypeFilterChoices)
                      ChoiceChip(
                        key: ValueKey('type-${option.name}'),
                        selected: type == option,
                        onSelected: (_) => setSheetState(() => type = option),
                        label: Text(option.label),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('期限', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
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
                  itemHeight: null,
                  decoration: const InputDecoration(labelText: '课程筛选'),
                  selectedItemBuilder: (context) => [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('全部课程'),
                    ),
                    for (final option in courseOptions)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Journal.metadata.copyWith(
                            fontSize: 14,
                            color: Journal.ink,
                          ),
                        ),
                      ),
                  ],
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部课程')),
                    for (final option in courseOptions)
                      DropdownMenuItem(
                        key: ValueKey('course-option-${option.courseKey}'),
                        value: option.courseKey,
                        child: _CourseOptionLabel(option: option),
                      ),
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
                      for (final order in homeSortOrderChoices)
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
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setSheetState(() {
                        query = '';
                        courseKey = null;
                        deadline = AssignmentDeadlineFilter.all;
                        type = AssignmentTypeFilter.all;
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
                              type: type,
                              sortOrder: sortOrder)),
                      child: const Text('应用'),
                    ),
                  ],
                ),
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
            type: selection.type,
            sortOrder: selection.sortOrder),
        openingEpoch,
        openingAccount);
  }
}

enum _DayHeadingTone { normal, today, undated, overdue }

class _HomeFilterSelection {
  const _HomeFilterSelection({
    required this.query,
    required this.courseKey,
    required this.deadline,
    required this.type,
    required this.sortOrder,
  });

  final String query;
  final String? courseKey;
  final AssignmentDeadlineFilter deadline;
  final AssignmentTypeFilter type;
  final HomeSortOrder sortOrder;
}

class _CourseOptionLabel extends StatelessWidget {
  const _CourseOptionLabel({required this.option});

  final HomeCourseFilterOption option;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            option.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Journal.metadata.copyWith(
              fontSize: 14,
              color: Journal.ink,
            ),
          ),
          if (option.showClass)
            Text(
              option.classLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Journal.metadata.copyWith(
                fontSize: 12,
                color: Journal.muted,
              ),
            ),
        ],
      );
}
