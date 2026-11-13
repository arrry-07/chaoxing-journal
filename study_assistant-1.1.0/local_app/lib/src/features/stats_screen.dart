import 'dart:async';

import 'package:flutter/material.dart';
import '../app/journal.dart';
import '../services/assignment_store.dart';
import '../services/assignment_statistics.dart';
import 'widgets/completion_pie_chart.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.store, this.clock});
  final AssignmentStore store;
  final DateTime Function()? clock;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Timer? _clock;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = widget.clock?.call() ?? DateTime.now();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = widget.clock?.call() ?? DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final now = _now;
        // Use one instant for the overview and each course, including deadlines
        // that pass while the widget is building.
        final records = store.formalAssignments;
        final stats = AssignmentStatistics(records, now: now);
        final keys = records.map((a) => a.courseKey!).toSet().toList()..sort();
        final names = {
          for (final key in keys)
            key: records.firstWhere((a) => a.courseKey == key).courseName
        };
        Widget legend() => ExcludeSemantics(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 4; i++)
                      if (i < 3 || stats.unknown > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                          color: CompletionPieChart.colors[i],
                                          shape: BoxShape.circle)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(CompletionPieChart.labels[i],
                                        style: Journal.time),
                                    const SizedBox(height: 3),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                              child: Text(
                                                  '${stats.counts[i]} 份',
                                                  style: Journal.metadata)),
                                          const SizedBox(width: 8),
                                          Flexible(
                                              child: Text(
                                                  '${stats.percentages[i]}%',
                                                  style: Journal.metadata,
                                                  textAlign: TextAlign.right)),
                                        ]),
                                  ],
                                )),
                              ]),
                        ),
                  ]),
            );
        return ListView(
            key: const PageStorageKey('stats-list'),
            padding: const EdgeInsets.all(20),
            children: [
              const Text('课业统计', style: Journal.section),
              const SizedBox(height: 8),
              const Text('当前关注课程 · 本机已读取记录', style: Journal.metadata),
              const SizedBox(height: 24),
              if (stats.total == 0)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('暂无可统计的作业', style: Journal.metadata))
              else ...[
                if (stats.unknown == stats.total)
                  const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text('全部状态待确认', style: Journal.entryTitle)),
                LayoutBuilder(builder: (context, c) {
                  final stacked = c.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(16) > 22;
                  return stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                              Center(
                                  child: CompletionPieChart(statistics: stats)),
                              const SizedBox(height: 18),
                              legend(),
                            ])
                      : Row(children: [
                          CompletionPieChart(
                              statistics: stats,
                              diameter: (c.maxWidth * .45).clamp(136, 176)),
                          const SizedBox(width: 20),
                          Expanded(child: legend()),
                        ]);
                }),
                const SizedBox(height: 16),
                Text('共 ${stats.total} 份作业', style: Journal.metadata),
                if (stats.unknown > 0) ...[
                  const SizedBox(height: 4),
                  const Text('提交未知记录计入总数，请以学习通实际提交结果为准。',
                      style: Journal.metadata),
                ],
              ],
              const SizedBox(height: 28),
              const Divider(height: 1, color: Journal.rule),
              const SizedBox(height: 24),
              const Text('各课程待处理', style: Journal.section),
              const SizedBox(height: 8),
              if (!records.any((a) => !a.isCompleted))
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('当前没有待处理的课程', style: Journal.metadata)),
              for (final key in keys)
                Builder(builder: (context) {
                  final own = AssignmentStatistics(
                      records.where((a) => a.courseKey == key),
                      now: now);
                  if (own.pending + own.expired + own.unknown == 0) {
                    return const SizedBox.shrink();
                  }
                  final same =
                      keys.where((k) => names[k] == names[key]).toList();
                  final name =
                      '${names[key]}${same.length > 1 ? ' · 分组${same.indexOf(key) + 1}' : ''}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CourseMark(names[key]!, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(name, style: Journal.entryTitle),
                                const SizedBox(height: 6),
                                Wrap(spacing: 16, runSpacing: 4, children: [
                                  Text('待完成 ${own.pending} 份',
                                      style: Journal.metadata),
                                  Text('已逾期 ${own.expired} 份',
                                      style: Journal.metadata.copyWith(
                                          color: own.expired > 0
                                              ? Journal.berry
                                              : null)),
                                  if (own.unknown > 0)
                                    Text('提交未知 ${own.unknown} 份',
                                        style: Journal.metadata),
                                ]),
                              ])),
                        ]),
                  );
                }),
            ]);
      });
}
