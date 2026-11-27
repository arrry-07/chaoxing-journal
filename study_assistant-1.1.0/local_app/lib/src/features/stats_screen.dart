import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../app/transient_feedback.dart';
import '../models/assignment.dart';
import '../models/sync_report.dart';
import '../services/assignment_statistics.dart';
import '../services/assignment_store.dart';
import '../services/clawd_companion_controller.dart';
import '../services/course_term_catalog.dart';
import '../services/local_record_query.dart';
import 'widgets/clawd_speech_bubble.dart';
import 'widgets/clawd_title_stage.dart';
import 'widgets/completion_pie_chart.dart';
import 'widgets/journal_context_menu.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_info_popover.dart';
import 'widgets/journal_swipe_tile.dart';

class _StatsGroup {
  const _StatsGroup(
    this.name,
    this.records, {
    required this.scope,
    this.courseKey,
  });

  final String name;
  final List<Assignment> records;
  final LocalRecordScopeFilter scope;
  final String? courseKey;

  bool get accountExam => scope == LocalRecordScopeFilter.accountExam;
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.store, this.clock});
  final AssignmentStore store;
  final DateTime Function()? clock;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with WidgetsBindingObserver {
  static const _bucketStatusParams = [
    'completed',
    'pending',
    'overdue',
    'unknown',
  ];

  Timer? _clock;
  late DateTime _now;
  CourseTermScope _termScope = CourseTermScope.currentTerm;
  StatsTimeRange _range = StatsTimeRange.all;
  final _feedback = TransientFeedbackController();
  late int _feedbackEpoch;
  String? _feedbackAccount;
  ClawdCompanionController? _clawdController;
  ClawdCompanionController? _localClawdController;
  final GlobalKey _cameoKey = GlobalKey();
  final GlobalKey _titleRowKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);
  final ValueNotifier<Offset> _cameoAnchor =
      ValueNotifier<Offset>(const Offset(156.0, 48.0));
  bool _appResumed = true;
  bool _tickerEnabled = true;
  bool _isCurrentRoute = true;
  bool _reducedMotion = false;

  ClawdCompanionController _ensureClawdController() {
    if (_clawdController != null) return _clawdController!;
    return _localClawdController ??=
        ClawdCompanionController(clock: widget.clock);
  }

  double _currentScrollOffset() {
    if (_scrollController.hasClients &&
        _scrollController.positions.length == 1) {
      return _scrollController.offset;
    }
    return _scrollOffset.value;
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.positions.length != 1) {
      return;
    }
    final raw = _scrollController.offset;
    if ((raw - _scrollOffset.value).abs() >= 0.5 ||
        (raw == 0.0 && _scrollOffset.value != 0.0)) {
      _scrollOffset.value = raw;
    }
  }

  void _measureCameoAnchorNow() {
    if (!mounted) return;
    final cameoBox = _cameoKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (cameoBox == null ||
        !cameoBox.attached ||
        !cameoBox.hasSize ||
        stackBox == null ||
        !stackBox.attached ||
        !stackBox.hasSize) {
      return;
    }
    final scrollOffset = _currentScrollOffset();
    if ((scrollOffset - _scrollOffset.value).abs() >= 0.5 ||
        (scrollOffset == 0.0 && _scrollOffset.value != 0.0)) {
      _scrollOffset.value = scrollOffset;
    }
    final topLeft = cameoBox.localToGlobal(Offset.zero, ancestor: stackBox);
    var bottomInStack = topLeft.dy + cameoBox.size.height;
    final rowBox =
        _titleRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowBox != null && rowBox.attached && rowBox.hasSize) {
      final rowTopLeft = rowBox.localToGlobal(Offset.zero, ancestor: stackBox);
      bottomInStack =
          math.max(bottomInStack, rowTopLeft.dy + rowBox.size.height);
    }
    final nextAtZero = Offset(
      topLeft.dx + cameoBox.size.width * 0.5,
      bottomInStack + scrollOffset,
    );
    if ((nextAtZero - _cameoAnchor.value).distance > 0.5) {
      _cameoAnchor.value = nextAtZero;
    }
  }

  void _scheduleCameoAnchorMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureCameoAnchorNow();
    });
  }

  ClawdPageContextSnapshot _buildStatsSnapshot() {
    final store = widget.store;
    final now = _now;
    final rangeResult = LocalRecordQuery.filterStatsRecords(
      store.statsAssignmentsForScope(_termScope, now: now),
      _range,
      now,
    );
    final stats = AssignmentStatistics(
      rangeResult.records,
      now: now,
      coursework: store.courseworkState,
    );
    final allUnknown = stats.total > 0 && stats.unknown == stats.total;
    return ClawdPageContextSnapshot(
      tab: ClawdPrimaryTab.stats,
      statsCompletionPercent: allUnknown ? 0 : stats.percentages[0],
      statsTotalCount: stats.total,
      statsPendingCount: stats.pending + stats.expired + stats.unknown,
    );
  }

  void _syncClawdEnvironment({bool notify = true}) {
    final controller = _clawdController;
    if (controller == null) return;
    final isSharedController = !identical(controller, _localClawdController);
    if (isSharedController && !_isCurrentRoute) return;
    final busy = widget.store.isLoading ||
        widget.store.syncReport.phase == SyncPhase.running;
    final hasError =
        ClawdCompanionController.resolveHasBlockingSyncNotice(widget.store);
    controller.updateEnvironment(
      displayPrefs: widget.store.display,
      appResumed: _appResumed,
      tickerEnabled: isSharedController ? null : _tickerEnabled,
      reducedMotion: _reducedMotion,
      isSyncing: busy,
      hasSyncErrorOrPending: hasError,
      snapshot: _buildStatsSnapshot(),
      notify: notify,
    );
  }

  void _checkFeedbackAccount() {
    if (_feedbackEpoch != widget.store.accountEpoch ||
        _feedbackAccount != widget.store.account) {
      _feedback.dismiss();
      _localClawdController?.resetForAccountChange();
      _feedbackEpoch = widget.store.accountEpoch;
      _feedbackAccount = widget.store.account;
    }
    _syncClawdEnvironment();
  }

  @override
  void initState() {
    super.initState();
    _appResumed =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
            AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _now = widget.clock?.call() ?? DateTime.now();
    _feedbackEpoch = widget.store.accountEpoch;
    _feedbackAccount = widget.store.account;
    widget.store.addListener(_checkFeedbackAccount);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = widget.clock?.call() ?? DateTime.now());
        _syncClawdEnvironment(notify: false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reducedMotion = JournalMotion.isReducedMotion(context);
    final scoped = ClawdCompanionScope.maybeOf(context);
    _clawdController = scoped ??
        (_localClawdController ??=
            ClawdCompanionController(clock: widget.clock));
    _syncClawdEnvironment(notify: false);
  }

  @override
  void didUpdateWidget(covariant StatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_checkFeedbackAccount);
      _feedback.dismiss();
      _localClawdController?.resetForAccountChange();
      _feedbackEpoch = widget.store.accountEpoch;
      _feedbackAccount = widget.store.account;
      widget.store.addListener(_checkFeedbackAccount);
      _syncClawdEnvironment();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextResumed = state == AppLifecycleState.resumed;
    if (_appResumed != nextResumed) {
      _appResumed = nextResumed;
      _syncClawdEnvironment();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_checkFeedbackAccount);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollOffset.dispose();
    _cameoAnchor.dispose();
    _localClawdController?.dispose();
    _feedback.dispose();
    _clock?.cancel();
    super.dispose();
  }

  List<Assignment> _actionableRecords(_StatsGroup group, DateTime now) =>
      group.records
          .where((r) => AssignmentStatistics.isPendingCourseAttention(
                r,
                now,
                coursework: widget.store.courseworkState,
              ))
          .toList(growable: false);

  Future<void> _unfollowCourseWithUndo(
    BuildContext context,
    String courseKey,
    String displayName,
  ) async {
    final store = widget.store;
    final epoch = store.accountEpoch;
    await store.followCourse(courseKey, false);
    if (store.error != null ||
        !context.mounted ||
        !mounted ||
        store.accountEpoch != epoch) {
      return;
    }
    _feedback.show(
      context,
      SnackBar(
        content: Text('已将「$displayName」移出首页与统计'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (store.accountEpoch == epoch) {
              unawaited(store.followCourse(courseKey, true));
            }
          },
        ),
      ),
    );
  }

  Future<void> _hideGroupWithUndo(
    BuildContext context,
    List<Assignment> actionable,
    String displayName,
  ) async {
    final store = widget.store;
    final epoch = store.accountEpoch;
    final ids = <String>{
      for (final r in actionable)
        ...(store.courseworkGroupFor(r.id)?.sources.map((s) => s.id) ?? [r.id]),
    };
    if (ids.isEmpty) return;
    final saved = await store.setAssignmentsHidden(ids, true);
    if (!saved || !context.mounted || !mounted || store.accountEpoch != epoch) {
      return;
    }
    _feedback.show(
      context,
      SnackBar(
        content: Text('已在本机隐藏「$displayName」的 ${actionable.length} 项待处理'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (store.accountEpoch == epoch) {
              unawaited(store.setAssignmentsHidden(ids, false));
            }
          },
        ),
      ),
    );
  }

  void _openRecords(
    BuildContext context, {
    required LocalRecordScopeFilter scope,
    required String status,
    String? courseKey,
  }) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    router.push(
      Uri(
        path: '/records',
        queryParameters: {
          'from': 'stats',
          'scope': scope.name,
          'status': status,
          if (courseKey != null && courseKey.isNotEmpty) 'courseKey': courseKey,
          'range': _range.name,
          'term': _termScope.name,
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final journal = Journal.of(context);
          final store = widget.store;
          final now = _now;
          final rangeResult = LocalRecordQuery.filterStatsRecords(
            store.statsAssignmentsForScope(_termScope, now: now),
            _range,
            now,
          );
          final coursework = store.courseworkState;
          final records = rangeResult.records;
          final excludedUnscheduled = rangeResult.excludedUnscheduledCount;
          final stats =
              AssignmentStatistics(records, now: now, coursework: coursework);
          final keyed = <String, List<Assignment>>{};
          final accountExams = <Assignment>[];
          final otherUnkeyed = <Assignment>[];
          for (final record in records) {
            final key = record.courseKey;
            if (key != null) {
              (keyed[key] ??= []).add(record);
            } else if (record.isExam) {
              accountExams.add(record);
            } else {
              otherUnkeyed.add(record);
            }
          }
          final keys = keyed.keys.toList()..sort();
          final groups = <_StatsGroup>[
            for (final key in keys)
              _StatsGroup(
                keyed[key]!.first.courseName,
                keyed[key]!,
                scope: LocalRecordScopeFilter.followedStats,
                courseKey: key,
              ),
            if (accountExams.isNotEmpty)
              _StatsGroup(
                '账号考试',
                accountExams,
                scope: LocalRecordScopeFilter.accountExam,
              ),
            if (otherUnkeyed.isNotEmpty)
              _StatsGroup(
                '其他课业',
                otherUnkeyed,
                scope: LocalRecordScopeFilter.otherUnkeyed,
              ),
          ];

          final pendingGroups = groups.where((g) {
            final own = AssignmentStatistics(
              _actionableRecords(g, now),
              now: now,
              coursework: coursework,
            );
            return own.pending + own.expired + own.unknown > 0;
          }).toList(growable: false);

          final allUnknown = stats.total > 0 && stats.unknown == stats.total;
          final barColors = CompletionPieChart.colorsFor(journal);
          final controller = _ensureClawdController();
          final showCameo = store.display.showClawdOnSecondaryTabs;
          final statsSnapshot = ClawdPageContextSnapshot(
            tab: ClawdPrimaryTab.stats,
            statsCompletionPercent: allUnknown ? 0 : stats.percentages[0],
            statsTotalCount: stats.total,
            statsPendingCount: stats.pending + stats.expired + stats.unknown,
          );
          if (showCameo) {
            _scheduleCameoAnchorMeasure();
          }

          return Material(
            type: MaterialType.transparency,
            child: Stack(
              key: _stackKey,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.depth != 0) return false;
                    if (notification is ScrollUpdateNotification &&
                        (notification.scrollDelta ?? 0.0).abs() > 0.5) {
                      final active = controller.activeBubble;
                      if (active != null &&
                          active.tab == ClawdPrimaryTab.stats) {
                        controller.dismissBubble();
                      }
                    } else if (notification is ScrollEndNotification) {
                      _measureCameoAnchorNow();
                    }
                    return false;
                  },
                  child: ListView(
                    key: const PageStorageKey('stats-list'),
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      18,
                      14,
                      18,
                      JournalLayout.floatingNavClearance(context),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          key: _titleRowKey,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: JournalHeading(
                                  '课业统计',
                                  bookTitle: true,
                                ),
                              ),
                            ),
                            if (showCameo)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: KeyedSubtree(
                                  key: _cameoKey,
                                  child: ClawdTabCameo(
                                    key: const ValueKey('stats-pixel-buddy'),
                                    controller: controller,
                                    snapshotBuilder: () {
                                      _measureCameoAnchorNow();
                                      return statsSnapshot;
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _StatsTermScopeBar(
                        selected: _termScope,
                        onChanged: (scope) {
                          if (_termScope == scope) return;
                          JournalMotion.tap(store.display);
                          setState(() => _termScope = scope);
                          _syncClawdEnvironment(notify: false);
                        },
                      ),
                      const SizedBox(height: 10),
                      _StatsRangeSegmentedBar(
                        selected: _range,
                        onChanged: (next) {
                          JournalMotion.tap(store.display);
                          setState(() => _range = next);
                          _syncClawdEnvironment(notify: false);
                        },
                      ),
                      if (_range != StatsTimeRange.all &&
                          excludedUnscheduled > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '不含 $excludedUnscheduled 项无确定时间课业',
                          style: journal.metadata,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (stats.total == 0)
                        JournalGroupedCard(
                          key: const ValueKey('stats-empty-card'),
                          padding: const EdgeInsets.all(18),
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('暂无可统计的作业', style: journal.entryTitle),
                                if (_range != StatsTimeRange.all) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_range.label}内暂无带确定时间的课业记录，可切回“不限时间”查看。',
                                    style: journal.metadata,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        )
                      else
                        JournalGroupedCard(
                          key: const ValueKey('stats-overview-card'),
                          dividerIndent: 16,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 10, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: _AnimatedRatioHero(
                                              completed: stats.completed,
                                              total: stats.total,
                                              journal: journal,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: allUnknown
                                              ? journal.parchment
                                              : journal.sage,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          allUnknown
                                              ? '待确认'
                                              : '${stats.percentages[0]}%',
                                          style: journal.pillLabel.copyWith(
                                            color: allUnknown
                                                ? journal.muted
                                                : journal.isDark
                                                    ? journal.accent
                                                    : journal.ink,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const JournalInfoButton(
                                        title: '统计口径说明',
                                        items: [
                                          '统计范围为已关注课程的作业/任务与账号级考试。',
                                          '已在本机隐藏的记录不计入统计；提交状态未知的记录计入总数，不折算为已完成。',
                                          '切换未来 7 天 / 30 天时，无确定时间的课业不参与时间窗口统计。',
                                          '点击状态行或课程行查看明细；长按或左滑课程行可快捷取消关注或本机隐藏。',
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _MultiSegmentStatsBar(
                                    counts: stats.counts,
                                    colors: barColors,
                                    trackColor: journal.parchment,
                                    overdueStripeColor: journal.isDark
                                        ? const Color(0xFF191816)
                                            .withValues(alpha: 0.36)
                                        : Colors.white.withValues(alpha: 0.45),
                                    animateDuration: JournalMotion.duration(
                                      context,
                                      const Duration(milliseconds: 340),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (var i = 0; i < 4; i++)
                              if (i < 3 || stats.unknown > 0)
                                _buildStatusRow(
                                  context,
                                  index: i,
                                  label: i == 0 && stats.localCompleted > 0
                                      ? '${CompletionPieChart.labels[i]}（含本机标记 ${stats.localCompleted}）'
                                      : CompletionPieChart.labels[i],
                                  count: stats.counts[i],
                                  percent: stats.percentages[i],
                                  dotColor: barColors[i],
                                  journal: journal,
                                ),
                          ],
                        ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 8),
                        child: Text('各课程待处理', style: journal.section),
                      ),
                      if (pendingGroups.isEmpty)
                        JournalGroupedCard(
                          key: const ValueKey('stats-course-empty'),
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text('当前没有待处理的课程', style: journal.metadata),
                          ],
                        )
                      else
                        JournalGroupedCard(
                          dividerIndent: 52,
                          children: [
                            for (final group in pendingGroups)
                              _buildCourseRow(
                                context,
                                group: group,
                                allGroups: groups,
                                now: now,
                                journal: journal,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge(
                      [controller, _cameoAnchor, _scrollOffset],
                    ),
                    builder: (context, _) {
                      final bubble = controller.activeBubble;
                      if (!showCameo ||
                          controller.isSyncing ||
                          controller.hasSyncErrorOrPending ||
                          bubble == null ||
                          bubble.tab != ClawdPrimaryTab.stats) {
                        return const SizedBox.shrink();
                      }
                      final screenW = MediaQuery.sizeOf(context).width;
                      final maxW = math.min(
                        220.0,
                        math.max(96.0, screenW - 36.0),
                      );
                      final anchor = _cameoAnchor.value;
                      return ClawdAnchoredSpeechBubble(
                        bubbleKey: const ValueKey('clawd-speech-bubble'),
                        message: bubble,
                        anchorX: anchor.dx,
                        top: math.max(
                          8.0,
                          anchor.dy - _scrollOffset.value + 4.0,
                        ),
                        minLeft: 18.0,
                        safeRight: math.max(18.0, screenW - 18.0),
                        maxWidth: maxW,
                        pointerDirection: ClawdBubblePointerDirection.up,
                        onTap: controller.onBubbleTapped,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildStatusRow(
    BuildContext context, {
    required int index,
    required String label,
    required int count,
    required int percent,
    required Color dotColor,
    required JournalPalette journal,
  }) {
    final canTap = count > 0;
    void open() => _openRecords(
          context,
          scope: LocalRecordScopeFilter.followedStats,
          status: _bucketStatusParams[index],
        );

    final largeText = JournalLayout.isLargeText(context);
    final dot = _StatusIndicatorDot(
      color: dotColor,
      striped: index == 2,
      stripeColor: journal.isDark
          ? const Color(0xFF191816).withValues(alpha: 0.42)
          : Colors.white.withValues(alpha: 0.55),
      borderColor: index == 2
          ? journal.ink.withValues(alpha: 0.35)
          : index == 3 && !journal.isDark
              ? journal.ruleStrong
              : null,
    );
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: largeText
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: dot,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(label, style: journal.entryTitle),
                            ),
                            if (canTap)
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: journal.muted,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count 份 · $percent%',
                          style: journal.metadata.copyWith(
                            color: canTap ? journal.ink : journal.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  dot,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: journal.entryTitle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count 份',
                    style: journal.metadata.copyWith(
                      color: canTap ? journal.ink : journal.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    ' · $percent%',
                    style: journal.metadata,
                  ),
                  if (canTap) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: journal.muted,
                    ),
                  ],
                ],
              ),
      ),
    );

    return Semantics(
      button: canTap,
      onTap: canTap ? open : null,
      label: '$label $count 份，$percent%',
      excludeSemantics: true,
      child: canTap
          ? InkWell(
              key: ValueKey('stats-status-$index'),
              onTap: open,
              child: content,
            )
          : content,
    );
  }

  Widget _buildCourseRow(
    BuildContext context, {
    required _StatsGroup group,
    required List<_StatsGroup> allGroups,
    required DateTime now,
    required JournalPalette journal,
  }) {
    final actionable = _actionableRecords(group, now);
    final own = AssignmentStatistics(
      actionable,
      now: now,
      coursework: widget.store.courseworkState,
    );
    final same = group.accountExam
        ? const <_StatsGroup>[]
        : allGroups
            .where((other) => !other.accountExam && other.name == group.name)
            .toList();
    final name =
        '${group.name}${same.length > 1 ? ' · 分组${same.indexOf(group) + 1}' : ''}';
    final largeText = JournalLayout.isLargeText(context);
    final pillTexts = [
      if (own.pending > 0) '待完成 ${own.pending}',
      if (own.expired > 0) '已逾期 ${own.expired}',
      if (own.unknown > 0) '待核对 ${own.unknown}',
    ];
    Widget pillsFor({required bool stacked}) => Wrap(
          spacing: 5,
          runSpacing: 4,
          alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
          children: [
            if (own.pending > 0)
              _CourseStatPill(
                text: '待完成 ${own.pending}',
                fg: journal.ink,
                bg: journal.parchment,
                journal: journal,
              ),
            if (own.expired > 0)
              _CourseStatPill(
                text: '已逾期 ${own.expired}',
                fg: journal.overdueSky,
                bg: journal.overdueSkyBg,
                journal: journal,
              ),
            if (own.unknown > 0)
              _CourseStatPill(
                text: '待核对 ${own.unknown}',
                fg: journal.muted,
                bg: journal.parchment,
                journal: journal,
              ),
          ],
        );

    Widget buildRowContent() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              group.courseKey == null
                  ? SizedBox.square(
                      dimension: 28,
                      child: Center(
                        child: Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: journal.muted,
                        ),
                      ),
                    )
                  : CourseMark(group.name, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  const minNameWidth = 96.0;
                  const gap = 6.0;
                  final pillsWidth = _CourseStatPill.estimateRowWidth(
                    context,
                    pillTexts,
                    spacing: 5,
                  );
                  final stacked = largeText ||
                      constraints.maxWidth - gap - pillsWidth < minNameWidth;
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: journal.entryTitle),
                        if (pillTexts.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          pillsFor(stacked: true),
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: journal.entryTitle,
                        ),
                      ),
                      const SizedBox(width: gap),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth - gap - minNameWidth,
                        ),
                        child: pillsFor(stacked: false),
                      ),
                    ],
                  );
                }),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: journal.muted,
              ),
            ],
          ),
        );

    void triggerQuickRemove() {
      if (group.courseKey != null) {
        unawaited(_unfollowCourseWithUndo(context, group.courseKey!, name));
      } else {
        unawaited(_hideGroupWithUndo(context, actionable, name));
      }
    }

    return Builder(
      builder: (rowContext) => JournalSwipeTile(
        key: ValueKey('stats-swipe-${group.courseKey ?? group.scope.name}'),
        displayPrefs: widget.store.display,
        leftAction: JournalSwipeAction(
          label: group.courseKey != null ? '取消关注' : '本机隐藏',
          icon: Icons.visibility_off_outlined,
          color: journal.berry,
          backgroundColor: journal.berryBg,
          onTrigger: triggerQuickRemove,
        ),
        child: InkWell(
          key: ValueKey('stats-course-${group.courseKey ?? group.scope.name}'),
          onTap: () => _openRecords(
            context,
            scope: group.scope,
            courseKey: group.courseKey,
            status: 'unfinished',
          ),
          onLongPress: () {
            final box = rowContext.findRenderObject() as RenderBox?;
            final anchor = box == null || !box.hasSize
                ? null
                : box.localToGlobal(Offset.zero) & box.size;
            unawaited(showJournalContextMenu(
              context: rowContext,
              anchorRect: anchor,
              displayPrefs: widget.store.display,
              previewCard: buildRowContent(),
              actions: [
                JournalContextMenuAction(
                  label: group.courseKey != null ? '查看该课全部记录' : '查看本组全部记录',
                  icon: Icons.list_alt_rounded,
                  onSelected: () => _openRecords(
                    context,
                    scope: group.scope,
                    courseKey: group.courseKey,
                    status: 'all',
                  ),
                ),
                JournalContextMenuAction(
                  label: group.courseKey != null ? '取消关注（移出统计）' : '本机隐藏本组待处理',
                  icon: Icons.visibility_off_outlined,
                  destructive: true,
                  onSelected: triggerQuickRemove,
                ),
              ],
            ));
          },
          child: buildRowContent(),
        ),
      ),
    );
  }
}

class _CourseStatPill extends StatelessWidget {
  const _CourseStatPill({
    required this.text,
    required this.fg,
    required this.bg,
    required this.journal,
  });

  final String text;
  final Color fg;
  final Color bg;
  final JournalPalette journal;

  static const _padding = EdgeInsets.symmetric(horizontal: 6.5, vertical: 3);

  static TextStyle _style(JournalPalette journal) => journal.pillLabel.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      );

  /// Measured width of a single-line row of pills at the current text scale.
  static double estimateRowWidth(
    BuildContext context,
    List<String> texts, {
    required double spacing,
  }) {
    if (texts.isEmpty) return 0;
    final journal = Journal.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    var total = spacing * (texts.length - 1);
    for (final text in texts) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _style(journal)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      total += painter.width + _padding.horizontal;
      painter.dispose();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: _style(journal).copyWith(color: fg),
      ),
    );
  }
}

class _StatsTermScopeBar extends StatefulWidget {
  const _StatsTermScopeBar({
    required this.selected,
    required this.onChanged,
  });

  final CourseTermScope selected;
  final ValueChanged<CourseTermScope> onChanged;

  @override
  State<_StatsTermScopeBar> createState() => _StatsTermScopeBarState();
}

class _StatsTermScopeBarState extends State<_StatsTermScopeBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static int _indexFor(CourseTermScope scope) {
    const scopes = CourseTermScope.values;
    return scopes.indexOf(scope).clamp(0, scopes.length - 1);
  }

  static String _shortLabel(CourseTermScope scope) => switch (scope) {
        CourseTermScope.currentTerm => '本学期',
        CourseTermScope.currentAcademicYear => '本学年',
        CourseTermScope.pastTerms => '往期',
        CourseTermScope.allTerms => '全部学期',
      };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(
      vsync: this,
      value: _indexFor(widget.selected).toDouble(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (JournalMotion.isReducedMotion(context)) {
      final target = _indexFor(widget.selected).toDouble();
      if (_controller.isAnimating || _controller.value != target) {
        _controller.stop();
        _controller.value = target;
      }
    }
  }

  @override
  void didUpdateWidget(covariant _StatsTermScopeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      final target = _indexFor(widget.selected).toDouble();
      if (JournalMotion.isReducedMotion(context)) {
        _controller.stop();
        _controller.value = target;
      } else {
        _controller.animateWith(
          JournalMotion.springFor(
            JournalMotion.interactiveSpring,
            start: _controller.value,
            end: target,
            velocity: _controller.velocity,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    const scopes = CourseTermScope.values;
    final selectedIndex = _indexFor(widget.selected);
    final reduced = JournalMotion.isReducedMotion(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: journal.divider, width: 0.8),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / scopes.length;
          const indicatorWidth = 28.0;
          final maxLeft = (constraints.maxWidth - indicatorWidth).clamp(
            0.0,
            double.infinity,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  for (final scope in scopes)
                    () {
                      final active = widget.selected == scope;
                      final label = _shortLabel(scope);
                      return Expanded(
                        child: Semantics(
                          button: true,
                          selected: active,
                          label: label,
                          child: InkWell(
                            key: ValueKey('stats-term-scope-${scope.name}'),
                            onTap: () => widget.onChanged(scope),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  4,
                                  10,
                                  4,
                                  12.5,
                                ),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: journal.pillLabel.copyWith(
                                        fontSize: 14,
                                        fontWeight: active
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: active
                                            ? journal.accent
                                            : journal.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }(),
                ],
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final posIndex =
                      reduced ? selectedIndex.toDouble() : _controller.value;
                  final indicatorLeft =
                      tabWidth * posIndex + (tabWidth - indicatorWidth) / 2;
                  return Positioned(
                    left: indicatorLeft.clamp(0.0, maxLeft),
                    bottom: 0,
                    width: indicatorWidth,
                    height: 2.5,
                    child: child!,
                  );
                },
                child: DecoratedBox(
                  key: const ValueKey('stats-term-scope-indicator'),
                  decoration: BoxDecoration(
                    color: journal.accent,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsRangeSegmentedBar extends StatelessWidget {
  const _StatsRangeSegmentedBar({
    required this.selected,
    required this.onChanged,
  });

  final StatsTimeRange selected;
  final ValueChanged<StatsTimeRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: journal.segmentTrack,
        borderRadius: BorderRadius.circular(12),
        border: journal.segmentBorder,
      ),
      child: Row(
        children: [
          for (final range in StatsTimeRange.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(range),
                child: AnimatedContainer(
                  duration: JournalMotion.duration(
                    context,
                    const Duration(milliseconds: 180),
                  ),
                  curve: JournalMotion.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6.5),
                  decoration: BoxDecoration(
                    color: selected == range
                        ? journal.segmentThumb
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9.5),
                    border: selected == range ? journal.segmentBorder : null,
                    boxShadow: selected == range
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: journal.isDark ? 0.22 : 0.05,
                              ),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        range.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        style: journal.pillLabel.copyWith(
                          fontSize: 12.5,
                          fontWeight: selected == range
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color:
                              selected == range ? journal.ink : journal.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedRatioHero extends StatelessWidget {
  const _AnimatedRatioHero({
    required this.completed,
    required this.total,
    required this.journal,
  });

  final int completed;
  final int total;
  final JournalPalette journal;

  @override
  Widget build(BuildContext context) {
    final dur = JournalMotion.duration(
      context,
      const Duration(milliseconds: 300),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: completed.toDouble()),
      duration: dur,
      curve: JournalMotion.easeOut,
      builder: (context, animatedDone, _) {
        final doneVal = animatedDone.round();
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '已完成 ',
                style: journal.metadata.copyWith(
                  fontSize: 13.5,
                  color: journal.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextSpan(text: '$doneVal', style: journal.statHero),
              TextSpan(
                text: ' / $total',
                style: journal.time.copyWith(
                  fontSize: 17,
                  color: journal.muted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MultiSegmentStatsBar extends StatelessWidget {
  const _MultiSegmentStatsBar({
    required this.counts,
    required this.colors,
    required this.trackColor,
    required this.overdueStripeColor,
    required this.animateDuration,
  });

  final List<int> counts;
  final List<Color> colors;
  final Color trackColor;
  final Color overdueStripeColor;
  final Duration animateDuration;

  @override
  Widget build(BuildContext context) {
    final total = counts.fold<int>(0, (s, c) => s + c);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (total <= 0 || maxWidth <= 0) {
          return Container(
            height: 10,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(5),
            ),
          );
        }
        final active = <({int index, int count})>[
          for (var i = 0; i < counts.length; i++)
            if (counts[i] > 0) (index: i, count: counts[i]),
        ];
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            width: maxWidth,
            child: ColoredBox(
              color: trackColor,
              child: Row(
                children: [
                  for (var i = 0; i < active.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2.5),
                    Expanded(
                      flex: math.max(1, active[i].count),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: 1.0),
                        duration: animateDuration,
                        curve: JournalMotion.easeOut,
                        builder: (context, factor, _) => FractionallySizedBox(
                          widthFactor: factor,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            key: ValueKey('stats-bar-seg-${active[i].index}'),
                            height: 10,
                            color: colors[active[i].index],
                            child: active[i].index == 2
                                ? CustomPaint(
                                    key: const ValueKey(
                                        'stats-bar-overdue-stripes'),
                                    painter: _DiagonalStripePainter(
                                      stripeColor: overdueStripeColor,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusIndicatorDot extends StatelessWidget {
  const _StatusIndicatorDot({
    required this.color,
    required this.striped,
    required this.stripeColor,
    this.borderColor,
  });

  final Color color;
  final bool striped;
  final Color stripeColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 0.8),
      ),
      child: striped
          ? ClipOval(
              child: CustomPaint(
                key: const ValueKey('stats-dot-overdue-stripes'),
                painter: _DiagonalStripePainter(
                  stripeColor: stripeColor,
                  spacing: 4.0,
                  strokeWidth: 1.4,
                ),
              ),
            )
          : null,
    );
  }
}

class _DiagonalStripePainter extends CustomPainter {
  const _DiagonalStripePainter({
    required this.stripeColor,
    this.spacing = 6.0,
    this.strokeWidth = 1.6,
  });

  final Color stripeColor;
  final double spacing;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = stripeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final maxExtent = size.width + size.height;
    for (var x = -size.height; x < maxExtent; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DiagonalStripePainter oldDelegate) =>
      oldDelegate.stripeColor != stripeColor ||
      oldDelegate.spacing != spacing ||
      oldDelegate.strokeWidth != strokeWidth;
}
