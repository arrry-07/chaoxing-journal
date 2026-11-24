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
import 'widgets/data_recovery_warning.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_picker_sheet.dart';
import 'widgets/manual_attachment_picker_section.dart';

String manualTime(DateTime? at) => at == null
    ? '未安排时间'
    : '${DateFormat('yyyy-MM-dd HH:mm').format(AssignmentQuery.beijing(at))} 北京时间';

class ManualAgendaScreen extends StatefulWidget {
  const ManualAgendaScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<ManualAgendaScreen> createState() => _AgendaState();
}

class _AgendaState extends State<ManualAgendaScreen> {
  late final int epoch;
  @override
  void initState() {
    super.initState();
    epoch = widget.store.accountEpoch;
  }

  bool busy = false;
  String? message;
  String filter = 'all';

  Future<void> update(StudyNotebook Function(StudyNotebook) action) async {
    if (busy) return;
    setState(() => busy = true);
    final ok = await widget.store.saveNotebook(action, epoch);
    if (mounted) {
      setState(() {
        busy = false;
        message = widget.store.saveFeedback(
          ok,
          successMessage: '个人安排已保存',
          failureMessage: '个人安排保存失败，请核对账号后重试',
          warnings: widget.store.manualSaveWarnings,
        );
      });
    }
  }

  Future<void> remove(ManualEntry e) async {
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
    if (mounted && yes == true) {
      await update(
          (n) => n.withEntries(n.entries.where((v) => v.id != e.id).toList()));
    }
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final journal = Journal.of(context);
        final rows = widget.store.notebook.entries
            .where((e) => filter == 'all' || e.kind == filter)
            .toList()
          ..sort((a, b) {
            final done = (a.done ? 1 : 0).compareTo(b.done ? 1 : 0);
            return done != 0
                ? done
                : (a.at ?? DateTime.utc(2200))
                    .compareTo(b.at ?? DateTime.utc(2200));
          });
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
                  Wrap(spacing: 8, children: [
                    for (final item
                        in {'all': '全部', 'todo': '待办', 'exam': '考试'}.entries)
                      ChoiceChip(
                          label: Text(item.value),
                          selected: filter == item.key,
                          onSelected: busy
                              ? null
                              : (_) => setState(() => filter = item.key))
                  ]),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    JournalGroupedCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 22),
                      children: [
                        Text('还没有个人安排，点击下方按钮添加待办或考试。', style: journal.metadata),
                      ],
                    )
                  else
                    JournalGroupedCard(
                      dividerIndent: 52,
                      children: [
                        for (final e in rows)
                          ListTile(
                              leading: Checkbox(
                                  value: e.done,
                                  onChanged: busy
                                      ? null
                                      : (v) => update((n) => n.withEntries([
                                            for (final q in n.entries)
                                              q.id == e.id
                                                  ? q.completed(v ?? false)
                                                  : q
                                          ]))),
                              title: Text(
                                '${e.kind == 'exam' ? '考试' : '待办'} · ${e.title}',
                                style: journal.entryTitle,
                              ),
                              subtitle: Text(
                                '${manualTime(e.at)}${e.course.isEmpty ? '' : '\n${e.course}'}${e.location.isEmpty ? '' : ' · ${e.location}'}${e.minutes == 0 ? '' : '\n预计 ${e.minutes} 分钟'}${e.done ? ' · 个人已完成' : ''}',
                                style: journal.metadata,
                              ),
                              onTap: busy
                                  ? null
                                  : () {
                                      final router = GoRouter.maybeOf(context);
                                      if (router != null) {
                                        router.push(
                                          '/assignments/manual/${Uri.encodeComponent(e.id)}',
                                        );
                                      } else {
                                        Navigator.of(context,
                                                rootNavigator: true)
                                            .push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                ManualEntryDetailScreen(
                                              store: widget.store,
                                              entryId: e.id,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              trailing: IconButton(
                                  tooltip: '删除个人日程',
                                  onPressed: busy ? null : () => remove(e),
                                  icon: const Icon(
                                      Icons.delete_outline_rounded))),
                      ],
                    ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(message!, style: journal.metadata)),
                    ),
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
                    '最多保存 500 项；勾选完成或删除后将自动移除该项未来提醒。',
                    style: journal.metadata,
                  ),
                ]));
      });
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
  UnsavedEditGuard? _leaveGuard;
  String? error;
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
    minutes = TextEditingController(text: '${_entry?.minutes ?? 0}');
    kind = _entry?.kind ??
        (widget.initialKind == ManualEntry.kindExam
            ? ManualEntry.kindExam
            : ManualEntry.kindTodo);
    remind = _entry?.remind ?? false;
    at = _entry?.at ??
        (widget.initialDay == null
            ? null
            : _defaultAtForDay(widget.initialDay!));
    for (final c in [title, course, location, note, minutes]) {
      c.addListener(_markDirty);
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

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
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
    for (final c in [title, course, location, note, minutes]) {
      c.removeListener(_markDirty);
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

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (kind == 'exam' && at == null) {
      setState(() => error = '请填写考试日期和时间');
      return;
    }
    final editorRoute = ModalRoute.of(context);
    setState(() {
      busy = true;
      _saving = true;
      error = null;
    });
    final e = ManualEntry(
        id: _entry?.id ?? 'm${DateTime.now().microsecondsSinceEpoch}',
        title: title.text.trim(),
        kind: kind,
        course: course.text.trim(),
        location: location.text.trim(),
        note: note.text,
        minutes: int.parse(minutes.text.trim()),
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
      if (manualWarnings.isNotEmpty) {
        showJournalMessage(context, feedback);
      }
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
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        JournalGroupedCard(
                          padding: const EdgeInsets.all(14),
                          children: [
                            Column(
                              children: [
                                TextFormField(
                                    controller: title,
                                    enabled: !busy,
                                    maxLength: 200,
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
                                      _dirty = true;
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                    controller: course,
                                    enabled: !busy,
                                    maxLength: 200,
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
                                TextFormField(
                                    controller: location,
                                    enabled: !busy,
                                    maxLength: 200,
                                    decoration: const InputDecoration(
                                        labelText: '地点（可选）')),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        JournalGroupedCard(
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
                            SwitchListTile(
                                title:
                                    Text('提前30分钟提醒', style: journal.entryTitle),
                                subtitle: Text('受通知权限和系统调度限制',
                                    style: journal.metadata),
                                value: remind,
                                onChanged: busy || at == null
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
                          padding: const EdgeInsets.all(14),
                          children: [
                            Column(
                              children: [
                                TextFormField(
                                    controller: minutes,
                                    enabled: !busy,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: '预计分钟（0表示未填写）'),
                                    validator: (s) {
                                      final v = int.tryParse(s?.trim() ?? '');
                                      return v == null || v < 0 || v > 1440
                                          ? '请输入0–1440的整数'
                                          : null;
                                    }),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: note,
                                    enabled: !busy,
                                    maxLength: 10000,
                                    minLines: 3,
                                    maxLines: 8,
                                    decoration:
                                        const InputDecoration(labelText: '备注')),
                              ],
                            ),
                          ],
                        ),
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
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
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
                        const SizedBox(height: 16),
                        JournalPrimaryButton(
                          loading: busy,
                          label: busy ? '正在保存…' : '保存个人安排',
                          onPressed: busy ? null : save,
                        ),
                        if (_entry != null) ...[
                          const SizedBox(height: 8),
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
                    )))));
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
