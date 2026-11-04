import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../app/journal.dart';

import '../models/assignment.dart';
import '../services/assignment_store.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final visible = store.visibleAssignments;
        final total = store.assignments.length;
        final completed =
            store.assignments.where((item) => item.isCompleted).length;
        final overdue = visible.where((item) => item.isOverdue).length;
        final percent = total == 0 ? 0.0 : completed / total;
        final byCourse = _courseCounts(visible);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            const JournalHeading('课业统计', eyebrow: 'CAMPUS JOURNAL   /   03'),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '已完成 ${(percent * 100).round()}%',
                      style: Journal.section,
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: percent,
                      backgroundColor: Journal.sage,
                    ),
                    const SizedBox(height: 12),
                    _StatRow(label: '已完成', value: completed),
                    _StatRow(label: '待完成', value: visible.length),
                    _StatRow(label: '已过期', value: overdue),
                    _StatRow(
                        label: '暂无截止时间',
                        value: visible
                            .where((item) => item.deadlineAt == null)
                            .length),
                    const Divider(),
                    _StatRow(label: '总计', value: total),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '课程完成情况',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (byCourse.isEmpty)
                      const Text('暂无待完成课程')
                    else
                      for (final entry in byCourse.entries)
                        _CourseProgress(
                          courseName: entry.key,
                          pendingCount: entry.value,
                          maxCount: byCourse.values.reduce(math.max),
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Map<String, int> _courseCounts(List<Assignment> assignments) {
    final result = <String, int>{};
    for (final item in assignments) {
      result[item.courseName] = (result[item.courseName] ?? 0) + 1;
    }
    return Map.fromEntries(
      result.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _CourseProgress extends StatelessWidget {
  const _CourseProgress({
    required this.courseName,
    required this.pendingCount,
    required this.maxCount,
  });

  final String courseName;
  final int pendingCount;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final value = maxCount == 0 ? 0.0 : pendingCount / maxCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              courseName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: Journal.rule,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('$pendingCount'),
        ],
      ),
    );
  }
}
