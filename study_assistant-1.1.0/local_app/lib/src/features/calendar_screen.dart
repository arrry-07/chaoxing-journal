import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../app/journal.dart';
import '../models/sync_report.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import 'assignment_list_screen.dart';
import 'widgets/assignment_card.dart';
import 'manual_agenda_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.store, this.clock});
  final AssignmentStore store;
  final DateTime Function()? clock;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  static const _dateStyle = TextStyle(
    fontFamily: Journal.bodyFamily,
    fontFamilyFallback: Journal.bodyFallback,
    fontSize: 14,
    height: 1.4,
  );
  TextStyle get _countStyle => TextStyle(
        fontFamily: Journal.bodyFamily,
        fontFamilyFallback: Journal.bodyFallback,
        fontSize: 11,
        height: 1.4,
        color: Journal.of(context).muted,
      );
  static const _cellBorderWidth = 1.0;
  static const _cellVerticalPadding = 2.0;
  static const _cellSlack = 1.0;

  Timer? _clock;
  late DateTime _now;
  late DateTime today;
  late DateTime month;
  DateTime? selected;
  bool _refreshing = false;
  String? _refreshMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.clock?.call() ?? DateTime.now();
    today = AssignmentQuery.dayKey(_now);
    month = DateTime(today.year, today.month);
    selected = today;
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

  void move(int delta) => setState(() {
        month = DateTime(month.year, month.month + delta);
        selected = DateTime(month.year, month.month);
      });

  Future<void> _refresh() async {
    if (_refreshing || widget.store.isLoading) return;
    setState(() {
      _refreshing = true;
      _refreshMessage = null;
    });
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
            .where(
                (a) => AssignmentRecoveryScope.deadlinePending.matches(a, now))
            .length;
        final agenda = selected == null
            ? dated.where((a) {
                final d = AssignmentQuery.dayKey(a.timelineAt!);
                return d.year == month.year && d.month == month.month;
              }).toList()
            : AssignmentQuery.forDay(all, selected!, {}, now: now);
        agenda.sort((a, b) => a.timelineAt!.compareTo(b.timelineAt!));
        final days = DateTime(month.year, month.month + 1, 0).day,
            leading = month.weekday % 7;
        final textScaler = MediaQuery.textScalerOf(context);
        final cellHeight = _calendarCellHeight(context, textScaler);
        return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text('课业日历', style: journal.display),
                  TextButton.icon(
                    onPressed: () => context.push('/agenda'),
                    icon: const Icon(Icons.event_note_outlined),
                    label: const Text('个人待办与考试'),
                  ),
                ],
              ),
              Row(children: [
                TextButton(
                    onPressed: () => setState(() {
                          month = DateTime(today.year, today.month);
                          selected = today;
                        }),
                    child: const Text('回今天')),
                TextButton(
                    onPressed: () => setState(() => selected = null),
                    child: const Text('本月')),
                const Spacer(),
                IconButton(
                    tooltip: '刷新',
                    onPressed:
                        _refreshing || widget.store.isLoading ? null : _refresh,
                    icon: _refreshing || widget.store.isLoading
                        ? MediaQuery.disableAnimationsOf(context)
                            ? const Icon(Icons.hourglass_top_rounded, size: 20)
                            : const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                        : const Icon(Icons.sync))
              ]),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _refreshing || widget.store.isLoading
                      ? '正在刷新${widget.store.lastSyncAt == null ? '' : '；上次成功 ${DateFormat('M月d日 HH:mm').format(widget.store.lastSyncAt!.toLocal())}'}…'
                      : _refreshMessage ??
                          (widget.store.lastSyncAt == null
                              ? '尚未成功同步；当前仅显示本机已有记录'
                              : '上次成功同步 ${DateFormat('M月d日 HH:mm').format(widget.store.lastSyncAt!.toLocal())}'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _refreshMessage?.contains('失败') == true
                        ? Theme.of(context).colorScheme.error
                        : journal.muted,
                  ),
                ),
              ),
              Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(children: [
                        Builder(builder: (context) {
                          final previous = IconButton(
                            tooltip: '上个月',
                            onPressed: () => move(-1),
                            icon: const Icon(Icons.chevron_left),
                          );
                          final next = IconButton(
                            tooltip: '下个月',
                            onPressed: () => move(1),
                            icon: const Icon(Icons.chevron_right),
                          );
                          final label = Text(
                            DateFormat('yyyy年M月').format(month),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Journal.of(context).section,
                          );
                          return LayoutBuilder(builder: (context, constraints) {
                            final painter = TextPainter(
                              text: TextSpan(
                                text: DateFormat('yyyy年M月').format(month),
                                style: Journal.of(context).section,
                              ),
                              textDirection: Directionality.of(context),
                              textScaler: textScaler,
                            )..layout();
                            final labelWidth = painter.width;
                            painter.dispose();
                            if (labelWidth + 96 <= constraints.maxWidth) {
                              return Row(
                                key: const ValueKey('calendar-month-inline'),
                                children: [
                                  previous,
                                  Expanded(child: label),
                                  next,
                                ],
                              );
                            }
                            return Column(
                              key: const ValueKey('calendar-month-stacked'),
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [previous, next],
                                ),
                                label,
                              ],
                            );
                          });
                        }),
                        Row(children: [
                          for (final label in [
                            '日',
                            '一',
                            '二',
                            '三',
                            '四',
                            '五',
                            '六'
                          ])
                            Expanded(
                                child: Center(
                                    child: Text(label,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: journal.muted))))
                        ]),
                        const Divider(height: 9, indent: 8, endIndent: 8),
                        for (var row = 0;
                            row < (leading + days + 6) ~/ 7;
                            row++)
                          Row(children: [
                            for (var col = 0; col < 7; col++)
                              Expanded(child: Builder(builder: (context) {
                                final journal = Journal.of(context);
                                final day = row * 7 + col - leading + 1;
                                if (day < 1 || day > days) {
                                  return SizedBox(height: cellHeight);
                                }
                                final date =
                                        DateTime(month.year, month.month, day),
                                    items = AssignmentQuery.forDay(
                                        all,
                                        DateTime(month.year, month.month, day),
                                        {},
                                        now: now);
                                final unknown = items
                                    .where((a) =>
                                        !a.isExam && !a.isPendingConfirmed)
                                    .length;
                                final exams =
                                    items.where((a) => a.isExam).length;
                                final personalCount = manual
                                    .where((e) =>
                                        AssignmentQuery.dayKey(e.at!) == date)
                                    .length;
                                return Semantics(
                                    label:
                                        '${month.month}月$day日${date == today ? '，今天' : ''}，${items.length - unknown - exams}份待交，$unknown份待确认，$exams项考试或考试通知，$personalCount项个人安排',
                                    selected: selected == date,
                                    button: true,
                                    onTap: () =>
                                        setState(() => selected = date),
                                    excludeSemantics: true,
                                    child: InkWell(
                                        onTap: () =>
                                            setState(() => selected = date),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                            height: cellHeight,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: _cellVerticalPadding),
                                            decoration: BoxDecoration(
                                                color: selected == date
                                                    ? journal.sage
                                                    : null,
                                                border: date == today
                                                    ? Border.all(
                                                        color: journal.accent)
                                                    : null,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      '$day',
                                                      maxLines: 1,
                                                      softWrap: false,
                                                      style: _dateStyle,
                                                    ),
                                                  ),
                                                  if (items.isNotEmpty ||
                                                      personalCount > 0)
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                          '${items.length + personalCount}',
                                                          key: ValueKey(
                                                              'calendar-count-$day'),
                                                          maxLines: 1,
                                                          softWrap: false,
                                                          style: _countStyle),
                                                    )
                                                ]))));
                              }))
                          ]),
                      ]))),
              Padding(
                padding: EdgeInsets.only(top: 10, bottom: 2),
                child: Text('日期下方数字为当天合计。考试按开考日，其余按截止日，均为北京时间。',
                    style: TextStyle(fontSize: 12, color: journal.muted)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  selected == null
                      ? '本月议程'
                      : '${DateFormat('M月d日').format(selected!)} · 议程',
                  style: journal.section,
                ),
              ),
              const Divider(height: 1),
              if (agenda.isEmpty && manualAgenda.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child:
                        Text(widget.store.syncReport.phase == SyncPhase.failed
                            ? '本次读取失败，请到同步详情重试'
                            : widget.store.lastSyncAt == null && all.isEmpty
                                ? '尚未获取作业，请先同步'
                                : '所选范围没有已知日期的课业')),
              for (final a in agenda)
                AssignmentCard(
                    assignment: a,
                    examSources: courseSources,
                    displayIndex: widget.store.homeDisplayIndex,
                    now: now,
                    compact: widget.store.display.compact,
                    countdown: widget.store.display.countdown,
                    showFullDeadline: false,
                    onTap: () => context
                        .push('/assignments/${Uri.encodeComponent(a.id)}')),
              for (final e in manualAgenda)
                Builder(builder: (context) {
                  final journal = Journal.of(context);
                  final exam = e.kind == 'exam';
                  final accent = exam ? journal.slate : journal.ink;
                  final label = exam ? '手动考试' : '个人待办';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      exam ? Icons.school_outlined : Icons.event_note_outlined,
                      color: accent,
                    ),
                    title: Text(
                      '$label · ${e.title}',
                      style: journal.entryTitle.copyWith(color: accent),
                    ),
                    subtitle: Text(manualTime(e.at)),
                    onTap: () => context.push('/agenda'),
                  );
                }),
              if (noDeadlineCount > 0 || pendingDeadlineCount > 0) ...[
                const Divider(height: 24),
                Text('待核对课业', style: journal.section),
                if (noDeadlineCount > 0)
                  TextButton.icon(
                      key: const ValueKey('calendar-no-deadline-scope'),
                      onPressed: () => context.go(_recoveryLocation(
                          AssignmentRecoveryScope.noDeadline)),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: Text('无截止日期（$noDeadlineCount）')),
                if (pendingDeadlineCount > 0)
                  TextButton.icon(
                      key: const ValueKey('calendar-deadline-pending-scope'),
                      style: TextButton.styleFrom(
                        foregroundColor: journal.ochre,
                      ),
                      onPressed: () => context.go(_recoveryLocation(
                          AssignmentRecoveryScope.deadlinePending)),
                      icon: const Icon(Icons.help_outline),
                      label: Text('截止时间未知（$pendingDeadlineCount）')),
              ],
            ]);
      });

  String _recoveryLocation(AssignmentRecoveryScope scope) =>
      Uri(path: '/assignments', queryParameters: {
        AssignmentRecoveryScope.queryParameter: scope.queryValue,
      }).toString();

  double _calendarCellHeight(BuildContext context, TextScaler textScaler) {
    double lineHeight(TextStyle style) =>
        textScaler.scale(style.fontSize!) * style.height!;

    final content = lineHeight(_dateStyle) + lineHeight(_countStyle);
    final chrome = 2 * (_cellBorderWidth + _cellVerticalPadding) + _cellSlack;
    return math.max(48.0, content + chrome);
  }
}
