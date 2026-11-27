import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../models/display_preferences.dart';
import '../../models/home_filters.dart';
import 'journal_buttons.dart';
import 'journal_context_menu.dart';

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

String homeSortOrderLabel(HomeSortOrder order) => switch (order) {
      HomeSortOrder.grouped => '默认分组',
      HomeSortOrder.deadlineAsc => '时间：近到远（考试按开考）',
      HomeSortOrder.deadlineDesc => '时间：远到近（考试按开考）',
      HomeSortOrder.courseName => '按课程',
      HomeSortOrder.title => '名称',
    };

String homeSortMenuLabel(HomeSortOrder order) =>
    switch (normalizedHomeSort(order)) {
      HomeSortOrder.deadlineDesc => '时间：远到近',
      HomeSortOrder.courseName => '按课程',
      _ => '时间：近到远',
    };

IconData _sortMenuIcon(HomeSortOrder order) =>
    switch (normalizedHomeSort(order)) {
      HomeSortOrder.deadlineDesc => Icons.arrow_downward_rounded,
      HomeSortOrder.courseName => Icons.menu_book_outlined,
      _ => Icons.arrow_upward_rounded,
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
    required this.sortOrder,
    required this.displayPrefs,
    required this.accountEpoch,
    required this.account,
    this.currentAccountEpoch,
    this.currentAccount,
    required this.onOpenFilters,
    required this.onSelectSortOrder,
    required this.onAddManual,
  });

  final bool filtersActive;
  final HomeSortOrder sortOrder;
  final DisplayPreferences displayPrefs;
  final int accountEpoch;
  final String? account;
  final int Function()? currentAccountEpoch;
  final String? Function()? currentAccount;
  final VoidCallback onOpenFilters;
  final Future<void> Function(
    HomeSortOrder order,
    int openingEpoch,
    String? openingAccount,
  ) onSelectSortOrder;
  final VoidCallback onAddManual;

  Future<void> _openSortMenu(BuildContext anchorContext) async {
    final openingEpoch = accountEpoch;
    final openingAccount = account;
    final scope = HomeAccountGuardScope.maybeOf(anchorContext);
    final resolveEpoch = currentAccountEpoch ?? scope?.currentAccountEpoch;
    final resolveAccount = currentAccount ?? scope?.currentAccount;
    if (resolveEpoch != null && resolveEpoch() != openingEpoch) return;
    if (resolveAccount != null && resolveAccount() != openingAccount) return;
    final box = anchorContext.findRenderObject() as RenderBox?;
    Rect? anchorRect;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      anchorRect = topLeft & box.size;
    }
    await showJournalContextMenu(
      context: anchorContext,
      anchorRect: anchorRect,
      previewCard: null,
      displayPrefs: displayPrefs,
      useSelectionFeedback: true,
      actions: [
        for (final order in homeSortOrderChoices)
          JournalContextMenuAction(
            label: homeSortMenuLabel(order),
            icon: _sortMenuIcon(order),
            selected: order == sortOrder,
            onSelected: () => unawaited(
              onSelectSortOrder(order, openingEpoch, openingAccount),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final filterColor = filtersActive ? journal.accent : journal.muted;
    final filterStyle = journal.metadata.copyWith(
      color: filtersActive ? journal.ink : journal.muted,
      fontWeight: FontWeight.w500,
    );
    final sortStyle = journal.metadata.copyWith(
      color: journal.muted,
      fontWeight: FontWeight.w500,
    );
    final addStyle = journal.metadata.copyWith(
      color: journal.ink,
      fontWeight: FontWeight.w600,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final filterLabel = filtersActive ? '已筛选' : '搜索与筛选';
    final sortLabel = homeShortSortLabel(sortOrder);
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
    final sortWidth = 16 + 5 + labelWidth(sortLabel, sortStyle) + 22;
    final addWidth = 16 + 5 + labelWidth(addLabel, addStyle) + 22;

    Widget buildFilterPill({bool fullWidth = false}) {
      final message = filtersActive ? '已筛选，打开搜索与期限筛选' : '搜索与筛选';
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
                          color:
                              filtersActive ? journal.sage : journal.parchment,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: filtersActive
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
                              filtersActive
                                  ? Icons.tune_rounded
                                  : Icons.search_rounded,
                              size: 16,
                              color: filterColor,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(filterLabel, style: filterStyle),
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

    Widget buildSortButton() {
      final message = '当前排序：$sortLabel，切换排序方式';
      return Builder(
        builder: (sortContext) {
          void onTap() => unawaited(_openSortMenu(sortContext));
          return Semantics(
            button: true,
            label: message,
            onTap: onTap,
            child: ExcludeSemantics(
              child: Tooltip(
                message: message,
                child: JournalPressableScale(
                  pressScale: 0.97,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onTap,
                      enableFeedback: false,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          widthFactor: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 6.5),
                            decoration: BoxDecoration(
                              color: journal.parchment,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.transparent,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.swap_vert_rounded,
                                    size: 16, color: journal.muted),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    sortLabel,
                                    key: const ValueKey('current-home-sort'),
                                    style: sortStyle,
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
        },
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
      // Three pill borders (4.8px) plus the 10 + 8 gaps need ~23px of slack.
      if (filterWidth + sortWidth + addWidth + 24 <= constraints.maxWidth) {
        return Row(children: [
          Expanded(child: buildFilterPill(fullWidth: true)),
          const SizedBox(width: 10),
          buildSortButton(),
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
          buildSortButton(),
          buildAddButton(),
        ],
      );
    });
  }
}
