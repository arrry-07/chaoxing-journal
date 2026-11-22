import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../models/assignment.dart';
import '../services/assignment_grouping.dart';
import '../services/assignment_query.dart';
import '../services/assignment_statistics.dart';
import '../services/assignment_store.dart';
import '../services/exam_schedule_presentation.dart';
import '../services/local_record_query.dart';
import 'widgets/assignment_card.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_picker_sheet.dart';
import 'widgets/journal_sliver_grouped_card.dart';

class LocalRecordsScreen extends StatefulWidget {
  const LocalRecordsScreen({
    super.key,
    required this.store,
    this.initialFilter = const LocalRecordFilterSpec(),
    this.clock,
  });

  final AssignmentStore store;
  final LocalRecordFilterSpec initialFilter;
  final DateTime Function()? clock;

  @override
  State<LocalRecordsScreen> createState() => _LocalRecordsScreenState();
}

class _LocalRecordsScreenState extends State<LocalRecordsScreen> {
  late LocalRecordFilterSpec _spec;
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  Timer? _clock;
  late DateTime _now;
  String? _accountHash;
  int _accountEpoch = 0;

  @override
  void initState() {
    super.initState();
    _spec = widget.initialFilter;
    _searchController = TextEditingController(text: _spec.query);
    _now = widget.clock?.call() ?? DateTime.now();
    _accountHash = widget.store.accountHash;
    _accountEpoch = widget.store.accountEpoch;
    widget.store.addListener(_handleIdentityChanged);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = widget.clock?.call() ?? DateTime.now());
      }
    });
  }

  void _handleIdentityChanged() {
    final nextHash = widget.store.accountHash;
    final nextEpoch = widget.store.accountEpoch;
    if (nextHash == _accountHash && nextEpoch == _accountEpoch) return;
    _accountHash = nextHash;
    _accountEpoch = nextEpoch;
    if (!mounted) return;
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _spec = const LocalRecordFilterSpec());
  }

  @override
  void didUpdateWidget(covariant LocalRecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final storeChanged = !identical(oldWidget.store, widget.store);
    if (storeChanged) {
      oldWidget.store.removeListener(_handleIdentityChanged);
      _accountHash = widget.store.accountHash;
      _accountEpoch = widget.store.accountEpoch;
      widget.store.addListener(_handleIdentityChanged);
    }
    final oldInit = oldWidget.initialFilter;
    final nextInit = widget.initialFilter;
    final filterChanged = oldInit.from != nextInit.from ||
        oldInit.category != nextInit.category ||
        oldInit.status != nextInit.status ||
        oldInit.scope != nextInit.scope ||
        oldInit.courseKey != nextInit.courseKey ||
        oldInit.timeRange != nextInit.timeRange ||
        oldInit.query != nextInit.query ||
        oldInit.sort != nextInit.sort;
    if (filterChanged) _spec = nextInit;
    if (storeChanged || filterChanged) {
      _searchDebounce?.cancel();
      if (_searchController.text != _spec.query) {
        _searchController.text = _spec.query;
      }
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleIdentityChanged);
    _clock?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query == _spec.query) return;
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      setState(() => _spec = _spec.copyWith(query: query));
    });
  }

  void _clearSearch({bool resetFilters = false}) {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _spec =
          resetFilters ? _spec.resetToAllLocal() : _spec.copyWith(query: '');
    });
  }

  void _handleBack(BuildContext context) {
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(_spec.from == 'stats' ? '/stats' : '/profile/records');
      }
    }
  }

  void _openDetail(BuildContext context, String assignmentId) {
    GoRouter.maybeOf(context)
        ?.push('/assignments/${Uri.encodeComponent(assignmentId)}');
  }

  String _businessTimeText(Assignment primary, List<Assignment> sources) {
    if (primary.isExam) {
      final projected =
          AssignmentQuery.projectDisplay(sources).firstOrNull ?? primary;
      final schedule =
          ExamSchedulePresentation.build(projected, records: sources);
      if (schedule.detailTimeLines.isNotEmpty) {
        return schedule.detailTimeLines.join(' · ');
      }
      if (projected.exam?.startAt != null && !projected.exam!.startTrusted) {
        return '开考（未核实） ${DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(projected.exam!.startAt!))}';
      }
      return '考试时间待确认';
    }
    final resolved = AssignmentQuery.effectiveDeadline(
      primary,
      coursework: widget.store.courseworkState,
    );
    if (resolved != null && resolved.isManual) {
      final formatted = DateFormat('yyyy年M月d日 HH:mm')
          .format(AssignmentQuery.beijing(resolved.at));
      return '手动截止 $formatted（官方待确认）';
    }
    final deadline = primary.deadlineAt;
    if (deadline == null) {
      return primary.deadlineLabel;
    }
    final formatted =
        DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(deadline));
    if (primary.deadlineReadFailed) {
      return '历史截止 $formatted（上次读取）';
    }
    if (!primary.deadlineTrusted) {
      return '截止 $formatted（待确认）';
    }
    return '截止 $formatted';
  }

  ({String label, Color bg, Color fg}) _statusBadge(
    Assignment primary,
    DateTime now,
  ) {
    final journal = Journal.of(context);
    final bucket = AssignmentStatistics.classify(primary, now);
    final label = primary.isExam
        ? AssignmentCard.examStateLabel(primary, now)
        : switch (bucket) {
            AssignmentStatBucket.expired => '已逾期',
            AssignmentStatBucket.completed ||
            AssignmentStatBucket.pending ||
            AssignmentStatBucket.unknown =>
              primary.statusLabel,
          };
    return switch (bucket) {
      AssignmentStatBucket.completed => (
          label: label,
          bg: journal.sage,
          fg: journal.ink,
        ),
      AssignmentStatBucket.expired => (
          label: label,
          bg: journal.berryBg,
          fg: journal.berry,
        ),
      AssignmentStatBucket.pending => (
          label: label,
          bg: journal.parchment,
          fg: journal.ink,
        ),
      AssignmentStatBucket.unknown => (
          label: label,
          bg: journal.parchment,
          fg: journal.muted,
        ),
    };
  }

  Widget _pill(String text, {required Color bg, required Color fg}) {
    final journal = Journal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
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

  String _scopeBannerSummary(Map<String, String> courseLabels) {
    final parts = <String>[
      if (_spec.scope != LocalRecordScopeFilter.allLocal) _spec.scope.label,
      if (_spec.timeRange != StatsTimeRange.all) _spec.timeRange.label,
      if (_spec.status != LocalRecordStatusFilter.all) _spec.status.label,
      if (_spec.courseKey != null)
        courseLabels[_spec.courseKey] ?? _spec.courseKey!,
    ];
    if (parts.isEmpty) {
      return '当前从课业统计进入明细视图';
    }
    return '当前统计筛选：${parts.join(' · ')}';
  }

  String _sourceLabel(AssignmentSource source) => switch (source) {
        AssignmentSource.courseWork => '正式作业',
        AssignmentSource.classroomActivity => '课堂活动',
        AssignmentSource.exam => '考试与通知',
        AssignmentSource.manual => '手动安排',
        AssignmentSource.legacyUnknown => '历史来源',
      };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final journal = Journal.of(context);
          final now = _now;
          final result = LocalRecordQuery.query(widget.store, _spec, now);
          final courseLabels = {
            for (final option in result.courseOptions)
              option.courseKey: option.label,
          };
          final selectedCourseKey = courseLabels.containsKey(_spec.courseKey)
              ? _spec.courseKey
              : null;
          final selectedCourseLabel = courseLabels[selectedCourseKey] ?? '全部课程';
          final duplicateCourseNames = <String>{
            for (final opt in result.courseOptions)
              if (opt.label.contains(' · 班级 '))
                opt.label.split(' · 班级 ').first.trim(),
          };

          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in LocalRecordCategory.values) ...[
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(category.label),
                        selected: _spec.category == category,
                        onSelected: (_) => setState(
                          () => _spec = _spec.copyWith(category: category),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_spec.category == LocalRecordCategory.coursework &&
                  _spec.isStatsScoped) ...[
                JournalGroupedCard(
                  backgroundColor: Color.lerp(
                    journal.sheet,
                    journal.sage,
                    journal.isDark ? 0.28 : 0.36,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _scopeBannerSummary(courseLabels),
                          style: journal.metadata.copyWith(color: journal.ink),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _clearSearch(resetFilters: true),
                          icon: const Icon(Icons.restart_alt_rounded, size: 16),
                          label: const Text('查看全部本机记录'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, _) => TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          hintText: '搜索标题或课程',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 19),
                          suffixIcon: value.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  icon:
                                      const Icon(Icons.close_rounded, size: 18),
                                  onPressed: _clearSearch,
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (_spec.category == LocalRecordCategory.coursework) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 146),
                      child: JournalFilterPill(
                        key: ValueKey(
                          'records-course-${selectedCourseKey ?? 'all'}-${_spec.scope.name}-${result.courseOptions.length}',
                        ),
                        label: selectedCourseLabel,
                        active: selectedCourseKey != null,
                        onTap: () async {
                          final picked = await showJournalPickerSheet<String>(
                            context,
                            title: '按课程筛选',
                            selectedValue: selectedCourseKey ?? '',
                            searchable: result.courseOptions.length > 5,
                            searchHint: '搜索课程名称...',
                            displayPrefs: widget.store.display,
                            options: [
                              const JournalPickerOption(
                                value: '',
                                label: '全部课程',
                              ),
                              for (final option in result.courseOptions)
                                JournalPickerOption(
                                  value: option.courseKey,
                                  label: option.label,
                                  icon: courseIconFor(option.label),
                                ),
                            ],
                          );
                          if (picked == null || !mounted) return;
                          setState(
                            () => picked.isEmpty
                                ? _spec = _spec.copyWith(clearCourseKey: true)
                                : _spec = _spec.copyWith(courseKey: picked),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
              if (_spec.category == LocalRecordCategory.coursework) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final status in LocalRecordStatusFilter.values) ...[
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: Text(status.label),
                          selected: _spec.status == status,
                          onSelected: (_) => setState(
                            () => _spec = _spec.copyWith(status: status),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  '${result.count} 条记录',
                  style: journal.metadata,
                ),
              ),
              const SizedBox(height: 8),
              if (result.count == 0)
                JournalGroupedCard(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          switch (_spec.category) {
                            LocalRecordCategory.hidden => '暂无隐藏作业',
                            LocalRecordCategory.otherSources => '暂无历史与其他来源记录',
                            LocalRecordCategory.coursework =>
                              _spec.isStatsScoped ||
                                      _spec.query.isNotEmpty ||
                                      _spec.status !=
                                          LocalRecordStatusFilter.all ||
                                      _spec.courseKey != null
                                  ? '当前筛选条件下没有课业记录'
                                  : '本机暂未保存课业记录',
                          },
                          style: journal.entryTitle,
                        ),
                        if (_spec.category == LocalRecordCategory.coursework &&
                            !_spec.isStatsScoped &&
                            (_spec.query.isNotEmpty ||
                                _spec.status != LocalRecordStatusFilter.all ||
                                _spec.courseKey != null)) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => _clearSearch(resetFilters: true),
                            child: const Text('查看全部本机记录'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
            ],
          );

          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              leading: IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => _handleBack(context),
              ),
              title: const Text('本地记录'),
              actions: [
                IconButton(
                  tooltip: '排序方式',
                  icon: const Icon(Icons.swap_vert_rounded),
                  onPressed: () async {
                    final picked =
                        await showJournalPickerSheet<LocalRecordSortOrder>(
                      context,
                      title: '排序方式',
                      selectedValue: _spec.sort,
                      searchable: false,
                      displayPrefs: widget.store.display,
                      options: [
                        for (final option in LocalRecordSortOrder.values)
                          JournalPickerOption(
                            value: option,
                            label: option.label,
                          ),
                      ],
                    );
                    if (picked != null && mounted) {
                      setState(() => _spec = _spec.copyWith(sort: picked));
                    }
                  },
                ),
              ],
            ),
            body: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(child: header),
                      if (result.otherSources.isNotEmpty)
                        JournalSliverGroupedCard(
                          dividerIndent: 52,
                          itemCount: result.otherSources.length,
                          itemBuilder: (context, index) => _buildOtherSourceRow(
                            context,
                            result.otherSources[index],
                            now,
                            journal,
                          ),
                        )
                      else if (result.groups.isNotEmpty)
                        JournalSliverGroupedCard(
                          dividerIndent: 52,
                          itemCount: result.groups.length,
                          itemBuilder: (context, index) => _buildGroupRow(
                            context,
                            result.groups[index],
                            now,
                            journal,
                            duplicateCourseNames: duplicateCourseNames,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildOtherSourceRow(
    BuildContext context,
    Assignment a,
    DateTime now,
    JournalPalette journal,
  ) {
    final badge = _statusBadge(a, now);
    final title = a.title.trim().isNotEmpty ? a.title.trim() : a.courseName;
    return InkWell(
      onTap: () => _openDetail(context, a.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CourseMark(a.courseName, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: journal.entryTitle),
                  if (a.courseName.trim().isNotEmpty &&
                      a.title.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${a.courseName.trim()} · ${_sourceLabel(a.source)}',
                      style: journal.metadata,
                    ),
                  ],
                  const SizedBox(height: 6),
                  _pill(badge.label, bg: badge.bg, fg: badge.fg),
                ],
              ),
            ),
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

  Widget _buildGroupRow(
    BuildContext context,
    CourseworkGroup group,
    DateTime now,
    JournalPalette journal, {
    required Set<String> duplicateCourseNames,
  }) {
    final primary = group.primary;
    final badge = _statusBadge(primary, now);
    final title = primary.title.trim().isNotEmpty
        ? primary.title.trim()
        : primary.courseName;
    final timeText = _businessTimeText(primary, group.sources);
    final isHiddenTab = _spec.category == LocalRecordCategory.hidden;
    final courseName = primary.courseName.trim();
    final showClass = duplicateCourseNames.contains(courseName) &&
        primary.clazzId != null &&
        primary.clazzId!.isNotEmpty;

    return InkWell(
      onTap: () => _openDetail(context, primary.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CourseMark(primary.courseName, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: journal.entryTitle),
                  if (courseName.isNotEmpty &&
                      primary.title.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      showClass
                          ? '$courseName · 班级 ${primary.clazzId}'
                          : courseName,
                      style: journal.metadata,
                    ),
                  ],
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (group.hidden)
                        _pill('已隐藏', bg: journal.parchment, fg: journal.muted),
                      _pill(badge.label, bg: badge.bg, fg: badge.fg),
                      if (primary.isExam || group.sources.length > 1)
                        _pill(
                          '${primary.isExam ? '考试' : _sourceLabel(primary.source)}${group.sources.length > 1 ? ' · ${group.sources.length} 条来源' : ''}',
                          bg: journal.parchment,
                          fg: journal.muted,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(timeText, style: journal.metadata),
                ],
              ),
            ),
            if (isHiddenTab) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.store.isLoading
                    ? null
                    : () => widget.store.setCourseworkGroupHidden(group, false),
                child: const Text('恢复'),
              ),
            ] else
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
