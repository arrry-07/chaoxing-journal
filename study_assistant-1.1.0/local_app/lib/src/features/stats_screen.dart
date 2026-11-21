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
  Color get _overviewCardColor =>
      Color.lerp(Journal.of(context).paper, Journal.of(context).sheet, .70)!;
  Color get _courseCardColor =>
      Color.lerp(Journal.of(context).paper, Journal.of(context).sheet, .50)!;
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
          side: BorderSide(color: Journal.of(context).rule, width: 0.8),
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
          final journal = Journal.of(context);
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

          Widget legend() => LayoutBuilder(
                builder: (context, constraints) {
                  final singleLine = constraints.maxWidth >= 170 &&
                      !JournalLayout.isLargeText(context);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 4; i++)
                        if (i < 3 || stats.unknown > 0)
                          Builder(
                            builder: (context) {
                              final journal = Journal.of(context);
                              final canTap = stats.counts[i] > 0;
                              final label = CompletionPieChart.labels[i];
                              final dot = Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color:
                                      CompletionPieChart.colorsFor(journal)[i],
                                  shape: BoxShape.circle,
                                ),
                              );
                              final countText = Text(
                                '${stats.counts[i]} 份',
                                style: journal.metadata,
                              );
                              final sepText = Text(
                                ' · ',
                                style: journal.metadata.copyWith(
                                  color: journal.muted.withValues(alpha: .55),
                                ),
                              );
                              final pctText = Text(
                                '${stats.percentages[i]}%',
                                style: journal.metadata.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              );
                              final row = Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: singleLine ? 5 : 3,
                                  horizontal: 2,
                                ),
                                child: singleLine
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          dot,
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: journal.entryTitle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          countText,
                                          sepText,
                                          pctText,
                                          if (canTap) ...[
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.chevron_right,
                                              size: 16,
                                              color: journal.muted,
                                            ),
                                          ],
                                        ],
                                      )
                                    : Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 7),
                                            child: dot,
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
                                                        style: journal.time,
                                                      ),
                                                    ),
                                                    if (canTap)
                                                      Icon(
                                                        Icons.chevron_right,
                                                        size: 16,
                                                        color: journal.muted,
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Flexible(child: countText),
                                                    sepText,
                                                    pctText,
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
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                },
              );

          return Material(
            type: MaterialType.transparency,
            child: ListView(
              key: const PageStorageKey('stats-list'),
              padding: EdgeInsets.fromLTRB(
                18,
                14,
                18,
                JournalLayout.floatingNavClearance(context),
              ),
              children: [
                const JournalHeading(
                  '课业统计',
                  bookTitle: true,
                ),
                const SizedBox(height: 4),
                Text('统计范围：已关注课程的课业与账号考试', style: journal.metadata),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final range in StatsTimeRange.values)
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
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
                    style: journal.metadata,
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
                          Text('暂无可统计的作业', style: journal.entryTitle),
                          if (_range != StatsTimeRange.all) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${_range.label}内暂无带确定时间的课业记录，可切回“全部”查看。',
                              style: journal.metadata,
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
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text('全部状态待确认', style: journal.entryTitle),
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
                          Divider(height: 1, color: journal.rule),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '共 ${stats.total} 项课业',
                                style: journal.metadata,
                              ),
                              Text(
                                '不含已隐藏；提交未知计入；点击图例或课程查看明细',
                                style: journal.metadata,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text('各课程待处理', style: journal.section),
                const SizedBox(height: 6),
                if (!records.any((a) => !a.isCompleted))
                  _statsCard(
                    key: const ValueKey('stats-course-empty'),
                    color: _overviewCardColor,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('当前没有待处理的课程', style: journal.metadata),
                    ),
                  ),
                for (final group in groups)
                  Builder(
                    builder: (context) {
                      final journal = Journal.of(context);
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
                                  group.courseKey == null
                                      ? Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: journal.paper,
                                            borderRadius:
                                                BorderRadius.circular(30 * .28),
                                            border: Border.all(
                                              color: journal.rule,
                                              width: 1,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.description_outlined,
                                            size: 17,
                                            color: journal.muted,
                                          ),
                                        )
                                      : CourseMark(group.name, size: 30),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: journal.entryTitle),
                                        const SizedBox(height: 3),
                                        Wrap(
                                          spacing: 14,
                                          runSpacing: 4,
                                          children: [
                                            if (own.pending > 0)
                                              Text(
                                                '待完成 ${own.pending} 份',
                                                style:
                                                    journal.metadata.copyWith(
                                                  color: journal.ink,
                                                ),
                                              ),
                                            if (own.expired > 0)
                                              Text(
                                                '已逾期 ${own.expired} 份',
                                                style:
                                                    journal.metadata.copyWith(
                                                  color: journal.berry,
                                                ),
                                              ),
                                            if (own.unknown > 0)
                                              Text(
                                                '提交未知 ${own.unknown} 份',
                                                style: journal.metadata,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Icon(
                                      Icons.chevron_right,
                                      color: journal.muted,
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
