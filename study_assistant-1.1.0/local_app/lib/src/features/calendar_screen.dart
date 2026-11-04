import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../app/journal.dart';
import '../models/sync_report.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import 'widgets/assignment_card.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime get today => AssignmentQuery.dayKey(DateTime.now());
  late DateTime month = DateTime(today.year, today.month);
  late DateTime? selected = today;
  void move(int delta) => setState(() {
        month = DateTime(month.year, month.month + delta);
        selected = DateTime(month.year, month.month);
      });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final all = widget.store.visibleAssignments;
        final dated = all
            .where((a) => a.deadlineAt != null && a.deadlineTrusted)
            .toList();
        final agenda = selected == null
            ? dated.where((a) {
                final d = AssignmentQuery.dayKey(a.deadlineAt!);
                return d.year == month.year && d.month == month.month;
              }).toList()
            : AssignmentQuery.forDay(all, selected!, {});
        agenda.sort((a, b) => a.deadlineAt!.compareTo(b.deadlineAt!));
        final days = DateTime(month.year, month.month + 1, 0).day,
            leading = month.weekday % 7;
        final large = MediaQuery.textScalerOf(context).scale(14) > 21;
        final cellHeight = large ? 82.0 : 48.0;
        return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Text('截止日历', style: Journal.section),
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
                    onPressed: widget.store.syncAssignments,
                    icon: const Icon(Icons.sync))
              ]),
              Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(children: [
                        Row(children: [
                          IconButton(
                              tooltip: '上个月',
                              onPressed: () => move(-1),
                              icon: const Icon(Icons.chevron_left)),
                          Expanded(
                              child: Text(DateFormat('yyyy年M月').format(month),
                                  textAlign: TextAlign.center,
                                  style: Journal.section)),
                          IconButton(
                              tooltip: '下个月',
                              onPressed: () => move(1),
                              icon: const Icon(Icons.chevron_right))
                        ]),
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
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Journal.muted))))
                        ]),
                        const SizedBox(height: 4),
                        for (var row = 0;
                            row < (leading + days + 6) ~/ 7;
                            row++)
                          Row(children: [
                            for (var col = 0; col < 7; col++)
                              Expanded(child: Builder(builder: (context) {
                                final day = row * 7 + col - leading + 1;
                                if (day < 1 || day > days) {
                                  return SizedBox(height: cellHeight);
                                }
                                final date =
                                        DateTime(month.year, month.month, day),
                                    items = AssignmentQuery.forDay(
                                        all,
                                        DateTime(month.year, month.month, day),
                                        {});
                                final unknown = items
                                    .where((a) => !a.isPendingConfirmed)
                                    .length;
                                return Semantics(
                                    label:
                                        '${month.month}月$day日，${items.length - unknown}份待交，$unknown份待确认',
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
                                            decoration: BoxDecoration(
                                                color: selected == date
                                                    ? Journal.sage
                                                    : null,
                                                border: date == today
                                                    ? Border.all(
                                                        color: Journal.ink)
                                                    : null,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text('$day',
                                                      style: const TextStyle(
                                                          fontSize: 14)),
                                                  if (items.isNotEmpty)
                                                    Text('${items.length}',
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                Journal.berry))
                                                ]))));
                              }))
                          ]),
                      ]))),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('日期下方数字为待交与待确认的作业份数',
                      style: TextStyle(fontSize: 12, color: Journal.muted))),
              Text(
                  selected == null
                      ? '本月议程'
                      : DateFormat('M月d日').format(selected!),
                  style: Journal.section),
              if (agenda.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child:
                        Text(widget.store.syncReport.phase == SyncPhase.failed
                            ? '本次读取失败，请到同步详情重试'
                            : widget.store.lastSyncAt == null && all.isEmpty
                                ? '尚未获取作业，请先同步'
                                : '所选范围没有已知截止作业')),
              for (final a in agenda)
                AssignmentCard(
                    assignment: a,
                    now: DateTime.now(),
                    onTap: () => context
                        .push('/assignments/${Uri.encodeComponent(a.id)}')),
              if (all.any((a) => a.deadlineAt == null))
                TextButton(
                    onPressed: () => context.go('/assignments'),
                    child: const Text('查看无截止 / 待确认作业')),
            ]);
      });
}
