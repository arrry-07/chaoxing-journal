import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../models/assignment.dart';
import '../services/assignment_statistics.dart';
import '../services/assignment_store.dart';
import '../services/local_record_query.dart';
import 'widgets/completion_pie_chart.dart';

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

class _StatsScreenState extends State<StatsScreen> {
  static final _overviewCardColor =
      Color.lerp(Journal.paper, Journal.sheet, .70)!;
  static final _courseCardColor =
      Color.lerp(Journal.paper, Journal.sheet, .50)!;
  static const _bucketStatusParams = [
    'completed',
    'pending',
    'overdue',
    'unknown',
  ];

  Timer? _clock;
  late DateTime _now;
  StatsTimeRange _range = StatsTimeRange.all;

  Widget _statsCard({
    Key? key,
    required Color color,
    required Widget child,
  }) =>
      Card(
        key: key,
        color: color,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Journal.rule, width: 0.8),
        ),
        child: child,
      );

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
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final store = widget.store;
          final now = _now;
          // Use one instant for the overview and each course, including deadlines
          // that pass while the widget is building.
          final rangeResult = LocalRecordQuery.filterStatsRecords(
            store.statsAssignments,
            _range,
            now,
          );
          final records = rangeResult.records;
          final excludedUnscheduled = rangeResult.excludedUnscheduledCount;
          final stats = AssignmentStatistics(records, now: now);
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

          Widget legend() => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 4; i++)
                    if (i < 3 || stats.unknown > 0)
                      Builder(
                        builder: (context) {
                          final canTap = stats.counts[i] > 0;
                          final label = CompletionPieChart.labels[i];
                          final row = Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 3,
                              horizontal: 2,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: CompletionPieChart.legendColors[i],
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: Journal.time,
                                            ),
                                          ),
                                          if (canTap)
                                            const Icon(
                                              Icons.chevron_right,
                                              size: 16,
                                              color: Journal.muted,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '${stats.counts[i]} 份',
                                              style: Journal.metadata,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              '${stats.percentages[i]}%',
                                              style: Journal.metadata,
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                          void open() => _openRecords(
                                context,
                                scope: LocalRecordScopeFilter.followedStats,
                                status: _bucketStatusParams[i],
                              );
                          return Semantics(
                            button: canTap,
                            onTap: canTap ? open : null,
                            label:
                                '$label ${stats.counts[i]} 份，${stats.percentages[i]}%',
                            excludeSemantics: true,
                            child: canTap
                                ? Material(
                                    type: MaterialType.transparency,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: open,
                                      child: row,
                                    ),
                                  )
                                : row,
                          );
                        },
                      ),
                ],
              );

          return Material(
            type: MaterialType.transparency,
            child: ListView(
              key: const PageStorageKey('stats-list'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              children: [
                const JournalHeading(
                  '课业统计',
                  eyebrow: 'CAMPUS JOURNAL   /   STATISTICS',
                ),
                const SizedBox(height: 4),
                const Text('统计范围：已关注课程的课业与账号考试', style: Journal.metadata),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final range in StatsTimeRange.values)
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(range.label),
                        selected: _range == range,
                        onSelected: (_) => setState(() => _range = range),
                      ),
                  ],
                ),
                if (_range != StatsTimeRange.all &&
                    excludedUnscheduled > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '不含 $excludedUnscheduled 项无确定时间课业（切回“全部”可查看）',
                    style: Journal.metadata,
                  ),
                ],
                const SizedBox(height: 8),
                if (stats.total == 0)
                  _statsCard(
                    key: const ValueKey('stats-empty-card'),
                    color: _overviewCardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('暂无可统计的作业', style: Journal.entryTitle),
                          if (_range != StatsTimeRange.all) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${_range.label}内暂无带确定时间的课业记录，可切回“全部”查看。',
                              style: Journal.metadata,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  _statsCard(
                    key: const ValueKey('stats-overview-card'),
                    color: _overviewCardColor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (stats.unknown == stats.total)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text('全部状态待确认', style: Journal.entryTitle),
                            ),
                          LayoutBuilder(
                            builder: (context, c) {
                              final stacked = c.maxWidth < 240 ||
                                  MediaQuery.textScalerOf(context).scale(16) >
                                      22;
                              return stacked
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Center(
                                          child: CompletionPieChart(
                                              statistics: stats),
                                        ),
                                        const SizedBox(height: 12),
                                        legend(),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        CompletionPieChart(
                                          statistics: stats,
                                          diameter: (c.maxWidth * .40)
                                              .clamp(118, 140),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(child: legend()),
                                      ],
                                    );
                            },
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1, color: Journal.rule),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '共 ${stats.total} 项课业',
                                style: Journal.metadata,
                              ),
                              const Text(
                                '不含已隐藏；提交未知计入；点击图例或课程查看明细',
                                style: Journal.metadata,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('各课程待处理', style: Journal.section),
                const SizedBox(height: 6),
                if (!records.any((a) => !a.isCompleted))
                  _statsCard(
                    key: const ValueKey('stats-course-empty'),
                    color: _overviewCardColor,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('当前没有待处理的课程', style: Journal.metadata),
                    ),
                  ),
                for (final group in groups)
                  Builder(
                    builder: (context) {
                      final own = AssignmentStatistics(group.records, now: now);
                      if (own.pending + own.expired + own.unknown == 0) {
                        return const SizedBox.shrink();
                      }
                      final same = group.accountExam
                          ? const <_StatsGroup>[]
                          : groups
                              .where((other) =>
                                  !other.accountExam &&
                                  other.name == group.name)
                              .toList();
                      final name =
                          '${group.name}${same.length > 1 ? ' · 分组${same.indexOf(group) + 1}' : ''}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _statsCard(
                          key: ValueKey(
                            'stats-course-${group.courseKey ?? group.scope.name}',
                          ),
                          color: _courseCardColor,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openRecords(
                              context,
                              scope: group.scope,
                              courseKey: group.courseKey,
                              status: 'unfinished',
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ExcludeSemantics(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Center(
                                        child: Icon(
                                          group.courseKey == null
                                              ? Icons.description_outlined
                                              : Icons.menu_book_outlined,
                                          size: 20,
                                          color: Journal.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: Journal.entryTitle),
                                        const SizedBox(height: 3),
                                        Wrap(
                                          spacing: 16,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              '待完成 ${own.pending} 份',
                                              style: Journal.metadata,
                                            ),
                                            Text(
                                              '已逾期 ${own.expired} 份',
                                              style: Journal.metadata.copyWith(
                                                color: own.expired > 0
                                                    ? Journal.berry
                                                    : null,
                                              ),
                                            ),
                                            if (own.unknown > 0)
                                              Text(
                                                '提交未知 ${own.unknown} 份',
                                                style: Journal.metadata,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Icon(
                                      Icons.chevron_right,
                                      color: Journal.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      );
}
