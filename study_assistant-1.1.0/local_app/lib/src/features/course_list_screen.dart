import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../models/course.dart';
import '../models/course_term_preferences.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import '../services/course_term_catalog.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_picker_sheet.dart';

class CourseListScreen extends StatefulWidget {
  const CourseListScreen({super.key, required this.store, this.clock});
  final AssignmentStore store;
  final DateTime Function()? clock;

  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> {
  final _searchController = TextEditingController();
  final Set<String> _selectedCourseKeys = <String>{};
  String? _lastAccountHash;
  bool _searching = false;
  bool _managingTerms = false;
  bool _autoPromoExpanded = false;
  bool _manualBlockedExpanded = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(CourseRef course, CourseTermEntry? entry, String q) {
    if (q.isEmpty) return true;
    if (course.name.toLowerCase().contains(q)) return true;
    if (course.clazzId.toLowerCase().contains(q)) return true;
    if ((course.clazzName ?? '').toLowerCase().contains(q)) return true;
    if (course.teacherNames.any((t) => t.toLowerCase().contains(q))) {
      return true;
    }
    if (entry != null &&
        (entry.stateLabel.toLowerCase().contains(q) ||
            (entry.term?.label.toLowerCase().contains(q) ?? false))) {
      return true;
    }
    return false;
  }

  Future<void> _pickBatchManualTerm(
    BuildContext context,
    AssignmentStore store,
    Set<String> courseKeys,
  ) async {
    if (courseKeys.isEmpty) return;
    final now = widget.clock?.call() ?? DateTime.now();
    final selectableTerms = AcademicTerm.recentSelectableTerms(now, count: 8);
    final selected = await showJournalPickerSheet<String>(
      context,
      title: '批量设置学期（${courseKeys.length} 门）',
      selectedValue: '__auto__',
      searchable: false,
      displayPrefs: store.display,
      options: [
        const JournalPickerOption<String>(
          key: ValueKey('term-option-auto'),
          value: '__auto__',
          label: '自动推断（清除手动设置）',
          icon: Icons.auto_awesome_outlined,
        ),
        for (final term in selectableTerms)
          JournalPickerOption<String>(
            key: ValueKey('term-option-${term.key}'),
            value: term.key,
            label: term.label,
            subtitle: term == AcademicTerm.fromInstant(now) ? '当前学期' : null,
            icon: Icons.calendar_today_outlined,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final saved = await store.batchUpdateCourseTerms(
      courseKeys: courseKeys,
      updateManualTerm: true,
      manualTerm:
          selected == '__auto__' ? null : AcademicTerm.tryParseKey(selected),
    );
    if (saved && mounted) {
      setState(() => _selectedCourseKeys.clear());
    }
  }

  Future<void> _pickManualTerm(
    BuildContext context,
    AssignmentStore store,
    CourseRef course,
    CourseTermEntry? entry,
  ) async {
    final now = widget.clock?.call() ?? DateTime.now();
    final selectableTerms = AcademicTerm.recentSelectableTerms(now, count: 8);
    final selected = await showJournalPickerSheet<String>(
      context,
      title: '调整学期 · ${course.name}',
      selectedValue: entry?.override.manualTermKey ?? '__auto__',
      searchable: false,
      displayPrefs: store.display,
      options: [
        const JournalPickerOption<String>(
          key: ValueKey('term-option-auto'),
          value: '__auto__',
          label: '自动推断（清除手动设置）',
          icon: Icons.auto_awesome_outlined,
        ),
        for (final term in selectableTerms)
          JournalPickerOption<String>(
            key: ValueKey('term-option-${term.key}'),
            value: term.key,
            label: term.label,
            subtitle: term == AcademicTerm.fromInstant(now) ? '当前学期' : null,
            icon: Icons.calendar_today_outlined,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    await store.setCourseManualTerm(
      course.key,
      selected == '__auto__' ? null : AcademicTerm.tryParseKey(selected),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final store = widget.store;
          if (_lastAccountHash != store.accountHash) {
            _lastAccountHash = store.accountHash;
            _selectedCourseKeys.clear();
          }
          final journal = Journal.of(context);
          final termCatalog = store.termCatalog;
          final archivableKeys = termCatalog.archivablePastCourseKeys;
          final visibleCourses = store.courses
              .where((c) => !termCatalog.isBlocked(c.key))
              .toList(growable: false);
          final visibleKeys = {for (final c in visibleCourses) c.key};
          final selectedKeys = _selectedCourseKeys.intersection(visibleKeys);
          final ungroupedKeys = [
            for (final c in visibleCourses)
              if (termCatalog.entryFor(c.key)?.isUngrouped ?? false) c.key,
          ];
          final autoPromoEntries = termCatalog.autoBlockedPromoEntries.toList()
            ..sort((a, b) => compareNaturalPinyin(a.courseName, b.courseName));
          final manualBlockedEntries = termCatalog.manuallyBlockedEntries
              .toList()
            ..sort((a, b) => compareNaturalPinyin(a.courseName, b.courseName));
          final nameCounts = <String, int>{};
          for (final c in visibleCourses) {
            final trimmed = c.name.trim();
            nameCounts[trimmed] = (nameCounts[trimmed] ?? 0) + 1;
          }
          final q = _query.trim().toLowerCase();
          final filtered = _searching
              ? visibleCourses
                  .where((c) => _matches(c, termCatalog.entryFor(c.key), q))
                  .toList(growable: false)
              : visibleCourses;

          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              title: const Text('我的课程'),
              actions: [
                if (store.courses.isNotEmpty)
                  IconButton(
                    key: const ValueKey('course-list-manage-terms'),
                    tooltip: _managingTerms ? '完成学期管理' : '管理学期与归档',
                    icon: Icon(
                      _managingTerms
                          ? Icons.done_all_rounded
                          : Icons.tune_rounded,
                    ),
                    onPressed: () {
                      setState(() {
                        _managingTerms = !_managingTerms;
                        if (!_managingTerms) {
                          _selectedCourseKeys.clear();
                        }
                      });
                    },
                  ),
                if (store.courses.isNotEmpty)
                  IconButton(
                    key: const ValueKey('course-list-search-toggle'),
                    tooltip: _searching ? '关闭搜索' : '搜索课程或教师',
                    icon: Icon(
                      _searching ? Icons.close_rounded : Icons.search_rounded,
                    ),
                    onPressed: () {
                      setState(() {
                        _searching = !_searching;
                        if (!_searching) {
                          _searchController.clear();
                          _query = '';
                        }
                      });
                    },
                  ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                Text(
                  '关注课程影响首页、日历、提醒、小组件和统计；已归档或往期课程仍可在统计与本地记录查看。',
                  style: journal.metadata,
                ),
                const SizedBox(height: 14),
                if (store.isLoading) ...[
                  JournalGroupedCard(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const LinearProgressIndicator(
                            semanticsLabel: '正在处理学习数据',
                          ),
                          const SizedBox(height: 8),
                          Text('正在处理学习数据，请稍候。', style: journal.metadata),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (store.error case final message?) ...[
                  JournalGroupedCard(
                    backgroundColor: journal.berryBg,
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text(
                        '当前提示：$message',
                        style: journal.metadata.copyWith(color: journal.berry),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (store.courses.isEmpty && !store.isLoading)
                  JournalGroupedCard(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Text('尚未读取课程，请同步后重试。', style: journal.metadata),
                    ],
                  ),
                if (!store.isLoading &&
                    (store.courses.isEmpty || store.error != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.push('/sync'),
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('查看同步状态'),
                      ),
                    ),
                  ),
                if (store.courses.isNotEmpty) ...[
                  if (_searching) ...[
                    TextField(
                      key: const ValueKey('course-list-search'),
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      style: journal.entryTitle.copyWith(fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: '搜索课程或教师...',
                        hintStyle: journal.metadata,
                        filled: true,
                        fillColor: journal.parchment,
                        isDense: true,
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: journal.muted,
                        ),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                tooltip: '清空',
                                icon: Icon(Icons.close_rounded,
                                    size: 17, color: journal.muted),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: journal.accent, width: 1.1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_managingTerms && visibleCourses.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: journal.parchment,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: journal.cardBorder,
                          width: 0.7,
                        ),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '已选 ${selectedKeys.length} 门',
                            style: journal.metadata.copyWith(
                              color: journal.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (ungroupedKeys.isNotEmpty)
                            OutlinedButton.icon(
                              key:
                                  const ValueKey('course-select-all-ungrouped'),
                              onPressed: store.isLoading
                                  ? null
                                  : () => setState(() {
                                        _selectedCourseKeys
                                            .addAll(ungroupedKeys);
                                      }),
                              icon:
                                  const Icon(Icons.checklist_rounded, size: 16),
                              label: Text(
                                '选中全部未分组（${ungroupedKeys.length}）',
                              ),
                            ),
                          if (filtered.isNotEmpty &&
                              selectedKeys.length < filtered.length)
                            TextButton(
                              key: const ValueKey('course-select-all-visible'),
                              onPressed: store.isLoading
                                  ? null
                                  : () => setState(() {
                                        for (final c in filtered) {
                                          _selectedCourseKeys.add(c.key);
                                        }
                                      }),
                              child: const Text('全选'),
                            ),
                          if (selectedKeys.isNotEmpty)
                            TextButton(
                              key: const ValueKey('course-clear-selection'),
                              onPressed: store.isLoading
                                  ? null
                                  : () => setState(_selectedCourseKeys.clear),
                              child: const Text('清空选择'),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_managingTerms && archivableKeys.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const ValueKey('course-list-batch-archive'),
                          onPressed:
                              store.isLoading ? null : store.archivePastCourses,
                          icon:
                              const Icon(Icons.inventory_2_outlined, size: 18),
                          label: Text('批量归档明确往期（${archivableKeys.length}）'),
                        ),
                      ),
                    ),
                  ],
                  if (filtered.isEmpty)
                    JournalGroupedCard(
                      padding: const EdgeInsets.all(18),
                      children: [
                        Text(
                          _searching
                              ? '没有匹配的课程或教师，请调整关键词后重试。'
                              : '暂无展示中的课程，可在下方折叠区恢复已过滤或已屏蔽课程。',
                          style: journal.metadata,
                        ),
                      ],
                    )
                  else
                    JournalGroupedCard(
                      dividerIndent: 52,
                      children: [
                        for (final course in filtered)
                          () {
                            final termEntry = termCatalog.entryFor(course.key);
                            final duplicateName =
                                (nameCounts[course.name.trim()] ?? 0) > 1;
                            final isArchived =
                                termEntry?.state == CourseCatalogState.archived;
                            final isRecalled =
                                termEntry?.state == CourseCatalogState.recalled;
                            final courseSelected =
                                selectedKeys.contains(course.key);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (_managingTerms)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: Checkbox(
                                          key: ValueKey(
                                            'course-select-${course.key}',
                                          ),
                                          value: courseSelected,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                          onChanged: store.isLoading
                                              ? null
                                              : (checked) => setState(() {
                                                    if (checked == true) {
                                                      _selectedCourseKeys
                                                          .add(course.key);
                                                    } else {
                                                      _selectedCourseKeys
                                                          .remove(course.key);
                                                    }
                                                  }),
                                        ),
                                      ),
                                    Expanded(
                                      child: SwitchListTile(
                                        contentPadding: _managingTerms
                                            ? const EdgeInsets.fromLTRB(
                                                2, 2, 12, 2)
                                            : const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 2,
                                              ),
                                        secondary:
                                            CourseMark(course.name, size: 28),
                                        title: Text(course.name,
                                            style: journal.entryTitle),
                                        subtitle: _buildCourseSubtitle(
                                          course: course,
                                          termEntry: termEntry,
                                          duplicateName: duplicateName,
                                          journal: journal,
                                        ),
                                        value: store.follows(course.key),
                                        onChanged: store.isLoading
                                            ? null
                                            : (v) => store.followCourse(
                                                course.key, v),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_managingTerms)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        56, 0, 14, 10),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        ActionChip(
                                          key: ValueKey(
                                              'course-term-btn-${course.key}'),
                                          onPressed: store.isLoading
                                              ? null
                                              : () => _pickManualTerm(
                                                    context,
                                                    store,
                                                    course,
                                                    termEntry,
                                                  ),
                                          avatar: const Icon(
                                            Icons.calendar_today_outlined,
                                            size: 15,
                                          ),
                                          label: Text(
                                            '学期：${termEntry?.term?.shortLabel ?? '未分组'}',
                                          ),
                                        ),
                                        if (termEntry?.isUngrouped ?? false)
                                          ActionChip(
                                            key: ValueKey(
                                                'course-mark-current-${course.key}'),
                                            onPressed: store.isLoading
                                                ? null
                                                : () =>
                                                    store.setCourseManualTerm(
                                                      course.key,
                                                      termCatalog.currentTerm,
                                                    ),
                                            avatar: const Icon(
                                              Icons
                                                  .check_circle_outline_rounded,
                                              size: 15,
                                            ),
                                            label: const Text('标为本学期'),
                                          ),
                                        ActionChip(
                                          key: ValueKey(
                                              'course-archive-btn-${course.key}'),
                                          onPressed: store.isLoading
                                              ? null
                                              : () =>
                                                  store.setCourseArchiveMode(
                                                    course.key,
                                                    isArchived
                                                        ? CourseArchiveMode
                                                            .restored
                                                        : CourseArchiveMode
                                                            .archived,
                                                  ),
                                          avatar: Icon(
                                            isArchived
                                                ? Icons.unarchive_outlined
                                                : Icons.archive_outlined,
                                            size: 15,
                                          ),
                                          label:
                                              Text(isArchived ? '恢复在学' : '归档'),
                                        ),
                                        ActionChip(
                                          key: ValueKey(
                                              'course-block-btn-${course.key}'),
                                          onPressed: store.isLoading
                                              ? null
                                              : () => store.setCourseBlockMode(
                                                    course.key,
                                                    CourseBlockMode.blocked,
                                                  ),
                                          avatar: const Icon(
                                            Icons.block_outlined,
                                            size: 15,
                                          ),
                                          label: const Text('屏蔽'),
                                        ),
                                        if (isRecalled)
                                          ActionChip(
                                            key: ValueKey(
                                                'course-dismiss-recall-${course.key}'),
                                            onPressed: store.isLoading
                                                ? null
                                                : () =>
                                                    store.dismissCourseRecall(
                                                        course.key),
                                            avatar: const Icon(
                                              Icons.notifications_off_outlined,
                                              size: 15,
                                            ),
                                            label: const Text('忽略召回'),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          }(),
                      ],
                    ),
                  if (autoPromoEntries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildBlockedSectionCard(
                      context: context,
                      journal: journal,
                      store: store,
                      toggleKey: const ValueKey('course-auto-promo-toggle'),
                      title: '已自动过滤的活动课（${autoPromoEntries.length}）',
                      icon: Icons.campaign_outlined,
                      expanded: _autoPromoExpanded,
                      onToggle: () => setState(
                          () => _autoPromoExpanded = !_autoPromoExpanded),
                      entries: autoPromoEntries,
                      restoreKeyBuilder: (key) =>
                          ValueKey('course-restore-promo-$key'),
                      onRestore: (entry) => store.setCourseBlockMode(
                        entry.courseKey,
                        CourseBlockMode.allowed,
                      ),
                    ),
                  ],
                  if (manualBlockedEntries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildBlockedSectionCard(
                      context: context,
                      journal: journal,
                      store: store,
                      toggleKey: const ValueKey('course-manual-blocked-toggle'),
                      title: '已手动屏蔽的课程（${manualBlockedEntries.length}）',
                      icon: Icons.visibility_off_outlined,
                      expanded: _manualBlockedExpanded,
                      onToggle: () => setState(() =>
                          _manualBlockedExpanded = !_manualBlockedExpanded),
                      entries: manualBlockedEntries,
                      restoreKeyBuilder: (key) =>
                          ValueKey('course-restore-blocked-$key'),
                      onRestore: (entry) => store.setCourseBlockMode(
                        entry.courseKey,
                        entry.isAutoPromo
                            ? CourseBlockMode.allowed
                            : CourseBlockMode.auto,
                      ),
                    ),
                  ],
                ],
              ],
            ),
            bottomNavigationBar: _managingTerms && selectedKeys.isNotEmpty
                ? Material(
                    color: journal.sheetElevated,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: journal.divider, width: 0.7),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '批量操作 · ${selectedKeys.length} 门',
                                style: journal.metadata.copyWith(
                                  color: journal.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  FilledButton.tonalIcon(
                                    key:
                                        const ValueKey('course-batch-set-term'),
                                    onPressed: store.isLoading
                                        ? null
                                        : () => _pickBatchManualTerm(
                                              context,
                                              store,
                                              selectedKeys,
                                            ),
                                    icon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('设学期'),
                                  ),
                                  OutlinedButton.icon(
                                    key: const ValueKey(
                                        'course-batch-archive-selected'),
                                    onPressed: store.isLoading
                                        ? null
                                        : () async {
                                            final saved = await store
                                                .batchUpdateCourseTerms(
                                              courseKeys: selectedKeys,
                                              archiveMode:
                                                  CourseArchiveMode.archived,
                                            );
                                            if (saved && mounted) {
                                              setState(
                                                  _selectedCourseKeys.clear);
                                            }
                                          },
                                    icon: const Icon(
                                      Icons.archive_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('归档'),
                                  ),
                                  OutlinedButton.icon(
                                    key: const ValueKey(
                                        'course-batch-block-selected'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: journal.berry,
                                      side: BorderSide(
                                        color: journal.berryBorder,
                                      ),
                                    ),
                                    onPressed: store.isLoading
                                        ? null
                                        : () async {
                                            final saved = await store
                                                .batchUpdateCourseTerms(
                                              courseKeys: selectedKeys,
                                              blockMode:
                                                  CourseBlockMode.blocked,
                                            );
                                            if (saved && mounted) {
                                              setState(
                                                  _selectedCourseKeys.clear);
                                            }
                                          },
                                    icon: const Icon(
                                      Icons.block_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('屏蔽'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          );
        },
      );

  Widget _buildBlockedSectionCard({
    required BuildContext context,
    required JournalPalette journal,
    required AssignmentStore store,
    required Key toggleKey,
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
    required List<CourseTermEntry> entries,
    required Key Function(String courseKey) restoreKeyBuilder,
    required Future<bool> Function(CourseTermEntry entry) onRestore,
  }) {
    final coursesByKey = {for (final c in store.courses) c.key: c};
    return JournalGroupedCard(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: toggleKey,
              onTap: () {
                JournalMotion.tap(store.display);
                onToggle();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: journal.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: journal.section.copyWith(fontSize: 15),
                        ),
                      ),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0.0,
                        duration: JournalMotion.duration(
                          context,
                          const Duration(milliseconds: 200),
                        ),
                        curve: JournalMotion.easeOut,
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: journal.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (JournalMotion.isReducedMotion(context))
              (expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in entries) ...[
                          Divider(
                            height: 0.6,
                            thickness: 0.6,
                            indent: 14,
                            endIndent: 14,
                            color: journal.divider,
                          ),
                          () {
                            final course = coursesByKey[entry.courseKey];
                            final teachers = course?.teacherLabel ?? '';
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 10, 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          entry.courseName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: journal.entryTitle,
                                        ),
                                        if (teachers.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            teachers,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: journal.metadata,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    key: restoreKeyBuilder(entry.courseKey),
                                    onPressed: store.isLoading
                                        ? null
                                        : () => onRestore(entry),
                                    child: const Text('恢复'),
                                  ),
                                ],
                              ),
                            );
                          }(),
                        ],
                      ],
                    )
                  : const SizedBox.shrink())
            else
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: JournalMotion.easeDrawer,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final entry in entries) ...[
                            Divider(
                              height: 0.6,
                              thickness: 0.6,
                              indent: 14,
                              endIndent: 14,
                              color: journal.divider,
                            ),
                            () {
                              final course = coursesByKey[entry.courseKey];
                              final teachers = course?.teacherLabel ?? '';
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 10, 10, 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            entry.courseName,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: journal.entryTitle,
                                          ),
                                          if (teachers.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              teachers,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: journal.metadata,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      key: restoreKeyBuilder(entry.courseKey),
                                      onPressed: store.isLoading
                                          ? null
                                          : () => onRestore(entry),
                                      child: const Text('恢复'),
                                    ),
                                  ],
                                ),
                              );
                            }(),
                          ],
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ],
    );
  }

  Widget? _buildCourseSubtitle({
    required CourseRef course,
    required CourseTermEntry? termEntry,
    required bool duplicateName,
    required JournalPalette journal,
  }) {
    final isUngrouped = termEntry?.isUngrouped ?? false;
    final showTermLabel = termEntry != null &&
        (termEntry.term != null ||
            termEntry.state != CourseCatalogState.active);
    final parts = <String>[
      if (duplicateName && course.clazzId.isNotEmpty) '班级 ${course.clazzId}',
      if (course.teacherNames.isNotEmpty) course.teacherLabel,
      if (showTermLabel)
        termEntry.stateLabel
      else if (isUngrouped)
        '未分组（未自动归入本学期）',
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: journal.metadata,
    );
  }
}
