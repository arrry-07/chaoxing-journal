import 'package:flutter/material.dart';
import '../app/journal.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../services/assignment_store.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.store});

  final AssignmentStore store;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
  }

  void _onDaySelected(int day) {
    final tapped = DateTime(_currentMonth.year, _currentMonth.month, day);
    setState(() {
      if (_selectedDate != null &&
          _selectedDate!.year == tapped.year &&
          _selectedDate!.month == tapped.month &&
          _selectedDate!.day == tapped.day) {
        _selectedDate = null;
      } else {
        _selectedDate = tapped;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final assignments = widget.store.visibleAssignments
            .where((item) => item.deadlineAt != null)
            .toList()
          ..sort(Assignment.compareByDeadline);
        final filtered = _selectedDate == null
            ? assignments
            : assignments
                .where((a) => DateUtils.isSameDay(a.deadlineAt, _selectedDate))
                .toList();
        final grouped = _groupByDate(filtered);
        final monthLabel = DateFormat('yyyy年M月', 'zh_CN').format(_currentMonth);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: const JournalHeading(
                    '截止日历',
                    eyebrow: 'CAMPUS JOURNAL   /   02',
                  ),
                ),
                if (_selectedDate != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _selectedDate = null),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('清除筛选'),
                  )
                else
                  TextButton.icon(
                    onPressed: widget.store.syncAssignments,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('刷新'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _MonthCard(
              month: monthLabel,
              currentMonth: _currentMonth,
              selectedDate: _selectedDate,
              assignments: assignments,
              onPrevious: _previousMonth,
              onNext: _nextMonth,
              onDaySelected: _onDaySelected,
            ),
            const SizedBox(height: 18),
            if (_selectedDate != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  DateFormat('M月d日 EEEE', 'zh_CN').format(_selectedDate!),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            if (grouped.isEmpty)
              const _CalendarEmpty()
            else if (_selectedDate != null)
              for (final assignment in filtered)
                _CalendarAssignmentTile(assignment: assignment)
            else
              for (final entry in grouped.entries) ...[
                _DateHeader(date: entry.key),
                const SizedBox(height: 8),
                for (final assignment in entry.value)
                  _CalendarAssignmentTile(assignment: assignment),
                const SizedBox(height: 14),
              ],
          ],
        );
      },
    );
  }

  Map<DateTime, List<Assignment>> _groupByDate(List<Assignment> assignments) {
    final grouped = <DateTime, List<Assignment>>{};
    for (final item in assignments) {
      final key = DateUtils.dateOnly(item.deadlineAt!);
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.currentMonth,
    required this.selectedDate,
    required this.assignments,
    required this.onPrevious,
    required this.onNext,
    required this.onDaySelected,
  });

  final String month;
  final DateTime currentMonth;
  final DateTime? selectedDate;
  final List<Assignment> assignments;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDay = DateTime(currentMonth.year, currentMonth.month);
    final daysInMonth = DateTime(
      currentMonth.year,
      currentMonth.month + 1,
      0,
    ).day;
    final dueDays = assignments
        .where(
          (a) =>
              a.deadlineAt?.year == currentMonth.year &&
              a.deadlineAt?.month == currentMonth.month,
        )
        .map((a) => a.deadlineAt!.day)
        .toSet();
    final leading = firstDay.weekday % 7;

    final cells = <Widget>[
      for (final label in const ['日', '一', '二', '三', '四', '五', '六'])
        Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Journal.muted,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      for (var i = 0; i < leading; i += 1) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day += 1)
        _DayCell(
          day: day,
          isToday: today.year == currentMonth.year &&
              today.month == currentMonth.month &&
              today.day == day,
          selected: selectedDate != null &&
              selectedDate!.year == currentMonth.year &&
              selectedDate!.month == currentMonth.month &&
              selectedDate!.day == day,
          hasAssignment: dueDays.contains(day),
          onTap: () => onDaySelected(day),
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                  style: IconButton.styleFrom(foregroundColor: Journal.muted),
                ),
                Expanded(
                  child: Text(
                    month,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                  style: IconButton.styleFrom(foregroundColor: Journal.muted),
                ),
              ],
            ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 7,
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(20) + 20,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 2,
              children: cells,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.selected,
    required this.hasAssignment,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final bool selected;
  final bool hasAssignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = selected
        ? colorScheme.primary
        : isToday
            ? colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent;
    final textColor = selected
        ? Colors.white
        : isToday
            ? colorScheme.primary
            : Journal.ink;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: textColor,
                fontWeight:
                    isToday || selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            if (hasAssignment)
              Positioned(
                bottom: 6,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Colors.white : Journal.berry,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final sameDay = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    return Text(
      '${DateFormat('M月d日', 'zh_CN').format(date)} ${sameDay ? '今天' : DateFormat('E', 'zh_CN').format(date)}',
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _CalendarAssignmentTile extends StatelessWidget {
  const _CalendarAssignmentTile({required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          leading: Text(
            DateFormat('HH:mm', 'zh_CN').format(assignment.deadlineAt!),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w900,
                ),
          ),
          title: Text(assignment.courseName),
          subtitle: Text(assignment.title),
          trailing: const _TypePill(label: '作业'),
          onTap: () => context.push(
            '/assignments/${Uri.encodeComponent(assignment.id)}',
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Journal.sage,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CalendarEmpty extends StatelessWidget {
  const _CalendarEmpty();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 46,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 10),
            const Text('暂无已知截止时间的作业'),
          ],
        ),
      ),
    );
  }
}
