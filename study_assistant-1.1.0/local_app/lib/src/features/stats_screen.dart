import 'package:flutter/material.dart';
import '../app/journal.dart';
import '../services/assignment_store.dart';
import '../services/assignment_statistics.dart';
import 'widgets/completion_pie_chart.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now();
        final records = store.formalAssignments;
        final stats = AssignmentStatistics(records);
        final percent = stats.percentages;
        final keys = records.map((a) => a.courseKey!).toSet().toList()..sort();
        final names = {
          for (final key in keys)
            key: records.firstWhere((a) => a.courseKey == key).courseName
        };
        final overdue = records
            .where((a) =>
                !a.isCompleted &&
                a.isPendingConfirmed &&
                a.deadlineTrusted &&
                !a.deadlineReadFailed &&
                a.deadlineAt?.isBefore(now) == true)
            .length;
        Widget legend() => ExcludeSemantics(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Container(
                                      width: 10,
                                      height: 10,
                                      color: CompletionPieChart.colors[i])),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      '${[
                                        '已完成',
                                        '待提交',
                                        '状态待确认'
                                      ][i]}\n${stats.counts[i]} 份 · ${percent[i]}%',
                                      style: const TextStyle(
                                          fontSize: 15, height: 1.5)))
                            ]))
                ]));
        return ListView(
            key: const PageStorageKey('stats-list'),
            padding: const EdgeInsets.all(16),
            children: [
              const Text('课业统计',
                  style: TextStyle(
                      fontFamily: 'JournalTitle',
                      fontSize: 24,
                      color: Journal.ink)),
              const SizedBox(height: 8),
              const Text('当前关注课程 · 本机已读取记录',
                  style: TextStyle(color: Journal.muted, fontSize: 14)),
              const SizedBox(height: 20),
              if (stats.total == 0)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('暂无可统计的作业'))
              else ...[
                Text(
                    stats.unknown == stats.total
                        ? '全部状态待确认'
                        : '已确认完成 ${percent[0]}%',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final stacked = c.maxWidth < 320 ||
                      MediaQuery.textScalerOf(context).scale(15) > 20;
                  return stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                              Center(
                                  child: CompletionPieChart(statistics: stats)),
                              const SizedBox(height: 12),
                              legend()
                            ])
                      : Row(children: [
                          CompletionPieChart(statistics: stats),
                          const SizedBox(width: 24),
                          Expanded(child: legend())
                        ]);
                }),
                const SizedBox(height: 8),
                Text('共 ${stats.total} 份 · 已逾期 $overdue 份（属于待提交）',
                    style: const TextStyle(fontSize: 14, color: Journal.muted)),
                if (stats.unknown > 0)
                  const Text('待确认记录计入总数，请以学习通实际提交结果为准。',
                      style: TextStyle(fontSize: 14, color: Journal.muted)),
              ],
              const SizedBox(height: 28),
              const Text('各课程待处理',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (!records.any((a) => !a.isCompleted)) const Text('当前没有待处理的课程'),
              for (final key in keys)
                Builder(builder: (context) {
                  final own = AssignmentStatistics(
                      records.where((a) => a.courseKey == key));
                  if (own.pending + own.unknown == 0) {
                    return const SizedBox.shrink();
                  }
                  final same =
                      keys.where((k) => names[k] == names[key]).toList();
                  final name =
                      '${names[key]}${same.length > 1 ? ' · 分组${same.indexOf(key) + 1}' : ''}';
                  return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('待提交 ${own.pending} 份 · 待确认 ${own.unknown} 份',
                                style: const TextStyle(
                                    color: Journal.muted, fontSize: 14)),
                            const Divider(height: 20)
                          ]));
                }),
            ]);
      });
}
