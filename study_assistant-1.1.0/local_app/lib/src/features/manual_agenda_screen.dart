import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../app/transient_feedback.dart';
import '../app/unsaved_edit_guard.dart';
import '../models/manual_attachment.dart';
import '../models/study_notebook.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import 'manual_entry_detail_screen.dart';
import 'reminder_status_screen.dart';
import 'widgets/coursework_status_pill.dart';
import 'widgets/data_recovery_warning.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_context_menu.dart';
import 'widgets/journal_expansion_tile.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_picker_sheet.dart';
import 'widgets/journal_swipe_tile.dart';
import 'widgets/manual_attachment_picker_section.dart';

String manualTime(DateTime? at) => at == null
    ? '未安排时间'
    : '${DateFormat('yyyy-MM-dd HH:mm').format(AssignmentQuery.beijing(at))} 北京时间';

String _compactAgendaTime(DateTime? at, DateTime now) {
  if (at == null) return '未安排时间';
  final bAt = AssignmentQuery.beijing(at);
  final bNow = AssignmentQuery.beijing(now);
  final clock = DateFormat('HH:mm').format(bAt);
  final atDay = DateTime(bAt.year, bAt.month, bAt.day);
  final today = DateTime(bNow.year, bNow.month, bNow.day);
  if (atDay == today) return '今天 $clock';
  if (atDay == today.add(const Duration(days: 1))) return '明天 $clock';
  if (bAt.year == bNow.year) return '${bAt.month}月${bAt.day}日 $clock';
  return '${bAt.year}年${bAt.month}月${bAt.day}日 $clock';
}

class ManualAgendaScreen extends StatefulWidget {
  const ManualAgendaScreen({super.key, required this.store, this.clock});
  final AssignmentStore store;
  final DateTime Function()? clock;
  @override
  State<ManualAgendaScreen> createState() => _AgendaState();
}

class _AgendaState extends State<ManualAgendaScreen> {
  late final int epoch;
  final _feedback = TransientFeedbackController();

  @override
  void initState() {
    super.initState();
    epoch = widget.store.accountEpoch;
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  bool busy = false;
  String filter = 'all';
  bool _completedExpanded = false;

  Future<void> _toggleDoneWithUndo(ManualEntry e) async {
    if (busy) return;
    setState(() => busy = true);
    final nextDone = !e.done;
    final ok = await widget.store.saveNotebook(
      (n) => n.withEntries([
        for (final q in n.entries) q.id == e.id ? q.completed(nextDone) : q,
      ]),
      epoch,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (!ok) {
      showJournalMessage(
        context,
        widget.store.operationError ?? '个人安排保存失败，请核对账号后重试',
      );
      return;
    }
    final warnings = widget.store.manualSaveWarnings;
    final warningSuffix = warnings.isEmpty ? '' : '；${warnings.join('；')}';
    if (nextDone) {
      JournalMotion.complete(widget.store.display);
    } else {
      JournalMotion.tap(widget.store.display);
    }
    _feedback.show(
      context,
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          nextDone ? '已完成「${e.title}」$warningSuffix' : '已恢复为未完成$warningSuffix',
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (widget.store.accountEpoch != epoch) return;
            unawaited(
              widget.store.saveNotebook(
                (n) => n.withEntries([
                  for (final q in n.entries)
                    q.id == e.id ? q.completed(!nextDone) : q,
                ]),
                epoch,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> remove(ManualEntry e) async {
    if (busy) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('删除这项个人日程？'),
                content: Text(e.title),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('取消')),
                  FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Journal.of(c).berry,
                        foregroundColor: Journal.of(c).onPrimaryFill,
                      ),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('删除'))
                ]));
    if (!mounted || yes != true) return;
    setState(() => busy = true);
    final ok = await widget.store.saveNotebook(
      (n) => n.withEntries(n.entries.where((v) => v.id != e.id).toList()),
      epoch,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (!ok) {
      showJournalMessage(
        context,
        widget.store.operationError ?? '个人安排保存失败，请核对账号后重试',
      );
      return;
    }
    final warnings = widget.store.manualSaveWarnings;
    final warningSuffix = warnings.isEmpty ? '' : '；${warnings.join('；')}';
    showJournalMessage(context, '已删除个人安排$warningSuffix');
  }

  Future<void> edit([ManualEntry? e]) async {
    final kind = filter == ManualEntry.kindExam
        ? ManualEntry.kindExam
        : ManualEntry.kindTodo;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push(
        e != null
            ? '/assignments/manual/${Uri.encodeComponent(e.id)}/edit'
            : Uri(
                path: '/assignments/new',
                queryParameters: {'kind': kind},
              ).toString(),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ManualEntryEditor(
              store: widget.store,
              entry: e,
              initialKind: e == null ? kind : null,
            )));
  }

  void _openDetail(ManualEntry e) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/assignments/manual/${Uri.encodeComponent(e.id)}');
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => ManualEntryDetailScreen(
            store: widget.store,
            entryId: e.id,
          ),
        ),
      );
    }
  }

  Future<void> _openEntryMenu(BuildContext itemContext, ManualEntry e) async {
    final box = itemContext.findRenderObject() as RenderBox?;
    Rect? anchorRect;
    if (box != null && box.hasSize) {
      anchorRect = box.localToGlobal(Offset.zero) & box.size;
    }
    await showJournalContextMenu(
      context: context,
      anchorRect: anchorRect,
      displayPrefs: widget.store.display,
      actions: [
        JournalContextMenuAction(
          label: '编辑',
          icon: Icons.edit_outlined,
          onSelected: () => unawaited(edit(e)),
        ),
        JournalContextMenuAction(
          label: e.done ? '恢复未完成' : '标记完成',
          icon: e.done ? Icons.undo_rounded : Icons.check_rounded,
          onSelected: () => unawaited(_toggleDoneWithUndo(e)),
        ),
        JournalContextMenuAction(
          label: '删除',
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () => unawaited(remove(e)),
        ),
      ],
    );
  }

  Widget _buildSwipeableRow(
    ManualEntry e,
    DateTime now,
    JournalPalette journal,
  ) {
    return JournalSwipeTile(
      key: ValueKey('agenda-swipe-${e.id}'),
      displayPrefs: widget.store.display,
      enabled: !busy,
      rightAction: e.done
          ? JournalSwipeAction(
              label: '恢复未完成',
              icon: Icons.undo_rounded,
              color: journal.accent,
              backgroundColor: journal.sage,
              onTrigger: () => unawaited(_toggleDoneWithUndo(e)),
            )
          : JournalSwipeAction(
              label: '标记完成',
              icon: Icons.check_rounded,
              color: journal.todoGreen,
              backgroundColor: journal.todoGreenBg,
              onTrigger: () => unawaited(_toggleDoneWithUndo(e)),
            ),
      leftAction: JournalSwipeAction(
        label: '删除',
        icon: Icons.delete_outline_rounded,
        color: journal.berry,
        backgroundColor: journal.berryBg,
        onTrigger: () => unawaited(remove(e)),
      ),
      child: Builder(
        builder: (rowContext) => _AgendaEntryRow(
          entry: e,
          now: now,
          busy: busy,
          onToggleDone: () => unawaited(_toggleDoneWithUndo(e)),
          onTap: () => _openDetail(e),
          onLongPress: () => unawaited(_openEntryMenu(rowContext, e)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final journal = Journal.of(context);
        final now = widget.clock?.call() ?? DateTime.now();
        final allEntries = widget.store.notebook.entries;
        final activeAllCount = allEntries.where((e) => !e.done).length;
        final activeTodoCount = allEntries
            .where((e) => !e.done && e.kind == ManualEntry.kindTodo)
            .length;
        final activeExamCount = allEntries
            .where((e) => !e.done && e.kind == ManualEntry.kindExam)
            .length;
        final scoped = allEntries
            .where((e) => filter == 'all' || e.kind == filter)
            .toList(growable: false);
        final activeRows = scoped.where((e) => !e.done).toList()
          ..sort((a, b) {
            final cmp = (a.at ?? DateTime.utc(2200))
                .compareTo(b.at ?? DateTime.utc(2200));
            return cmp != 0 ? cmp : a.id.compareTo(b.id);
          });
        final doneRows = scoped.where((e) => e.done).toList()
          ..sort((a, b) {
            final aKey = a.updatedAt ??
                a.at ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
            final bKey = b.updatedAt ??
                b.at ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
            final cmp = bKey.compareTo(aKey);
            return cmp != 0 ? cmp : a.id.compareTo(b.id);
          });
        final filterCounts = {
          'all': activeAllCount,
          'todo': activeTodoCount,
          'exam': activeExamCount,
        };
        return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              title: const Text('个人待办与考试'),
            ),
            body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  if (widget.store.recoveryWarning case final warning?) ...[
                    DataRecoveryWarning(warning: warning),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    '手动记录独立于学习通作业；考试时间请以教务通知为准（北京时间）。',
                    style: journal.metadata,
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final item
                        in {'all': '全部', 'todo': '待办', 'exam': '考试'}.entries)
                      ChoiceChip(
                          label: Text(
                            (filterCounts[item.key] ?? 0) > 0
                                ? '${item.value} (${filterCounts[item.key]})'
                                : item.value,
                          ),
                          selected: filter == item.key,
                          onSelected: busy
                              ? null
                              : (_) => setState(() => filter = item.key))
                  ]),
                  const SizedBox(height: 12),
                  if (activeRows.isEmpty && doneRows.isEmpty)
                    JournalGroupedCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 22),
                      children: [
                        Text('还没有个人安排，点击下方按钮添加待办或考试。', style: journal.metadata),
                      ],
                    )
                  else ...[
                    if (activeRows.isEmpty)
                      JournalGroupedCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        children: [
                          Text('当前筛选下的个人安排已全部完成', style: journal.metadata),
                        ],
                      )
                    else
                      JournalGroupedCard(
                        key: const ValueKey('agenda-active-card'),
                        dividerIndent: 52,
                        children: [
                          for (final e in activeRows)
                            _buildSwipeableRow(e, now, journal),
                        ],
                      ),
                    if (doneRows.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      JournalGroupedCard(
                        key: const ValueKey('agenda-completed-card'),
                        dividerIndent: 52,
                        children: [
                          JournalExpansionTile(
                            toggleKey:
                                const ValueKey('agenda-completed-toggle'),
                            expanded: _completedExpanded,
                            title: Text(
                              '已完成（${doneRows.length}）',
                              style: journal.section.copyWith(fontSize: 15),
                            ),
                            leading: Icon(
                              Icons.check_circle_outline_rounded,
                              size: 18,
                              color: journal.todoGreen,
                            ),
                            tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            dividerIndent: 52,
                            dividerEndIndent: 16,
                            onExpansionChanged: (value) {
                              JournalMotion.tap(widget.store.display);
                              setState(() => _completedExpanded = value);
                            },
                            children: [
                              for (final e in doneRows)
                                _buildSwipeableRow(e, now, journal),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  JournalPrimaryButton(
                    icon: Icons.add_rounded,
                    label: '添加个人安排',
                    onPressed:
                        busy || widget.store.notebook.entries.length >= 500
                            ? null
                            : () => edit(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '最多保存 500 项；右滑可快速完成或恢复，左滑可删除，勾选完成或删除后将自动移除该项未来提醒。',
                    style: journal.metadata,
                  ),
                ]));
      });
}

class _AgendaEntryRow extends StatelessWidget {
  const _AgendaEntryRow({
    required this.entry,
    required this.now,
    required this.busy,
    required this.onToggleDone,
    required this.onTap,
    required this.onLongPress,
  });

  final ManualEntry entry;
  final DateTime now;
  final bool busy;
  final VoidCallback onToggleDone;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final isExam = entry.kind == ManualEntry.kindExam;
    final at = entry.at;
    final overdue = !entry.done && at != null && !at.isAfter(now);
    final overdueDays = overdue ? now.difference(at).inDays : 0;
    final overdueLabel = overdueDays > 0 ? '已逾期$overdueDays天' : '已逾期';
    final metaParts = <String>[
      if (entry.course.trim().isNotEmpty) entry.course.trim(),
      _compactAgendaTime(at, now),
      if (entry.location.trim().isNotEmpty) entry.location.trim(),
      if (entry.attachments.isNotEmpty) '附件 ${entry.attachments.length}',
    ];

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: busy ? null : onTap,
        onLongPress: busy ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                key: ValueKey('agenda-toggle-${entry.id}'),
                tooltip: entry.done ? '恢复为未完成' : '标记完成',
                constraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
                padding: EdgeInsets.zero,
                onPressed: busy ? null : onToggleDone,
                icon: Icon(
                  entry.done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: entry.done ? journal.todoGreen : journal.muted,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      style: entry.done
                          ? journal.entryTitle.copyWith(
                              color: journal.muted,
                              decoration: TextDecoration.lineThrough,
                            )
                          : journal.entryTitle,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CourseworkStatusPill(
                          label: isExam ? '考试' : '待办',
                          tone: isExam
                              ? CourseworkPillTone.exam
                              : CourseworkPillTone.todo,
                        ),
                        if (overdue)
                          CourseworkStatusPill(
                            label: overdueLabel,
                            tone: CourseworkPillTone.overdue,
                          ),
                        Text(
                          metaParts.join(' · '),
                          style: journal.metadata.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                    if (!entry.done && entry.note.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.note.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: journal.metadata.copyWith(fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: journal.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ManualEntryEditor extends StatefulWidget {
  const ManualEntryEditor({
    super.key,
    required this.store,
    this.entry,
    this.entryId,
    this.initialDay,
    this.initialCourse,
    this.initialKind,
    this.routeScope = '/agenda',
  });
  final AssignmentStore store;
  final ManualEntry? entry;
  final String? entryId;
  final DateTime? initialDay;

  /// Prefills the course for a new entry, e.g. from an empty course filter.
  final String? initialCourse;
  final String? initialKind;
  final String routeScope;
  @override
  State<ManualEntryEditor> createState() => _EditorState();
}

class _EditorState extends State<ManualEntryEditor> {
  static DateTime _defaultAtForDay(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day, 9, 0)
          .subtract(const Duration(hours: 8))
          .toLocal();

  final form = GlobalKey<FormState>();
  final _titleFieldKey = GlobalKey<FormFieldState<String>>();
  final _timeCardKey = GlobalKey();
  final _moreOptionsCardKey = GlobalKey();
  final _minutesFieldKey = GlobalKey<FormFieldState<String>>();
  final _scrollController = ScrollController();
  Timer? _expandScrollTimer;
  Completer<void>? _expandScrollCompleter;
  late final int epoch;
  late final String? _accountHashAtStart;

  late final TextEditingController title;
  late final TextEditingController course;
  late final TextEditingController location;
  late final TextEditingController note;
  late final TextEditingController minutes;
  late String kind;
  late bool remind;
  late DateTime? at;
  ManualEntry? _entry;
  bool _missingEntry = false;
  bool busy = false;
  bool _dirty = false;
  bool _saving = false;
  bool _moreOptionsExpanded = false;
  int _lastFilledMoreCount = 0;
  UnsavedEditGuard? _leaveGuard;
  String? error;
  String? _timeError;
  List<ManualAttachment> _attachments = const [];
  final Set<String> _draftAddedPaths = {};
  String? _attachmentHint;
  String? _attachmentRoot;

  @override
  void initState() {
    super.initState();
    epoch = widget.store.accountEpoch;
    _accountHashAtStart = widget.store.accountHash;
    _entry = widget.entry ??
        (widget.entryId == null
            ? null
            : widget.store.notebook.entries
                .where((item) => item.id == widget.entryId)
                .firstOrNull);
    _missingEntry =
        widget.entry == null && widget.entryId != null && _entry == null;
    _attachments = List<ManualAttachment>.from(
      _entry?.attachments ?? const <ManualAttachment>[],
    );
    _attachmentRoot = widget.store.manualAttachmentService.cachedRootPath;
    if (_attachments.isNotEmpty) {
      unawaited(_ensureAttachmentRoot());
    }
    title = TextEditingController(text: _entry?.title);
    course = TextEditingController(
        text: _entry?.course ?? widget.initialCourse?.trim());
    location = TextEditingController(text: _entry?.location);
    note = TextEditingController(text: _entry?.note);
    final initialMinutes = _entry?.minutes ?? 0;
    minutes = TextEditingController(
      text: initialMinutes > 0 ? '$initialMinutes' : '',
    );
    kind = _entry?.kind ??
        (widget.initialKind == ManualEntry.kindExam
            ? ManualEntry.kindExam
            : ManualEntry.kindTodo);
    remind = _entry?.remind ?? false;
    at = _entry?.at ??
        (widget.initialDay == null
            ? null
            : _defaultAtForDay(widget.initialDay!));
    final hasInitialCourse = widget.initialCourse?.trim().isNotEmpty ?? false;
    final hasEntryMoreFields = _entry != null &&
        (_entry!.course.trim().isNotEmpty ||
            _entry!.location.trim().isNotEmpty ||
            _entry!.minutes > 0 ||
            _entry!.note.trim().isNotEmpty ||
            _entry!.attachments.isNotEmpty);
    _moreOptionsExpanded = hasInitialCourse || hasEntryMoreFields;
    _lastFilledMoreCount = _filledMoreCount;
    title.addListener(_markDirty);
    for (final c in [course, location, note, minutes]) {
      c.addListener(_handleOptionalFieldChanged);
    }
  }

  Future<void> _ensureAttachmentRoot() async {
    final root = await widget.store.manualAttachmentService.getAttachmentRoot();
    if (!mounted || root == null || root == _attachmentRoot) return;
    setState(() => _attachmentRoot = root);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final guard = UnsavedEditGuardScope.maybeOf(context);
    if (identical(guard, _leaveGuard)) return;
    _leaveGuard?.unregister(this);
    _leaveGuard = guard;
    _leaveGuard?.register(
      this,
      routeScope: widget.routeScope,
      hasUnsavedChanges: () => _dirty || _saving,
      draftRevision: () =>
          '${title.text}|${course.text}|${location.text}|${note.text}|'
          '${minutes.text}|$kind|$remind|$at|'
          '${_attachments.map((a) => a.relativePath).join(',')}',
      blocksNavigation: () => _saving,
      confirmDiscard: _confirmDiscard,
      isStale: () =>
          !widget.store.isAuthenticated ||
          widget.store.accountEpoch != epoch ||
          widget.store.accountHash != _accountHashAtStart,
    );
  }

  Future<bool> _requestLeave() async {
    final guard = _leaveGuard;
    if (guard != null) return guard.confirmLeave();
    return _confirmDiscard();
  }

  int get _filledMoreCount {
    var count = 0;
    if (course.text.trim().isNotEmpty) count++;
    if (location.text.trim().isNotEmpty) count++;
    final parsedMinutes = int.tryParse(minutes.text.trim()) ?? 0;
    if (parsedMinutes > 0) count++;
    if (note.text.trim().isNotEmpty) count++;
    if (_attachments.isNotEmpty) count++;
    return count;
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  void _handleOptionalFieldChanged() {
    final nextCount = _filledMoreCount;
    final dirtyChanged = !_dirty;
    if (dirtyChanged || nextCount != _lastFilledMoreCount) {
      _lastFilledMoreCount = nextCount;
      if (mounted) {
        setState(() => _dirty = true);
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_saving) {
      setState(() => error = '个人安排正在保存，请稍候再离开');
      return false;
    }
    final result = await showUnsavedEditDialog(
      context: context,
      guard: _leaveGuard,
      builder: (c) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('这项个人安排的修改尚未保存。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('继续编辑')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('放弃修改')),
        ],
      ),
    );
    return result == true;
  }

  @override
  void dispose() {
    if (_draftAddedPaths.isNotEmpty) {
      final cleanup = _draftAddedPaths.toList();
      _draftAddedPaths.clear();
      unawaited(widget.store.manualAttachmentService.deleteFiles(cleanup));
    }
    _leaveGuard?.unregister(this);
    _expandScrollTimer?.cancel();
    _expandScrollTimer = null;
    if (_expandScrollCompleter != null &&
        !_expandScrollCompleter!.isCompleted) {
      _expandScrollCompleter!.complete();
    }
    _expandScrollCompleter = null;
    _scrollController.dispose();
    title.removeListener(_markDirty);
    title.dispose();
    for (final c in [course, location, note, minutes]) {
      c.removeListener(_handleOptionalFieldChanged);
      c.dispose();
    }
    super.dispose();
  }

  int get _remainingImageSlots => (ManualAttachment.maxImagesPerEntry -
          _attachments.where((a) => a.isImage).length)
      .clamp(0, ManualAttachment.maxImagesPerEntry);

  int get _remainingTotalSlots =>
      (ManualAttachment.maxAttachmentsPerEntry - _attachments.length)
          .clamp(0, ManualAttachment.maxAttachmentsPerEntry);

  void _acceptAttachments(
    List<ManualAttachment> incoming, {
    String? hint,
  }) {
    final kept = <ManualAttachment>[..._attachments];
    final rejectedPaths = <String>[];
    var imageCount = kept.where((a) => a.isImage).length;
    var capHit = false;
    var addedAny = false;
    for (final item in incoming) {
      if (kept.length >= ManualAttachment.maxAttachmentsPerEntry ||
          (item.isImage && imageCount >= ManualAttachment.maxImagesPerEntry)) {
        capHit = true;
        rejectedPaths.add(item.relativePath);
        continue;
      }
      if (kept.any((existing) => existing.relativePath == item.relativePath)) {
        continue;
      }
      kept.add(item);
      _draftAddedPaths.add(item.relativePath);
      addedAny = true;
      if (item.isImage) imageCount++;
    }
    if (rejectedPaths.isNotEmpty) {
      unawaited(
          widget.store.manualAttachmentService.deleteFiles(rejectedPaths));
    }
    setState(() {
      _attachments = kept;
      _lastFilledMoreCount = _filledMoreCount;
      if (addedAny) _dirty = true;
      _attachmentHint = capHit ? '已达到附件数量上限，超出部分未添加' : hint;
    });
    if (kept.isNotEmpty) {
      unawaited(_ensureAttachmentRoot());
    }
  }

  Future<void> _capturePhoto() async {
    if (busy || _remainingImageSlots <= 0 || _remainingTotalSlots <= 0) {
      return;
    }
    setState(() {
      busy = true;
      _attachmentHint = null;
    });
    try {
      final result = await widget.store.manualAttachmentService.capturePhoto();
      if (!mounted) {
        final att = result.attachment;
        if (att != null) {
          unawaited(widget.store.manualAttachmentService
              .deleteFiles([att.relativePath]));
        }
        return;
      }
      if (result.attachment != null) {
        _acceptAttachments([result.attachment!]);
      } else if (!result.cancelled) {
        setState(() => _attachmentHint = result.message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickImages() async {
    if (busy) return;
    final allowed = _remainingImageSlots < _remainingTotalSlots
        ? _remainingImageSlots
        : _remainingTotalSlots;
    if (allowed <= 0) {
      setState(() => _attachmentHint = '图片已达 9 张上限');
      return;
    }
    setState(() {
      busy = true;
      _attachmentHint = null;
    });
    try {
      final result = await widget.store.manualAttachmentService
          .pickImages(maxCount: allowed);
      if (!mounted) {
        if (result.attachments.isNotEmpty) {
          unawaited(widget.store.manualAttachmentService.deleteFiles(
            result.attachments.map((a) => a.relativePath),
          ));
        }
        return;
      }
      if (result.attachments.isNotEmpty) {
        _acceptAttachments(result.attachments, hint: result.message);
      } else if (result.message != null) {
        setState(() => _attachmentHint = result.message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickAttachmentFile() async {
    if (busy) return;
    if (_remainingTotalSlots <= 0) {
      setState(() => _attachmentHint = '已达单条 20 个附件上限');
      return;
    }
    setState(() {
      busy = true;
      _attachmentHint = null;
    });
    try {
      final result =
          await widget.store.manualAttachmentService.pickAttachmentFile();
      if (!mounted) {
        final att = result.attachment;
        if (att != null) {
          unawaited(widget.store.manualAttachmentService
              .deleteFiles([att.relativePath]));
        }
        return;
      }
      if (result.attachment != null) {
        _acceptAttachments([result.attachment!]);
      } else if (!result.cancelled) {
        setState(() => _attachmentHint = result.message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _removeAttachment(ManualAttachment target) {
    if (busy) return;
    setState(() {
      _attachments = [
        for (final item in _attachments)
          if (item.relativePath != target.relativePath) item,
      ];
      _lastFilledMoreCount = _filledMoreCount;
      _dirty = true;
      _attachmentHint = null;
    });
    if (_draftAddedPaths.remove(target.relativePath)) {
      unawaited(widget.store.manualAttachmentService
          .deleteFiles([target.relativePath]));
    }
  }

  Future<void> chooseDate() async {
    final anchor = at ??
        (widget.initialDay == null
            ? DateTime.now()
            : _defaultAtForDay(widget.initialDay!));
    final start = AssignmentQuery.beijing(anchor);
    final d = await showDatePicker(
        context: context,
        initialDate: DateTime(start.year, start.month, start.day),
        firstDate: DateTime(2000),
        lastDate: DateTime(2200, 12, 31));
    if (!mounted || d == null) return;
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: start.hour, minute: start.minute));
    if (mounted && t != null) {
      setState(() {
        at = DateTime.utc(d.year, d.month, d.day, t.hour, t.minute)
            .subtract(const Duration(hours: 8));
        _timeError = null;
        _dirty = true;
      });
    }
  }

  Future<void> chooseCourse() async {
    final names = <String>[];
    final seen = <String>{};
    for (final item in widget.store.courses) {
      if (seen.add(item.name)) names.add(item.name);
    }
    final picked = await showJournalPickerSheet<String>(
      context,
      title: '选择课程',
      selectedValue: course.text.trim(),
      searchable: names.length > 5,
      searchHint: '搜索课程...',
      displayPrefs: widget.store.display,
      options: [
        for (final name in names)
          JournalPickerOption<String>(value: name, label: name),
      ],
    );
    if (picked != null && mounted) {
      setState(() {
        course.text = picked;
        _dirty = true;
      });
    }
  }

  Future<void> toggleDone() async {
    final entry = _entry;
    if (entry == null || busy) return;
    final nextDone = !entry.done;
    setState(() => busy = true);
    final ok = await widget.store.saveNotebook(
      (n) => n.withEntries([
        for (final item in n.entries)
          item.id == entry.id ? item.completed(nextDone) : item,
      ]),
      epoch,
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      if (ok) _entry = entry.completed(nextDone);
    });
    if (ok) {
      showJournalMessage(context, nextDone ? '已标记完成' : '已恢复未完成');
    }
  }

  Future<void> deleteEntry() async {
    final entry = _entry;
    if (entry == null || busy) return;
    final journal = Journal.of(context);
    final editorRoute = ModalRoute.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这项个人安排？'),
        content: Text(entry.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: journal.berry,
              foregroundColor: journal.onPrimaryFill,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      _saving = true;
    });
    final ok = await widget.store.saveNotebook(
      (n) => n.withEntries([
        for (final item in n.entries)
          if (item.id != entry.id) item,
      ]),
      epoch,
    );
    if (ok) {
      final discardedDrafts = _draftAddedPaths.toList();
      _draftAddedPaths.clear();
      if (discardedDrafts.isNotEmpty) {
        unawaited(
          widget.store.manualAttachmentService.deleteFiles(discardedDrafts),
        );
      }
      _saving = false;
      _dirty = false;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !ok) {
      if (mounted) {
        setState(() {
          busy = false;
          _saving = false;
          if (!ok) {
            error = widget.store.saveFeedback(
              false,
              successMessage: '',
              failureMessage: '删除失败，请核对账号后重试',
              warnings: widget.store.manualSaveWarnings,
            );
          }
        });
      }
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (editorRoute?.settings is Page && router != null && router.canPop()) {
      router.pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget? _buildCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) {
    if (maxLength == null) return null;
    final threshold = (maxLength * 0.8).floor();
    if (currentLength < threshold) return null;
    final journal = Journal.of(context);
    return Text(
      '$currentLength / $maxLength',
      style: journal.metadata.copyWith(
        fontSize: 12,
        color: currentLength >= maxLength ? journal.berry : journal.subtle,
      ),
    );
  }

  Future<void> _waitForExpansionAnimation() {
    _expandScrollTimer?.cancel();
    if (_expandScrollCompleter != null &&
        !_expandScrollCompleter!.isCompleted) {
      _expandScrollCompleter!.complete();
    }
    final completer = Completer<void>();
    _expandScrollCompleter = completer;
    _expandScrollTimer = Timer(const Duration(milliseconds: 250), () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> _ensureTargetVisible(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null || !targetContext.mounted) return;
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.25,
      duration: JournalLayout.motionDuration(context),
      curve: JournalMotion.easeOut,
    );
  }

  Future<void> _scrollToFirstInvalidField({
    required bool missingExamTime,
  }) async {
    if (_titleFieldKey.currentState?.hasError ?? false) {
      await _ensureTargetVisible(_titleFieldKey);
      return;
    }
    if (missingExamTime) {
      await _ensureTargetVisible(_timeCardKey);
      return;
    }
    if (_minutesFieldKey.currentState?.hasError ?? false) {
      final wasCollapsed = !_moreOptionsExpanded;
      if (wasCollapsed) {
        setState(() => _moreOptionsExpanded = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await _ensureTargetVisible(_moreOptionsCardKey);
        if (!mounted) return;
        if (!JournalMotion.isReducedMotion(context)) {
          await _waitForExpansionAnimation();
          if (!mounted) return;
        }
      }
      await _ensureTargetVisible(_minutesFieldKey);
    }
  }

  Future<void> save() async {
    if (busy) return;
    final formValid = form.currentState!.validate();
    final missingExamTime = kind == ManualEntry.kindExam && at == null;
    if (!formValid || missingExamTime) {
      setState(() {
        _timeError = missingExamTime ? '请填写考试日期和时间' : null;
      });
      await _scrollToFirstInvalidField(missingExamTime: missingExamTime);
      return;
    }
    final editorRoute = ModalRoute.of(context);
    setState(() {
      busy = true;
      _saving = true;
      error = null;
      _timeError = null;
    });
    final trimmedMinutes = minutes.text.trim();
    final parsedMinutes =
        trimmedMinutes.isEmpty ? 0 : int.parse(trimmedMinutes);
    final e = ManualEntry(
        id: _entry?.id ?? 'm${DateTime.now().microsecondsSinceEpoch}',
        title: title.text.trim(),
        kind: kind,
        course: course.text.trim(),
        location: location.text.trim(),
        note: note.text,
        minutes: parsedMinutes,
        at: at,
        remind: at != null && remind,
        done: _entry?.done ?? false,
        updatedAt: DateTime.now(),
        attachments: _attachments);
    final ok = await widget.store.saveNotebook(
        (n) => n.withEntries([...n.entries.where((v) => v.id != e.id), e]),
        epoch);
    if (ok) {
      final savedPaths = {for (final item in e.attachments) item.relativePath};
      final discardedDrafts =
          _draftAddedPaths.where((path) => !savedPaths.contains(path)).toList();
      _draftAddedPaths.clear();
      if (discardedDrafts.isNotEmpty) {
        unawaited(
          widget.store.manualAttachmentService.deleteFiles(discardedDrafts),
        );
      }
      _saving = false;
      _dirty = false;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final manualWarnings = widget.store.manualSaveWarnings;
    final feedback = widget.store.saveFeedback(
      ok,
      successMessage: '个人安排已保存',
      failureMessage: '保存失败，输入仍保留，请核对账号后重试',
      warnings: manualWarnings,
    );
    if (ok && editorRoute?.isCurrent != false) {
      showJournalMessage(context, feedback);
      final router = GoRouter.maybeOf(context);
      if (editorRoute?.settings is Page && router != null && router.canPop()) {
        router.pop();
      } else {
        Navigator.pop(context);
      }
      return;
    }
    setState(() {
      busy = false;
      _saving = false;
      error = feedback;
    });
  }

  Widget _buildReminderDisabledRow(JournalPalette journal) {
    final compact = JournalLayout.isLargeText(context);
    final titleCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '提前30分钟提醒',
          style: journal.entryTitle.copyWith(color: journal.muted),
        ),
        const SizedBox(height: 2),
        Text(
          '设置时间后可开启提醒',
          style: journal.metadata,
        ),
      ],
    );
    final setTimeButton = TextButton(
      key: const ValueKey('manual-set-time-for-reminder'),
      onPressed: busy ? null : chooseDate,
      child: const Text('去设置时间'),
    );
    const disabledSwitch = Switch(
      value: false,
      onChanged: null,
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: titleCol),
                const SizedBox(width: 8),
                disabledSwitch,
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: setTimeButton,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: titleCol),
          const SizedBox(width: 8),
          setTimeButton,
          disabledSwitch,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    if (_missingEntry) {
      return Scaffold(
        backgroundColor: journal.paper,
        appBar: AppBar(
          backgroundColor: journal.paper,
          title: const Text('个人安排不存在'),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              JournalGroupedCard(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    '这条个人安排已被删除，无法继续编辑。',
                    style: journal.metadata.copyWith(color: journal.ink),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              JournalPrimaryButton(
                label: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      );
    }
    final filledMoreCount = _filledMoreCount;
    return PopScope(
        canPop: !_dirty && !_saving,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || (!_dirty && !_saving)) return;
          final editorRoute = ModalRoute.of(context);
          final router = GoRouter.maybeOf(context);
          final guard = _leaveGuard;
          if (editorRoute?.settings is Page &&
              guard != null &&
              router != null &&
              router.canPop()) {
            await guard.navigate(
              owner: this,
              isCurrent: () => mounted,
              action: () {
                if (!context.mounted) return;
                if (router.canPop()) router.pop();
              },
            );
            return;
          }
          final leave = await _requestLeave();
          if (leave && context.mounted) Navigator.of(context).pop();
        },
        child: Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              title: Text(_entry == null ? '添加个人安排' : '编辑个人安排'),
            ),
            body: Form(
                key: form,
                child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        JournalGroupedCard(
                          padding: const EdgeInsets.all(14),
                          children: [
                            Column(
                              children: [
                                TextFormField(
                                    key: _titleFieldKey,
                                    controller: title,
                                    enabled: !busy,
                                    maxLength: 200,
                                    buildCounter: _buildCounter,
                                    decoration:
                                        const InputDecoration(labelText: '标题'),
                                    validator: (s) =>
                                        s == null || s.trim().isEmpty
                                            ? '请填写标题'
                                            : null),
                                const SizedBox(height: 10),
                                _AgendaKindSegment(
                                  selected: kind,
                                  enabled: !busy,
                                  onChanged: (next) {
                                    JournalMotion.tap(widget.store.display);
                                    setState(() {
                                      kind = next;
                                      if (kind != ManualEntry.kindExam) {
                                        _timeError = null;
                                      }
                                      _dirty = true;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        JournalGroupedCard(
                          key: _timeCardKey,
                          dividerIndent: 16,
                          children: [
                            ListTile(
                                title: Text(manualTime(at),
                                    style: journal.entryTitle),
                                subtitle: Text(
                                  kind == 'exam' ? '考试必须填写时间' : '待办可以暂不安排时间',
                                  style: journal.metadata,
                                ),
                                trailing: const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 19),
                                onTap: busy ? null : chooseDate),
                            if (_timeError != null)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                child: Text(
                                  _timeError!,
                                  key: const ValueKey('manual-time-error'),
                                  style: journal.metadata
                                      .copyWith(color: journal.berry),
                                ),
                              ),
                            if (at != null && kind == 'todo')
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  child: TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => setState(() {
                                                at = null;
                                                remind = false;
                                                _dirty = true;
                                              }),
                                      child: const Text('清除时间')),
                                ),
                              ),
                            if (at == null)
                              _buildReminderDisabledRow(journal)
                            else
                              SwitchListTile(
                                  title: Text('提前30分钟提醒',
                                      style: journal.entryTitle),
                                  subtitle: Text('受通知权限和系统调度限制',
                                      style: journal.metadata),
                                  value: remind,
                                  onChanged: busy
                                      ? null
                                      : (v) => setState(() {
                                            remind = v;
                                            _dirty = true;
                                          })),
                            if (_entry != null)
                              JournalGroupTile(
                                icon: Icons.notifications_active_outlined,
                                title: '提醒状态',
                                onTap: busy
                                    ? null
                                    : () {
                                        final router =
                                            GoRouter.maybeOf(context);
                                        if (router != null) {
                                          router.push(
                                            '/reminder-status/manual/${Uri.encodeComponent(_entry!.id)}?unsaved=${_dirty ? 1 : 0}',
                                          );
                                        } else {
                                          Navigator.of(context,
                                                  rootNavigator: true)
                                              .push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  ReminderStatusScreen(
                                                store: widget.store,
                                                kind: 'manual',
                                                id: _entry!.id,
                                                hasUnsavedEdits: _dirty,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        JournalGroupedCard(
                          key: _moreOptionsCardKey,
                          children: [
                            JournalExpansionTile(
                              key: const ValueKey('manual-more-options-tile'),
                              toggleKey:
                                  const ValueKey('manual-more-options-toggle'),
                              expanded: _moreOptionsExpanded,
                              maintainState: true,
                              title: Text(
                                '更多选项',
                                style: journal.section.copyWith(fontSize: 15.5),
                              ),
                              subtitle: Text(
                                filledMoreCount > 0
                                    ? '课程、地点、用时、备注与附件（已填 $filledMoreCount 项）'
                                    : '课程、地点、用时、备注与附件',
                                style: journal.metadata,
                              ),
                              tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(14, 4, 14, 14),
                              onExpansionChanged: (value) {
                                JournalMotion.tap(widget.store.display);
                                setState(() => _moreOptionsExpanded = value);
                              },
                              children: [
                                Divider(
                                  height: 0.6,
                                  thickness: 0.6,
                                  color: journal.divider,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: course,
                                    enabled: !busy,
                                    maxLength: 200,
                                    buildCounter: _buildCounter,
                                    decoration: InputDecoration(
                                      labelText: '课程（可选）',
                                      suffixIcon: widget.store.courses.isEmpty
                                          ? null
                                          : IconButton(
                                              tooltip: '从我的课程选择',
                                              onPressed:
                                                  busy ? null : chooseCourse,
                                              icon: const Icon(
                                                Icons.menu_book_outlined,
                                              ),
                                            ),
                                    )),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: location,
                                    enabled: !busy,
                                    maxLength: 200,
                                    buildCounter: _buildCounter,
                                    decoration: const InputDecoration(
                                        labelText: '地点（可选）')),
                                const SizedBox(height: 12),
                                TextFormField(
                                    key: _minutesFieldKey,
                                    controller: minutes,
                                    enabled: !busy,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '预计用时（可选）',
                                      hintText: '例如 30（分钟，可选）',
                                    ),
                                    validator: (s) {
                                      final trimmed = s?.trim() ?? '';
                                      if (trimmed.isEmpty) return null;
                                      final v = int.tryParse(trimmed);
                                      return v == null || v < 0 || v > 1440
                                          ? '请输入0–1440的整数'
                                          : null;
                                    }),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: note,
                                    enabled: !busy,
                                    maxLength: 10000,
                                    buildCounter: _buildCounter,
                                    minLines: 3,
                                    maxLines: 8,
                                    decoration:
                                        const InputDecoration(labelText: '备注')),
                                const SizedBox(height: 12),
                                ManualAttachmentPickerSection(
                                  attachments: _attachments,
                                  service: widget.store.manualAttachmentService,
                                  busy: busy,
                                  rootPath: _attachmentRoot,
                                  statusHint: _attachmentHint,
                                  onCapturePhoto: _capturePhoto,
                                  onPickImages: _pickImages,
                                  onPickFile: _pickAttachmentFile,
                                  onRemove: _removeAttachment,
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_entry != null) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: busy ? null : toggleDone,
                                icon: Icon(
                                  _entry!.done
                                      ? Icons.undo_rounded
                                      : Icons.check_rounded,
                                ),
                                label: Text(
                                  _entry!.done ? '恢复未完成' : '标记完成',
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: journal.berry,
                                ),
                                onPressed: busy ? null : deleteEntry,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('删除个人安排'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ))),
            bottomNavigationBar: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Material(
                color: journal.paper,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: journal.divider, width: 0.8),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Semantics(
                                key: const ValueKey('manual-editor-feedback'),
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: journal.metadata
                                      .copyWith(color: journal.berry),
                                ),
                              ),
                            ),
                          JournalPrimaryButton(
                            buttonKey: const ValueKey('manual-editor-save'),
                            loading: busy,
                            label: busy ? '正在保存…' : '保存个人安排',
                            onPressed: busy ? null : save,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )));
  }
}

class _AgendaKindSegment extends StatelessWidget {
  const _AgendaKindSegment({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    Widget item(String value, String label) {
      final active = selected == value;
      return Expanded(
        child: GestureDetector(
          onTap: enabled ? () => onChanged(value) : null,
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
          item('todo', '待办'),
          item('exam', '考试'),
        ],
      ),
    );
  }
}
