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
    setState(() {
      _searchController.clear();
      _spec = const LocalRecordFilterSpec();
    });
  }

  @override
  void didUpdateWidget(covariant LocalRecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_handleIdentityChanged);
      _accountHash = widget.store.accountHash;
      _accountEpoch = widget.store.accountEpoch;
      widget.store.addListener(_handleIdentityChanged);
    }
    final oldInit = oldWidget.initialFilter;
    final nextInit = widget.initialFilter;
    if (oldInit.from != nextInit.from ||
        oldInit.category != nextInit.category ||
        oldInit.status != nextInit.status ||
        oldInit.scope != nextInit.scope ||
        oldInit.courseKey != nextInit.courseKey ||
        oldInit.timeRange != nextInit.timeRange ||
        oldInit.query != nextInit.query ||
        oldInit.sort != nextInit.sort) {
      _spec = nextInit;
      if (_searchController.text != nextInit.query) {
        _searchController.text = nextInit.query;
      }
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleIdentityChanged);
    _clock?.cancel();
    _searchController.dispose();
    super.dispose();
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
    final bucket = AssignmentStatistics.classify(primary, now);
    final label = switch (bucket) {
      AssignmentStatBucket.expired => '已逾期',
      AssignmentStatBucket.completed => primary.isExam
          ? AssignmentCard.examStateLabel(primary, now)
          : primary.statusLabel,
      AssignmentStatBucket.pending => primary.isExam
          ? AssignmentCard.examStateLabel(primary, now)
          : primary.statusLabel,
      AssignmentStatBucket.unknown => primary.isExam
          ? AssignmentCard.examStateLabel(primary, now)
          : primary.statusLabel,
    };
    return switch (bucket) {
      AssignmentStatBucket.completed => (
          label: label,
          bg: Journal.sage,
          fg: Journal.ink,
        ),
      AssignmentStatBucket.expired => (
          label: label,
          bg: Journal.berry.withValues(alpha: 0.12),
          fg: Journal.berry,
        ),
      AssignmentStatBucket.pending => (
          label: label,
          bg: Journal.paper,
          fg: Journal.ink,
        ),
      AssignmentStatBucket.unknown => (
          label: label,
          bg: Journal.paper,
          fg: Journal.muted,
        ),
    };
  }

  Widget _pill(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Journal.rule),
      ),
      child: Text(
        text,
        style: Journal.metadata.copyWith(
          fontSize: 12,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _scopeBannerSummary(LocalRecordQueryResult result) {
    final parts = <String>[
      if (_spec.scope != LocalRecordScopeFilter.allLocal) _spec.scope.label,
      if (_spec.timeRange != StatsTimeRange.all) _spec.timeRange.label,
      if (_spec.status != LocalRecordStatusFilter.all) _spec.status.label,
      if (_spec.courseKey != null)
        result.courseOptions
                .where((option) => option.courseKey == _spec.courseKey)
                .map((option) => option.label)
                .firstOrNull ??
            _spec.courseKey!,
    ];
    if (parts.isEmpty) {
      return '当前从课业统计进入明细视图';
    }
    return '当前统计筛选：${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final now = _now;
          final result = LocalRecordQuery.query(widget.store, _spec, now);
          final selectedCourseKey = result.courseOptions
                  .any((option) => option.courseKey == _spec.courseKey)
              ? _spec.courseKey
              : null;

          return Scaffold(
            backgroundColor: Journal.paper,
            appBar: AppBar(
              toolbarHeight: 40,
              backgroundColor: Journal.paper,
              leading: IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _handleBack(context),
              ),
              actions: [
                PopupMenuButton<LocalRecordSortOrder>(
                  tooltip: '排序方式',
                  icon: const Icon(Icons.swap_vert),
                  onSelected: (value) => setState(
                    () => _spec = _spec.copyWith(sort: value),
                  ),
                  itemBuilder: (_) => [
                    for (final option in LocalRecordSortOrder.values)
                      CheckedPopupMenuItem<LocalRecordSortOrder>(
                        value: option,
                        checked: _spec.sort == option,
                        child: Text(option.label),
                      ),
                  ],
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                const JournalHeading(
                  '本地记录',
                  eyebrow: 'CAMPUS JOURNAL   /   ARCHIVE',
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final category in LocalRecordCategory.values) ...[
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
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
                  Card(
                    color: Journal.sage.withValues(alpha: 0.45),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _scopeBannerSummary(result),
                            style:
                                Journal.metadata.copyWith(color: Journal.ink),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _spec = _spec.resetToAllLocal());
                            },
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: const Text('查看全部本机记录'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _spec = _spec.copyWith(query: value)),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    labelText: '搜索标题或课程',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _spec.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              setState(
                                () => _spec = _spec.copyWith(query: ''),
                              );
                            },
                          ),
                  ),
                ),
                if (_spec.category == LocalRecordCategory.coursework) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final status
                            in LocalRecordStatusFilter.values) ...[
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
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(
                      'records-course-${selectedCourseKey ?? 'all'}-${_spec.scope.name}-${result.courseOptions.length}',
                    ),
                    initialValue: selectedCourseKey,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      labelText: '按课程筛选',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('全部课程'),
                      ),
                      for (final option in result.courseOptions)
                        DropdownMenuItem<String?>(
                          value: option.courseKey,
                          child: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => value == null
                          ? _spec = _spec.copyWith(clearCourseKey: true)
                          : _spec = _spec.copyWith(courseKey: value),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '${result.count} 条记录',
                  style: Journal.metadata,
                ),
                const SizedBox(height: 8),
                if (result.count == 0)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
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
                            style: Journal.entryTitle,
                          ),
                          if (_spec.category ==
                                  LocalRecordCategory.coursework &&
                              !_spec.isStatsScoped &&
                              (_spec.query.isNotEmpty ||
                                  _spec.status != LocalRecordStatusFilter.all ||
                                  _spec.courseKey != null)) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _spec = _spec.resetToAllLocal());
                              },
                              child: const Text('查看全部本机记录'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else if (_spec.category == LocalRecordCategory.otherSources)
                  for (final assignment in result.otherSources)
                    _buildOtherSourceCard(context, assignment, now)
                else
                  for (final group in result.groups)
                    _buildGroupCard(context, group, now),
              ],
            ),
          );
        },
      );

  Widget _buildOtherSourceCard(
    BuildContext context,
    Assignment a,
    DateTime now,
  ) {
    final badge = _statusBadge(a, now);
    final title = a.title.trim().isNotEmpty ? a.title.trim() : a.courseName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openDetail(context, a.id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CourseMark(a.courseName, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Journal.entryTitle),
                      if (a.courseName.trim().isNotEmpty &&
                          a.title.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(a.courseName.trim(), style: Journal.metadata),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _pill(badge.label, bg: badge.bg, fg: badge.fg),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '来源：${a.source.name} · 读取：${DateFormat('yyyy-MM-dd HH:mm').format(AssignmentQuery.beijing(a.lastSyncedAt))}',
                        style: Journal.metadata,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    CourseworkGroup group,
    DateTime now,
  ) {
    final primary = group.primary;
    final badge = _statusBadge(primary, now);
    final title = primary.title.trim().isNotEmpty
        ? primary.title.trim()
        : primary.courseName;
    final timeText = _businessTimeText(primary, group.sources);
    final isHiddenTab = _spec.category == LocalRecordCategory.hidden;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openDetail(context, primary.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CourseMark(primary.courseName, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Journal.entryTitle),
                      if (primary.courseName.trim().isNotEmpty &&
                          primary.title.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          primary.clazzId == null || primary.clazzId!.isEmpty
                              ? primary.courseName.trim()
                              : '${primary.courseName.trim()} · 班级 ${primary.clazzId}',
                          style: Journal.metadata,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (group.hidden)
                            _pill('已隐藏', bg: Journal.paper, fg: Journal.muted),
                          _pill(badge.label, bg: badge.bg, fg: badge.fg),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(timeText, style: Journal.metadata),
                      const SizedBox(height: 2),
                      Text(
                        '来源：${group.sourceLabel} · 读取：${DateFormat('yyyy-MM-dd HH:mm').format(AssignmentQuery.beijing(primary.lastSyncedAt))}',
                        style: Journal.metadata,
                      ),
                    ],
                  ),
                ),
                if (isHiddenTab) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.store.isLoading
                        ? null
                        : () =>
                            widget.store.setCourseworkGroupHidden(group, false),
                    child: const Text('恢复'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
