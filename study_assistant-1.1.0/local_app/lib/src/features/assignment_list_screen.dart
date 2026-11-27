import 'dart:async';
import 'dart:math' as math;

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
import '../models/local_coursework_state.dart';
import '../models/personal_workspace.dart';
import '../models/pinned_assignments.dart';
import '../models/study_notebook.dart';
import '../models/sync_report.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import '../services/assignment_web_link.dart';
import '../services/clawd_companion_controller.dart';
import '../services/external_link_service.dart';
import '../services/home_sync_presentation.dart';
import '../services/interaction_feedback_service.dart';
import '../services/todo_copy_formatter.dart';
import 'widgets/appearance_controls.dart';
import 'widgets/clawd_speech_bubble.dart';
import 'widgets/clawd_title_stage.dart';
import 'widgets/home_action_bar.dart';
import 'widgets/home_filter_sheet.dart';
import 'widgets/home_list_sections.dart';
import 'widgets/home_manual_actions.dart';
import 'widgets/home_timeline_list.dart';
import 'widgets/journal_context_menu.dart';
import 'widgets/journal_pixel_buddy.dart';
import 'widgets/journal_sliver_header.dart';

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
  bool matches(
    Assignment assignment,
    DateTime now, {
    LocalCourseworkState coursework = const LocalCourseworkState.empty(),
  }) {
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
      noDeadline => AssignmentQuery.timelineBucketAt(assignment, now,
              coursework: coursework) ==
          AssignmentDeadlineBucket.confirmedNoDeadline,
      examUnknown => false,
      deadlinePending => AssignmentQuery.timelineBucketAt(assignment, now,
              coursework: coursework) ==
          AssignmentDeadlineBucket.unconfirmed,
    };
  }
}

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key, required this.store, this.clock});
  final AssignmentStore store;
  final DateTime Function()? clock;
  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen>
    with WidgetsBindingObserver {
  Timer? _clock;
  final _scrollController = ScrollController();
  final _homeStackKey = GlobalKey();
  final _syncStatusRowKey = GlobalKey();
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _bubbleScrollOffset = ValueNotifier<double>(0.0);
  final ValueNotifier<double?> _syncStatusBottomAtZero =
      ValueNotifier<double?>(null);
  final ValueNotifier<ClawdStageAnchor> _stageAnchor =
      ValueNotifier<ClawdStageAnchor>(
    const ClawdStageAnchor(centerX: 140.0, bottomY: 42.0, safeWidth: 160.0),
  );
  final _feedback = TransientFeedbackController();
  final Map<String, int> _pinPulseByKey = <String, int>{};
  final Set<String> _completingManualIds = <String>{};
  final Map<String, Timer> _completingManualTimers = <String, Timer>{};
  final Map<String, String> _completingPinnedKeyById = <String, String>{};
  PinnedAssignments? _completingPinnedSnapshot;
  late int _feedbackEpoch;
  String? _feedbackAccount;
  HomeFilters? _preExamStripFilters;
  int? _preExamStripEpoch;
  HomeSortOrder? _pendingSortOrder;
  int? _pendingSortEpoch;
  int _pendingSortSeq = 0;
  ClawdCompanionController? _clawdController;
  ClawdCompanionController? _localClawdController;
  bool _appResumed = true;
  bool _tickerEnabled = true;
  bool _isCurrentRoute = true;
  bool _reducedMotion = false;

  bool get _isBusy =>
      _refreshing ||
      store.isLoading ||
      store.syncReport.phase == SyncPhase.running;

  bool get _hasStoreSyncErrorOrPending =>
      ClawdCompanionController.resolveHasBlockingSyncNotice(
        store,
        localBusy: _refreshing,
      );

  ClawdCompanionController _ensureClawdController() {
    if (_clawdController != null) return _clawdController!;
    return _localClawdController ??=
        ClawdCompanionController(clock: widget.clock);
  }

  ({JournalPixelBuddyMood mood, ClawdPageContextSnapshot snapshot})
      _buildHomeClawdState() => prepareHomeClawdState(
            store: store,
            now: widget.clock?.call() ?? DateTime.now(),
            isBusy: _isBusy,
            courseKey: _courseKey,
            query: _query,
            deadlineFilter: _deadlineFilter,
            typeFilter: _typeFilter,
            completingManualIds: _completingManualIds,
          );

  void _syncClawdEnvironment({bool notify = true}) {
    final controller = _clawdController;
    if (controller == null) return;
    final isSharedController = !identical(controller, _localClawdController);
    if (isSharedController && !_isCurrentRoute) return;
    final state = _buildHomeClawdState();
    controller.updateEnvironment(
      displayPrefs: store.display,
      appResumed: _appResumed,
      tickerEnabled: isSharedController ? null : _tickerEnabled,
      reducedMotion: _reducedMotion,
      isSyncing: _isBusy,
      hasSyncErrorOrPending: _hasStoreSyncErrorOrPending,
      mood: state.mood,
      snapshot: state.snapshot,
      notify: notify,
    );
  }

  bool _canCheerOnCurrentRoute(ClawdCompanionController controller) {
    if (identical(controller, _localClawdController)) return true;
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? _isCurrentRoute;
    return routeCurrent &&
        controller.onPrimaryTab &&
        controller.lastVisitedTab == ClawdPrimaryTab.home;
  }

  void _triggerBuddyCheer() {
    if (!mounted || _reducedMotion) return;
    final controller = _ensureClawdController();
    if (_canCheerOnCurrentRoute(controller)) {
      controller.triggerCheer();
    }
  }

  void _clearCompletingManual({String? entryId, bool notify = false}) {
    if (entryId != null) {
      _completingManualTimers.remove(entryId)?.cancel();
      final removed = _completingManualIds.remove(entryId);
      _completingPinnedKeyById.remove(entryId);
      if (_completingPinnedKeyById.isEmpty) {
        _completingPinnedSnapshot = null;
      }
      if (removed && notify && mounted) {
        setState(() {});
      }
      return;
    }
    for (final timer in _completingManualTimers.values) {
      timer.cancel();
    }
    _completingManualTimers.clear();
    final hadAny = _completingManualIds.isNotEmpty;
    _completingManualIds.clear();
    _completingPinnedKeyById.clear();
    _completingPinnedSnapshot = null;
    if (hadAny && notify && mounted) {
      setState(() {});
    }
  }

  void _onManualCompletingStart(String entryId) {
    if (!mounted || JournalMotion.isReducedMotion(context)) return;
    _completingManualTimers.remove(entryId)?.cancel();
    final entry =
        store.notebook.entries.where((item) => item.id == entryId).firstOrNull;
    final wasPinned = entry != null && store.isManualPinned(entry);
    setState(() {
      _completingManualIds.add(entryId);
      if (wasPinned) {
        _completingPinnedKeyById[entryId] = entry.pinKey;
        _completingPinnedSnapshot ??= store.pinnedAssignments;
      }
    });
  }

  void _onManualCompletingCommit(String entryId) {
    if (!mounted || JournalMotion.isReducedMotion(context)) {
      _clearCompletingManual(entryId: entryId, notify: true);
      return;
    }
    _completingManualTimers.remove(entryId)?.cancel();
    setState(() {
      _completingManualIds.add(entryId);
    });
    final controller = _ensureClawdController();
    if (_canCheerOnCurrentRoute(controller)) {
      controller.triggerCheer();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_completingManualIds.contains(entryId)) return;
      _completingManualTimers.remove(entryId)?.cancel();
      _completingManualTimers[entryId] = Timer(
        const Duration(milliseconds: 220),
        () {
          _completingManualTimers.remove(entryId);
          if (!mounted) return;
          if (_completingManualIds.remove(entryId)) {
            _completingPinnedKeyById.remove(entryId);
            if (_completingPinnedKeyById.isEmpty) {
              _completingPinnedSnapshot = null;
            }
            setState(() {});
          }
        },
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onStoreChanged() {
    _checkFeedbackAccount();
    _syncClawdEnvironment();
  }

  void _checkFeedbackAccount() {
    if (_feedbackEpoch != store.accountEpoch ||
        _feedbackAccount != store.account) {
      _feedback.dismiss();
      _localClawdController?.resetForAccountChange();
      _clearCompletingManual();
      _pinPulseByKey.clear();
      _preExamStripFilters = null;
      _preExamStripEpoch = null;
      _feedbackEpoch = store.accountEpoch;
      _feedbackAccount = store.account;
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.positions.length != 1) {
      return;
    }
    final raw = _scrollController.offset;
    if ((raw - _bubbleScrollOffset.value).abs() >= 0.5 ||
        (raw == 0.0 && _bubbleScrollOffset.value != 0.0)) {
      _bubbleScrollOffset.value = raw;
    }
    final next = raw.clamp(0.0, 120.0);
    if ((next - _scrollOffset.value).abs() >= 1.5 ||
        (next == 0.0 && _scrollOffset.value != 0.0) ||
        (next == 120.0 && _scrollOffset.value != 120.0)) {
      _scrollOffset.value = next;
    }
  }

  void _scheduleSyncStatusMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final statusBox =
          _syncStatusRowKey.currentContext?.findRenderObject() as RenderBox?;
      final stackBox =
          _homeStackKey.currentContext?.findRenderObject() as RenderBox?;
      if (statusBox == null ||
          !statusBox.hasSize ||
          stackBox == null ||
          !stackBox.hasSize) {
        return;
      }
      final bottomLeft = statusBox.localToGlobal(
        Offset(0, statusBox.size.height),
        ancestor: stackBox,
      );
      final scrollOffset = _scrollController.hasClients &&
              _scrollController.positions.length == 1
          ? _scrollController.offset
          : _bubbleScrollOffset.value;
      final baseBottom = bottomLeft.dy + scrollOffset;
      final prev = _syncStatusBottomAtZero.value;
      if (prev == null || (baseBottom - prev).abs() > 0.5) {
        _syncStatusBottomAtZero.value = baseBottom;
      }
    });
  }

  @override
  void didUpdateWidget(covariant AssignmentListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != store) {
      oldWidget.store.removeListener(_onStoreChanged);
      _feedback.dismiss();
      _localClawdController?.resetForAccountChange();
      _clearCompletingManual();
      _pinPulseByKey.clear();
      _preExamStripFilters = null;
      _preExamStripEpoch = null;
      _pendingSortOrder = null;
      _pendingSortEpoch = null;
      _pendingSortSeq++;
      _feedbackEpoch = store.accountEpoch;
      _feedbackAccount = store.account;
      store.addListener(_onStoreChanged);
      _syncClawdEnvironment();
    }
  }

  @override
  void initState() {
    super.initState();
    _appResumed =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
            AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _feedbackEpoch = store.accountEpoch;
    _feedbackAccount = store.account;
    store.addListener(_onStoreChanged);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      _syncClawdEnvironment(notify: false);
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reducedMotion = JournalMotion.isReducedMotion(context);
    final scoped = ClawdCompanionScope.maybeOf(context);
    if (scoped != null) {
      _clawdController = scoped;
    } else {
      _clawdController = _localClawdController ??=
          ClawdCompanionController(clock: widget.clock);
    }
    if (_reducedMotion) {
      _clearCompletingManual();
    }
    _syncClawdEnvironment(notify: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollOffset.dispose();
    _bubbleScrollOffset.dispose();
    _syncStatusBottomAtZero.dispose();
    _stageAnchor.dispose();
    _localClawdController?.dispose();
    _clearCompletingManual();
    store.removeListener(_onStoreChanged);
    _feedback.dispose();
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextResumed = state == AppLifecycleState.resumed;
    if (_appResumed != nextResumed) {
      _appResumed = nextResumed;
      _syncClawdEnvironment();
    }
    if (nextResumed && mounted) setState(() {});
  }

  bool _refreshing = false;
  String? get _courseKey {
    final key = store.homeFilters.courseKey;
    if (key != null && store.termCatalog.isBlocked(key)) return null;
    return key;
  }

  String get _query => store.homeFilters.query;
  AssignmentDeadlineFilter get _deadlineFilter => store.homeFilters.deadline;
  HomeSortOrder get _sortOrder =>
      normalizedHomeSort(store.homeFilters.sortOrder);
  HomeSortOrder _effectiveSortOrder(int epoch) =>
      (_pendingSortEpoch == epoch && _pendingSortOrder != null)
          ? _pendingSortOrder!
          : _sortOrder;
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
          style: journal.metadata.copyWith(color: journal.onInvertedSurface),
        ),
        action: effectiveAction != null && effectiveLabel != null
            ? SnackBarAction(
                label: effectiveLabel,
                onPressed: effectiveAction,
              )
            : null,
      ),
    );
  }

  void _triggerCardPulse(String pinKey) {
    if (!mounted || JournalMotion.isReducedMotion(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || JournalMotion.isReducedMotion(context)) return;
      setState(() {
        _pinPulseByKey[pinKey] = (_pinPulseByKey[pinKey] ?? 0) + 1;
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _togglePin(Assignment assignment) async {
    if (!store.canTogglePin(assignment)) return;
    final ok = await store.togglePin(assignment);
    if (!mounted || !ok) return;
    final pinned = store.isPinned(assignment);
    JournalMotion.pin(store.display, pinned: pinned);
    _triggerCardPulse(AssignmentStore.pinKeyOf(assignment));
    if (pinned) {
      _triggerBuddyCheer();
    }
    feedback(pinned ? '已置顶' : '已取消置顶');
  }

  late final HomeManualActions _manualActions = HomeManualActions(
    store: store,
    feedback: (message, {action, actionLabel}) =>
        feedback(message, action: action, actionLabel: actionLabel),
    isMounted: () => mounted,
    onBouncePulse: _triggerCardPulse,
    onPinAdded: _triggerBuddyCheer,
    onCompletingStart: _onManualCompletingStart,
    onCompletingCommit: _onManualCompletingCommit,
    onCompletingCancel: (id) =>
        _clearCompletingManual(entryId: id, notify: true),
  );

  Future<void> _toggleTodayPlan(Assignment assignment) async {
    final epoch = store.accountEpoch;
    final day =
        PersonalWorkspace.dayKey(widget.clock?.call() ?? DateTime.now());
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

  Future<void> _copyNext7DaysTodos({required DateTime now}) async {
    final result = TodoCopyFormatter.formatNext7Days(
      store.homeCatalogAssignments,
      manualEntries: store.isAuthenticated ? store.notebook.entries : const [],
      now: now,
      index: store.homeDisplayIndex,
      coursework: store.courseworkState,
    );
    if (result.isEmpty) {
      feedback('近 7 天暂无可复制的待办');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: result.text!));
      if (mounted) {
        feedback('已复制近 7 天待办（共 ${result.count} 项）');
      }
    } catch (_) {
      if (mounted) {
        feedback('复制失败，请稍后重试');
      }
    }
  }

  Future<void> _openMoreMenu(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    Rect? anchorRect;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      anchorRect = topLeft & box.size;
    }
    await showJournalContextMenu(
      context: context,
      anchorRect: anchorRect,
      displayPrefs: store.display,
      actions: [
        JournalContextMenuAction(
          label: '添加课业或待办',
          icon: Icons.add_rounded,
          onSelected: () => _manualActions.openEditor(
            context,
            initialKind: _typeFilter == AssignmentTypeFilter.exam
                ? ManualEntry.kindExam
                : ManualEntry.kindTodo,
          ),
        ),
        JournalContextMenuAction(
          label: '个人待办与考试',
          icon: Icons.checklist_rounded,
          onSelected: () {
            if (mounted) context.push('/agenda');
          },
        ),
        JournalContextMenuAction(
          label: '每日计划',
          icon: Icons.today_outlined,
          onSelected: () {
            if (mounted) context.push('/plan');
          },
        ),
        JournalContextMenuAction(
          label: '切换主题（当前：${store.display.themeMode.label}）',
          icon: switch (store.display.themeMode) {
            JournalThemeMode.system => Icons.brightness_auto_outlined,
            JournalThemeMode.light => Icons.light_mode_outlined,
            JournalThemeMode.dark => Icons.dark_mode_outlined,
          },
          onSelected: () => _cycleTheme(context),
        ),
        JournalContextMenuAction(
          label: '复制近 7 天待办',
          icon: Icons.copy_all_outlined,
          onSelected: () => unawaited(
            _copyNext7DaysTodos(now: widget.clock?.call() ?? DateTime.now()),
          ),
        ),
        JournalContextMenuAction(
          label: '同步详情',
          icon: Icons.sync_alt_rounded,
          onSelected: () {
            if (mounted) context.push('/sync');
          },
        ),
      ],
    );
  }

  Future<void> _openContextMenu(
    BuildContext itemContext,
    Assignment assignment,
    Widget previewCard, {
    required bool inTodayPlan,
    bool pinned = false,
    List<String> pinnedVisibleKeys = const [],
  }) async {
    final box = itemContext.findRenderObject() as RenderBox?;
    Rect? anchorRect;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      anchorRect = topLeft & box.size;
    }
    final url = AssignmentWebLink.validatedUrl(assignment);
    final canPin = store.canTogglePin(assignment);
    final isPinned = store.isPinned(assignment);
    final pinKey = AssignmentStore.pinKeyOf(assignment);
    final pinIndex = pinnedVisibleKeys.indexOf(pinKey);
    final actions = <JournalContextMenuAction>[
      if (url != null)
        JournalContextMenuAction(
          label: assignment.isExam ? '在学习通查看' : '在学习通打开',
          icon: Icons.open_in_new_rounded,
          onSelected: () => openAssignment(assignment.id),
        ),
      if (pinned && pinnedVisibleKeys.length >= 2 && pinIndex > 0)
        JournalContextMenuAction(
          label: '置顶上移',
          icon: Icons.arrow_upward_rounded,
          onSelected: () {
            final next = List<String>.of(pinnedVisibleKeys);
            final moved = next.removeAt(pinIndex);
            next.insert(pinIndex - 1, moved);
            JournalMotion.selectionTick(store.display);
            unawaited(store.reorderPinned(next));
          },
        ),
      if (pinned &&
          pinnedVisibleKeys.length >= 2 &&
          pinIndex >= 0 &&
          pinIndex < pinnedVisibleKeys.length - 1)
        JournalContextMenuAction(
          label: '置顶下移',
          icon: Icons.arrow_downward_rounded,
          onSelected: () {
            final next = List<String>.of(pinnedVisibleKeys);
            final moved = next.removeAt(pinIndex);
            next.insert(pinIndex + 1, moved);
            JournalMotion.selectionTick(store.display);
            unawaited(store.reorderPinned(next));
          },
        ),
      if (canPin)
        JournalContextMenuAction(
          label: isPinned ? '取消置顶' : '置顶',
          icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
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
    _clawdController?.dismissBubble();
    setState(() => _refreshing = true);
    _syncClawdEnvironment();
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
      if (mounted) {
        setState(() => _refreshing = false);
        _syncClawdEnvironment();
      }
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

  String _syncProgressLabel(AssignmentStore store) {
    final progress = store.homeSyncProgress;
    if (progress == null) return '正在刷新作业…';
    if (progress.stage == AssignmentSyncStage.details &&
        progress.attemptedCount > 0) {
      return '${progress.stageLabel}，已处理 ${progress.resolvedCount} 项详情';
    }
    return progress.stageLabel;
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

  Future<void> _selectSortOrder(
    HomeSortOrder order,
    int openingEpoch,
    String? openingAccount,
  ) async {
    if (!mounted ||
        store.accountEpoch != openingEpoch ||
        store.account != openingAccount) {
      return;
    }
    final seq = ++_pendingSortSeq;
    _pendingSortOrder = order;
    _pendingSortEpoch = openingEpoch;
    try {
      await _saveFilters(
        HomeFilters(
          query: _query,
          courseKey: _courseKey,
          deadline: _deadlineFilter,
          type: _typeFilter,
          sortOrder: order,
        ),
        openingEpoch,
        openingAccount,
      );
    } finally {
      if (_pendingSortSeq == seq) {
        _pendingSortOrder = null;
        _pendingSortEpoch = null;
      }
    }
  }

  Future<void> _openFilters() async {
    final openingEpoch = store.accountEpoch;
    final openingAccount = store.account;
    final selection = await showHomeFilterSheet(
      context: context,
      store: store,
      initialFilters: HomeFilters(
        query: _query,
        courseKey: _courseKey,
        deadline: _deadlineFilter,
        type: _typeFilter,
        sortOrder: _effectiveSortOrder(openingEpoch),
      ),
      clock: widget.clock,
    );
    if (!mounted ||
        selection == null ||
        store.accountEpoch != openingEpoch ||
        store.account != openingAccount) {
      return;
    }
    final nextQuery = selection.query.trim();
    final filtersChanged = nextQuery != _query.trim() ||
        selection.courseKey != _courseKey ||
        selection.deadline != _deadlineFilter ||
        selection.type != _typeFilter;
    if (filtersChanged) {
      _preExamStripFilters = null;
      _preExamStripEpoch = null;
    }
    _pendingSortOrder = null;
    _pendingSortEpoch = null;
    _pendingSortSeq++;
    await _saveFilters(
      HomeFilters(
        query: nextQuery,
        courseKey: selection.courseKey,
        deadline: selection.deadline,
        type: selection.type,
        sortOrder: selection.sortOrder,
      ),
      openingEpoch,
      openingAccount,
    );
  }

  void _toggleUpcomingExamView() {
    final inExamView = _typeFilter == AssignmentTypeFilter.exam;
    final epoch = store.accountEpoch;
    final account = store.account;
    final effectiveSortOrder = _effectiveSortOrder(epoch);
    if (!inExamView) {
      _preExamStripFilters = HomeFilters(
        query: _query,
        courseKey: _courseKey,
        deadline: _deadlineFilter,
        type: _typeFilter,
        sortOrder: effectiveSortOrder,
      );
      _preExamStripEpoch = epoch;
      unawaited(_saveFilters(
        HomeFilters(
          query: _query,
          courseKey: _courseKey,
          deadline: AssignmentDeadlineFilter.all,
          type: AssignmentTypeFilter.exam,
          sortOrder: effectiveSortOrder,
        ),
        epoch,
        account,
      ));
    } else {
      final previous =
          _preExamStripEpoch == epoch ? _preExamStripFilters : null;
      _preExamStripFilters = null;
      _preExamStripEpoch = null;
      final previousCourseKey = previous?.courseKey;
      final restoredCourseKey = previous == null
          ? _courseKey
          : (previousCourseKey != null &&
                  store.termCatalog.isBlocked(previousCourseKey)
              ? null
              : previousCourseKey);
      unawaited(_saveFilters(
        HomeFilters(
          query: previous?.query ?? _query,
          courseKey: restoredCourseKey,
          deadline: previous?.deadline ?? _deadlineFilter,
          type: previous?.type ?? AssignmentTypeFilter.all,
          sortOrder: effectiveSortOrder,
        ),
        epoch,
        account,
      ));
    }
  }

  JournalPixelBuddyPose _poseForController(
    ClawdCompanionController controller,
  ) =>
      switch (controller.transientPose) {
        ClawdTransientPose.none => JournalPixelBuddyPose.normal,
        ClawdTransientPose.wave => JournalPixelBuddyPose.wave,
        ClawdTransientPose.doubleStar => JournalPixelBuddyPose.doubleStar,
        ClawdTransientPose.tsundere => JournalPixelBuddyPose.tsunderePuff,
        ClawdTransientPose.petting => JournalPixelBuddyPose.petSquint,
        ClawdTransientPose.grabbed => JournalPixelBuddyPose.grabbedFlail,
        ClawdTransientPose.landing => JournalPixelBuddyPose.landing,
        ClawdTransientPose.cheer => JournalPixelBuddyPose.cheer,
      };

  Widget _buildClawdBubbleOverlay(
    BuildContext context, {
    required ClawdCompanionController controller,
    required JournalPalette journal,
    required bool showPixelBuddy,
    required bool showSliverBuddy,
    required bool busy,
    required bool syncErrorOrPending,
    required int headerActionsCount,
  }) =>
      Positioned.fill(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            controller,
            _scrollOffset,
            _bubbleScrollOffset,
            _stageAnchor,
            _syncStatusBottomAtZero,
          ]),
          builder: (context, _) {
            final bubble = controller.activeBubble;
            if (!showPixelBuddy ||
                busy ||
                syncErrorOrPending ||
                bubble == null ||
                bubble.tab != ClawdPrimaryTab.home) {
              return const SizedBox.shrink();
            }
            final offset = _scrollOffset.value;
            final actualOffset = _bubbleScrollOffset.value;
            final anchor = _stageAnchor.value;
            final fallbackBottomAtZero =
                math.max(114.0, 14.0 + anchor.bottomY + 58.0);
            final statusBottom =
                (_syncStatusBottomAtZero.value ?? fallbackBottomAtZero) -
                    actualOffset;
            final sliverVisible = showSliverBuddy && offset >= 30.6;
            final sliverShowing =
                sliverVisible && (bubble.fromSliver || offset >= 54.0);
            final screenWidth = MediaQuery.sizeOf(context).width;
            final double top;
            final double minLeft;
            final double safeRight;
            final double anchorX;
            final double maxWidth;
            if (sliverShowing) {
              minLeft = 18.0;
              safeRight = screenWidth - 18.0 - headerActionsCount * 48.0 - 8.0;
              final availableWidth = math.max(36.0, safeRight - minLeft);
              maxWidth = math.min(210.0, availableWidth);
              final tp = TextPainter(
                text: TextSpan(
                  text: '课业手记',
                  style: journal.pageTitle.copyWith(fontSize: 19.5),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final titleAvailable = math.max(
                12.0,
                screenWidth - 36.0 - headerActionsCount * 48.0 - 5.0 - 26.0,
              );
              final titleW = math.min(tp.width, titleAvailable);
              tp.dispose();
              final rawBuddyCenter = 18.0 + titleW + 5.0 + 13.0;
              anchorX = rawBuddyCenter.clamp(
                minLeft + 13.0,
                math.max(minLeft + 13.0, safeRight),
              );
              top = math.max(50.0, statusBottom + 2.0);
            } else {
              minLeft = 16.0;
              safeRight = 16.0 + anchor.safeWidth;
              maxWidth = math.min(
                210.0,
                math.max(36.0, anchor.safeWidth),
              );
              anchorX = 16.0 + anchor.centerX;
              final stageBottom = 14.0 - actualOffset + anchor.bottomY;
              top = math.max(
                8.0,
                math.max(stageBottom + 2.0, statusBottom + 2.0),
              );
            }
            return ClawdAnchoredSpeechBubble(
              bubbleKey: const ValueKey('clawd-speech-bubble'),
              message: bubble,
              anchorX: anchorX,
              top: top,
              minLeft: minLeft,
              safeRight: safeRight,
              maxWidth: maxWidth,
              pointerDirection: ClawdBubblePointerDirection.up,
              onTap: controller.onBubbleTapped,
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final journal = Journal.of(context);
        final busy = _refreshing ||
            store.isLoading ||
            store.syncReport.phase == SyncPhase.running;
        final recoveryScope = AssignmentRecoveryScope.of(context);
        final now = widget.clock?.call() ?? DateTime.now();
        final data = prepareHomeViewData(
          store: store,
          now: now,
          busy: busy,
          recoveryActive: recoveryScope != null,
          recoveryMatches: recoveryScope == null
              ? null
              : (assignment) => recoveryScope.matches(
                    assignment,
                    now,
                    coursework: store.courseworkState,
                  ),
          courseKey: _courseKey,
          query: _query,
          deadlineFilter: _deadlineFilter,
          typeFilter: _typeFilter,
          sortOrder: _sortOrder,
          completingManualIds: _completingManualIds,
        );
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        _reducedMotion = reduceMotion;
        final showPixelBuddy = store.display.showPixelBuddy;
        final controller = _ensureClawdController();
        final syncAction = data.sync.action == HomeSyncAction.login ||
                data.sync.action == HomeSyncAction.verify
            ? data.sync.action
            : HomeSyncAction.retry;
        final syncErrorOrPending =
            ClawdCompanionController.resolveHasBlockingSyncNotice(
          store,
          localBusy: _refreshing,
        );
        final syncBusyWithBuddy = busy && showPixelBuddy;
        final epoch = store.accountEpoch;
        final account = store.account;

        final headerBlock = HomeAccountGuardScope(
          currentAccountEpoch: () => store.accountEpoch,
          currentAccount: () => store.account,
          child: HomeHeaderSection(
            controller: controller,
            showPixelBuddy: showPixelBuddy,
            busy: busy,
            reduceMotion: reduceMotion,
            recoveryLabel: recoveryScope?.label,
            recoveryItemCount: data.items.length,
            syncErrorOrPending: syncErrorOrPending,
            displayPrefs: store.display,
            buddyMood: data.buddyMood,
            homeSnapshot: data.homeSnapshot,
            stageAnchor: _stageAnchor,
            statusRowKey: _syncStatusRowKey,
            sync: data.sync,
            syncPhase: store.syncReport.phase,
            statusText: data.statusText,
            syncStage: store.homeSyncProgress?.stage,
            syncBusyWithBuddy: syncBusyWithBuddy,
            showDueSummary: data.showDueSummary,
            dueSummary: data.dueSummary,
            plans: data.plans,
            upcomingExam: data.upcomingExam,
            filtersActive: data.filtersActive,
            query: _query,
            typeFilter: _typeFilter,
            deadlineFilter: _deadlineFilter,
            courseKey: _courseKey,
            sortOrder: data.sortOrder,
            courseOptions: data.options,
            syncProgressLabel: _syncProgressLabel(store),
            hasTimelineItems: data.sortedTimelineItems.isNotEmpty,
            onRefresh: () => refresh(syncAction),
            onRetrySync: () => refresh(HomeSyncAction.retry),
            onOpenSyncIssues: () => context.push('/sync?expand=issues'),
            onToggleNearDueFilter: () {
              final nextDeadline =
                  _deadlineFilter == AssignmentDeadlineFilter.next7Days
                      ? AssignmentDeadlineFilter.all
                      : AssignmentDeadlineFilter.next7Days;
              unawaited(_saveFilters(
                HomeFilters(
                  query: _query,
                  courseKey: _courseKey,
                  deadline: nextDeadline,
                  type: _typeFilter,
                  sortOrder: _effectiveSortOrder(epoch),
                ),
                epoch,
                account,
              ));
            },
            onOpenMoreMenu: (anchorContext) =>
                unawaited(_openMoreMenu(anchorContext)),
            onExitRecoveryScope: () => _exitRecoveryScope(context),
            onOpenPlan: () => context.push('/plan'),
            onToggleUpcomingExam: _toggleUpcomingExamView,
            onOpenFilters: () => unawaited(_openFilters()),
            onAddManual: () => _manualActions.openEditor(
              context,
              initialKind: _typeFilter == AssignmentTypeFilter.exam
                  ? ManualEntry.kindExam
                  : ManualEntry.kindTodo,
            ),
            onClearQuery: () => _saveFilters(
              HomeFilters(
                query: '',
                courseKey: _courseKey,
                deadline: _deadlineFilter,
                type: _typeFilter,
                sortOrder: _effectiveSortOrder(epoch),
              ),
              epoch,
              account,
            ),
            onClearType: () {
              _preExamStripFilters = null;
              _preExamStripEpoch = null;
              unawaited(_saveFilters(
                HomeFilters(
                  query: _query,
                  courseKey: _courseKey,
                  deadline: _deadlineFilter,
                  type: AssignmentTypeFilter.all,
                  sortOrder: _effectiveSortOrder(epoch),
                ),
                epoch,
                account,
              ));
            },
            onClearDeadline: () => _saveFilters(
              HomeFilters(
                query: _query,
                courseKey: _courseKey,
                deadline: AssignmentDeadlineFilter.all,
                type: _typeFilter,
                sortOrder: _effectiveSortOrder(epoch),
              ),
              epoch,
              account,
            ),
            onClearCourse: () => _saveFilters(
              HomeFilters(
                query: _query,
                courseKey: null,
                deadline: _deadlineFilter,
                type: _typeFilter,
                sortOrder: _effectiveSortOrder(epoch),
              ),
              epoch,
              account,
            ),
            onResetSortOrder: () => unawaited(
              _selectSortOrder(HomeSortOrder.deadlineAsc, epoch, account),
            ),
            onResetAllFilters: () {
              _preExamStripFilters = null;
              _preExamStripEpoch = null;
              unawaited(_saveFilters(
                HomeFilters(sortOrder: _effectiveSortOrder(epoch)),
                epoch,
                account,
              ));
            },
          ),
        );

        final listView = HomeTimelineList(
          scrollController: _scrollController,
          store: store,
          now: now,
          recoveryQueryParameter: AssignmentRecoveryScope.queryParameter,
          recoveryQueryValue: recoveryScope?.queryValue,
          headerBlock: headerBlock,
          catalogAssignments: data.catalogAssignments,
          displayAssignments: data.displayAssignments,
          displayIndex: data.displayIndex,
          coursework: data.coursework,
          courseOptions: data.options,
          sortedTimelineItems: data.sortedTimelineItems,
          plannedIds: data.plannedIds,
          openingAssignments: _openingAssignments,
          pinPulseByKey: _pinPulseByKey,
          completingPinnedKeyById: _completingPinnedKeyById,
          completingPinnedSnapshot: _completingPinnedSnapshot,
          manualActions: _manualActions,
          courseKey: _courseKey,
          typeFilter: _typeFilter,
          sortOrder: data.sortOrder,
          filtersActive: data.filtersActive,
          selectedCourseIdle: data.selectedCourseIdle,
          busy: busy,
          onClearCourseFilter: () => _saveFilters(
            HomeFilters(
              query: _query,
              deadline: _deadlineFilter,
              type: _typeFilter,
              sortOrder: _effectiveSortOrder(epoch),
            ),
            epoch,
            account,
          ),
          onClearAllFilters: () => _saveFilters(
            HomeFilters(sortOrder: _effectiveSortOrder(epoch)),
            epoch,
            account,
          ),
          onOpenAssignment: openAssignment,
          onToggleTodayPlan: _toggleTodayPlan,
          onTogglePin: _togglePin,
          onOpenContextMenu: _openContextMenu,
        );

        final headerActions = buildHomeSliverActions(
          context,
          recoveryActive: recoveryScope != null,
          busy: busy,
          onAddManual: () => _manualActions.openEditor(
            context,
            initialKind: _typeFilter == AssignmentTypeFilter.exam
                ? ManualEntry.kindExam
                : ManualEntry.kindTodo,
          ),
          onRefresh: () => refresh(syncAction),
          onOpenMoreMenu: (anchorContext) =>
              unawaited(_openMoreMenu(anchorContext)),
        );
        final showSliverBuddy = showPixelBuddy &&
            !JournalLayout.isLargeText(context) &&
            MediaQuery.sizeOf(context).width >= 330;
        final Widget? sliverStatusContent = syncBusyWithBuddy
            ? HomeSliverSyncStatus(
                key: const ValueKey('home-sliver-sync-status'),
                syncTick: controller.syncTick,
                syncStage: store.homeSyncProgress?.stage,
                reduceMotion: reduceMotion,
              )
            : null;

        _scheduleSyncStatusMeasure();

        return Stack(
          key: _homeStackKey,
          children: [
            listView,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => JournalSliverHeader(
                    title: '课业手记',
                    scrollOffset: offset,
                    titleTrailing: showSliverBuddy
                        ? JournalPixelBuddy(
                            key: const ValueKey('home-sliver-pixel-buddy'),
                            mood: data.buddyMood,
                            mini: true,
                            size: 20.0,
                            onTap: () => controller.registerTap(
                              snapshot: data.homeSnapshot,
                              fromSliver: true,
                            ),
                            syncTickListenable: controller.syncTick,
                            celebratePulse: controller.celebratePulse,
                            allowTapCombo: !busy && !syncErrorOrPending,
                            poseOverride: _poseForController(controller),
                            posePulse: controller.transientPulse,
                          )
                        : null,
                    statusContent: sliverStatusContent,
                    actions: headerActions,
                  ),
                ),
              ),
            ),
            _buildClawdBubbleOverlay(
              context,
              controller: controller,
              journal: journal,
              showPixelBuddy: showPixelBuddy,
              showSliverBuddy: showSliverBuddy,
              busy: busy,
              syncErrorOrPending: syncErrorOrPending,
              headerActionsCount: headerActions.length,
            ),
          ],
        );
      });
}
