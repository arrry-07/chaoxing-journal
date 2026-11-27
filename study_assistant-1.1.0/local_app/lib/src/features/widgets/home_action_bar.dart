import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../models/home_filters.dart';
import 'journal_buttons.dart';

String homeDeadlineFilterLabel(AssignmentDeadlineFilter filter) =>
    switch (filter) {
      AssignmentDeadlineFilter.all => '全部',
      AssignmentDeadlineFilter.next7Days => '7天内',
      AssignmentDeadlineFilter.next30Days => '30天内',
      AssignmentDeadlineFilter.overdue => '已逾期',
      AssignmentDeadlineFilter.uncertain => '期限待确认',
      AssignmentDeadlineFilter.noDeadline => '无截止日期',
      AssignmentDeadlineFilter.notExpired => '未逾期',
    };

String homeShortSortLabel(HomeSortOrder order) =>
    switch (normalizedHomeSort(order)) {
      HomeSortOrder.deadlineDesc => '时间远到近',
      HomeSortOrder.courseName => '按课程',
      _ => '时间近到远',
    };

class HomeAccountGuardScope extends InheritedWidget {
  const HomeAccountGuardScope({
    super.key,
    required this.currentAccountEpoch,
    required this.currentAccount,
    required super.child,
  });

  final int Function() currentAccountEpoch;
  final String? Function() currentAccount;

  static HomeAccountGuardScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeAccountGuardScope>();

  @override
  bool updateShouldNotify(HomeAccountGuardScope oldWidget) => false;
}

class HomeActionBar extends StatelessWidget {
  const HomeActionBar({
    super.key,
    required this.filtersActive,
    this.activeFilterCount = 0,
    required this.onOpenFilters,
    required this.onAddManual,
  });

  final bool filtersActive;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;
  final VoidCallback onAddManual;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final effectiveCount =
        activeFilterCount > 0 ? activeFilterCount : (filtersActive ? 1 : 0);
    final hasFilters = filtersActive && effectiveCount > 0;
    final filterColor = hasFilters ? journal.accent : journal.muted;
    final filterStyle = journal.metadata.copyWith(
      color: hasFilters ? journal.ink : journal.muted,
      fontWeight: FontWeight.w500,
    );
    final addStyle = journal.metadata.copyWith(
      color: journal.ink,
      fontWeight: FontWeight.w600,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final filterLabel = hasFilters ? '搜索与筛选 ($effectiveCount)' : '搜索与筛选';
    const addLabel = '添加';

    double labelWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    final filterWidth = 16 + 5 + labelWidth(filterLabel, filterStyle) + 22;
    final addWidth = 16 + 5 + labelWidth(addLabel, addStyle) + 22;

    Widget buildFilterPill({bool fullWidth = false}) {
      final message = hasFilters ? '已启用 $effectiveCount 项筛选，打开搜索与筛选' : '搜索与筛选';
      return Semantics(
        button: true,
        label: message,
        onTap: onOpenFilters,
        child: ExcludeSemantics(
          child: Tooltip(
            message: message,
            child: JournalPressableScale(
              pressScale: 0.97,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('home-filter-action'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: onOpenFilters,
                  enableFeedback: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 48,
                      minWidth: fullWidth ? double.infinity : 0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: fullWidth ? null : 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6.5),
                        decoration: BoxDecoration(
                          color: hasFilters ? journal.sage : journal.parchment,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasFilters
                                ? journal.sageBorder
                                : Colors.transparent,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize:
                              fullWidth ? MainAxisSize.max : MainAxisSize.min,
                          children: [
                            Icon(
                              hasFilters
                                  ? Icons.tune_rounded
                                  : Icons.search_rounded,
                              size: 16,
                              color: filterColor,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                filterLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: filterStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildAddButton() {
      const message = '添加课业或待办';
      return Semantics(
        button: true,
        label: message,
        onTap: onAddManual,
        child: ExcludeSemantics(
          child: Tooltip(
            message: message,
            child: JournalPressableScale(
              pressScale: 0.97,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('home-add-manual'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: onAddManual,
                  enableFeedback: false,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Center(
                      widthFactor: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6.5,
                        ),
                        decoration: BoxDecoration(
                          color: journal.sage,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: journal.sageBorder,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 16,
                              color: journal.ink,
                            ),
                            const SizedBox(width: 5),
                            Text(addLabel, style: addStyle),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      if (filterWidth + addWidth + 16 <= constraints.maxWidth) {
        return Row(children: [
          Expanded(child: buildFilterPill(fullWidth: true)),
          const SizedBox(width: 8),
          buildAddButton(),
        ]);
      }
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          buildFilterPill(),
          buildAddButton(),
        ],
      );
    });
  }
}
