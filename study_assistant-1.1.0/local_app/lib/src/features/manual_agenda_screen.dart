import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app/unsaved_edit_guard.dart';
import '../models/study_notebook.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import 'widgets/data_recovery_warning.dart';

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
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('删除'))
                ]));
    if (mounted && yes == true) {
      await update(
          (n) => n.withEntries(n.entries.where((v) => v.id != e.id).toList()));
    }
  }

  void edit([ManualEntry? e]) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => ManualEntryEditor(store: widget.store, entry: e)));
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
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
            appBar: AppBar(title: const Text('个人待办与考试')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              if (widget.store.recoveryWarning case final warning?) ...[
                DataRecoveryWarning(warning: warning),
                const SizedBox(height: 12),
              ],
              const Text('手动记录的个人安排，与学习通作业分开；考试时间请自行核对教务通知。'),
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
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('还没有个人安排，添加一项待办或考试。')),
              for (final e in rows) ...[
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                        value: e.done,
                        onChanged: busy
                            ? null
                            : (v) => update((n) => n.withEntries([
                                  for (final q in n.entries)
                                    q.id == e.id ? q.completed(v ?? false) : q
                                ]))),
                    title:
                        Text('${e.kind == 'exam' ? '考试' : '待办'} · ${e.title}'),
                    subtitle: Text(
                        '${manualTime(e.at)}${e.course.isEmpty ? '' : '\n${e.course}'}${e.location.isEmpty ? '' : ' · ${e.location}'}${e.minutes == 0 ? '' : '\n预计 ${e.minutes} 分钟'}${e.done ? ' · 个人已完成' : ''}'),
                    onTap: busy ? null : () => edit(e),
                    trailing: IconButton(
                        tooltip: '删除个人日程',
                        onPressed: busy ? null : () => remove(e),
                        icon: const Icon(Icons.delete_outline))),
                const Divider()
              ],
              if (message != null)
                Semantics(liveRegion: true, child: Text(message!)),
              FilledButton.icon(
                  onPressed: busy || widget.store.notebook.entries.length >= 500
                      ? null
                      : () => edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('添加个人安排')),
              const Text('最多保存500项；勾选完成或删除后将移除该项未来提醒。')
            ]));
      });
}

class ManualEntryEditor extends StatefulWidget {
  const ManualEntryEditor({super.key, required this.store, this.entry});
  final AssignmentStore store;
  final ManualEntry? entry;
  @override
  State<ManualEntryEditor> createState() => _EditorState();
}

class _EditorState extends State<ManualEntryEditor> {
  final form = GlobalKey<FormState>();
  late final int epoch;
  late final String? _accountHashAtStart;

  late final title = TextEditingController(text: widget.entry?.title);
  late final course = TextEditingController(text: widget.entry?.course);
  late final location = TextEditingController(text: widget.entry?.location);
  late final note = TextEditingController(text: widget.entry?.note);
  late final minutes =
      TextEditingController(text: '${widget.entry?.minutes ?? 0}');
  late String kind = widget.entry?.kind ?? 'todo';
  late bool remind = widget.entry?.remind ?? false;
  late DateTime? at = widget.entry?.at;
  bool busy = false;
  bool _dirty = false;
  bool _saving = false;
  UnsavedEditGuard? _leaveGuard;
  String? error;

  @override
  void initState() {
    super.initState();
    epoch = widget.store.accountEpoch;
    _accountHashAtStart = widget.store.accountHash;
    for (final c in [title, course, location, note, minutes]) {
      c.addListener(_markDirty);
    }
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
      hasUnsavedChanges: () => _dirty || _saving,
      draftRevision: () =>
          '${title.text}|${course.text}|${location.text}|${note.text}|'
          '${minutes.text}|$kind|$remind|$at',
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
    _leaveGuard?.unregister(this);
    for (final c in [title, course, location, note, minutes]) {
      c.removeListener(_markDirty);
      c.dispose();
    }
    super.dispose();
  }

  Future<void> chooseDate() async {
    final start = AssignmentQuery.beijing(at ?? DateTime.now());
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
        id: widget.entry?.id ?? 'm${DateTime.now().microsecondsSinceEpoch}',
        title: title.text.trim(),
        kind: kind,
        course: course.text.trim(),
        location: location.text.trim(),
        note: note.text,
        minutes: int.parse(minutes.text.trim()),
        at: at,
        remind: at != null && remind,
        done: widget.entry?.done ?? false);
    final ok = await widget.store.saveNotebook(
        (n) => n.withEntries([...n.entries.where((v) => v.id != e.id), e]),
        epoch);
    if (ok) {
      _saving = false;
      _dirty = false;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final feedback = widget.store.saveFeedback(
      ok,
      successMessage: '个人安排已保存',
      failureMessage: '保存失败，输入仍保留，请核对账号后重试',
    );
    if (ok && editorRoute?.isCurrent != false) {
      if (widget.store.serviceWarnings.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(feedback)));
      }
      Navigator.pop(context);
      return;
    }
    setState(() {
      busy = false;
      _saving = false;
      error = feedback;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || (!_dirty && !_saving)) return;
        final leave = await _requestLeave();
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
          appBar:
              AppBar(title: Text(widget.entry == null ? '添加个人安排' : '编辑个人安排')),
          body: Form(
              key: form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                const Text('仅记录个人安排，不会创建或提交学习通作业。所有时间使用北京时间。'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: const [
                      DropdownMenuItem(value: 'todo', child: Text('个人待办')),
                      DropdownMenuItem(value: 'exam', child: Text('手动考试'))
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                              kind = v!;
                              _dirty = true;
                            })),
                const SizedBox(height: 12),
                TextFormField(
                    controller: title,
                    enabled: !busy,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '标题'),
                    validator: (s) =>
                        s == null || s.trim().isEmpty ? '请填写标题' : null),
                TextFormField(
                    controller: course,
                    enabled: !busy,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '课程（可选）')),
                TextFormField(
                    controller: location,
                    enabled: !busy,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '地点（可选）')),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(manualTime(at)),
                    subtitle: Text(kind == 'exam' ? '考试必须填写时间' : '待办可以暂不安排时间'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: busy ? null : chooseDate),
                if (at != null && kind == 'todo')
                  TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                at = null;
                                remind = false;
                                _dirty = true;
                              }),
                      child: const Text('清除时间')),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('提前30分钟提醒'),
                    subtitle: const Text('受通知权限和系统调度限制'),
                    value: remind,
                    onChanged: busy || at == null
                        ? null
                        : (v) => setState(() {
                              remind = v;
                              _dirty = true;
                            })),
                TextFormField(
                    controller: minutes,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '预计分钟（0表示未填写）'),
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
                    decoration: const InputDecoration(labelText: '备注')),
                if (error != null)
                  Semantics(
                    key: const ValueKey('manual-editor-feedback'),
                    liveRegion: true,
                    child: Text(error!),
                  ),
                FilledButton(
                    onPressed: busy ? null : save,
                    child: Text(busy ? '正在保存…' : '保存个人安排'))
              ]))));
}
