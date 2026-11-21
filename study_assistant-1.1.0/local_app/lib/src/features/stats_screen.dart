import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../models/assignment.dart';
import '../services/assignment_statistics.dart';
import '../services/assignment_store.dart';
import '../services/local_record_query.dart';
import 'widgets/completion_pie_chart.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_info_popover.dart';

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
  static const _bucketStatusParams = [
    'completed',
    'pending',
    'overdue',
    'unknown',
  ];

  Timer? _clock;
  late DateTime _now;
  StatsTimeRange _range = StatsTimeRange.all;

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

          final pendingGroups = groups.where((g) {
            final own = AssignmentStatistics(g.records, now: now);
            return own.pending + own.expired + own.unknown > 0;
          }).toList(growable: false);

          final allUnknown = stats.total > 0 && stats.unknown == stats.total;
          final barColors = CompletionPieChart.colorsFor(journal);

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
                const JournalHeading('课业统计', bookTitle: true),
                const SizedBox(height: 10),
                _StatsRangeSegmentedBar(
                  selected: _range,
                  onChanged: (next) {
                    JournalMotion.tap(store.display);
                    setState(() => _range = next);
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
                              '${_range.label}内暂无带确定时间的课业记录，可切回“全部”查看。',
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
                        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
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
                                    borderRadius: BorderRadius.circular(14),
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
                                    '点击下方状态行或课程行可直接查看对应记录明细。',
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _MultiSegmentStatsBar(
                              counts: stats.counts,
                              colors: barColors,
                              trackColor: journal.parchment,
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
                            label: CompletionPieChart.labels[i],
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
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: largeText
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
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
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
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
      child: canTap ? InkWell(onTap: open, child: content) : content,
    );
  }

  Widget _buildCourseRow(
    BuildContext context, {
    required _StatsGroup group,
    required List<_StatsGroup> allGroups,
    required DateTime now,
    required JournalPalette journal,
  }) {
    final own = AssignmentStatistics(group.records, now: now);
    final same = group.accountExam
        ? const <_StatsGroup>[]
        : allGroups
            .where((other) => !other.accountExam && other.name == group.name)
            .toList();
    final name =
        '${group.name}${same.length > 1 ? ' · 分组${same.indexOf(group) + 1}' : ''}';
    final largeText = JournalLayout.isLargeText(context);
    final pills = Wrap(
      spacing: 5,
      runSpacing: 4,
      alignment: largeText ? WrapAlignment.start : WrapAlignment.end,
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
            fg: journal.berry,
            bg: journal.berryBg,
            journal: journal,
          ),
        if (own.unknown > 0)
          _CourseStatPill(
            text: '未知 ${own.unknown}',
            fg: journal.muted,
            bg: journal.parchment,
            journal: journal,
          ),
      ],
    );

    return InkWell(
      key: ValueKey('stats-course-${group.courseKey ?? group.scope.name}'),
      onTap: () => _openRecords(
        context,
        scope: group.scope,
        courseKey: group.courseKey,
        status: 'unfinished',
      ),
      child: Padding(
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
            const SizedBox(width: 10),
            Expanded(
              child: largeText
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: journal.entryTitle),
                        const SizedBox(height: 6),
                        pills,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: journal.entryTitle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(flex: 0, child: pills),
                      ],
                    ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: journal.muted,
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: journal.pillLabel.copyWith(
          fontSize: 11.5,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
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
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: journal.parchment,
        borderRadius: BorderRadius.circular(14),
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        selected == range ? journal.sheet : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
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
                  child: Text(
                    range.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: journal.pillLabel.copyWith(
                      fontSize: 13,
                      fontWeight:
                          selected == range ? FontWeight.w600 : FontWeight.w500,
                      color: selected == range ? journal.ink : journal.muted,
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
              TextSpan(text: '$doneVal', style: journal.statHero),
              TextSpan(
                text: ' / $total',
                style: journal.entryTitle.copyWith(
                  fontSize: 17,
                  color: journal.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
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
    required this.animateDuration,
  });

  final List<int> counts;
  final List<Color> colors;
  final Color trackColor;
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
                    if (i > 0) const SizedBox(width: 2),
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
                            height: 10,
                            color: colors[active[i].index],
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
