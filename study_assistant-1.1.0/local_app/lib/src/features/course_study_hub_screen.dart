import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../app/transient_feedback.dart';
import '../models/course.dart';
import '../models/course_chapter_progress.dart';
import '../models/course_notice.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import '../services/interaction_feedback_service.dart';
import 'widgets/data_recovery_warning.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_info_popover.dart';
import 'widgets/journal_picker_sheet.dart';

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

  static String cleanNoticeSummary(String summary) {
    final trimmed = summary.trim();
    if (trimmed.isEmpty) return '';
    return trimmed
        .replaceFirst(
          RegExp(r'^课程名称\s*[:：][^\r\n]*(?:\r?\n)+'),
          '',
        )
        .replaceFirst(
          RegExp(r'^课程名称\s*[:：][^\r\n]*$'),
          '',
        )
        .trim();
  }

  @override
  State<CourseStudyHubScreen> createState() => _CourseStudyHubScreenState();
}

enum _NoticeFilter { all, localUnread, withTime }

enum _NoticeScope { linked, inbox, course }

class _CourseStudyHubScreenState extends State<CourseStudyHubScreen> {
  late String _tab;
  _NoticeFilter _noticeFilter = _NoticeFilter.all;
  _NoticeScope _noticeScope = _NoticeScope.linked;
  String? _selectedCourseKey;
  bool _pendingChaptersOnly = false;
  late final TextEditingController _searchController;
  String? _accountHash;
  int _accountEpoch = 0;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab == 'chapters' ? 'chapters' : 'notices';
    final initialCourseKey = widget.initialCourseKey?.trim();
    if (initialCourseKey != null && initialCourseKey.isNotEmpty) {
      _noticeScope = _NoticeScope.course;
      _selectedCourseKey = initialCourseKey;
    }
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
      _noticeScope = _NoticeScope.linked;
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
      final initialCourseKey = widget.initialCourseKey?.trim();
      if (initialCourseKey != null && initialCourseKey.isNotEmpty) {
        _noticeScope = _NoticeScope.course;
        _selectedCourseKey = initialCourseKey;
      } else {
        _noticeScope = _NoticeScope.linked;
        _selectedCourseKey = null;
      }
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
    showJournalMessage(context, message);
  }

  Future<void> _syncNotices() async {
    final before = widget.store.syncReport;
    final beforeEpoch = widget.store.accountEpoch;
    await widget.store.syncAssignments();
    if (!mounted) return;
    InteractionFeedback.triggerSyncDoneIfReady(
      prefs: widget.store.display,
      before: before,
      after: widget.store.syncReport,
      beforeEpoch: beforeEpoch,
      afterEpoch: widget.store.accountEpoch,
      operationError: widget.store.error,
    );
  }

  Future<void> _syncChapters({String? courseKey}) async {
    final beforeEpoch = widget.store.accountEpoch;
    final ok = await widget.store.syncCourseChapters(courseKey: courseKey);
    if (ok &&
        mounted &&
        widget.store.accountEpoch == beforeEpoch &&
        widget.store.error == null) {
      InteractionFeedback.trigger(
        widget.store.display,
        kind: InteractionSoundKind.syncDone,
      );
    }
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
    final openingEpoch = widget.store.accountEpoch;
    final openingHash = widget.store.accountHash;
    if (!notice.localRead) {
      await widget.store.markNoticeLocalRead(
        notice.id,
        read: true,
        expectedEpoch: openingEpoch,
      );
    }
    if (!mounted ||
        widget.store.accountEpoch != openingEpoch ||
        widget.store.accountHash != openingHash ||
        !widget.store.isAuthenticated) {
      return;
    }
    var closingForAccountChange = false;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final journal = Journal.of(sheetContext);
        void scheduleClose() {
          if (closingForAccountChange) return;
          closingForAccountChange = true;
          final sheetRoute = ModalRoute.of(sheetContext);
          final rootNavigator = Navigator.of(sheetContext, rootNavigator: true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (sheetRoute == null ||
                !sheetRoute.isActive ||
                !rootNavigator.mounted) {
              return;
            }
            // Pop any child picker/dialog pushed above this sheet, then remove
            // only the sheet route itself so the underlying page is never popped.
            rootNavigator.popUntil(
              (route) => route == sheetRoute || !sheetRoute.isActive,
            );
            if (sheetRoute.isActive) {
              rootNavigator.removeRoute(sheetRoute);
            }
          });
        }

        return Container(
          decoration: BoxDecoration(
            color: journal.sheetElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            builder: (_, scrollController) => AnimatedBuilder(
              animation: widget.store,
              builder: (context, _) {
                final journal = Journal.of(context);
                final accountChanged = !widget.store.isAuthenticated ||
                    widget.store.accountEpoch != openingEpoch ||
                    widget.store.accountHash != openingHash;
                final latest = accountChanged
                    ? null
                    : widget.store.courseNotices.items
                        .where((item) => item.id == notice.id)
                        .firstOrNull;
                if (latest == null) {
                  scheduleClose();
                  return const SizedBox.shrink();
                }
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
                final cleanBody =
                    CourseStudyHubScreen.cleanNoticeSummary(latest.summary);

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                  children: [
                    Center(
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
                    Text(latest.title, style: journal.section),
                    const SizedBox(height: 6),
                    Text(
                      [
                        latest.courseName,
                        if (latest.senderName.isNotEmpty) latest.senderName,
                        timeText,
                      ].join(' · '),
                      style: journal.metadata,
                    ),
                    if (latest.extractedEventAt != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: journal.sage.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: journal.cardBorder, width: 0.8),
                        ),
                        child: Text(
                          '识别时间：${DateFormat('yyyy-MM-dd HH:mm').format(AssignmentQuery.beijing(latest.extractedEventAt!))}（北京时间）',
                          style: journal.metadata.copyWith(color: journal.ink),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    JournalGroupedCard(
                      padding: const EdgeInsets.all(14),
                      children: [
                        Text(
                          cleanBody.isEmpty ? '无补充正文内容' : cleanBody,
                          style: journal.entryTitle.copyWith(
                            fontSize: 14.5,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '本机已读状态仅保存在当前设备手记，不修改学习通平台状态。',
                      style: journal.metadata,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (linked)
                          JournalPrimaryButton(
                            expanded: false,
                            icon: Icons.event_available_outlined,
                            label: '查看已设提醒',
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              context.push('/agenda');
                            },
                          )
                        else
                          JournalPrimaryButton(
                            expanded: false,
                            icon: Icons.notifications_active_outlined,
                            label: '设为本地提醒',
                            onPressed: widget.store.isLoading
                                ? null
                                : () async {
                                    final picked = await _pickDateTime(
                                      initial: latest.extractedEventAt,
                                    );
                                    if (picked == null ||
                                        !mounted ||
                                        widget.store.accountEpoch !=
                                            openingEpoch ||
                                        widget.store.accountHash !=
                                            openingHash) {
                                      return;
                                    }
                                    final created = await widget.store
                                        .createReminderFromNotice(
                                      latest,
                                      remindAt: picked,
                                      expectedEpoch: openingEpoch,
                                    );
                                    if (!mounted ||
                                        widget.store.accountEpoch !=
                                            openingEpoch ||
                                        widget.store.accountHash !=
                                            openingHash) {
                                      return;
                                    }
                                    if (created != null) {
                                      _showSnack('已添加到个人待办并安排本地提醒');
                                    } else if (widget.store.error != null) {
                                      _showSnack(widget.store.error!);
                                    }
                                  },
                          ),
                        JournalSecondaryButton(
                          expanded: false,
                          icon: latest.localRead
                              ? Icons.mark_email_unread_outlined
                              : Icons.mark_email_read_outlined,
                          label: latest.localRead ? '标为本机未读' : '标为本机已读',
                          onPressed: widget.store.isLoading
                              ? null
                              : () async {
                                  await widget.store.markNoticeLocalRead(
                                    latest.id,
                                    read: !latest.localRead,
                                    expectedEpoch: openingEpoch,
                                  );
                                },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
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
    final openingHash = widget.store.accountHash;
    final picked = await _pickDateTime();
    if (!mounted ||
        widget.store.accountEpoch != epoch ||
        widget.store.accountHash != openingHash) {
      return;
    }
    final created = await widget.store.createTodoFromChapterNode(
      snapshot,
      node,
      remindAt: picked,
      minutes: 30,
      expectedEpoch: epoch,
    );
    if (!mounted ||
        widget.store.accountEpoch != epoch ||
        widget.store.accountHash != openingHash) {
      return;
    }
    if (created != null) {
      _showSnack(picked == null ? '已添加到个人待办' : '已添加到个人待办并设置本地提醒');
    } else if (widget.store.error != null) {
      _showSnack(widget.store.error!);
    }
  }

  List<CourseNotice> _scopedNotices(List<CourseNotice> notices) {
    return switch (_noticeScope) {
      _NoticeScope.linked => notices.where((n) => n.courseKey != null).toList(),
      _NoticeScope.inbox => notices,
      _NoticeScope.course =>
        notices.where((n) => n.courseKey == _selectedCourseKey).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final journal = Journal.of(context);
        final notices = widget.store.courseNotices.items;
        final scoped = _scopedNotices(notices);
        final scopedUnread = scoped.where((n) => !n.localRead).length;

        return Scaffold(
          backgroundColor: journal.paper,
          appBar: AppBar(
            backgroundColor: journal.paper,
            leading: IconButton(
              tooltip: '返回我的',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
            title: const Text('课程通知与章节'),
            actions: [
              if (_tab == 'notices') ...[
                IconButton(
                  tooltip: '全部标为已读',
                  icon: const Icon(Icons.done_all_rounded, size: 21),
                  onPressed: widget.store.isLoading || scopedUnread == 0
                      ? null
                      : () => widget.store.markAllNoticesLocalRead(
                            noticeIds: scoped
                                .where((n) => !n.localRead)
                                .map((n) => n.id),
                          ),
                ),
                IconButton(
                  tooltip: '手动同步通知',
                  icon: widget.store.isLoading
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: journal.ink,
                          ),
                        )
                      : const Icon(Icons.sync_rounded, size: 21),
                  onPressed: widget.store.isLoading ? null : _syncNotices,
                ),
              ] else ...[
                IconButton(
                  tooltip: widget.store.isChapterSyncing ? '取消读取' : '刷新课程章节',
                  icon: Icon(
                    widget.store.isChapterSyncing
                        ? Icons.stop_circle_outlined
                        : Icons.sync_rounded,
                    size: 21,
                  ),
                  onPressed: widget.store.isChapterSyncing
                      ? widget.store.cancelSynchronization
                      : widget.store.isLoading || widget.store.courses.isEmpty
                          ? null
                          : () => _syncChapters(courseKey: _selectedCourseKey),
                ),
              ],
              const JournalInfoButton(
                title: '课程通知与章节说明',
                items: [
                  '课程通知仅在前台手动同步时读取；本机已读状态仅用于手记整理，不会修改学习通平台状态。',
                  '章节任务点仅在手动按需刷新时读取，仅供个人学习安排参考，不自动学习或代完成。',
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              if (widget.store.recoveryWarning case final warning?) ...[
                DataRecoveryWarning(warning: warning),
                const SizedBox(height: 12),
              ],
              _StudyHubTabBar(
                tab: _tab,
                unreadCount: widget.store.unreadCourseNoticeCount,
                pendingSectionCount: widget.store.pendingChapterSectionCount,
                onChanged: (next) {
                  JournalMotion.tap(widget.store.display);
                  setState(() => _tab = next);
                },
              ),
              const SizedBox(height: 12),
              if (_tab == 'notices')
                ..._buildNoticesTab(context, notices, scoped, scopedUnread)
              else
                ..._buildChaptersTab(context),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildNoticesTab(
    BuildContext context,
    List<CourseNotice> notices,
    List<CourseNotice> scoped,
    int scopedUnread,
  ) {
    final journal = Journal.of(context);
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
    if (_noticeScope == _NoticeScope.course &&
        _selectedCourseKey != null &&
        !courseOptions.containsKey(_selectedCourseKey)) {
      courseOptions[_selectedCourseKey!] = '所选课程';
    }

    final currentScopeKey = switch (_noticeScope) {
      _NoticeScope.linked => '__linked__',
      _NoticeScope.inbox => '__inbox__',
      _NoticeScope.course => _selectedCourseKey ?? '__linked__',
    };
    final currentScopeLabel = switch (_noticeScope) {
      _NoticeScope.linked => '已关联课程',
      _NoticeScope.inbox => '收件箱',
      _NoticeScope.course => courseOptions[_selectedCourseKey] ?? '所选课程',
    };

    final filtered = scoped.where((n) {
      if (_noticeFilter == _NoticeFilter.localUnread && n.localRead) {
        return false;
      }
      if (_noticeFilter == _NoticeFilter.withTime &&
          n.extractedEventAt == null) {
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
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索标题、正文或发布人',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 146),
            child: JournalFilterPill(
              key: ValueKey(
                'notice-scope-field-${_noticeScope.name}-${_selectedCourseKey ?? ''}',
              ),
              label: currentScopeLabel,
              active: _noticeScope != _NoticeScope.linked,
              onTap: () async {
                final picked = await showJournalPickerSheet<String>(
                  context,
                  title: '通知范围',
                  selectedValue: currentScopeKey,
                  searchable: courseOptions.length > 4,
                  searchHint: '搜索课程名称...',
                  displayPrefs: widget.store.display,
                  options: [
                    const JournalPickerOption(
                      value: '__linked__',
                      label: '已关联课程',
                      group: '默认范围',
                      icon: Icons.link_rounded,
                    ),
                    const JournalPickerOption(
                      value: '__inbox__',
                      label: '收件箱（全部）',
                      group: '默认范围',
                      icon: Icons.inbox_outlined,
                    ),
                    for (final entry in courseOptions.entries)
                      JournalPickerOption(
                        value: entry.key,
                        label: entry.value,
                        group: '按课程筛选',
                        icon: courseIconFor(entry.value),
                      ),
                  ],
                );
                if (picked == null || !mounted) return;
                setState(() {
                  if (picked == '__linked__') {
                    _noticeScope = _NoticeScope.linked;
                    _selectedCourseKey = null;
                  } else if (picked == '__inbox__') {
                    _noticeScope = _NoticeScope.inbox;
                    _selectedCourseKey = null;
                  } else {
                    _noticeScope = _NoticeScope.course;
                    _selectedCourseKey = picked;
                  }
                });
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          ChoiceChip(
            label: Text('全部 (${scoped.length})'),
            selected: _noticeFilter == _NoticeFilter.all,
            onSelected: (_) =>
                setState(() => _noticeFilter = _NoticeFilter.all),
          ),
          ChoiceChip(
            label: Text('本机未读 ($scopedUnread)'),
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
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        JournalGroupedCard(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              notices.isEmpty
                  ? '暂无课程通知记录，点击右上角同步图标读取。'
                  : scoped.isEmpty
                      ? '当前通知范围内没有记录，可切换到「收件箱」查看平台消息。'
                      : '当前筛选条件下没有匹配的通知。',
              style: journal.metadata,
            ),
          ],
        )
      else
        JournalGroupedCard(
          dividerIndent: 16,
          children: [
            for (final notice in filtered)
              _buildNoticeTile(context, notice, journal),
          ],
        ),
    ];
  }

  Widget _buildNoticeTile(
    BuildContext context,
    CourseNotice notice,
    JournalPalette journal,
  ) {
    final cleanSummary =
        CourseStudyHubScreen.cleanNoticeSummary(notice.summary);
    return InkWell(
      onTap: () => _openNoticeDetail(notice),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    notice.title,
                    style: journal.entryTitle.copyWith(
                      fontWeight:
                          notice.localRead ? FontWeight.w500 : FontWeight.w600,
                    ),
                  ),
                ),
                if (!notice.localRead) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: journal.berryBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '未读',
                      style: journal.pillLabel.copyWith(
                        fontSize: 11.5,
                        color: journal.berry,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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
              style: journal.metadata,
            ),
            if (cleanSummary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                cleanSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: journal.metadata.copyWith(color: journal.ink),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildChaptersTab(BuildContext context) {
    final journal = Journal.of(context);
    final courses = widget.store.courses;
    final catalog = widget.store.courseChapters;
    final nameCounts = <String, int>{};
    for (final c in courses) {
      final n = c.name.trim();
      nameCounts[n] = (nameCounts[n] ?? 0) + 1;
    }
    final targetCourses = <CourseRef>[
      if (_selectedCourseKey != null)
        ...courses.where((c) => c.key == _selectedCourseKey)
      else
        ...courses,
    ];

    return [
      if (widget.store.isChapterSyncing) ...[
        JournalGroupedCard(
          padding: const EdgeInsets.all(14),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(semanticsLabel: '正在读取章节进度'),
                const SizedBox(height: 8),
                Text(
                  widget.store.chapterSyncProgressText ?? '正在读取章节进度…',
                  style: journal.metadata,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
      JournalGroupedCard(
        children: [
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            title: Text('仅看待完成任务点小节', style: journal.entryTitle),
            value: _pendingChaptersOnly,
            onChanged: (v) => setState(() => _pendingChaptersOnly = v),
          ),
        ],
      ),
      if (widget.store.error != null) ...[
        const SizedBox(height: 10),
        JournalGroupedCard(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              widget.store.error!,
              style: journal.metadata.copyWith(color: journal.berry),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      if (targetCourses.isEmpty)
        JournalGroupedCard(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              '暂无课程资料，请先前往「同步学习通」同步课程列表。',
              style: journal.metadata,
            ),
          ],
        )
      else
        JournalGroupedCard(
          dividerIndent: 16,
          children: [
            for (final course in targetCourses)
              _buildChapterCourseExpansion(
                context,
                course: course,
                catalog: catalog,
                duplicateName: (nameCounts[course.name.trim()] ?? 0) > 1,
                journal: journal,
              ),
          ],
        ),
    ];
  }

  Widget _buildChapterCourseExpansion(
    BuildContext context, {
    required CourseRef course,
    required CourseChapterCatalog catalog,
    required bool duplicateName,
    required JournalPalette journal,
  }) {
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

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('chapter-course-${course.key}'),
        leading: CourseMark(course.name, size: 26),
        title: Text(course.name, style: journal.entryTitle),
        subtitle: Text(
          snapshot == null
              ? duplicateName
                  ? '班级 ${course.clazzId} · $progressLabel'
                  : progressLabel
              : '$progressLabel · 更新于 ${DateFormat('M月d日 HH:mm').format(AssignmentQuery.beijing(snapshot.lastSyncedAt))}',
          style: journal.metadata,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '刷新 ${course.name} 章节进度',
              onPressed: widget.store.isLoading
                  ? null
                  : () => _syncChapters(courseKey: course.key),
              icon: const Icon(Icons.sync_rounded, size: 19),
            ),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
        children: [
          if (snapshot == null)
            ListTile(
              title: Text('尚未读取该课程章节目录', style: journal.metadata),
            )
          else if (visibleNodes.isEmpty)
            ListTile(
              title: Text('当前筛选下没有可显示的章节小节', style: journal.metadata),
            )
          else
            for (final node in visibleNodes)
              if (node.level == 0)
                ListTile(
                  dense: true,
                  title: Text(
                    '${node.code}. ${node.title}',
                    style: journal.entryTitle.copyWith(fontSize: 15),
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
                    style: journal.metadata.copyWith(
                      color: node.state == ChapterTaskState.pendingPoints
                          ? journal.berry
                          : journal.muted,
                    ),
                  ),
                  trailing: node.state == ChapterTaskState.pendingPoints
                      ? (node.linkedManualEntryId != null &&
                              widget.store.notebook.entries
                                  .any((e) => e.id == node.linkedManualEntryId)
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
  }
}

class _StudyHubTabBar extends StatelessWidget {
  const _StudyHubTabBar({
    required this.tab,
    required this.unreadCount,
    required this.pendingSectionCount,
    required this.onChanged,
  });

  final String tab;
  final int unreadCount;
  final int pendingSectionCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    Widget segment(String value, String label) {
      final active = tab == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: JournalMotion.duration(
              context,
              const Duration(milliseconds: 180),
            ),
            curve: JournalMotion.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? journal.segmentThumb : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: active ? journal.segmentBorder : null,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: journal.isDark ? 0.22 : 0.05,
                        ),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: journal.pillLabel.copyWith(
                fontSize: 13.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? journal.ink : journal.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: journal.segmentTrack,
        borderRadius: BorderRadius.circular(14),
        border: journal.segmentBorder,
      ),
      child: Row(
        children: [
          segment('notices', '课程通知 ($unreadCount)'),
          segment('chapters', '章节任务点 ($pendingSectionCount)'),
        ],
      ),
    );
  }
}
