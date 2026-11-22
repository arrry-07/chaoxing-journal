import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../models/assignment.dart';
import '../models/study_notebook.dart';
import '../models/sync_report.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import '../services/interaction_feedback_service.dart';
import 'assignment_list_screen.dart';
import 'manual_agenda_screen.dart';
import 'widgets/assignment_card.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_info_popover.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.store, this.clock});
  final AssignmentStore store;
  final DateTime Function()? clock;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  static const int _basePageIndex = 1200;
  static const int _maxWeekRows = 6;
  static const TextStyle _dateStyle = TextStyle(
    fontFamily: Journal.bodyFamily,
    fontFamilyFallback: Journal.bodyFallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.35,
  );

  Timer? _clock;
  late DateTime _now;
  late DateTime today;
  late DateTime _baseMonth;
  late DateTime month;
  late final PageController _pageController;
  DateTime? selected;
  bool _weekCollapsed = false;
  bool _refreshing = false;
  String? _refreshMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.clock?.call() ?? DateTime.now();
    today = AssignmentQuery.dayKey(_now);
    _baseMonth = DateTime(today.year, today.month);
    month = _baseMonth;
    selected = today;
    _pageController = PageController(initialPage: _basePageIndex);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = widget.clock?.call() ?? DateTime.now();
        today = AssignmentQuery.dayKey(_now);
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(() {
      _now = widget.clock?.call() ?? DateTime.now();
      today = AssignmentQuery.dayKey(_now);
    });
  }

  int _pageIndexForMonth(DateTime target) =>
      _basePageIndex +
      (target.year - _baseMonth.year) * 12 +
      (target.month - _baseMonth.month);

  DateTime _monthForPageIndex(int index) =>
      DateTime(_baseMonth.year, _baseMonth.month + (index - _basePageIndex));

  void move(int delta) {
    final target = DateTime(month.year, month.month + delta);
    final targetPage = _pageIndexForMonth(target);
    setState(() {
      month = target;
      selected = DateTime(target.year, target.month);
    });
    if (_pageController.hasClients) {
      if (!JournalMotion.isReducedMotion(context)) {
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 260),
          curve: JournalMotion.easeOut,
        );
      } else {
        _pageController.jumpToPage(targetPage);
      }
    }
  }

  void _goToday() {
    JournalMotion.tap(widget.store.display);
    final target = DateTime(today.year, today.month);
    final targetPage = _pageIndexForMonth(target);
    if (_pageController.hasClients && !JournalMotion.isReducedMotion(context)) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 260),
        curve: JournalMotion.easeOut,
      );
    } else if (_pageController.hasClients) {
      _pageController.jumpToPage(targetPage);
    }
    setState(() {
      month = target;
      selected = today;
    });
  }

  void _toggleWeekCollapse([bool? collapsed]) {
    final next = collapsed ?? !_weekCollapsed;
    if (next == _weekCollapsed) return;
    JournalMotion.tap(widget.store.display);
    setState(() => _weekCollapsed = next);
  }

  Future<void> _refresh() async {
    if (_refreshing || widget.store.isLoading) return;
    setState(() {
      _refreshing = true;
      _refreshMessage = null;
    });
    final before = widget.store.syncReport;
    final epoch = widget.store.accountEpoch;
    try {
      await widget.store.syncAssignments();
      if (!mounted) return;
      final completedAt = widget.clock?.call() ?? DateTime.now();
      final report = widget.store.syncReport;
      final last = report.lastDataSuccessAt ?? widget.store.lastSyncAt;
      final formattedTime = DateFormat('HH:mm:ss').format(completedAt);
      final String message;
      switch (report.phase) {
        case SyncPhase.success:
          InteractionFeedback.triggerSyncDoneIfReady(
            prefs: widget.store.display,
            before: before,
            after: report,
            beforeEpoch: epoch,
            afterEpoch: widget.store.accountEpoch,
            operationError: widget.store.operationError,
          );
          if (widget.store.operationError != null) {
            message = last == null
                ? '本次刷新失败，且没有可用的本机缓存；请到同步详情重试'
                : '本次刷新失败，已保留上次成功数据（${DateFormat('M月d日 HH:mm').format(last.toLocal())}）';
          } else if (widget.store.serviceWarnings.isNotEmpty) {
            message = '本次刷新已完成（$formattedTime），本机提醒或小组件需处理';
          } else {
            message = '本次刷新已完成（$formattedTime）';
          }
        case SyncPhase.partial:
          message = '本次刷新部分完成（$formattedTime），部分来源待确认；请查看同步详情';
        case SyncPhase.cancelled:
          message = last == null
              ? '本次刷新已取消，且没有可用的本机缓存；请重试'
              : '本次刷新已取消，已保留上次成功数据（${DateFormat('M月d日 HH:mm').format(last.toLocal())}）';
        case SyncPhase.idle:
        case SyncPhase.running:
        case SyncPhase.failed:
          message = last == null
              ? '本次刷新失败，且没有可用的本机缓存；请到同步详情重试'
              : '本次刷新失败，已保留上次成功数据（${DateFormat('M月d日 HH:mm').format(last.toLocal())}）';
      }
      setState(() => _refreshMessage = message);
    } catch (error) {
      if (!mounted) return;
      final last = widget.store.lastSyncAt;
      setState(() {
        _refreshMessage = last == null
            ? '本次刷新失败：$error'
            : '本次刷新失败，已保留上次成功数据（${DateFormat('M月d日 HH:mm').format(last.toLocal())}）：$error';
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final journal = Journal.of(context);
          final now = _now;
          final courseSources = widget.store.courseAssignments;
          final all = AssignmentQuery.projectDisplay(courseSources);
          final manual = widget.store.notebook.entries
              .where((e) => !e.done && e.at != null)
              .toList();
          final manualAgenda = manual.where((e) {
            final d = AssignmentQuery.dayKey(e.at!);
            return selected == null
                ? d.year == month.year && d.month == month.month
                : d == selected;
          }).toList()
            ..sort((a, b) => a.at!.compareTo(b.at!));
          final dated = all
              .where((assignment) =>
                  AssignmentQuery.isCalendarDated(assignment, now))
              .toList();
          final noDeadlineCount = all
              .where((a) => AssignmentRecoveryScope.noDeadline.matches(a, now))
              .length;
          final pendingDeadlineCount = all
              .where((a) =>
                  AssignmentRecoveryScope.deadlinePending.matches(a, now))
              .length;
          final agenda = selected == null
              ? dated.where((a) {
                  final d = AssignmentQuery.dayKey(a.timelineAt!);
                  return d.year == month.year && d.month == month.month;
                }).toList()
              : AssignmentQuery.forDay(all, selected!, {}, now: now);
          agenda.sort((a, b) => a.timelineAt!.compareTo(b.timelineAt!));

          final textScaler = MediaQuery.textScalerOf(context);
          final cellHeight = _calendarCellHeight(textScaler);
          final isOffToday = selected != today ||
              month.year != today.year ||
              month.month != today.month;
          final busy = _refreshing || widget.store.isLoading;
          final syncStatusText = busy
              ? '正在刷新${widget.store.lastSyncAt == null ? '' : ' · 上次 ${DateFormat('M月d日 HH:mm').format(widget.store.lastSyncAt!.toLocal())}'}…'
              : _refreshMessage ??
                  (widget.store.lastSyncAt == null
                      ? '尚未同步 · 当前显示本机记录'
                      : '上次同步 ${DateFormat('M月d日 HH:mm').format(widget.store.lastSyncAt!.toLocal())}');

          final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
          final leading = month.weekday % 7;
          final rowCount = (leading + daysInMonth + 6) ~/ 7;
          final gridHeight =
              _weekCollapsed ? cellHeight : rowCount * cellHeight;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              JournalLayout.floatingNavClearance(context),
            ),
            children: [
              Builder(builder: (context) {
                final titleWidget = Text('课业日历', style: journal.display);
                final refreshBtn = IconButton(
                  tooltip: '刷新',
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : _refresh,
                  icon: busy
                      ? JournalMotion.isReducedMotion(context)
                          ? const Icon(Icons.hourglass_top_rounded, size: 20)
                          : SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: journal.ink,
                              ),
                            )
                      : const Icon(Icons.sync_rounded, size: 21),
                );
                final agendaBtn = JournalPillButton(
                  label: '个人待办与考试',
                  icon: Icons.event_note_outlined,
                  onPressed: () => context.push('/agenda'),
                );
                return LayoutBuilder(
                  builder: (context, constraints) {
                    if (!JournalLayout.isLargeText(context) &&
                        !isOffToday &&
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
                                child: titleWidget,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          refreshBtn,
                          agendaBtn,
                        ],
                      );
                    }
                    return Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        titleWidget,
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isOffToday)
                              JournalPillButton(
                                label: '回今天',
                                onPressed: _goToday,
                              ),
                            refreshBtn,
                            agendaBtn,
                          ],
                        ),
                      ],
                    );
                  },
                );
              }),
              const SizedBox(height: 2),
              Text(
                syncStatusText,
                style: journal.metadata.copyWith(
                  color: _refreshMessage?.contains('失败') == true
                      ? journal.berry
                      : journal.muted,
                ),
              ),
              const SizedBox(height: 12),
              JournalGroupedCard(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                children: [
                  Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final monthLabelText =
                              DateFormat('yyyy年M月').format(month);
                          final label = Text(
                            monthLabelText,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: journal.section.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          );
                          final painter = TextPainter(
                            text: TextSpan(
                                text: monthLabelText, style: journal.section),
                            textDirection: Directionality.of(context),
                            textScaler: textScaler,
                          )..layout();
                          final labelWidth = painter.width;
                          painter.dispose();

                          final monthPill = GestureDetector(
                            onTap: () {
                              JournalMotion.tap(widget.store.display);
                              setState(() => selected = null);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: selected == null
                                    ? journal.sage
                                    : journal.parchment,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected == null
                                      ? journal.sageBorder
                                      : Colors.transparent,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                '本月',
                                style: journal.pillLabel.copyWith(
                                  fontSize: 12,
                                  color: selected == null && journal.isDark
                                      ? journal.accent
                                      : journal.ink,
                                ),
                              ),
                            ),
                          );

                          const infoBtn = JournalInfoButton(
                            title: '日历统计与圆点说明',
                            items: [
                              '蓝色圆点表示当天有待交或待确认课业，珊瑚红圆点表示考试或已逾期，中性灰点表示个人待办。',
                              '考试按开考日展示，作业与课堂任务按截止日展示，均使用北京时间。',
                              '左右滑动可切换月份；上滑或轻点底部横条可收拢为单周视图。',
                            ],
                          );

                          final previous = IconButton(
                            tooltip: '上个月',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 34, minHeight: 36),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => move(-1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          );
                          final next = IconButton(
                            tooltip: '下个月',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 34, minHeight: 36),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => move(1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          );

                          final controlsEstimate = 155.0 +
                              (textScaler.scale(12) - 12).clamp(0.0, 24.0) *
                                  2.5;
                          if (labelWidth + controlsEstimate <=
                              constraints.maxWidth) {
                            return Row(
                              key: const ValueKey('calendar-month-inline'),
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          previous,
                                          const SizedBox(width: 2),
                                          label,
                                          const SizedBox(width: 2),
                                          next,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                monthPill,
                                const SizedBox(width: 2),
                                infoBtn,
                              ],
                            );
                          }
                          return Column(
                            key: const ValueKey('calendar-month-stacked'),
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [previous, next],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [monthPill, infoBtn],
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: label,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (final label in [
                            '日',
                            '一',
                            '二',
                            '三',
                            '四',
                            '五',
                            '六',
                          ])
                            Expanded(
                              child: Center(
                                child: Text(
                                  label,
                                  style: journal.metadata.copyWith(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Divider(
                        height: 0.6,
                        thickness: 0.6,
                        indent: 6,
                        endIndent: 6,
                        color: journal.divider,
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        key: const ValueKey('calendar-grid-viewport'),
                        duration: JournalMotion.duration(
                          context,
                          const Duration(milliseconds: 240),
                        ),
                        curve: JournalMotion.easeOut,
                        height: gridHeight,
                        clipBehavior: Clip.hardEdge,
                        decoration: const BoxDecoration(),
                        child: OverflowBox(
                          // Neighbouring months may need up to six rows while
                          // they slide in; render that full height and let the
                          // animated viewport clip to the current month.
                          minHeight: cellHeight,
                          maxHeight: _maxWeekRows * cellHeight,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            height: _maxWeekRows * cellHeight,
                            child: PageView.builder(
                              controller: _pageController,
                              onPageChanged: (index) {
                                final nextMonth = _monthForPageIndex(index);
                                if (nextMonth.year == month.year &&
                                    nextMonth.month == month.month) {
                                  return;
                                }
                                setState(() {
                                  month = nextMonth;
                                  if (selected != null) {
                                    selected = (nextMonth.year == today.year &&
                                            nextMonth.month == today.month)
                                        ? today
                                        : DateTime(
                                            nextMonth.year, nextMonth.month, 1);
                                  }
                                });
                              },
                              itemBuilder: (context, index) {
                                final pageMonth = _monthForPageIndex(index);
                                return _buildMonthGrid(
                                  context,
                                  pageMonth: pageMonth,
                                  all: all,
                                  manual: manual,
                                  now: now,
                                  cellHeight: cellHeight,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: _weekCollapsed ? '展开月视图' : '收拢为周视图',
                        onTap: () => _toggleWeekCollapse(),
                        excludeSemantics: true,
                        child: GestureDetector(
                          onVerticalDragEnd: (details) {
                            final v = details.primaryVelocity ?? 0;
                            if (v < -180) {
                              _toggleWeekCollapse(true);
                            } else if (v > 180) {
                              _toggleWeekCollapse(false);
                            }
                          },
                          child: InkWell(
                            key: const ValueKey('calendar-week-toggle'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _toggleWeekCollapse(),
                            child: SizedBox(
                              height: 28,
                              width: double.infinity,
                              child: Center(
                                child: Container(
                                  width: 28,
                                  height: 3.5,
                                  decoration: BoxDecoration(
                                    color: journal.ruleStrong,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8, left: 2),
                child: Text(
                  selected == null
                      ? '本月议程'
                      : '${DateFormat('M月d日').format(selected!)} · 议程',
                  style: journal.section,
                ),
              ),
              if (agenda.isEmpty && manualAgenda.isEmpty)
                JournalGroupedCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  children: [
                    Text(
                      widget.store.syncReport.phase == SyncPhase.failed
                          ? '本次读取失败，请到同步详情重试'
                          : widget.store.lastSyncAt == null && all.isEmpty
                              ? '尚未获取作业，请先同步'
                              : '所选范围没有已知日期的课业',
                      style: journal.metadata.copyWith(fontSize: 13.5),
                    ),
                  ],
                )
              else
                JournalGroupedCard(
                  dividerIndent: 16,
                  children: [
                    for (final a in agenda)
                      AssignmentCard(
                        assignment: a,
                        examSources: courseSources,
                        displayIndex: widget.store.homeDisplayIndex,
                        now: now,
                        compact: widget.store.display.compact,
                        countdown: widget.store.display.countdown,
                        showFullDeadline: false,
                        showDivider: false,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        onTap: () => context
                            .push('/assignments/${Uri.encodeComponent(a.id)}'),
                      ),
                    for (final e in manualAgenda)
                      _buildManualAgendaRow(context, e, journal),
                  ],
                ),
              if (noDeadlineCount > 0 || pendingDeadlineCount > 0) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8, left: 2),
                  child: Text('待核对课业', style: journal.section),
                ),
                JournalGroupedCard(
                  dividerIndent: 48,
                  children: [
                    if (noDeadlineCount > 0)
                      _buildRecoveryRow(
                        key: const ValueKey('calendar-no-deadline-scope'),
                        icon: Icons.event_busy_outlined,
                        label: '无截止日期',
                        count: noDeadlineCount,
                        color: journal.ink,
                        journal: journal,
                        onTap: () => context.go(_recoveryLocation(
                            AssignmentRecoveryScope.noDeadline)),
                      ),
                    if (pendingDeadlineCount > 0)
                      _buildRecoveryRow(
                        key: const ValueKey('calendar-deadline-pending-scope'),
                        icon: Icons.help_outline_rounded,
                        label: '截止时间未知',
                        count: pendingDeadlineCount,
                        color: journal.ochre,
                        journal: journal,
                        onTap: () => context.go(_recoveryLocation(
                            AssignmentRecoveryScope.deadlinePending)),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      );

  Widget _buildMonthGrid(
    BuildContext context, {
    required DateTime pageMonth,
    required List<Assignment> all,
    required List<ManualEntry> manual,
    required DateTime now,
    required double cellHeight,
  }) {
    final days = DateTime(pageMonth.year, pageMonth.month + 1, 0).day;
    final leading = pageMonth.weekday % 7;
    final totalRows = (leading + days + 6) ~/ 7;

    int activeRow = 0;
    if (_weekCollapsed) {
      final anchorDay = (selected != null &&
              selected!.year == pageMonth.year &&
              selected!.month == pageMonth.month)
          ? selected!.day
          : (today.year == pageMonth.year && today.month == pageMonth.month)
              ? today.day
              : 1;
      activeRow = ((leading + anchorDay - 1) ~/ 7).clamp(0, totalRows - 1);
    }

    final rowIndices =
        _weekCollapsed ? [activeRow] : [for (var r = 0; r < totalRows; r++) r];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rowIndices)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _buildDayCell(
                    context,
                    pageMonth: pageMonth,
                    day: row * 7 + col - leading + 1,
                    daysInMonth: days,
                    all: all,
                    manual: manual,
                    now: now,
                    cellHeight: cellHeight,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context, {
    required DateTime pageMonth,
    required int day,
    required int daysInMonth,
    required List<Assignment> all,
    required List<ManualEntry> manual,
    required DateTime now,
    required double cellHeight,
  }) {
    if (day < 1 || day > daysInMonth) {
      return SizedBox(height: cellHeight);
    }
    final journal = Journal.of(context);
    final date = DateTime(pageMonth.year, pageMonth.month, day);
    final items = AssignmentQuery.forDay(all, date, {}, now: now);
    final unknown =
        items.where((a) => !a.isExam && !a.isPendingConfirmed).length;
    final exams = items.where((a) => a.isExam).length;
    final overdueCount = items
        .where((a) =>
            AssignmentQuery.timelineBucketAt(a, now) ==
            AssignmentDeadlineBucket.overdue)
        .length;
    final personalCount =
        manual.where((e) => AssignmentQuery.dayKey(e.at!) == date).length;
    final isSelected = selected == date;
    final isToday = date == today;

    final dots = <Color>[];
    if (exams > 0 || overdueCount > 0) dots.add(journal.berry);
    if (items.length - exams > 0 && dots.length < 3) dots.add(journal.accent);
    if (personalCount > 0 && dots.length < 3) dots.add(journal.muted);
    if (dots.length == 1 && (items.length + personalCount) >= 2) {
      dots.add(dots.first);
    }

    final circleSize =
        (MediaQuery.textScalerOf(context).scale(14) * 1.9).clamp(32.0, 46.0);
    return Semantics(
      label:
          '${pageMonth.month}月$day日${isToday ? '，今天' : ''}，${items.length - unknown - exams}份待交，$unknown份待确认，$exams项考试或考试通知，$personalCount项个人安排',
      selected: isSelected,
      button: true,
      onTap: () {
        JournalMotion.tap(widget.store.display);
        setState(() => selected = date);
      },
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            JournalMotion.tap(widget.store.display);
            setState(() => selected = date);
          },
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: cellHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: JournalMotion.duration(
                    context,
                    const Duration(milliseconds: 160),
                  ),
                  curve: JournalMotion.easeOut,
                  width: circleSize,
                  height: circleSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? journal.accent : Colors.transparent,
                    border: !isSelected && isToday
                        ? Border.all(color: journal.accent, width: 1.3)
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$day',
                      maxLines: 1,
                      softWrap: false,
                      style: _dateStyle.copyWith(
                        color: isSelected
                            ? journal.onPrimaryFill
                            : isToday
                                ? journal.accent
                                : journal.ink,
                        fontWeight: isSelected || isToday
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 6,
                  child: dots.isEmpty
                      ? const SizedBox.shrink()
                      : Row(
                          key: ValueKey('calendar-dots-$day'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < dots.length; i++) ...[
                              if (i > 0) const SizedBox(width: 2.5),
                              Container(
                                width: 4.5,
                                height: 4.5,
                                decoration: BoxDecoration(
                                  color: dots[i],
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualAgendaRow(
      BuildContext context, ManualEntry e, JournalPalette journal) {
    final exam = e.kind == 'exam';
    final accent = exam ? journal.slate : journal.ink;
    final label = exam ? '手动考试' : '个人待办';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(
        exam ? Icons.school_outlined : Icons.event_note_outlined,
        size: 20,
        color: accent,
      ),
      title: Text(
        '$label · ${e.title}',
        style: journal.entryTitle.copyWith(color: accent),
      ),
      subtitle: Text(manualTime(e.at), style: journal.metadata),
      trailing:
          Icon(Icons.chevron_right_rounded, size: 19, color: journal.muted),
      onTap: () => context.push('/agenda'),
    );
  }

  Widget _buildRecoveryRow({
    required Key key,
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required JournalPalette journal,
    required VoidCallback onTap,
  }) =>
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Icon(icon, size: 19, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: journal.entryTitle.copyWith(color: color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count 项',
                    style: journal.metadata.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 2),
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
      );

  String _recoveryLocation(AssignmentRecoveryScope scope) =>
      Uri(path: '/assignments', queryParameters: {
        AssignmentRecoveryScope.queryParameter: scope.queryValue,
      }).toString();

  double _calendarCellHeight(TextScaler textScaler) {
    final circleSize = (textScaler.scale(14) * 1.9).clamp(32.0, 46.0);
    return math.max(48.0, circleSize + 16.0);
  }
}
