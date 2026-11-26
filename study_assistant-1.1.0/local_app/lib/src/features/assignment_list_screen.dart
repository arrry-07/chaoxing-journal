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
import '../services/home_course_filter.dart';
import '../services/home_manual_timeline.dart';
import '../services/home_sync_presentation.dart';
import '../services/home_upcoming_exam.dart';
import '../services/interaction_feedback_service.dart';
import '../services/todo_copy_formatter.dart';
import 'widgets/appearance_controls.dart';
import 'widgets/assignment_card.dart';
import 'widgets/clawd_speech_bubble.dart';
import 'widgets/clawd_title_stage.dart';
import 'widgets/home_manual_actions.dart';
import 'widgets/home_course_filter_row.dart';
import 'widgets/home_manual_sections.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_context_menu.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_picker_sheet.dart';
import 'widgets/journal_pixel_buddy.dart';
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
  ClawdCompanionController? _clawdController;
  ClawdCompanionController? _localClawdController;
  bool _appResumed = true;
  bool _tickerEnabled = true;
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
      _buildHomeClawdState() {
    final now = widget.clock?.call() ?? DateTime.now();
    final coursework = store.courseworkState;
    final catalogAssignments = _courseKey == null
        ? store.homeCatalogAssignments
        : store.homeCatalogAssignmentsWithSelectedCourse(_courseKey);
    final displayIndex = _courseKey == null
        ? store.homeDisplayIndex
        : AssignmentDisplayIndex.from(catalogAssignments);
    final dueSummary = HomeDueSummary.from(
      catalogAssignments,
      now: now,
      index: displayIndex,
      coursework: coursework,
      manualEntries: store.isAuthenticated ? store.notebook.entries : const [],
    );
    final displayAssignments = AssignmentQuery.currentDisplay(
      catalogAssignments,
      now,
      index: displayIndex,
      coursework: coursework,
    );
    final items = AssignmentQuery.filterHome(
      catalogAssignments,
      query: _query,
      courseKey: _courseKey,
      deadline: _deadlineFilter,
      type: _typeFilter,
      includeHistorical: false,
      index: displayIndex,
      now: now,
      coursework: coursework,
    );
    final selectedCourseName = _courseKey == null
        ? null
        : store.courses
                .where((course) => course.key == _courseKey)
                .firstOrNull
                ?.name ??
            catalogAssignments
                .where((assignment) => assignment.courseKey == _courseKey)
                .firstOrNull
                ?.courseName;
    final manualItems = HomeManualTimeline.filterManualEntries(
      store.isAuthenticated ? store.notebook.entries : const <ManualEntry>[],
      query: _query,
      selectedCourseName: selectedCourseName,
      deadline: _deadlineFilter,
      type: _typeFilter,
      keepVisibleIds: _completingManualIds,
      now: now,
    );
    final showDueSummary = catalogAssignments.isNotEmpty ||
        displayAssignments.isNotEmpty ||
        manualItems.isNotEmpty ||
        store.syncReport.phase == SyncPhase.success ||
        store.syncReport.lastDataSuccessAt != null ||
        store.lastSyncAt != null;
    final mood = _isBusy
        ? JournalPixelBuddyMood.syncing
        : dueSummary.dueToday > 0
            ? JournalPixelBuddyMood.dueToday
            : (showDueSummary &&
                    dueSummary.dueToday == 0 &&
                    (dueSummary.completedToday > 0 ||
                        (items.isEmpty && manualItems.isEmpty)))
                ? JournalPixelBuddyMood.allClear
                : JournalPixelBuddyMood.idle;
    final followedCourses =
        store.courses.where((c) => store.follows(c.key)).length;
    final activeAgenda = store.notebook.entries.where((e) => !e.done).length;
    final snapshot = ClawdPageContextSnapshot(
      tab: ClawdPrimaryTab.home,
      dueToday: dueSummary.dueToday,
      dueIn3Days: dueSummary.dueIn3Days,
      completedToday: dueSummary.completedToday,
      followedCourseCount: followedCourses,
      activeAgendaCount: activeAgenda,
    );
    return (mood: mood, snapshot: snapshot);
  }

  void _syncClawdEnvironment({bool notify = true}) {
    final controller = _clawdController;
    if (controller == null) return;
    final state = _buildHomeClawdState();
    controller.updateEnvironment(
      displayPrefs: store.display,
      appResumed: _appResumed,
      tickerEnabled: _tickerEnabled,
      reducedMotion: _reducedMotion,
      isSyncing: _isBusy,
      hasSyncErrorOrPending: _hasStoreSyncErrorOrPending,
      mood: state.mood,
      snapshot: state.snapshot,
      notify: notify,
    );
  }

  void _triggerBuddyCheer() {
    if (!mounted || _reducedMotion) return;
    _ensureClawdController().triggerCheer();
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
    _ensureClawdController().triggerCheer();
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
      _clawdController?.resetForAccountChange();
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
      _clawdController?.resetForAccountChange();
      _clearCompletingManual();
      _pinPulseByKey.clear();
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

  /// Per-course item counts for the picker, refreshed on every build so the
  /// sheet can recount when the user changes type or deadline before applying.
  Map<String, int> Function(AssignmentTypeFilter, AssignmentDeadlineFilter)
      _courseCountsFor = (_, __) => const {};

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
          onSelected: () => _manualActions.openEditor(context),
        ),
        JournalContextMenuAction(
          label: '每日计划',
          icon: Icons.today_outlined,
          onSelected: () {
            if (mounted) context.push('/plan');
          },
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
        final filtersActive = _query.trim().isNotEmpty ||
            _typeFilter != AssignmentTypeFilter.all ||
            _courseKey != null ||
            _deadlineFilter != AssignmentDeadlineFilter.all;
        final coursework = store.courseworkState;
        final termCatalog = store.termCatalog;
        final catalogAssignments = _courseKey == null
            ? store.homeCatalogAssignments
            : store.homeCatalogAssignmentsWithSelectedCourse(_courseKey);
        final examSources = catalogAssignments;
        final displayIndex = _courseKey == null
            ? store.homeDisplayIndex
            : AssignmentDisplayIndex.from(catalogAssignments);
        final displayAssignments = AssignmentQuery.currentDisplay(
          catalogAssignments,
          now,
          index: displayIndex,
          coursework: coursework,
        );
        final allFollowedSources = [
          for (final group in store.localRecordGroups)
            if (!group.hidden &&
                (group.primary.courseKey == null ||
                    (store.follows(group.primary.courseKey!) &&
                        !termCatalog.isBlocked(group.primary.courseKey!))))
              ...group.sources,
        ];
        final pickerIndex = allFollowedSources.isEmpty
            ? displayIndex
            : AssignmentDisplayIndex.from(allFollowedSources);
        final pickerAssignments = AssignmentQuery.currentDisplay(
          AssignmentQuery.scope(allFollowedSources, {}),
          now,
          index: pickerIndex,
          coursework: coursework,
        );
        final options = buildHomeCourseFilterOptions(
          assignments: pickerAssignments,
          catalog: [
            for (final course in store.courses)
              if (store.follows(course.key) &&
                  !termCatalog.isBlocked(course.key))
                course,
          ],
          records: allFollowedSources,
          selectedCourseKey: _courseKey,
          termCatalog: termCatalog,
          includeIdleCourses: true,
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
                coursework: coursework,
              )
            : displayAssignments
                .where((assignment) => recoveryScope.matches(
                      assignment,
                      now,
                      coursework: coursework,
                    ))
                .toList();
        final sortOrder = _sortOrder;
        final selectedCourseName = _courseKey == null
            ? null
            : options
                .where((option) => option.courseKey == _courseKey)
                .firstOrNull
                ?.name;
        final manualItems = recoveryScope == null
            ? HomeManualTimeline.filterManualEntries(
                store.isAuthenticated
                    ? store.notebook.entries
                    : const <ManualEntry>[],
                query: _query,
                selectedCourseName: selectedCourseName,
                deadline: _deadlineFilter,
                type: _typeFilter,
                keepVisibleIds: _completingManualIds,
                now: now,
              )
            : const <ManualEntry>[];
        final selectedCourseIdle = recoveryScope == null &&
            _courseKey != null &&
            _query.trim().isEmpty &&
            _deadlineFilter == AssignmentDeadlineFilter.all &&
            _typeFilter == AssignmentTypeFilter.all &&
            manualItems.isEmpty &&
            !displayAssignments.any((a) => a.courseKey == _courseKey);
        _courseCountsFor = (type, deadline) => countHomeCourseItems(
              options: options,
              filteredAssignments: AssignmentQuery.filterHome(
                allFollowedSources,
                query: _query,
                deadline: deadline,
                type: type,
                includeHistorical: false,
                index: pickerIndex,
                now: now,
                coursework: coursework,
              ),
              filteredManualEntries: HomeManualTimeline.filterManualEntries(
                store.isAuthenticated
                    ? store.notebook.entries
                    : const <ManualEntry>[],
                query: _query,
                deadline: deadline,
                type: type,
                now: now,
              ),
            );
        final sortedTimelineItems = HomeManualTimeline.mergeAndSort(
          assignments: items,
          manualEntries: manualItems,
          order: sortOrder,
          now: now,
          sourceRecords: catalogAssignments,
          displayIndex: displayIndex,
          prioritizeStartOnly: recoveryScope == null,
          coursework: coursework,
          keepVisibleIds: _completingManualIds,
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
            serviceWarning: (store.hasNonQuietServiceWarning ||
                    store.recoveryWarning != null ||
                    store.operationError != null) &&
                store.syncReport.phase == SyncPhase.success,
            widgetWarning:
                store.serviceWarnings.any((w) => w.contains('小组件')) &&
                    store.syncReport.phase == SyncPhase.success);
        final dueSummary = HomeDueSummary.from(
          catalogAssignments,
          now: now,
          index: displayIndex,
          coursework: coursework,
          manualEntries:
              store.isAuthenticated ? store.notebook.entries : const [],
        );
        final showDueSummary = recoveryScope == null &&
            (catalogAssignments.isNotEmpty ||
                displayAssignments.isNotEmpty ||
                manualItems.isNotEmpty ||
                store.syncReport.phase == SyncPhase.success ||
                store.syncReport.lastDataSuccessAt != null ||
                store.lastSyncAt != null);
        final statusText = sync.gentle && sync.action == HomeSyncAction.retry
            ? '${sync.summary} · 重试'
            : sync.showCached
                ? '${sync.summary} · 显示上次记录'
                : sync.summary;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        _reducedMotion = reduceMotion;
        final showPixelBuddy = store.display.showPixelBuddy;
        final controller = _ensureClawdController();
        final syncAction = sync.action == HomeSyncAction.login ||
                sync.action == HomeSyncAction.verify
            ? sync.action
            : HomeSyncAction.retry;
        final upcomingExam = recoveryScope == null
            ? HomeUpcomingExam.select(
                catalogAssignments,
                now: now,
                index: displayIndex,
                coursework: coursework,
                courseKey: _courseKey,
              )
            : null;

        Widget buildCard(
          Assignment a, {
          bool pinned = false,
          bool preview = false,
          bool previewOnly = false,
          Widget? dragHandle,
          VoidCallback? onLongPress,
        }) =>
            AssignmentCard(
              key: preview ? null : ValueKey('assignment-${a.id}'),
              assignment: a,
              examSources: examSources,
              displayIndex: displayIndex,
              courseworkEntry: store.courseworkEntryFor(a),
              now: now,
              showFullDeadline: false,
              showDivider: false,
              enableTapFeedback: false,
              inPinnedSection: pinned,
              dragHandle: preview ? null : dragHandle,
              compact: store.display.compact,
              countdown: store.display.countdown,
              deadlinePending:
                  preview ? false : store.isHomeDeadlinePending(a.id),
              hasDeadlineAlert:
                  preview ? false : store.activeDeadlineAlertFor(a) != null,
              previewOnly: preview ? false : previewOnly,
              previewSaving: !preview &&
                  store.homeSyncProgress?.stage == AssignmentSyncStage.saving,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              onOpenAssignment:
                  preview || AssignmentWebLink.validatedUrl(a) == null
                      ? null
                      : () => openAssignment(a.id),
              opening: !preview && _openingAssignments.contains(a.id),
              onLongPress: preview ? null : onLongPress,
              onTap: preview
                  ? () {}
                  : () {
                      InteractionFeedback.trigger(store.display);
                      final path = '/assignments/${Uri.encodeComponent(a.id)}';
                      final scope = recoveryScope == null
                          ? ''
                          : '?${AssignmentRecoveryScope.queryParameter}=${recoveryScope.queryValue}';
                      context.push('$path$scope');
                    },
            );

        Widget card(
          Assignment a, {
          bool pinned = false,
          Widget? dragHandle,
          List<String> pinnedVisibleKeys = const [],
        }) {
          final previewOnly = store.isHomeAssignmentPreviewOnly(a.id);
          if (previewOnly) {
            return buildCard(a, pinned: pinned, previewOnly: true);
          }
          final inTodayPlan = plannedIds.contains(a.id);
          final canPin = store.canTogglePin(a);
          final isPinned = store.isPinned(a);

          final pinKey = AssignmentStore.pinKeyOf(a);
          return Builder(
            key: ValueKey('home-timeline-item-$pinKey'),
            builder: (itemContext) {
              final interactiveCard = buildCard(
                a,
                pinned: pinned,
                dragHandle: dragHandle,
                onLongPress: () => _openContextMenu(
                  itemContext,
                  a,
                  buildCard(a, pinned: pinned, preview: true),
                  inTodayPlan: inTodayPlan,
                  pinned: pinned,
                  pinnedVisibleKeys: pinnedVisibleKeys,
                ),
              );

              return JournalMicroBounce(
                key: ValueKey('home-micro-bounce-$pinKey'),
                pulse: _pinPulseByKey[pinKey] ?? 0,
                child: JournalSwipeTile(
                  key: ValueKey('swipe-${a.id}'),
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
                ),
              );
            },
          );
        }

        Widget timelineCard(
          HomeTimelineItem item, {
          bool pinned = false,
          Widget? dragHandle,
          List<String> pinnedVisibleKeys = const [],
        }) {
          if (item.isManual) {
            return buildHomeManualTile(
              store: store,
              now: now,
              entry: item.manual!,
              actions: _manualActions,
              pinned: pinned,
              dragHandle: dragHandle,
              pinnedVisibleKeys: pinnedVisibleKeys,
              bouncePulse: _pinPulseByKey[item.pinKey] ?? 0,
            );
          }
          return card(
            item.assignment!,
            pinned: pinned,
            dragHandle: dragHandle,
            pinnedVisibleKeys: pinnedVisibleKeys,
          );
        }

        List<HomeTimelineSection> buildTimelineSections(
          List<HomeTimelineItem> list,
        ) =>
            buildHomeTimelineSections(
              list: list,
              now: now,
              store: store,
              recovery: recoveryScope != null,
              coursework: coursework,
              examSources: examSources,
              displayIndex: displayIndex,
              keepPinnedKeys: _completingPinnedKeyById.values.toSet(),
              completingPinnedSnapshot: _completingPinnedSnapshot,
            );

        final timelineSections = sortedTimelineItems.isEmpty
            ? const <HomeTimelineSection>[]
            : buildTimelineSections(sortedTimelineItems);
        final compactDensity = store.display.compact;
        final buddyMood = busy
            ? JournalPixelBuddyMood.syncing
            : dueSummary.dueToday > 0
                ? JournalPixelBuddyMood.dueToday
                : (showDueSummary &&
                        dueSummary.dueToday == 0 &&
                        (dueSummary.completedToday > 0 ||
                            sortedTimelineItems.isEmpty))
                    ? JournalPixelBuddyMood.allClear
                    : JournalPixelBuddyMood.idle;

        final syncErrorOrPending =
            ClawdCompanionController.resolveHasBlockingSyncNotice(
          store,
          localBusy: _refreshing,
        );
        final syncBusyWithBuddy = busy && showPixelBuddy;
        final followedCourses =
            store.courses.where((c) => store.follows(c.key)).length;
        final activeAgenda =
            store.notebook.entries.where((e) => !e.done).length;
        final homeSnapshot = ClawdPageContextSnapshot(
          tab: ClawdPrimaryTab.home,
          dueToday: dueSummary.dueToday,
          dueIn3Days: dueSummary.dueIn3Days,
          completedToday: dueSummary.completedToday,
          followedCourseCount: followedCourses,
          activeAgendaCount: activeAgenda,
        );

        JournalPixelBuddyPose poseForController() =>
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

        final headerBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                if (recoveryScope == null)
                  action(
                    '待办',
                    IconButton(
                      key: const ValueKey('home-agenda-entry'),
                      tooltip: '个人待办与考试',
                      padding: const EdgeInsets.only(bottom: 12),
                      iconSize: 21,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: () => context.push('/agenda'),
                      icon: const Icon(Icons.checklist_rounded),
                    ),
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
                  Builder(
                    builder: (moreContext) => IconButton(
                      key: const ValueKey('home-more-menu'),
                      tooltip: '更多',
                      padding: const EdgeInsets.only(bottom: 12),
                      iconSize: 21,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: () => unawaited(_openMoreMenu(moreContext)),
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  ),
                ),
              ]);

              return LayoutBuilder(
                builder: (context, constraints) {
                  final largeText = JournalLayout.isLargeText(context);
                  final buddySize = largeText
                      ? 24.0
                      : (constraints.maxWidth < 350 ? 32.0 : 38.0);
                  final allowStageMotion = showPixelBuddy &&
                      !reduceMotion &&
                      recoveryScope == null &&
                      !largeText &&
                      constraints.maxWidth >= 330;
                  final titleStage = AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => ClawdTitleStage(
                      title: '课业手记',
                      titleStyle: journal.display,
                      controller: controller,
                      showBuddy: showPixelBuddy,
                      buddySize: buddySize,
                      interactive: !busy && !syncErrorOrPending,
                      allowStageMotion: allowStageMotion,
                      snapshotBuilder: () => homeSnapshot,
                      anchorNotifier: _stageAnchor,
                      moodOverride: buddyMood,
                    ),
                  );
                  if (!largeText && constraints.maxWidth >= 300) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: titleStage),
                        const SizedBox(width: 8),
                        actionsRow,
                      ],
                    );
                  }
                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                        ),
                        child: titleStage,
                      ),
                      actionsRow,
                    ],
                  );
                },
              );
            }),
            const SizedBox(height: 2),
            KeyedSubtree(
              key: _syncStatusRowKey,
              child: LayoutBuilder(builder: (context, constraints) {
                final nearDueActive =
                    _deadlineFilter == AssignmentDeadlineFilter.next7Days;
                final compactSummary = constraints.maxWidth <= 360 ||
                    JournalLayout.isLargeText(context);
                final summaryLabel = dueSummary.label(compact: compactSummary);
                final statusIcon = sync.gentle
                    ? Icons.wifi_off_rounded
                    : store.syncReport.phase == SyncPhase.failed
                        ? Icons.error_outline_rounded
                        : store.syncReport.phase == SyncPhase.partial
                            ? Icons.info_outline_rounded
                            : Icons.schedule_rounded;
                final statusColor = sync.gentle
                    ? journal.muted
                    : store.syncReport.phase == SyncPhase.failed
                        ? journal.berry
                        : store.syncReport.phase == SyncPhase.partial
                            ? journal.ochre
                            : journal.muted;
                final VoidCallback? onSyncTap =
                    sync.gentle && sync.action == HomeSyncAction.retry
                        ? (busy ? null : () => refresh(HomeSyncAction.retry))
                        : sync.action == HomeSyncAction.none
                            ? null
                            : () => context.push('/sync?expand=issues');
                final showChevron =
                    sync.action != HomeSyncAction.none && !sync.gentle;

                final effectiveStatusText = syncBusyWithBuddy
                    ? journalBuddySyncPhrase(
                        store.homeSyncProgress?.stage,
                        controller.syncTick.value,
                      )
                    : statusText;

                final scaler = MediaQuery.textScalerOf(context);
                final direction = Directionality.of(context);
                double measureWidth(String text, TextStyle style) {
                  final painter = TextPainter(
                    text: TextSpan(text: text, style: style),
                    textScaler: scaler,
                    textDirection: direction,
                  )..layout();
                  final width = painter.width.ceilToDouble();
                  painter.dispose();
                  return width;
                }

                final summaryStyle = journal.metadata.copyWith(
                  color: nearDueActive || dueSummary.dueToday > 0
                      ? journal.accent
                      : journal.muted,
                  fontWeight: nearDueActive || dueSummary.dueToday > 0
                      ? FontWeight.w600
                      : FontWeight.w400,
                );
                final leftWidth = 14.5 +
                    5.0 +
                    measureWidth(effectiveStatusText, journal.metadata) +
                    (showChevron ? 18.0 : 0.0) +
                    4.0;
                final rightWidth = showDueSummary
                    ? measureWidth(summaryLabel, summaryStyle) + 4.0
                    : 0.0;
                final fitsSingleRow = !showDueSummary ||
                    (leftWidth + rightWidth + 6.0 <= constraints.maxWidth);

                Widget buildStatusContent({
                  required Widget leading,
                  required String text,
                  required TextStyle style,
                  bool singleLineScaleDown = false,
                }) {
                  final textWidget = singleLineScaleDown
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            text,
                            maxLines: 1,
                            softWrap: false,
                            style: style,
                          ),
                        )
                      : Text(text, style: style);
                  return Semantics(
                    liveRegion: true,
                    button: onSyncTap != null,
                    label: text,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        leading,
                        const SizedBox(width: 5),
                        Flexible(
                          fit: FlexFit.loose,
                          child: ExcludeSemantics(
                            child: textWidget,
                          ),
                        ),
                        if (showChevron)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: journal.muted,
                          ),
                      ],
                    ),
                  );
                }

                final statusControl = Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey('home-sync-status'),
                    onTap: onSyncTap,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            onSyncTap == null ? (showDueSummary ? 40 : 22) : 48,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: syncBusyWithBuddy
                            ? ValueListenableBuilder<int>(
                                valueListenable: controller.syncTick,
                                builder: (context, tick, _) {
                                  final glyph = reduceMotion
                                      ? '✻'
                                      : kJournalSpinnerGlyphs[
                                          tick % kJournalSpinnerGlyphs.length];
                                  final phrase = journalBuddySyncPhrase(
                                    store.homeSyncProgress?.stage,
                                    tick,
                                  );
                                  return buildStatusContent(
                                    leading: SizedBox(
                                      width: 14.5,
                                      child: Center(
                                        child: ExcludeSemantics(
                                          child: Text(
                                            glyph,
                                            style: journal.metadata.copyWith(
                                              color: journal.accent,
                                              fontWeight: FontWeight.w600,
                                              height: 1.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    text: phrase,
                                    style: journal.metadata,
                                  );
                                },
                              )
                            : buildStatusContent(
                                leading: Icon(
                                  statusIcon,
                                  size: 14.5,
                                  color: statusColor,
                                ),
                                text: statusText,
                                style: journal.metadata,
                              ),
                      ),
                    ),
                  ),
                );

                final summaryControl = !showDueSummary
                    ? null
                    : Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          key: const ValueKey('home-due-summary'),
                          onTap: () {
                            final nextDeadline = nearDueActive
                                ? AssignmentDeadlineFilter.all
                                : AssignmentDeadlineFilter.next7Days;
                            unawaited(_saveFilters(
                              HomeFilters(
                                query: _query,
                                courseKey: _courseKey,
                                deadline: nextDeadline,
                                type: _typeFilter,
                                sortOrder: _sortOrder,
                              ),
                              store.accountEpoch,
                              store.account,
                            ));
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 40),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: Semantics(
                                button: true,
                                label: '$summaryLabel，点击筛选7天内临期课业',
                                child: ExcludeSemantics(
                                  child: Center(
                                    widthFactor: 1,
                                    child: Text(
                                      summaryLabel,
                                      style: summaryStyle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );

                if (fitsSingleRow) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(fit: FlexFit.loose, child: statusControl),
                      if (summaryControl != null) ...[
                        const SizedBox(width: 6),
                        summaryControl,
                      ],
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusControl,
                    if (summaryControl != null) summaryControl,
                  ],
                );
              }),
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
            if (upcomingExam != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _buildUpcomingExamStrip(context, upcomingExam, journal),
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
            if (sortedTimelineItems.isNotEmpty && recoveryScope == null)
              SizedBox(height: compactDensity ? 6 : 12),
          ],
        );

        Widget buildEmptyState() {
          if (recoveryScope != null) {
            return _emptyStateCard(
              icon: Icons.event_available_outlined,
              message: '当前范围没有课业',
            );
          }
          if (selectedCourseIdle) {
            final courseName = store.courses
                    .where((course) => course.key == _courseKey)
                    .firstOrNull
                    ?.name ??
                options
                    .where((option) => option.courseKey == _courseKey)
                    .firstOrNull
                    ?.name;
            return _emptyStateCard(
              icon: Icons.event_note_outlined,
              message: '这门课暂无作业和考试',
              actions: [
                JournalPrimaryButton(
                  key: const ValueKey('home-course-empty-add'),
                  expanded: false,
                  label: '为这门课添加待办',
                  onPressed: () => _manualActions.openEditor(
                    context,
                    initialCourse: courseName,
                  ),
                ),
                JournalSecondaryButton(
                  expanded: false,
                  label: '查看全部课程',
                  onPressed: () => _saveFilters(
                    HomeFilters(
                      query: _query,
                      deadline: _deadlineFilter,
                      type: _typeFilter,
                      sortOrder: _sortOrder,
                    ),
                    store.accountEpoch,
                    store.account,
                  ),
                ),
              ],
            );
          }
          if (filtersActive &&
              (displayAssignments.isNotEmpty ||
                  store.assignments.isNotEmpty ||
                  (store.isAuthenticated &&
                      store.notebook.entries.any((entry) => !entry.done)))) {
            return _emptyStateCard(
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
            );
          }
          if (store.assignments.isNotEmpty) {
            return _emptyStateCard(
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
                JournalSecondaryButton(
                  expanded: false,
                  label: '添加课业或待办',
                  onPressed: () => _manualActions.openEditor(
                    context,
                    initialKind: _typeFilter == AssignmentTypeFilter.exam
                        ? ManualEntry.kindExam
                        : ManualEntry.kindTodo,
                  ),
                ),
              ],
            );
          }
          return _emptyStateCard(
            icon: busy
                ? Icons.hourglass_top_rounded
                : store.syncReport.phase == SyncPhase.success
                    ? Icons.task_alt_rounded
                    : Icons.menu_book_rounded,
            message:
                store.isLoading || store.syncReport.phase == SyncPhase.running
                    ? '正在读取课程与作业，请稍候。'
                    : store.syncReport.phase == SyncPhase.success
                        ? '暂无待办，已读取的作业、任务与考试会显示在这里。'
                        : store.syncReport.phase == SyncPhase.failed
                            ? '本次尚未取得作业，请点击右上角刷新继续。'
                            : '点击右上角刷新，开始整理这本课业手记。',
            actions: [
              JournalSecondaryButton(
                expanded: false,
                label: '添加课业或待办',
                onPressed: () => _manualActions.openEditor(
                  context,
                  initialKind: _typeFilter == AssignmentTypeFilter.exam
                      ? ManualEntry.kindExam
                      : ManualEntry.kindTodo,
                ),
              ),
            ],
          );
        }

        final listView = ListView.builder(
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
          itemCount:
              1 + (timelineSections.isEmpty ? 1 : timelineSections.length),
          itemBuilder: (context, index) {
            if (index == 0) return headerBlock;
            if (timelineSections.isEmpty) return buildEmptyState();
            final sectionIndex = index - 1;
            final section = timelineSections[sectionIndex];
            final isEmphasizedSection = section.pinned || section.badge == '今天';
            final completingPinnedKeys =
                _completingPinnedKeyById.values.toSet();
            final useReorderablePinned = section.pinned &&
                (section.items.length >= 2 ||
                    (completingPinnedKeys.isNotEmpty &&
                        (_completingPinnedSnapshot?.keys.length ?? 0) >= 2));
            final groupCard = useReorderablePinned
                ? JournalGroupedCard(
                    emphasized: isEmphasizedSection,
                    children: [
                      Builder(
                        builder: (context) {
                          final visualKeys = [
                            for (final item in section.items) item.pinKey,
                          ];
                          final activePinnedKeys = [
                            for (final key in visualKeys)
                              if (!completingPinnedKeys.contains(key)) key,
                          ];
                          return ReorderableListView.builder(
                            shrinkWrap: true,
                            primary: false,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            proxyDecorator: (child, index, animation) =>
                                Material(
                              color: journal.sheetElevated,
                              elevation: 4,
                              shadowColor: Colors.black.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: child,
                            ),
                            onReorderStart: (_) =>
                                JournalMotion.selectionTick(store.display),
                            onReorderItem: (oldIndex, newIndex) {
                              if (oldIndex == newIndex) return;
                              final nextVisualKeys =
                                  List<String>.of(visualKeys);
                              final moved = nextVisualKeys.removeAt(oldIndex);
                              nextVisualKeys.insert(newIndex, moved);
                              final nextActiveKeys = [
                                for (final key in nextVisualKeys)
                                  if (!completingPinnedKeys.contains(key)) key,
                              ];
                              if (nextActiveKeys.length >= 2) {
                                unawaited(store.reorderPinned(nextActiveKeys));
                              }
                            },
                            itemCount: section.items.length,
                            itemBuilder: (context, itemIndex) {
                              final item = section.items[itemIndex];
                              final isCompletingItem =
                                  completingPinnedKeys.contains(item.pinKey);
                              final dragHandle = isCompletingItem ||
                                      activePinnedKeys.length < 2
                                  ? null
                                  : ReorderableDragStartListener(
                                      index: itemIndex,
                                      child: Tooltip(
                                        message: '拖动调整置顶顺序',
                                        child: SizedBox(
                                          width: 34,
                                          height: 48,
                                          child: Center(
                                            child: Icon(
                                              Icons.drag_indicator_rounded,
                                              size: 18,
                                              color: journal.muted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                              return Column(
                                key: ValueKey('pinned-reorder-${item.pinKey}'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  timelineCard(
                                    item,
                                    pinned: true,
                                    dragHandle: dragHandle,
                                    pinnedVisibleKeys: activePinnedKeys,
                                  ),
                                  if (itemIndex < section.items.length - 1)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 70),
                                      child: Divider(
                                        height: 1,
                                        thickness: 0.8,
                                        color: journal.rule,
                                      ),
                                    ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  )
                : JournalGroupedCard(
                    emphasized: isEmphasizedSection,
                    dividerIndent: 70.0,
                    children: [
                      for (final item in section.items)
                        timelineCard(item, pinned: section.pinned),
                    ],
                  );
            if (section.heading == null) return groupCard;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dayHeading(
                  section.heading!,
                  top: compactDensity
                      ? (sectionIndex == 0 ? 4 : 10)
                      : (sectionIndex == 0 ? 8 : 18),
                  bottom: compactDensity ? 4 : 8,
                  tone: section.tone,
                  badge: section.badge,
                ),
                groupCard,
              ],
            );
          },
        );

        final headerActions = [
          if (recoveryScope == null)
            IconButton(
              key: const ValueKey('home-sliver-add-manual'),
              tooltip: '添加课业或待办',
              iconSize: 20,
              onPressed: () => _manualActions.openEditor(context),
              icon: const Icon(Icons.add_rounded),
            ),
          if (recoveryScope == null)
            IconButton(
              key: const ValueKey('home-sliver-agenda-entry'),
              tooltip: '个人待办与考试',
              iconSize: 20,
              onPressed: () => context.push('/agenda'),
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
                JournalThemeMode.system => Icons.brightness_auto_outlined,
                JournalThemeMode.light => Icons.light_mode_outlined,
                JournalThemeMode.dark => Icons.dark_mode_outlined,
              }),
            ),
        ];

        final showSliverBuddy = showPixelBuddy &&
            !JournalLayout.isLargeText(context) &&
            MediaQuery.sizeOf(context).width >= 330;
        final Widget? sliverStatusContent = syncBusyWithBuddy
            ? ValueListenableBuilder<int>(
                key: const ValueKey('home-sliver-sync-status'),
                valueListenable: controller.syncTick,
                builder: (context, tick, _) {
                  final glyph = reduceMotion
                      ? '✻'
                      : kJournalSpinnerGlyphs[
                          tick % kJournalSpinnerGlyphs.length];
                  final phrase = journalBuddySyncPhrase(
                    store.homeSyncProgress?.stage,
                    tick,
                  );
                  return Semantics(
                    liveRegion: true,
                    label: phrase,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14.5,
                          child: Center(
                            child: ExcludeSemantics(
                              child: Text(
                                glyph,
                                style: journal.metadata.copyWith(
                                  color: journal.accent,
                                  fontWeight: FontWeight.w600,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: ExcludeSemantics(
                            child: Text(
                              phrase,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: journal.metadata,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            : null;

        _scheduleSyncStatusMeasure();

        return Stack(
          key: _homeStackKey,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 240,
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scrollOffset,
                    builder: (context, offset, _) {
                      final fade = (1.0 - offset / 110.0).clamp(0.0, 1.0);
                      if (fade <= 0.01) {
                        return const SizedBox.shrink();
                      }
                      return CustomPaint(
                        key: const ValueKey('home-ambient-glow'),
                        painter: _HomeAmbientGlowPainter(
                          primaryGlow: journal.ambientPrimaryGlow,
                          warmGlow: journal.ambientWarmGlow,
                          fade: fade,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
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
                            mood: buddyMood,
                            mini: true,
                            size: 20.0,
                            onTap: () => controller.registerTap(
                              snapshot: homeSnapshot,
                              fromSliver: true,
                            ),
                            syncTickListenable: controller.syncTick,
                            celebratePulse: controller.celebratePulse,
                            allowTapCombo: !busy && !syncErrorOrPending,
                            poseOverride: poseForController(),
                            posePulse: controller.transientPulse,
                          )
                        : null,
                    statusContent: sliverStatusContent,
                    actions: headerActions,
                  ),
                ),
              ),
            ),
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
                  final sliverShowing = offset > 18.0 && showSliverBuddy;
                  final screenWidth = MediaQuery.sizeOf(context).width;
                  final double top;
                  final double minLeft;
                  final double safeRight;
                  final double anchorX;
                  final double maxWidth;
                  if (sliverShowing) {
                    minLeft = 18.0;
                    safeRight =
                        screenWidth - 18.0 - headerActions.length * 48.0 - 8.0;
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
                      screenWidth -
                          36.0 -
                          headerActions.length * 48.0 -
                          5.0 -
                          26.0,
                    );
                    final titleW = math.min(tp.width, titleAvailable);
                    tp.dispose();
                    final rawBuddyCenter = 18.0 + titleW + 5.0 + 13.0;
                    anchorX = rawBuddyCenter.clamp(
                      minLeft + 13.0,
                      math.max(minLeft + 13.0, safeRight),
                    );
                    top = 50.0;
                  } else {
                    final actualOffset = _bubbleScrollOffset.value;
                    final anchor = _stageAnchor.value;
                    minLeft = 16.0;
                    safeRight = 16.0 + anchor.safeWidth;
                    maxWidth = math.min(
                      210.0,
                      math.max(36.0, anchor.safeWidth),
                    );
                    anchorX = 16.0 + anchor.centerX;
                    final fallbackBottomAtZero =
                        math.max(114.0, 14.0 + anchor.bottomY + 58.0);
                    final statusBottom = (_syncStatusBottomAtZero.value ??
                            fallbackBottomAtZero) -
                        actualOffset;
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
            () {
              _preExamStripFilters = null;
              _preExamStripEpoch = null;
              unawaited(_saveFilters(
                HomeFilters(
                  query: _query,
                  courseKey: _courseKey,
                  deadline: _deadlineFilter,
                  type: AssignmentTypeFilter.all,
                  sortOrder: _sortOrder,
                ),
                epoch,
                account,
              ));
            },
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
          onPressed: () {
            _preExamStripFilters = null;
            _preExamStripEpoch = null;
            unawaited(_saveFilters(
              HomeFilters(sortOrder: _sortOrder),
              epoch,
              account,
            ));
          },
          child: const Text('重置条件'),
        ),
      ],
    );
  }

  Widget dayHeading(
    String label, {
    double top = 12,
    double bottom = 8,
    HomeDayHeadingTone tone = HomeDayHeadingTone.normal,
    String? badge,
  }) {
    final journal = Journal.of(context);
    final textColor = switch (tone) {
      HomeDayHeadingTone.overdue => journal.muted,
      HomeDayHeadingTone.undated => journal.ochre,
      HomeDayHeadingTone.today => journal.ink,
      HomeDayHeadingTone.normal => journal.muted,
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
      padding: EdgeInsets.only(top: top, bottom: bottom, left: 2),
      child: Row(
        children: [
          Flexible(child: labelWidget),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: tone == HomeDayHeadingTone.overdue
                    ? journal.parchment
                    : journal.sage,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: journal.metadata.copyWith(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: tone == HomeDayHeadingTone.overdue
                      ? journal.muted
                      : journal.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpcomingExamStrip(
    BuildContext context,
    HomeUpcomingExam upcomingExam,
    JournalPalette journal,
  ) {
    final inExamView = _typeFilter == AssignmentTypeFilter.exam;
    void onTap() {
      final epoch = store.accountEpoch;
      final account = store.account;
      if (!inExamView) {
        _preExamStripFilters = store.homeFilters;
        _preExamStripEpoch = epoch;
        unawaited(_saveFilters(
          HomeFilters(
            query: _query,
            courseKey: _courseKey,
            deadline: AssignmentDeadlineFilter.all,
            type: AssignmentTypeFilter.exam,
            sortOrder: _sortOrder,
          ),
          epoch,
          account,
        ));
      } else {
        final previous =
            _preExamStripEpoch == epoch ? _preExamStripFilters : null;
        _preExamStripFilters = null;
        _preExamStripEpoch = null;
        unawaited(_saveFilters(
          previous ??
              HomeFilters(
                query: _query,
                courseKey: _courseKey,
                deadline: _deadlineFilter,
                type: AssignmentTypeFilter.all,
                sortOrder: _sortOrder,
              ),
          epoch,
          account,
        ));
      }
    }

    return Semantics(
      button: true,
      label: '${upcomingExam.label}，点击${inExamView ? '返回全部课业' : '查看考试筛选视图'}',
      onTap: onTap,
      child: Material(
        color: inExamView ? journal.sage : journal.parchment,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: inExamView ? journal.sageBorder : journal.rule,
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('home-upcoming-exam-strip'),
          onTap: onTap,
          enableFeedback: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Icon(
                      Icons.school_outlined,
                      size: 16,
                      color: inExamView ? journal.accent : journal.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        upcomingExam.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: journal.metadata.copyWith(
                          color: journal.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (inExamView)
                      Text(
                        '返回',
                        style: journal.metadata.copyWith(
                          color: journal.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: journal.muted,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
    final addStyle = journal.metadata.copyWith(
      color: journal.ink,
      fontWeight: FontWeight.w600,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final filterLabel = filtersActive ? '已筛选' : '搜索与筛选';
    final sortLabel = _shortSortLabel(sortOrder);
    const addLabel = '添加';
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

    final filterWidth = 16 + 5 + labelWidth(filterLabel, filterStyle) + 22;
    final sortWidth = 16 + 5 + labelWidth(sortLabel, sortStyle) + 22;
    final addWidth = 16 + 5 + labelWidth(addLabel, addStyle) + 22;

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
            child: JournalPressableScale(
              pressScale: 0.97,
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
                            horizontal: 11, vertical: 6.5),
                        decoration: BoxDecoration(
                          color:
                              filtersActive ? journal.sage : journal.parchment,
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
                            const SizedBox(width: 5),
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
            child: JournalPressableScale(
              pressScale: 0.97,
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
                            horizontal: 11, vertical: 6.5),
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
                          const SizedBox(width: 5),
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
        ),
      );
    }

    Widget buildAddButton() {
      const message = '添加课业或待办';
      void onTap() => _manualActions.openEditor(
            context,
            initialKind: _typeFilter == AssignmentTypeFilter.exam
                ? ManualEntry.kindExam
                : ManualEntry.kindTodo,
          );
      return Semantics(
        button: true,
        label: message,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Tooltip(
            message: message,
            child: JournalPressableScale(
              pressScale: 0.97,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('home-add-manual'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: onTap,
                  enableFeedback: false,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Center(
                      widthFactor: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6.5,
                        ),
                        decoration: BoxDecoration(
                          color: journal.sage,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: journal.sageBorder,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 16,
                              color: journal.ink,
                            ),
                            const SizedBox(width: 5),
                            Text(addLabel, style: addStyle),
                          ],
                        ),
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

    return LayoutBuilder(builder: (context, constraints) {
      // Three pill borders (4.8px) plus the 10 + 8 gaps need ~23px of slack.
      if (filterWidth + sortWidth + addWidth + 24 <= constraints.maxWidth) {
        return Row(children: [
          Expanded(child: buildFilterPill(fullWidth: true)),
          const SizedBox(width: 10),
          buildSortButton(),
          const SizedBox(width: 8),
          buildAddButton(),
        ]);
      }
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          buildFilterPill(),
          buildSortButton(),
          buildAddButton(),
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
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: JournalMotion.modalSheetAnimationStyle(context),
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
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: JournalSheetRubberBand(
              fillColor: journal.sheetElevated,
              builder: (context, wrapGrabArea) => Container(
                decoration: BoxDecoration(
                  color: journal.sheetElevated,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      wrapGrabArea(
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              key: const ValueKey('home-filter-drag-handle'),
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: journal.ruleStrong,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text('搜索、筛选与排序', style: journal.section),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: _query.isNotEmpty,
                        onChanged: (value) =>
                            setSheetState(() => query = value),
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
                              onSelected: (_) =>
                                  setSheetState(() => type = option),
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
                      HomeCourseFilterRow(
                        key: const ValueKey('home-course-filter'),
                        tapKey: ValueKey(
                            'course-${store.accountEpoch}-${courseKey ?? "all"}'),
                        value: selectedCourseLabel,
                        selected: courseKey != null,
                        onClear: () => setSheetState(() => courseKey = null),
                        onTap: () async {
                          final counts = _courseCountsFor(type, deadline);
                          final ordered = sortHomeCourseOptionsByCount(
                              courseOptions, counts);
                          final picked = await showJournalPickerSheet<String>(
                            context,
                            title: '课程筛选',
                            selectedValue: courseKey ?? '',
                            searchable: courseOptions.length > 5 ||
                                courseOptions
                                    .any((o) => o.teacherNames.isNotEmpty),
                            searchHint: '搜索课程或教师...',
                            displayPrefs: store.display,
                            filterOptions: const [
                              JournalPickerFilterOption(
                                id: 'currentTerm',
                                label: '本学期',
                              ),
                              JournalPickerFilterOption(
                                id: 'currentAcademicYear',
                                label: '本学年',
                              ),
                              JournalPickerFilterOption(
                                id: 'pastTerms',
                                label: '往期',
                              ),
                              JournalPickerFilterOption(
                                id: 'allTerms',
                                label: '全部学期',
                              ),
                            ],
                            initialFilterId: 'currentTerm',
                            filterPredicate: (option, filterId) {
                              if (option.value.isEmpty) return true;
                              return store.termCatalog.matchesHomeCoursePicker(
                                option.value,
                                filterId,
                                hasVisibleItems:
                                    (counts[option.value] ?? 0) > 0,
                              );
                            },
                            filterNoticeBuilder: (filterId, filtered) =>
                                filterId == 'currentTerm' &&
                                        filtered
                                            .every((o) => o.value.isEmpty) &&
                                        courseOptions.isNotEmpty
                                    ? '本学期暂未识别出课程，可切换到「本学年」或「全部学期」查看'
                                    : null,
                            options: [
                              const JournalPickerOption<String>(
                                value: '',
                                label: '全部课程',
                              ),
                              for (final option in ordered)
                                JournalPickerOption<String>(
                                  key: ValueKey(
                                      'course-option-${option.courseKey}'),
                                  value: option.courseKey,
                                  label: option.name,
                                  subtitle: option.subtitle,
                                  keywords: option.searchKeywords,
                                  icon: courseIconFor(option.name),
                                  trailingText: homeCourseCountLabel(
                                      counts[option.courseKey] ?? 0),
                                ),
                            ],
                          );
                          if (picked != null) {
                            setSheetState(
                                () => courseKey = picked == '' ? null : picked);
                          }
                        },
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
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12),
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
                            style:
                                FilledButton.styleFrom(enableFeedback: false),
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
    _preExamStripFilters = null;
    _preExamStripEpoch = null;
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

class _HomeAmbientGlowPainter extends CustomPainter {
  const _HomeAmbientGlowPainter({
    required this.primaryGlow,
    required this.warmGlow,
    required this.fade,
  });

  final Color primaryGlow;
  final Color warmGlow;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || fade <= 0.01) return;

    final primaryCenter = Offset(size.width * 0.16, -24);
    final primaryRadius = size.width * 0.72;
    final primaryPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryGlow.withValues(alpha: primaryGlow.a * fade),
          primaryGlow.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(center: primaryCenter, radius: primaryRadius),
      );
    canvas.drawCircle(primaryCenter, primaryRadius, primaryPaint);

    final warmCenter = Offset(size.width * 0.88, 12);
    final warmRadius = size.width * 0.56;
    final warmPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          warmGlow.withValues(alpha: warmGlow.a * fade),
          warmGlow.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(center: warmCenter, radius: warmRadius),
      );
    canvas.drawCircle(warmCenter, warmRadius, warmPaint);
  }

  @override
  bool shouldRepaint(covariant _HomeAmbientGlowPainter oldDelegate) =>
      oldDelegate.primaryGlow != primaryGlow ||
      oldDelegate.warmGlow != warmGlow ||
      oldDelegate.fade != fade;
}
