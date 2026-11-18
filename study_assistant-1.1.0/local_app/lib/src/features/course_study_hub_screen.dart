import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../models/course.dart';
import '../models/course_chapter_progress.dart';
import '../models/course_notice.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import 'widgets/data_recovery_warning.dart';

class CourseStudyHubScreen extends StatefulWidget {
  const CourseStudyHubScreen({
    super.key,
    required this.store,
    this.initialTab,
    this.initialCourseKey,
  });

  final AssignmentStore store;
  final String? initialTab;
  final String? initialCourseKey;

  @override
  State<CourseStudyHubScreen> createState() => _CourseStudyHubScreenState();
}

enum _NoticeFilter { all, localUnread, withTime }

class _CourseStudyHubScreenState extends State<CourseStudyHubScreen> {
  late String _tab;
  _NoticeFilter _noticeFilter = _NoticeFilter.all;
  String? _selectedCourseKey;
  bool _pendingChaptersOnly = false;
  late final TextEditingController _searchController;
  String? _accountHash;
  int _accountEpoch = 0;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab == 'chapters' ? 'chapters' : 'notices';
    _selectedCourseKey = widget.initialCourseKey?.trim().isEmpty == true
        ? null
        : widget.initialCourseKey?.trim();
    _searchController = TextEditingController();
    _accountHash = widget.store.accountHash;
    _accountEpoch = widget.store.accountEpoch;
    widget.store.addListener(_handleIdentityChanged);
  }

  void _handleIdentityChanged() {
    final nextHash = widget.store.accountHash;
    final nextEpoch = widget.store.accountEpoch;
    if (nextHash == _accountHash && nextEpoch == _accountEpoch) return;
    _accountHash = nextHash;
    _accountEpoch = nextEpoch;
    if (!mounted) return;
    setState(() {
      _selectedCourseKey = null;
      _noticeFilter = _NoticeFilter.all;
      _searchController.clear();
    });
  }

  @override
  void didUpdateWidget(covariant CourseStudyHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_handleIdentityChanged);
      _accountHash = widget.store.accountHash;
      _accountEpoch = widget.store.accountEpoch;
      widget.store.addListener(_handleIdentityChanged);
    }
    if (oldWidget.initialTab != widget.initialTab &&
        widget.initialTab != null) {
      _tab = widget.initialTab == 'chapters' ? 'chapters' : 'notices';
    }
    if (oldWidget.initialCourseKey != widget.initialCourseKey) {
      _selectedCourseKey = widget.initialCourseKey?.trim().isEmpty == true
          ? null
          : widget.initialCourseKey?.trim();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleIdentityChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<DateTime?> _pickDateTime({DateTime? initial}) async {
    final now = DateTime.now();
    final base = initial != null && initial.isAfter(now)
        ? initial
        : now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200, 12, 31),
    );
    if (!mounted || date == null) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _openNoticeDetail(CourseNotice notice) async {
    if (!notice.localRead) {
      await widget.store.markNoticeLocalRead(notice.id, read: true);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Journal.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scrollController) => AnimatedBuilder(
            animation: widget.store,
            builder: (context, _) {
              final latest = widget.store.courseNotices.items
                      .where((item) => item.id == notice.id)
                      .firstOrNull ??
                  notice;
              final linked = latest.linkedManualEntryId != null &&
                  widget.store.notebook.entries
                      .any((e) => e.id == latest.linkedManualEntryId);
              final timeText = latest.publishedAt == null
                  ? '发布时间待确认'
                  : DateFormat(
                      latest.publishedTrusted
                          ? 'yyyy-MM-dd HH:mm'
                          : 'yyyy-MM-dd',
                    ).format(AssignmentQuery.beijing(latest.publishedAt!));
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Journal.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(latest.title, style: Journal.section),
                  const SizedBox(height: 6),
                  Text(
                    [
                      latest.courseName,
                      if (latest.senderName.isNotEmpty) latest.senderName,
                      timeText,
                    ].join(' · '),
                    style: Journal.metadata,
                  ),
                  if (latest.extractedEventAt != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Journal.sage.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Journal.rule),
                      ),
                      child: Text(
                        '识别时间：${DateFormat('yyyy-MM-dd HH:mm').format(AssignmentQuery.beijing(latest.extractedEventAt!))}（北京时间）',
                        style: Journal.metadata.copyWith(color: Journal.ink),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        latest.summary.isEmpty ? '无补充正文内容' : latest.summary,
                        style:
                            const TextStyle(height: 1.55, color: Journal.ink),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '说明：本机已读状态仅保存在当前设备手记，不会修改学习通平台未读状态。',
                    style: Journal.metadata,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (linked)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            context.push('/agenda');
                          },
                          icon: const Icon(Icons.event_available_outlined),
                          label: const Text('查看已设提醒'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: widget.store.isLoading
                              ? null
                              : () async {
                                  final picked = await _pickDateTime(
                                    initial: latest.extractedEventAt,
                                  );
                                  if (picked == null || !mounted) return;
                                  final created = await widget.store
                                      .createReminderFromNotice(
                                    latest,
                                    remindAt: picked,
                                  );
                                  if (!mounted) return;
                                  if (created != null) {
                                    _showSnack('已添加到个人待办并安排本地提醒');
                                  } else if (widget.store.error != null) {
                                    _showSnack(widget.store.error!);
                                  }
                                },
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('设为本地提醒'),
                        ),
                      OutlinedButton.icon(
                        onPressed: widget.store.isLoading
                            ? null
                            : () async {
                                await widget.store.markNoticeLocalRead(
                                  latest.id,
                                  read: !latest.localRead,
                                );
                              },
                        icon: Icon(latest.localRead
                            ? Icons.mark_email_unread_outlined
                            : Icons.mark_email_read_outlined),
                        label: Text(latest.localRead ? '标为本机未读' : '标为本机已读'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _addChapterTodo(
    CourseChapterSnapshot snapshot,
    ChapterNode node,
  ) async {
    final epoch = widget.store.accountEpoch;
    final picked = await _pickDateTime();
    if (!mounted) return;
    final created = await widget.store.createTodoFromChapterNode(
      snapshot,
      node,
      remindAt: picked,
      minutes: 30,
      expectedEpoch: epoch,
    );
    if (created != null) {
      _showSnack(picked == null ? '已添加到个人待办' : '已添加到个人待办并设置本地提醒');
    } else if (widget.store.error != null) {
      _showSnack(widget.store.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Journal.paper,
          appBar: AppBar(
            backgroundColor: Journal.paper,
            leading: IconButton(
              tooltip: '返回我的',
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              const JournalHeading(
                '课程通知与章节',
                eyebrow: 'CAMPUS JOURNAL   /   STUDY HUB',
              ),
              const SizedBox(height: 12),
              if (widget.store.recoveryWarning case final warning?) ...[
                DataRecoveryWarning(warning: warning),
                const SizedBox(height: 12),
              ],
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'notices',
                    icon: const Icon(Icons.notifications_none_outlined),
                    label:
                        Text('课程通知 (${widget.store.unreadCourseNoticeCount})'),
                  ),
                  ButtonSegment(
                    value: 'chapters',
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(
                      '章节任务点 (${widget.store.pendingChapterSectionCount})',
                    ),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (values) {
                  setState(() => _tab = values.first);
                },
              ),
              const SizedBox(height: 14),
              if (_tab == 'notices')
                ..._buildNoticesTab(context)
              else
                ..._buildChaptersTab(context),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildNoticesTab(BuildContext context) {
    final notices = widget.store.courseNotices.items;
    final query = _searchController.text.trim().toLowerCase();
    final courseOptions = <String, String>{};
    for (final c in widget.store.courses) {
      courseOptions[c.key] = c.name;
    }
    for (final n in notices) {
      if (n.courseKey != null && !courseOptions.containsKey(n.courseKey)) {
        courseOptions[n.courseKey!] = n.courseName;
      }
    }
    final effectiveCourseKey = (_selectedCourseKey != null &&
            courseOptions.containsKey(_selectedCourseKey))
        ? _selectedCourseKey
        : null;

    final filtered = notices.where((n) {
      if (_noticeFilter == _NoticeFilter.localUnread && n.localRead) {
        return false;
      }
      if (_noticeFilter == _NoticeFilter.withTime &&
          n.extractedEventAt == null) {
        return false;
      }
      if (effectiveCourseKey != null && n.courseKey != effectiveCourseKey) {
        return false;
      }
      if (query.isNotEmpty) {
        final hay = '${n.title}\n${n.summary}\n${n.courseName}\n${n.senderName}'
            .toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '仅在前台手动同步时读取收件箱近期通知；本机已读仅用于手记整理，不会修改学习通平台状态。',
                style: Journal.metadata,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: widget.store.isLoading
                        ? null
                        : widget.store.syncAssignments,
                    icon: const Icon(Icons.sync),
                    label: Text(widget.store.isLoading ? '正在同步…' : '手动同步通知'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.store.isLoading ||
                            widget.store.unreadCourseNoticeCount == 0
                        ? null
                        : widget.store.markAllNoticesLocalRead,
                    icon: const Icon(Icons.done_all),
                    label: const Text('全部标为已读'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索通知标题、正文、课程或发布人',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close),
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          ChoiceChip(
            label: Text('全部 (${notices.length})'),
            selected: _noticeFilter == _NoticeFilter.all,
            onSelected: (_) =>
                setState(() => _noticeFilter = _NoticeFilter.all),
          ),
          ChoiceChip(
            label: Text('本机未读 (${widget.store.unreadCourseNoticeCount})'),
            selected: _noticeFilter == _NoticeFilter.localUnread,
            onSelected: (_) =>
                setState(() => _noticeFilter = _NoticeFilter.localUnread),
          ),
          ChoiceChip(
            label: const Text('含识别时间'),
            selected: _noticeFilter == _NoticeFilter.withTime,
            onSelected: (_) =>
                setState(() => _noticeFilter = _NoticeFilter.withTime),
          ),
        ],
      ),
      if (courseOptions.isNotEmpty) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          key: ValueKey(
            'hub-course-${effectiveCourseKey ?? 'all'}-${courseOptions.length}',
          ),
          initialValue: effectiveCourseKey,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '按已关联课程筛选',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('全部通知'),
            ),
            for (final entry in courseOptions.entries)
              DropdownMenuItem<String?>(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(() => _selectedCourseKey = value),
        ),
      ],
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              notices.isEmpty ? '暂无课程通知记录，点击上方「手动同步通知」获取。' : '当前筛选条件下没有匹配的通知。',
              style: Journal.metadata,
            ),
          ),
        ),
      for (final notice in filtered) ...[
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openNoticeDetail(notice),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notice.title,
                          style: Journal.entryTitle.copyWith(
                            fontWeight: notice.localRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!notice.localRead)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Journal.berry.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '未读',
                            style: TextStyle(
                              fontSize: 12,
                              color: Journal.berry,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      notice.courseName,
                      if (notice.senderName.isNotEmpty) notice.senderName,
                      if (notice.publishedAt != null)
                        DateFormat(
                          notice.publishedTrusted ? 'M月d日 HH:mm' : 'M月d日',
                        ).format(AssignmentQuery.beijing(notice.publishedAt!)),
                      if (notice.platformUnread) '平台未读',
                      if (notice.linkedManualEntryId != null) '已设提醒',
                    ].join(' · '),
                    style: Journal.metadata,
                  ),
                  if (notice.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      notice.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Journal.metadata.copyWith(color: Journal.ink),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _buildChaptersTab(BuildContext context) {
    final courses = widget.store.courses;
    final catalog = widget.store.courseChapters;
    final targetCourses = <CourseRef>[
      if (_selectedCourseKey != null)
        ...courses.where((c) => c.key == _selectedCourseKey)
      else
        ...courses,
    ];

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '仅在前台手动按需读取课程章节与任务点进度，仅供个人学习安排参考，不自动学习或代完成。',
                style: Journal.metadata,
              ),
              const SizedBox(height: 10),
              if (widget.store.isChapterSyncing) ...[
                const LinearProgressIndicator(semanticsLabel: '正在读取章节进度'),
                const SizedBox(height: 8),
                Text(
                  widget.store.chapterSyncProgressText ?? '正在读取章节进度…',
                  style: Journal.metadata,
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!widget.store.isChapterSyncing)
                    FilledButton.icon(
                      onPressed: widget.store.isLoading || courses.isEmpty
                          ? null
                          : () => widget.store.syncCourseChapters(
                                courseKey: _selectedCourseKey,
                              ),
                      icon: const Icon(Icons.refresh),
                      label: Text(_selectedCourseKey == null
                          ? '刷新已关注课程章节'
                          : '刷新所选课程章节'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: widget.store.cancelSynchronization,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('取消读取'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('仅看待完成任务点小节'),
                value: _pendingChaptersOnly,
                onChanged: (v) => setState(() => _pendingChaptersOnly = v),
              ),
            ],
          ),
        ),
      ),
      if (widget.store.error != null) ...[
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.store.error!,
              style: Journal.metadata.copyWith(color: Journal.berry),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (targetCourses.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('暂无课程资料，请先前往「同步学习通」同步课程列表。', style: Journal.metadata),
          ),
        ),
      for (final course in targetCourses) ...[
        Builder(builder: (context) {
          final snapshot = catalog.byCourse[course.key];
          final progressLabel = snapshot == null
              ? '尚未读取章节'
              : snapshot.progressTrusted
                  ? '已完成 ${snapshot.completedPoints}/${snapshot.totalPoints} 任务点'
                  : '平台未提供总计 · 待完成小节 ${snapshot.pendingSectionCount} 处';
          final visibleNodes = snapshot == null
              ? const <ChapterNode>[]
              : snapshot.nodes.where((node) {
                  if (!_pendingChaptersOnly) return true;
                  return node.level == 0 ||
                      node.state == ChapterTaskState.pendingPoints;
                }).toList();

          return Card(
            child: ExpansionTile(
              key: ValueKey('chapter-course-${course.key}'),
              title: Text(course.name, style: Journal.entryTitle),
              subtitle: Text(
                snapshot == null
                    ? '班级 ${course.clazzId} · $progressLabel'
                    : '$progressLabel · 更新于 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(snapshot.lastSyncedAt))}',
                style: Journal.metadata,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '刷新 ${course.name} 章节进度',
                    onPressed: widget.store.isLoading
                        ? null
                        : () => widget.store
                            .syncCourseChapters(courseKey: course.key),
                    icon: const Icon(Icons.sync),
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
              children: [
                if (snapshot == null)
                  const ListTile(
                    title: Text('尚未读取该课程章节目录', style: Journal.metadata),
                  )
                else if (visibleNodes.isEmpty)
                  const ListTile(
                    title: Text('当前筛选下没有可显示的章节小节', style: Journal.metadata),
                  )
                else
                  for (final node in visibleNodes)
                    if (node.level == 0)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${node.code}. ${node.title}',
                          style: Journal.entryTitle.copyWith(fontSize: 15),
                        ),
                      )
                    else
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.fromLTRB(26, 2, 12, 2),
                        title: Text('${node.code} ${node.title}'),
                        subtitle: Text(
                          switch (node.state) {
                            ChapterTaskState.completed => '已完成',
                            ChapterTaskState.pendingPoints =>
                              '${node.pendingPoints} 个任务点待完成',
                            ChapterTaskState.locked => '暂未开放',
                            ChapterTaskState.noTaskPoints => '无任务点',
                            ChapterTaskState.unknown => '状态待确认',
                          },
                          style: Journal.metadata.copyWith(
                            color: node.state == ChapterTaskState.pendingPoints
                                ? Journal.berry
                                : Journal.muted,
                          ),
                        ),
                        trailing: node.state == ChapterTaskState.pendingPoints
                            ? (node.linkedManualEntryId != null &&
                                    widget.store.notebook.entries.any(
                                        (e) => e.id == node.linkedManualEntryId)
                                ? TextButton(
                                    onPressed: () => context.push('/agenda'),
                                    child: const Text('已加待办'),
                                  )
                                : TextButton(
                                    onPressed: widget.store.isLoading
                                        ? null
                                        : () => _addChapterTodo(snapshot, node),
                                    child: const Text('设待办'),
                                  ))
                            : null,
                      ),
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
      ],
    ];
  }
}
