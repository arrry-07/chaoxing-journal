import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../models/home_filters.dart';
import '../../services/assignment_store.dart';
import '../../services/home_course_filter.dart';
import '../../services/interaction_feedback_service.dart';
import 'home_action_bar.dart';
import 'home_course_filter_row.dart';
import 'home_timeline_list.dart';
import 'journal_buttons.dart';
import 'journal_modal_sheet.dart';
import 'journal_picker_sheet.dart';

class HomeFilterSelection {
  const HomeFilterSelection({
    required this.query,
    required this.courseKey,
    required this.deadline,
    required this.type,
    required this.sortOrder,
  });

  final String query;
  final String? courseKey;
  final AssignmentDeadlineFilter deadline;
  final AssignmentTypeFilter type;
  final HomeSortOrder sortOrder;
}

Future<HomeFilterSelection?> showHomeFilterSheet({
  required BuildContext context,
  required AssignmentStore store,
  required HomeFilters initialFilters,
  DateTime Function()? clock,
}) {
  InteractionFeedback.trigger(store.display);
  return showJournalModalSheet<HomeFilterSelection>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _HomeFilterSheetBody(
      store: store,
      initialFilters: initialFilters,
      clock: clock,
    ),
  );
}

class _HomeFilterSheetBody extends StatefulWidget {
  const _HomeFilterSheetBody({
    required this.store,
    required this.initialFilters,
    this.clock,
  });

  final AssignmentStore store;
  final HomeFilters initialFilters;
  final DateTime Function()? clock;

  @override
  State<_HomeFilterSheetBody> createState() => _HomeFilterSheetBodyState();
}

class _HomeFilterSheetBodyState extends State<_HomeFilterSheetBody> {
  late final TextEditingController _controller;
  late String _query;
  String? _courseKey;
  late AssignmentDeadlineFilter _deadline;
  late AssignmentTypeFilter _type;
  late HomeSortOrder _sortOrder;

  @override
  void initState() {
    super.initState();
    _query = widget.initialFilters.query;
    final rawCourseKey = widget.initialFilters.courseKey;
    _courseKey =
        rawCourseKey != null && widget.store.termCatalog.isBlocked(rawCourseKey)
            ? null
            : rawCourseKey;
    _deadline = widget.initialFilters.deadline;
    _type = normalizedHomeType(widget.initialFilters.type);
    _sortOrder = normalizedHomeSort(widget.initialFilters.sortOrder);
    _controller = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _effectiveCourseKey(AssignmentStore store) {
    final key = _courseKey;
    if (key != null && store.termCatalog.isBlocked(key)) return null;
    return key;
  }

  HomeCoursePickerProjection _coursePickerProjection(AssignmentStore store) =>
      computeHomeCoursePickerProjection(
        store: store,
        now: widget.clock?.call() ?? DateTime.now(),
        selectedCourseKey: _effectiveCourseKey(store),
      );

  bool get _hasActiveFilters =>
      _query.trim().isNotEmpty ||
      _courseKey != null ||
      _deadline != AssignmentDeadlineFilter.all ||
      _type != AssignmentTypeFilter.all;

  void _clearConditions() {
    setState(() {
      _query = '';
      _courseKey = null;
      _deadline = AssignmentDeadlineFilter.all;
      _type = AssignmentTypeFilter.all;
      _controller.clear();
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      HomeFilterSelection(
        query: _query,
        courseKey: _effectiveCourseKey(widget.store),
        deadline: _deadline,
        type: _type,
        sortOrder: _sortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final journal = Journal.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final effectiveCourseKey = _effectiveCourseKey(store);
        final courseOptions = _coursePickerProjection(store).options;
        final selectedCourseLabel = effectiveCourseKey == null
            ? '全部课程'
            : courseOptions
                    .where((o) => o.courseKey == effectiveCourseKey)
                    .firstOrNull
                    ?.label ??
                '全部课程';
        final hasActiveFilters = _hasActiveFilters;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: JournalSheetRubberBand(
            fillColor: journal.sheetElevated,
            builder: (context, wrapGrabArea) => LayoutBuilder(
              builder: (context, outerConstraints) {
                final availableHeight = outerConstraints.hasBoundedHeight
                    ? outerConstraints.maxHeight
                    : screenHeight - bottomInset;
                final maxHeight =
                    math.min(screenHeight * 0.86, availableHeight);
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Container(
                    decoration: BoxDecoration(
                      color: journal.sheetElevated,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        wrapGrabArea(
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  key:
                                      const ValueKey('home-filter-drag-handle'),
                                  child: Container(
                                    width: 36,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: journal.ruleStrong,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '搜索与筛选',
                                        style: journal.section,
                                      ),
                                    ),
                                    TextButton(
                                      key: const ValueKey(
                                          'home-filter-sheet-clear'),
                                      onPressed: hasActiveFilters
                                          ? _clearConditions
                                          : null,
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(48, 48),
                                        foregroundColor: journal.accent,
                                        disabledForegroundColor: journal.subtle,
                                      ),
                                      child: const Text('清空条件'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _controller,
                                  autofocus:
                                      widget.initialFilters.query.isNotEmpty,
                                  onChanged: (value) =>
                                      setState(() => _query = value),
                                  onSubmitted: (_) => _apply(),
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    hintText: '搜索课业或课程',
                                    prefixIcon:
                                        const Icon(Icons.search_rounded),
                                    suffixIcon: _query.isNotEmpty
                                        ? IconButton(
                                            key: const ValueKey(
                                                'home-filter-clear-query'),
                                            tooltip: '清空关键词',
                                            onPressed: () {
                                              _controller.clear();
                                              setState(() => _query = '');
                                            },
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text('类型', style: journal.dayHeading),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final option in homeTypeFilterChoices)
                                      ChoiceChip(
                                        key: ValueKey('type-${option.name}'),
                                        selected: _type == option,
                                        onSelected: (_) =>
                                            setState(() => _type = option),
                                        label: Text(option.label),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text('期限', style: journal.dayHeading),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final filter
                                        in homeDeadlineFilterChoices)
                                      ChoiceChip(
                                        key:
                                            ValueKey('deadline-${filter.name}'),
                                        selected: _deadline == filter,
                                        onSelected: (_) =>
                                            setState(() => _deadline = filter),
                                        label: Text(
                                            homeDeadlineFilterLabel(filter)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                HomeCourseFilterRow(
                                  key: const ValueKey('home-course-filter'),
                                  tapKey: ValueKey(
                                      'course-${store.accountEpoch}-${effectiveCourseKey ?? "all"}'),
                                  value: selectedCourseLabel,
                                  selected: effectiveCourseKey != null,
                                  onClear: () =>
                                      setState(() => _courseKey = null),
                                  onTap: () async {
                                    final initialOptions =
                                        _coursePickerProjection(store).options;
                                    JournalPickerLiveSnapshot<String>
                                        buildCoursePickerSnapshot() {
                                      final projection =
                                          _coursePickerProjection(store);
                                      final liveCourseOptions =
                                          projection.options;
                                      final counts = projection.countsFor(
                                          _query, _type, _deadline);
                                      final ordered =
                                          sortHomeCourseOptionsByCount(
                                        liveCourseOptions,
                                        counts,
                                      );
                                      return JournalPickerLiveSnapshot<String>(
                                        options: [
                                          const JournalPickerOption<String>(
                                            value: '',
                                            label: '全部课程',
                                          ),
                                          for (final option in ordered)
                                            JournalPickerOption<String>(
                                              key: ValueKey(
                                                  'course-option-${option.courseKey}'),
                                              value: option.courseKey,
                                              label: option.name,
                                              subtitle: option.subtitle,
                                              keywords: option.searchKeywords,
                                              icon: courseIconFor(option.name),
                                              trailingText:
                                                  homeCourseCountLabel(counts[
                                                          option.courseKey] ??
                                                      0),
                                            ),
                                        ],
                                        filterPredicate: (option, filterId) {
                                          if (option.value.isEmpty) return true;
                                          return store.termCatalog
                                              .matchesHomeCoursePicker(
                                            option.value,
                                            filterId,
                                            hasVisibleItems:
                                                (counts[option.value] ?? 0) > 0,
                                          );
                                        },
                                        filterNoticeBuilder: (filterId,
                                                filtered) =>
                                            filterId == 'currentTerm' &&
                                                    filtered.every((o) =>
                                                        o.value.isEmpty) &&
                                                    liveCourseOptions.isNotEmpty
                                                ? '本学期暂未识别出课程，可切换到「本学年」或「全部学期」查看'
                                                : null,
                                      );
                                    }

                                    final picked =
                                        await showJournalPickerSheet<String>(
                                      context,
                                      title: '课程筛选',
                                      selectedValue: effectiveCourseKey ?? '',
                                      searchable: initialOptions.length > 5 ||
                                          initialOptions.any(
                                              (o) => o.teacherNames.isNotEmpty),
                                      searchHint: '搜索课程或教师...',
                                      displayPrefs: store.display,
                                      filterOptions: const [
                                        JournalPickerFilterOption(
                                          id: 'currentTerm',
                                          label: '本学期',
                                        ),
                                        JournalPickerFilterOption(
                                          id: 'currentAcademicYear',
                                          label: '本学年',
                                        ),
                                        JournalPickerFilterOption(
                                          id: 'pastTerms',
                                          label: '往期',
                                        ),
                                        JournalPickerFilterOption(
                                          id: 'allTerms',
                                          label: '全部学期',
                                        ),
                                      ],
                                      initialFilterId: 'currentTerm',
                                      refreshListenable: store,
                                      liveBuilder: buildCoursePickerSnapshot,
                                    );
                                    if (picked != null && mounted) {
                                      setState(() => _courseKey =
                                          picked == '' ? null : picked);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                Text('排序', style: journal.dayHeading),
                                const SizedBox(height: 4),
                                Text(
                                  '作业按截止、考试按开考，逾期始终置底',
                                  style: journal.metadata.copyWith(
                                    color: journal.subtle,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final order in homeSortOrderChoices)
                                      ChoiceChip(
                                        key: ValueKey('sort-${order.name}'),
                                        selected: _sortOrder == order,
                                        onSelected: (_) =>
                                            setState(() => _sortOrder = order),
                                        label: Text(homeShortSortLabel(order)),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: journal.sheetElevated,
                            border: Border(
                              top: BorderSide(
                                color: journal.divider,
                                width: 0.8,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                          child: SafeArea(
                            top: false,
                            left: false,
                            right: false,
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                    ),
                                    child: const Text('取消'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: FilledButton(
                                    onPressed: _apply,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      enableFeedback: false,
                                    ),
                                    child: const Text('应用'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class ActiveFilterSummaryBar extends StatelessWidget {
  const ActiveFilterSummaryBar({
    super.key,
    required this.query,
    required this.typeFilter,
    required this.deadlineFilter,
    required this.courseKey,
    this.sortOrder = HomeSortOrder.deadlineAsc,
    required this.options,
    required this.onClearQuery,
    required this.onClearType,
    required this.onClearDeadline,
    required this.onClearCourse,
    this.onResetSort,
    required this.onResetAll,
  });

  final String query;
  final AssignmentTypeFilter typeFilter;
  final AssignmentDeadlineFilter deadlineFilter;
  final String? courseKey;
  final HomeSortOrder sortOrder;
  final List<HomeCourseFilterOption> options;
  final VoidCallback onClearQuery;
  final VoidCallback onClearType;
  final VoidCallback onClearDeadline;
  final VoidCallback onClearCourse;
  final VoidCallback? onResetSort;
  final VoidCallback onResetAll;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final hasFilterChips = query.trim().isNotEmpty ||
        typeFilter != AssignmentTypeFilter.all ||
        deadlineFilter != AssignmentDeadlineFilter.all ||
        courseKey != null;
    final hasSortChip = sortOrder != HomeSortOrder.deadlineAsc;

    Widget removableTag(String text, VoidCallback onRemove) => Semantics(
          container: true,
          button: true,
          label: '移除筛选：$text',
          onTap: onRemove,
          excludeSemantics: true,
          child: JournalPressableScale(
            pressScale: 0.97,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onRemove,
                enableFeedback: false,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: journal.sage,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: journal.metadata.copyWith(
                                fontSize: 12,
                                color: journal.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.close_rounded,
                              size: 14, color: journal.ink),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (query.trim().isNotEmpty)
          removableTag('关键词：${query.trim()}', onClearQuery),
        if (typeFilter != AssignmentTypeFilter.all)
          removableTag('类型：${typeFilter.label}', onClearType),
        if (deadlineFilter != AssignmentDeadlineFilter.all)
          removableTag(
              '期限：${homeDeadlineFilterLabel(deadlineFilter)}', onClearDeadline),
        if (courseKey != null)
          removableTag(
            '课程：${options.where((option) => option.courseKey == courseKey).firstOrNull?.label ?? "已选课程"}',
            onClearCourse,
          ),
        if (hasSortChip)
          removableTag(
            '排序：${homeShortSortLabel(sortOrder)}',
            onResetSort ?? () {},
          ),
        if (hasFilterChips)
          JournalPressableScale(
            pressScale: 0.97,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                enableFeedback: false,
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
                foregroundColor: journal.muted,
              ),
              onPressed: onResetAll,
              child: const Text('清空条件'),
            ),
          ),
      ],
    );
  }
}
