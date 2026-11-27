import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../models/home_filters.dart';
import '../../services/assignment_store.dart';
import '../../services/home_course_filter.dart';
import '../../services/interaction_feedback_service.dart';
import 'home_action_bar.dart';
import 'home_course_filter_row.dart';
import 'journal_buttons.dart';
import 'journal_grouped_card.dart';
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
  required List<HomeCourseFilterOption> courseOptions,
  required Map<String, int> Function(
          AssignmentTypeFilter, AssignmentDeadlineFilter)
      courseCountsFor,
}) {
  InteractionFeedback.trigger(store.display);
  return showJournalModalSheet<HomeFilterSelection>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _HomeFilterSheetBody(
      store: store,
      initialFilters: initialFilters,
      courseOptions: courseOptions,
      courseCountsFor: courseCountsFor,
    ),
  );
}

class _HomeFilterSheetBody extends StatefulWidget {
  const _HomeFilterSheetBody({
    required this.store,
    required this.initialFilters,
    required this.courseOptions,
    required this.courseCountsFor,
  });

  final AssignmentStore store;
  final HomeFilters initialFilters;
  final List<HomeCourseFilterOption> courseOptions;
  final Map<String, int> Function(
      AssignmentTypeFilter, AssignmentDeadlineFilter) courseCountsFor;

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
    _courseKey = widget.initialFilters.courseKey;
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

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final courseOptions = widget.courseOptions;
    final journal = Journal.of(context);
    final selectedCourseLabel = _courseKey == null
        ? '全部课程'
        : courseOptions
                .where((o) => o.courseKey == _courseKey)
                .firstOrNull
                ?.label ??
            '全部课程';
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: JournalSheetRubberBand(
        fillColor: journal.sheetElevated,
        builder: (context, wrapGrabArea) => Container(
          decoration: BoxDecoration(
            color: journal.sheetElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                wrapGrabArea(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        key: const ValueKey('home-filter-drag-handle'),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: journal.ruleStrong,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('搜索、筛选与排序', style: journal.section),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  autofocus: widget.initialFilters.query.isNotEmpty,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: '搜索作业、任务、考试或课程',
                    prefixIcon: Icon(Icons.search_rounded),
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
                        onSelected: (_) => setState(() => _type = option),
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
                    for (final filter in homeDeadlineFilterChoices)
                      ChoiceChip(
                        key: ValueKey('deadline-${filter.name}'),
                        selected: _deadline == filter,
                        onSelected: (_) => setState(() => _deadline = filter),
                        label: Text(homeDeadlineFilterLabel(filter)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                HomeCourseFilterRow(
                  key: const ValueKey('home-course-filter'),
                  tapKey: ValueKey(
                      'course-${store.accountEpoch}-${_courseKey ?? "all"}'),
                  value: selectedCourseLabel,
                  selected: _courseKey != null,
                  onClear: () => setState(() => _courseKey = null),
                  onTap: () async {
                    final counts = widget.courseCountsFor(_type, _deadline);
                    final ordered =
                        sortHomeCourseOptionsByCount(courseOptions, counts);
                    final picked = await showJournalPickerSheet<String>(
                      context,
                      title: '课程筛选',
                      selectedValue: _courseKey ?? '',
                      searchable: courseOptions.length > 5 ||
                          courseOptions.any((o) => o.teacherNames.isNotEmpty),
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
                      filterPredicate: (option, filterId) {
                        if (option.value.isEmpty) return true;
                        return store.termCatalog.matchesHomeCoursePicker(
                          option.value,
                          filterId,
                          hasVisibleItems: (counts[option.value] ?? 0) > 0,
                        );
                      },
                      filterNoticeBuilder: (filterId, filtered) =>
                          filterId == 'currentTerm' &&
                                  filtered.every((o) => o.value.isEmpty) &&
                                  courseOptions.isNotEmpty
                              ? '本学期暂未识别出课程，可切换到「本学年」或「全部学期」查看'
                              : null,
                      options: [
                        const JournalPickerOption<String>(
                          value: '',
                          label: '全部课程',
                        ),
                        for (final option in ordered)
                          JournalPickerOption<String>(
                            key: ValueKey('course-option-${option.courseKey}'),
                            value: option.courseKey,
                            label: option.name,
                            subtitle: option.subtitle,
                            keywords: option.searchKeywords,
                            icon: courseIconFor(option.name),
                            trailingText: homeCourseCountLabel(
                                counts[option.courseKey] ?? 0),
                          ),
                      ],
                    );
                    if (picked != null && mounted) {
                      setState(() => _courseKey = picked == '' ? null : picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text('排序', style: journal.dayHeading),
                const SizedBox(height: 8),
                JournalGroupedCard(
                  children: [
                    RadioGroup<HomeSortOrder>(
                      groupValue: _sortOrder,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _sortOrder = value);
                        }
                      },
                      child: Column(
                        children: [
                          for (final order in homeSortOrderChoices)
                            RadioListTile<HomeSortOrder>(
                              key: ValueKey('sort-${order.name}'),
                              value: order,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              dense: true,
                              title: Text(
                                homeSortOrderLabel(order),
                                style:
                                    journal.entryTitle.copyWith(fontSize: 14.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _query = '';
                        _courseKey = null;
                        _deadline = AssignmentDeadlineFilter.all;
                        _type = AssignmentTypeFilter.all;
                        _controller.clear();
                      }),
                      child: const Text('清空筛选'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        HomeFilterSelection(
                          query: _query,
                          courseKey: _courseKey,
                          deadline: _deadline,
                          type: _type,
                          sortOrder: _sortOrder,
                        ),
                      ),
                      style: FilledButton.styleFrom(enableFeedback: false),
                      child: const Text('应用'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
    required this.options,
    required this.onClearQuery,
    required this.onClearType,
    required this.onClearDeadline,
    required this.onClearCourse,
    required this.onResetAll,
  });

  final String query;
  final AssignmentTypeFilter typeFilter;
  final AssignmentDeadlineFilter deadlineFilter;
  final String? courseKey;
  final List<HomeCourseFilterOption> options;
  final VoidCallback onClearQuery;
  final VoidCallback onClearType;
  final VoidCallback onClearDeadline;
  final VoidCallback onClearCourse;
  final VoidCallback onResetAll;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);

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
                          horizontal: 11, vertical: 4),
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
      spacing: 8,
      runSpacing: 6,
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
            child: const Text('重置条件'),
          ),
        ),
      ],
    );
  }
}
