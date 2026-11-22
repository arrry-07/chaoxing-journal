import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../app/transient_feedback.dart';
import '../local/chaoxing_local_client.dart';
import '../models/assignment.dart';
import '../models/assignment_sync_progress.dart';
import '../models/display_preferences.dart';
import '../models/home_filters.dart';
import '../models/personal_workspace.dart';
import '../models/sync_report.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import '../services/assignment_web_link.dart';
import '../services/exam_schedule_presentation.dart';
import '../services/external_link_service.dart';
import '../services/home_course_filter.dart';
import '../services/home_sync_presentation.dart';
import '../services/interaction_feedback_service.dart';
import 'widgets/appearance_controls.dart';
import 'widgets/assignment_card.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_context_menu.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_picker_sheet.dart';
import 'widgets/journal_sliver_header.dart';
import 'widgets/journal_swipe_tile.dart';

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

  static AssignmentRecoveryScope? of(BuildContext context) {
    if (GoRouter.maybeOf(context) == null) return null;
    try {
      return fromQueryValue(
        GoRouterState.of(context).uri.queryParameters[queryParameter],
      );
    } on GoError {
      return null;
    }
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
  final _scrollController = ScrollController();
  double _scrollOffset = 0.0;
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = _scrollController.offset;
    if ((next - _scrollOffset).abs() >= 1.5 &&
        (next <= 80 || _scrollOffset <= 80)) {
      setState(() => _scrollOffset = next);
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
    _scrollController.addListener(_onScroll);
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  void feedback(String message,
      {bool details = false, VoidCallback? action, String? actionLabel}) {
    if (!mounted) return;
    final journal = Journal.of(context);
    final effectiveAction = action ??
        (details
            ? () {
                _feedback.dismiss();
                if (mounted) context.push('/sync?expand=issues');
              }
            : null);
    final effectiveLabel = actionLabel ?? (details ? '查看详情' : null);
    _feedback.show(
      context,
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: journal.ink,
        content: Text(
          message,
          style: journal.metadata.copyWith(color: journal.onPrimaryFill),
        ),
        action: effectiveAction != null && effectiveLabel != null
            ? SnackBarAction(
                label: effectiveLabel,
                textColor: journal.isDark ? journal.slate : journal.slateBg,
                onPressed: effectiveAction,
              )
            : null,
      ),
    );
  }

  Future<void> _togglePin(Assignment assignment) async {
    if (!store.canTogglePin(assignment)) return;
    final ok = await store.togglePin(assignment);
    if (!mounted || !ok) return;
    final pinned = store.isPinned(assignment);
    JournalMotion.pin(store.display, pinned: pinned);
    feedback(pinned ? '已置顶' : '已取消置顶');
  }

  Future<void> _toggleTodayPlan(Assignment assignment) async {
    final epoch = store.accountEpoch;
    final day = PersonalWorkspace.dayKey(DateTime.now());
    final existing = store.personal.plans
        .where((p) => p.day == day && p.assignmentId == assignment.id)
        .firstOrNull;
    final adding = existing == null;
    final ok = await store.savePersonal(
      (w) => w.withPlans(
        adding
            ? [
                ...w.plans.where(
                    (p) => p.day != day || p.assignmentId != assignment.id),
                DailyPlanItem(assignment.id, day, 30, done: false),
              ]
            : w.plans
                .where((p) => p.day != day || p.assignmentId != assignment.id)
                .toList(),
      ),
      epoch,
    );
    if (!mounted || !ok) return;
    if (adding) {
      JournalMotion.complete(store.display);
      feedback(
        '已加入今日计划（30 分钟）',
        actionLabel: '改时长',
        action: () {
          _feedback.dismiss();
          if (mounted) context.push('/plan');
        },
      );
    } else {
      JournalMotion.tap(store.display);
      feedback('已移出今日计划');
    }
  }

  Future<void> _copyLinkWithConfirm(Assignment assignment) async {
    final url = AssignmentWebLink.validatedUrl(assignment);
    if (url == null) {
      feedback('当前链接暂不可用，请刷新后再试');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('复制${assignment.isExam ? "考试" : "作业"}链接'),
        content: const Text('链接含个人访问参数，请只在本人设备使用，勿转发或公开。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认复制'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) feedback('链接已复制，请勿转发他人');
  }

  Future<void> _hideWithUndo(Assignment assignment) async {
    final epoch = store.accountEpoch;
    final group = store.courseworkGroupFor(assignment.id);
    final sourceIds =
        group?.sources.map((a) => a.id).toList() ?? [assignment.id];
    final hidden = await store.setAssignmentsHidden(sourceIds, true);
    if (!mounted || !hidden) return;
    feedback(
      '已在本机隐藏，可在本地记录中恢复',
      actionLabel: '撤销',
      action: () {
        if (store.accountEpoch == epoch) {
          unawaited(store.setAssignmentsHidden(sourceIds, false));
        }
      },
    );
  }

  Future<void> _openContextMenu(
    BuildContext itemContext,
    Assignment assignment,
    Widget previewCard, {
    required bool inTodayPlan,
  }) async {
    final box = itemContext.findRenderObject() as RenderBox?;
    Rect? anchorRect;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      anchorRect = topLeft & box.size;
    }
    final url = AssignmentWebLink.validatedUrl(assignment);
    final canPin = store.canTogglePin(assignment);
    final pinned = store.isPinned(assignment);
    final actions = <JournalContextMenuAction>[
      if (url != null)
        JournalContextMenuAction(
          label: assignment.isExam ? '在学习通查看' : '在学习通打开',
          icon: Icons.open_in_new_rounded,
          onSelected: () => openAssignment(assignment.id),
        ),
      if (canPin)
        JournalContextMenuAction(
          label: pinned ? '取消置顶' : '置顶',
          icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          onSelected: () => _togglePin(assignment),
        ),
      if (!assignment.isCompleted)
        JournalContextMenuAction(
          label: inTodayPlan ? '移出今日计划' : '加入今日计划',
          icon: inTodayPlan
              ? Icons.playlist_remove_rounded
              : Icons.playlist_add_check_rounded,
          onSelected: () => _toggleTodayPlan(assignment),
        ),
      if (url != null)
        JournalContextMenuAction(
          label: '复制链接',
          icon: Icons.copy_outlined,
          onSelected: () => _copyLinkWithConfirm(assignment),
        ),
      if (!assignment.isCompleted)
        JournalContextMenuAction(
          label: '在本机隐藏',
          icon: Icons.visibility_off_outlined,
          destructive: true,
          onSelected: () => _hideWithUndo(assignment),
        ),
    ];
    await showJournalContextMenu(
      context: context,
      anchorRect: anchorRect,
      previewCard: previewCard,
      actions: actions,
      displayPrefs: store.display,
    );
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
    if (_refreshing ||
        store.isLoading ||
        store.syncReport.phase == SyncPhase.running) {
      return;
    }
    setState(() => _refreshing = true);
    final before = store.syncReport;
    final epoch = store.accountEpoch;
    try {
      final attempted = await act(action);
      if (!mounted || !attempted) return;
      final report = store.syncReport;
      if (identical(report, before) ||
          report.phase == SyncPhase.idle ||
          report.phase == SyncPhase.running) {
        feedback('刷新未完成，请查看同步详情', details: true);
      } else if (report.phase == SyncPhase.success) {
        InteractionFeedback.triggerSyncDoneIfReady(
          prefs: store.display,
          before: before,
          after: report,
          beforeEpoch: epoch,
          afterEpoch: store.accountEpoch,
          operationError: store.operationError,
        );
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

  void _exitRecoveryScope(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      context.go('/assignments');
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _cycleTheme(BuildContext context) {
    final display = store.display;
    final system = MediaQuery.platformBrightnessOf(context) == Brightness.dark
        ? JournalThemeMode.dark
        : JournalThemeMode.light;
    final mode = switch (display.themeMode) {
      JournalThemeMode.system => system == JournalThemeMode.dark
          ? JournalThemeMode.light
          : JournalThemeMode.dark,
      final current when current != system => system,
      _ => JournalThemeMode.system,
    };
    InteractionFeedback.trigger(display);
    saveDisplaySetting(context, store, display.copyWith(themeMode: mode));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final journal = Journal.of(context);
        final busy = _refreshing ||
            store.isLoading ||
            store.syncReport.phase == SyncPhase.running;
        final recoveryScope = AssignmentRecoveryScope.of(context);
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
          prioritizeStartOnly: recoveryScope == null,
        );
        final today = PersonalWorkspace.dayKey(now);
        final plans =
            store.personal.plans.where((p) => p.day == today).toList();
        final plannedIds = plans.map((p) => p.assignmentId).toSet();
        final sync = HomeSyncPresentation.from(store.syncReport,
            loading: store.isLoading,
            hasCache:
                catalogAssignments.isNotEmpty || displayAssignments.isNotEmpty,
            hasPreviousData: store.hadCacheBeforeLastSync,
            now: now,
            successAt: store.lastSyncAt,
            serviceWarning: store.error != null &&
                store.syncReport.phase == SyncPhase.success);
        final freshness = _freshnessLabel(sync.summary,
            store.syncReport.lastDataSuccessAt ?? store.lastSyncAt, now);
        final statusText = sync.showCached ? '$freshness · 显示上次记录' : freshness;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final syncAction = sync.action == HomeSyncAction.login ||
                sync.action == HomeSyncAction.verify
            ? sync.action
            : HomeSyncAction.retry;

        Widget buildCardWidget(Assignment a, {bool pinned = false}) =>
            AssignmentCard(
              key: ValueKey('assignment-${a.id}'),
              assignment: a,
              examSources: examSources,
              displayIndex: displayIndex,
              now: now,
              showFullDeadline: false,
              showDivider: false,
              enableTapFeedback: false,
              inPinnedSection: pinned,
              compact: store.display.compact,
              countdown: store.display.countdown,
              deadlinePending: store.isHomeDeadlinePending(a.id),
              previewOnly: store.isHomeAssignmentPreviewOnly(a.id),
              previewSaving:
                  store.homeSyncProgress?.stage == AssignmentSyncStage.saving,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              onOpenAssignment: AssignmentWebLink.validatedUrl(a) == null
                  ? null
                  : () => openAssignment(a.id),
              opening: _openingAssignments.contains(a.id),
              onTap: () {
                InteractionFeedback.trigger(store.display);
                final path = '/assignments/${Uri.encodeComponent(a.id)}';
                final scope = recoveryScope == null
                    ? ''
                    : '?${AssignmentRecoveryScope.queryParameter}=${recoveryScope.queryValue}';
                context.push('$path$scope');
              },
            );

        Widget card(Assignment a, {bool pinned = false}) {
          final previewOnly = store.isHomeAssignmentPreviewOnly(a.id);
          final inTodayPlan = plannedIds.contains(a.id);
          final canPin = store.canTogglePin(a);
          final isPinned = store.isPinned(a);
          final preview = AssignmentCard(
            assignment: a,
            examSources: examSources,
            displayIndex: displayIndex,
            now: now,
            showFullDeadline: false,
            showDivider: false,
            enableTapFeedback: false,
            inPinnedSection: pinned,
            compact: store.display.compact,
            countdown: store.display.countdown,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            onTap: () {},
          );

          return Builder(
            builder: (itemContext) {
              final interactiveCard = AssignmentCard(
                key: ValueKey('assignment-${a.id}'),
                assignment: a,
                examSources: examSources,
                displayIndex: displayIndex,
                now: now,
                showFullDeadline: false,
                showDivider: false,
                enableTapFeedback: false,
                inPinnedSection: pinned,
                compact: store.display.compact,
                countdown: store.display.countdown,
                deadlinePending: store.isHomeDeadlinePending(a.id),
                previewOnly: previewOnly,
                previewSaving:
                    store.homeSyncProgress?.stage == AssignmentSyncStage.saving,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                onOpenAssignment: AssignmentWebLink.validatedUrl(a) == null
                    ? null
                    : () => openAssignment(a.id),
                opening: _openingAssignments.contains(a.id),
                onLongPress: previewOnly
                    ? null
                    : () => _openContextMenu(
                          itemContext,
                          a,
                          preview,
                          inTodayPlan: inTodayPlan,
                        ),
                onTap: () {
                  InteractionFeedback.trigger(store.display);
                  final path = '/assignments/${Uri.encodeComponent(a.id)}';
                  final scope = recoveryScope == null
                      ? ''
                      : '?${AssignmentRecoveryScope.queryParameter}=${recoveryScope.queryValue}';
                  context.push('$path$scope');
                },
              );

              if (previewOnly) return buildCardWidget(a, pinned: pinned);

              return JournalSwipeTile(
                displayPrefs: store.display,
                rightAction: a.isCompleted
                    ? null
                    : JournalSwipeAction(
                        label: inTodayPlan ? '移出计划' : '今日计划',
                        icon: inTodayPlan
                            ? Icons.playlist_remove_rounded
                            : Icons.playlist_add_check_rounded,
                        color: journal.accent,
                        backgroundColor: journal.sage,
                        onTrigger: () => unawaited(_toggleTodayPlan(a)),
                      ),
                leftAction: !canPin
                    ? null
                    : JournalSwipeAction(
                        label: isPinned ? '取消置顶' : '置顶',
                        icon: isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        color: journal.ink,
                        backgroundColor: journal.parchment,
                        onTrigger: () => unawaited(_togglePin(a)),
                      ),
                child: interactiveCard,
              );
            },
          );
        }

        List<Widget> timeline(List<Assignment> list) {
          final widgets = <Widget>[];
          var regular = list;

          void flushGroup({
            String? heading,
            _DayHeadingTone tone = _DayHeadingTone.normal,
            String? badge,
            required List<Widget> rows,
          }) {
            if (rows.isEmpty) return;
            if (heading != null) {
              widgets.add(dayHeading(
                heading,
                top: widgets.isEmpty ? 8 : 18,
                tone: tone,
                badge: badge,
              ));
            }
            widgets.add(JournalGroupedCard(
              dividerIndent: 70.0,
              children: rows,
            ));
          }

          if (recoveryScope == null && store.isAuthenticated) {
            final pinned = <Assignment>[];
            regular = <Assignment>[];
            for (final a in list) {
              if (store.isPinned(a) &&
                  !store.isHomeAssignmentPreviewOnly(a.id)) {
                pinned.add(a);
              } else {
                regular.add(a);
              }
            }
            if (pinned.isNotEmpty) {
              flushGroup(
                heading: '置顶',
                tone: _DayHeadingTone.today,
                rows: [for (final item in pinned) card(item, pinned: true)],
              );
            }
          }

          String? previousKey;
          String? activeHeading;
          String? activeBadge;
          var activeTone = _DayHeadingTone.normal;
          var activeRows = <Widget>[];
          var overdueTierAnnounced = false;
          final todayDay = AssignmentQuery.dayKey(now);
          final tomorrowDay =
              DateTime(todayDay.year, todayDay.month, todayDay.day + 1);

          for (final a in regular) {
            final bucket = AssignmentQuery.timelineBucketAt(a, now);
            final isOverdue = bucket == AssignmentDeadlineBucket.overdue;
            DateTime? badgeDay;
            String? key;
            String? heading;
            if (a.isExam) {
              final stamp = ExamSchedulePresentation.build(a,
                      records: examSources, index: displayIndex)
                  .timeline;
              key = stamp?.key;
              heading = stamp?.heading;
              final start = a.timelineAt;
              if (start != null &&
                  (a.timelineTrusted || recoveryScope != null)) {
                badgeDay = AssignmentQuery.dayKey(start);
              }
            } else if (a.timelineAt != null &&
                a.timelineTrusted &&
                !a.deadlineReadFailed) {
              final day = AssignmentQuery.dayKey(a.timelineAt!);
              badgeDay = day;
              final showYear =
                  recoveryScope != null || day.year != todayDay.year;
              key =
                  '${showYear ? '' : 'work:'}${day.year}:${day.month}:${day.day}';
              heading =
                  '${showYear ? '${day.year}年' : ''}${day.month}月${day.day}日 '
                  '周${'一二三四五六日'[day.weekday - 1]}';
            }
            if (heading == null && recoveryScope == null) {
              if (!a.isExam &&
                  AssignmentQuery.timelineBucketAt(a, now) ==
                      AssignmentDeadlineBucket.confirmedNoDeadline) {
                key = 'noDeadline';
                heading = '无截止日期';
              } else {
                key = 'undated';
                heading = '无日期与待确认';
              }
            }
            final effectiveKey = isOverdue ? 'overdue:$key' : key;
            if (heading != null && effectiveKey != previousKey) {
              flushGroup(
                heading: activeHeading,
                tone: activeTone,
                badge: activeBadge,
                rows: activeRows,
              );
              activeRows = <Widget>[];
              activeHeading = heading;
              activeBadge = null;
              activeTone = _DayHeadingTone.normal;
              if (isOverdue) {
                activeTone = _DayHeadingTone.overdue;
                if (!overdueTierAnnounced && recoveryScope == null) {
                  activeBadge = '已逾期置底';
                  overdueTierAnnounced = true;
                }
              } else if (key == 'undated' || key == 'noDeadline') {
                activeTone = _DayHeadingTone.undated;
              } else if (badgeDay == todayDay) {
                activeTone = _DayHeadingTone.today;
                activeBadge = '今天';
              } else if (recoveryScope == null && badgeDay == tomorrowDay) {
                activeTone = _DayHeadingTone.today;
                activeBadge = '明天';
              }
            }
            previousKey = effectiveKey;
            activeRows.add(card(a));
          }

          flushGroup(
            heading: activeHeading,
            tone: activeTone,
            badge: activeBadge,
            rows: activeRows,
          );
          return widgets;
        }

        final listView = ListView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          key: PageStorageKey(recoveryScope == null
              ? 'home-list'
              : 'home-recovery-${recoveryScope.queryValue}'),
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            JournalLayout.floatingNavClearance(context),
          ),
          children: [
            Builder(builder: (context) {
              Widget action(String label, Widget button) => Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      button,
                      Positioned(
                        bottom: 2,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: Text(
                              label,
                              style: journal.metadata.copyWith(
                                fontSize: 11,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );

              final actionsRow = Row(mainAxisSize: MainAxisSize.min, children: [
                if (plans.isEmpty)
                  action(
                    '计划',
                    IconButton(
                        key: const ValueKey('home-plan-entry'),
                        tooltip: '今日计划',
                        padding: const EdgeInsets.only(bottom: 12),
                        iconSize: 21,
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: () => context.push('/plan'),
                        icon: const Icon(Icons.checklist_rounded)),
                  ),
                action(
                  '刷新',
                  IconButton(
                      enableFeedback: false,
                      tooltip: '刷新作业',
                      padding: const EdgeInsets.only(bottom: 12),
                      iconSize: 21,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: busy ? null : () => refresh(syncAction),
                      icon: busy
                          ? reduceMotion
                              ? Icon(Icons.hourglass_top_rounded,
                                  size: 19, color: journal.ink)
                              : SizedBox.square(
                                  dimension: 19,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: journal.ink))
                          : const Icon(Icons.sync_rounded)),
                ),
                if (recoveryScope == null)
                  action(
                    '主题',
                    IconButton(
                      key: const ValueKey('home-theme-toggle'),
                      enableFeedback: false,
                      padding: const EdgeInsets.only(bottom: 12),
                      iconSize: 21,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      tooltip: '切换主题（当前：${store.display.themeMode.label}）',
                      icon: Icon(switch (store.display.themeMode) {
                        JournalThemeMode.system =>
                          Icons.brightness_auto_outlined,
                        JournalThemeMode.light => Icons.light_mode_outlined,
                        JournalThemeMode.dark => Icons.dark_mode_outlined,
                      }),
                      onPressed: () => _cycleTheme(context),
                    ),
                  ),
                action(
                  '更多',
                  IconButton(
                      tooltip: '同步详情',
                      padding: const EdgeInsets.only(bottom: 12),
                      iconSize: 21,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: () => context.push('/sync'),
                      icon: const Icon(Icons.more_horiz_rounded)),
                ),
              ]);

              final title = Text('课业手记', style: journal.display);
              return LayoutBuilder(
                builder: (context, constraints) {
                  if (!JournalLayout.isLargeText(context) &&
                      constraints.maxWidth >= 300) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: title,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        actionsRow,
                      ],
                    );
                  }
                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [title, actionsRow],
                  );
                },
              );
            }),
            const SizedBox(height: 2),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const ValueKey('home-sync-status'),
                onTap: sync.action == HomeSyncAction.none
                    ? null
                    : () => context.push('/sync?expand=issues'),
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: sync.action == HomeSyncAction.none ? 22 : 48,
                  ),
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
                        size: 14.5,
                        color: store.syncReport.phase == SyncPhase.failed
                            ? journal.berry
                            : store.syncReport.phase == SyncPhase.partial
                                ? journal.ochre
                                : journal.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(statusText, style: journal.metadata),
                        ),
                      ),
                      if (sync.action != HomeSyncAction.none)
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: journal.muted),
                    ]),
                  ),
                ),
              ),
            ),
            if (recoveryScope != null) ...[
              const SizedBox(height: 6),
              _recoveryHeader(context, recoveryScope, items.length),
              const SizedBox(height: 8),
            ],
            if (plans.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: JournalGroupedCard(
                  backgroundColor: Color.lerp(
                    journal.sheet,
                    journal.sage,
                    journal.isDark ? 0.35 : 0.45,
                  ),
                  children: [
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: const ValueKey('home-plan-summary'),
                        onTap: () => context.push('/plan'),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 46),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            child: Row(children: [
                              Icon(Icons.checklist_rounded,
                                  size: 18, color: journal.ink),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '今日计划 · 已完成${plans.where((p) => p.done).length}/${plans.length}',
                                  style: journal.metadata.copyWith(
                                    color: journal.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: journal.muted),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (recoveryScope == null) ...[
              const SizedBox(height: 6),
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
                          ? Container(height: 3, color: journal.sageBorder)
                          : LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: journal.parchment,
                              color: journal.ink,
                            ),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _syncProgressLabel(store),
                        style: journal.metadata.copyWith(color: journal.ink),
                      ),
                    ),
                  ],
                ),
              ),
            if (recoveryScope == null &&
                _courseKey != null &&
                !displayAssignments.any((a) => a.courseKey == _courseKey))
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('已保留课程筛选，当前没有可显示的作业。可在搜索与筛选中更改条件。',
                      style: journal.metadata)),
            if (sortedItems.isNotEmpty) ...[
              if (recoveryScope == null) const SizedBox(height: 12),
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
                  JournalPrimaryButton(
                    expanded: false,
                    label: '清除搜索与筛选条件',
                    onPressed: () => _saveFilters(
                      HomeFilters(sortOrder: _sortOrder),
                      store.accountEpoch,
                      store.account,
                    ),
                  ),
                ],
              ),
            ] else if (store.assignments.isNotEmpty) ...[
              _emptyStateCard(
                icon: Icons.inventory_2_outlined,
                message: '本机有已完成、已结束、已隐藏、未关注、历史课堂练习或非课业来源的记录，可在本地记录查看。',
                actions: [
                  JournalPrimaryButton(
                    expanded: false,
                    label: '查看全部本地记录',
                    onPressed: () => context.push('/records'),
                  ),
                  JournalSecondaryButton(
                    expanded: false,
                    label: '管理课程',
                    onPressed: () => context.push('/courses'),
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

        return Stack(
          children: [
            listView,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: JournalSliverHeader(
                title: '课业手记',
                scrollOffset: _scrollOffset,
                actions: [
                  IconButton(
                    tooltip: '今日计划',
                    iconSize: 20,
                    onPressed: () => context.push('/plan'),
                    icon: const Icon(Icons.checklist_rounded),
                  ),
                  IconButton(
                    tooltip: '刷新作业',
                    enableFeedback: false,
                    iconSize: 20,
                    onPressed: busy ? null : () => refresh(syncAction),
                    icon: busy
                        ? SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: journal.ink,
                            ),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                  if (recoveryScope == null)
                    IconButton(
                      enableFeedback: false,
                      tooltip: '切换主题',
                      iconSize: 20,
                      onPressed: () => _cycleTheme(context),
                      icon: Icon(switch (store.display.themeMode) {
                        JournalThemeMode.system =>
                          Icons.brightness_auto_outlined,
                        JournalThemeMode.light => Icons.light_mode_outlined,
                        JournalThemeMode.dark => Icons.dark_mode_outlined,
                      }),
                    ),
                ],
              ),
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
        padding: const EdgeInsets.only(top: 18),
        child: JournalGroupedCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Journal.of(context).parchment,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 22, color: Journal.of(context).muted),
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Journal.of(context).metadata.copyWith(
                        color: Journal.of(context).ink,
                        fontSize: 14.5,
                      ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ],
            ),
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
              enableFeedback: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                    decoration: BoxDecoration(
                      color: Journal.of(context).sage,
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
                            style: Journal.of(context).metadata.copyWith(
                                  fontSize: 12,
                                  color: Journal.of(context).ink,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.close_rounded,
                            size: 14, color: Journal.of(context).ink),
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
            enableFeedback: false,
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
            foregroundColor: Journal.of(context).muted,
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
    final journal = Journal.of(context);
    final textColor = switch (tone) {
      _DayHeadingTone.overdue => journal.berry,
      _DayHeadingTone.undated => journal.ochre,
      _DayHeadingTone.today => journal.ink,
      _DayHeadingTone.normal => journal.muted,
    };
    final baseStyle = journal.dayHeading.copyWith(
      color: textColor,
      fontSize: 14,
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
      padding: EdgeInsets.only(top: top, bottom: 8, left: 2),
      child: Row(
        children: [
          Flexible(child: labelWidget),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: tone == _DayHeadingTone.overdue
                    ? journal.berryBg
                    : journal.sage,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: journal.metadata.copyWith(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: tone == _DayHeadingTone.overdue
                      ? journal.berry
                      : journal.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recoveryHeader(
      BuildContext context, AssignmentRecoveryScope scope, int count) {
    final journal = Journal.of(context);
    return Column(
      key: const ValueKey('assignment-recovery-scope'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.filter_alt_outlined, size: 17, color: journal.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      scope.label,
                      style: journal.entryTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '· 共 $count 项',
                      style: journal.metadata.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: journal.ink,
                  minimumSize: const Size(48, 40),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                onPressed: () => _exitRecoveryScope(context),
                child: const Text('返回全部'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Divider(height: 1, thickness: 0.8, color: journal.rule),
      ],
    );
  }

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
    final journal = Journal.of(context);
    final filterColor = filtersActive ? journal.accent : journal.muted;
    final filterStyle = journal.metadata.copyWith(
      color: filtersActive ? journal.ink : journal.muted,
      fontWeight: FontWeight.w500,
    );
    final sortStyle = journal.metadata.copyWith(
      color: journal.muted,
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

    final filterWidth = 18 + 8 + labelWidth(filterLabel, filterStyle) + 26;
    final sortWidth = 17 + 7 + labelWidth(sortLabel, sortStyle) + 26;

    Widget buildFilterPill({bool fullWidth = false}) {
      final journal = Journal.of(context);
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
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                enableFeedback: false,
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
                          horizontal: 13, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: filtersActive ? journal.sage : journal.parchment,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: filtersActive
                              ? journal.sageBorder
                              : Colors.transparent,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize:
                            fullWidth ? MainAxisSize.max : MainAxisSize.min,
                        children: [
                          Icon(
                            filtersActive
                                ? Icons.tune_rounded
                                : Icons.search_rounded,
                            size: 16,
                            color: filterColor,
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

    Widget buildSortButton() {
      final journal = Journal.of(context);
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
                enableFeedback: false,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    widthFactor: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: journal.parchment,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.transparent,
                          width: 0.8,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.swap_vert_rounded,
                            size: 16, color: journal.muted),
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
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      if (filterWidth + sortWidth + 10 <= constraints.maxWidth) {
        return Row(children: [
          Expanded(child: buildFilterPill(fullWidth: true)),
          const SizedBox(width: 10),
          buildSortButton(),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildFilterPill(),
          buildSortButton(),
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
    if (saved) {
      InteractionFeedback.trigger(store.display);
    } else {
      feedback('搜索、筛选与排序未能保存，请重试；原偏好已保留');
    }
  }

  Future<void> _openFilters(List<HomeCourseFilterOption> courseOptions) async {
    InteractionFeedback.trigger(store.display);
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
        builder: (context, setSheetState) {
          final journal = Journal.of(context);
          final selectedCourseLabel = courseKey == null
              ? '全部课程'
              : courseOptions
                      .where((o) => o.courseKey == courseKey)
                      .firstOrNull
                      ?.label ??
                  '全部课程';
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 14, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
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
                        color: journal.ruleStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text('搜索、筛选与排序', style: journal.section),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: _query.isNotEmpty,
                    onChanged: (value) => setSheetState(() => query = value),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: '搜索作业、任务、考试或课程',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('类型', style: journal.dayHeading),
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
                  Text('期限', style: journal.dayHeading),
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
                  Text('课程筛选', style: journal.dayHeading),
                  const SizedBox(height: 8),
                  JournalGroupedCard(
                    children: [
                      JournalGroupTile(
                        key: ValueKey(
                            'course-${store.accountEpoch}-${courseKey ?? "all"}'),
                        title: '所选课程',
                        trailingText: selectedCourseLabel,
                        icon: Icons.menu_book_outlined,
                        onTap: () async {
                          final picked = await showJournalPickerSheet<String>(
                            context,
                            title: '课程筛选',
                            selectedValue: courseKey ?? '',
                            searchable: courseOptions.length > 5,
                            searchHint: '搜索课程名称...',
                            displayPrefs: store.display,
                            options: [
                              const JournalPickerOption<String>(
                                value: '',
                                label: '全部课程',
                              ),
                              for (final option in courseOptions)
                                JournalPickerOption<String>(
                                  key: ValueKey(
                                      'course-option-${option.courseKey}'),
                                  value: option.courseKey,
                                  label: option.name,
                                  subtitle: option.showClass
                                      ? option.classLabel
                                      : null,
                                  icon: courseIconFor(option.name),
                                ),
                            ],
                          );
                          if (picked != null) {
                            setSheetState(
                                () => courseKey = picked == '' ? null : picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('排序', style: journal.dayHeading),
                  const SizedBox(height: 8),
                  JournalGroupedCard(
                    children: [
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
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                dense: true,
                                title: Text(
                                  _sortLabel(order),
                                  style: journal.entryTitle
                                      .copyWith(fontSize: 14.5),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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
                        style: FilledButton.styleFrom(enableFeedback: false),
                        child: const Text('应用'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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
