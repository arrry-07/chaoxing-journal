import 'package:flutter/material.dart';
import '../models/study_notebook.dart';
import '../services/assignment_store.dart';
import 'manual_agenda_screen.dart';

class TermArchivesScreen extends StatefulWidget {
  const TermArchivesScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<TermArchivesScreen> createState() => _ArchivesState();
}

class _ArchivesState extends State<TermArchivesScreen> {
  late final int epoch;
  @override
  void initState() {
    super.initState();
    epoch = widget.store.accountEpoch;
  }

  bool busy = false;
  String? message;
  Future<void> create() async {
    final name = TextEditingController();
    final label = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('保存学期快照'),
                content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        '将当前账号本机全部正式作业、个人笔记、计划与手动安排保存为只读快照。不会删除或隐藏当前记录；请先同步核对。'),
                    TextField(
                        controller: name,
                        maxLength: 80,
                        decoration:
                            const InputDecoration(labelText: '名称，例如 2026秋季学期'))
                  ]),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        if (name.text.trim().isNotEmpty) {
                          Navigator.pop(c, name.text.trim());
                        }
                      },
                      child: const Text('保存快照'))
                ]));
    Future<void>.delayed(const Duration(milliseconds: 350), name.dispose);
    if (!mounted || label == null) return;
    setState(() => busy = true);
    final ok = await widget.store.saveNotebook(
        (n) => n.withTerms([
              ...n.terms,
              TermArchive.capture(
                  id: 't${DateTime.now().microsecondsSinceEpoch}',
                  label: label,
                  rows: [
                    ...widget.store.assignments,
                    ...widget.store.hiddenAssignments
                  ].where((a) => a.isFormal).toList(),
                  personal: widget.store.personal,
                  entries: n.entries)
            ]),
        epoch);
    if (mounted) {
      setState(() {
        busy = false;
        message = ok ? '快照已保存，当前记录保持原样。' : '保存失败，请核对账号、数量或存储空间后重试';
      });
    }
  }

  Future<void> remove(TermArchive term) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('删除这份学期快照？'),
                content: Text('${term.label}\n只删除快照，当前作业与个人记录保持原样。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('删除快照'))
                ]));
    if (!mounted || yes != true) return;
    setState(() => busy = true);
    final ok = await widget.store.saveNotebook(
        (n) => n.withTerms(n.terms.where((v) => v.id != term.id).toList()),
        epoch);
    if (mounted) {
      setState(() {
        busy = false;
        message = ok ? '快照已删除' : '删除失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('学期归档')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('按你命名的学期保存本机快照，日后回看。快照不会随同步变化，也不是服务端提交证明。'),
            const SizedBox(height: 16),
            if (widget.store.notebook.terms.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('还没有学期快照。保存前建议先完成同步。')),
            for (final term in widget.store.notebook.terms.reversed) ...[
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(term.label),
                  subtitle: Text(
                      '${manualTime(term.createdAt)}\n${term.rows.length}份作业 · ${term.entries.length}项个人安排'),
                  onTap: busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => TermArchiveDetail(
                                  store: widget.store, id: term.id))),
                  trailing: IconButton(
                      tooltip: '删除学期快照',
                      onPressed: busy ? null : () => remove(term),
                      icon: const Icon(Icons.delete_outline))),
              const Divider()
            ],
            if (message != null)
              Semantics(liveRegion: true, child: Text(message!)),
            FilledButton.icon(
                onPressed: busy || widget.store.notebook.terms.length >= 12
                    ? null
                    : create,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('保存当前学期快照')),
            const Text('最多12份快照。快照不保存作业访问链接、说明正文或本地文件关联；个人资料链接会保留并纳入加密备份。')
          ])));
}

class TermArchiveDetail extends StatelessWidget {
  const TermArchiveDetail({super.key, required this.store, required this.id});
  final AssignmentStore store;
  final String id;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final term = store.notebook.terms.where((t) => t.id == id).firstOrNull;
        return Scaffold(
            appBar: AppBar(title: Text(term?.label ?? '学期快照')),
            body: term == null
                ? const Center(child: Text('当前账号未找到这份快照，请返回核对。'))
                : ListView(padding: const EdgeInsets.all(16), children: [
                    Text('只读快照 · ${manualTime(term.createdAt)}'),
                    const SizedBox(height: 12),
                    Text(
                        '作业 ${term.rows.length} 份 · 已完成 ${term.rows.where((r) => r.completed).length} 份 · 提交未知 ${term.rows.where((r) => r.status == 'unknown').length} 份'),
                    Text(
                        '个人安排 ${term.entries.length} 项 · 计划 ${term.plans.length} 项\n用户预计总计 ${term.plans.fold<int>(0, (v, p) => v + p.minutes) + term.entries.fold<int>(0, (v, e) => v + e.minutes)} 分钟'),
                    const Text('预计分钟来自手动填写，不代表实际学习时长或成绩；平台状态是保存时的观察值。'),
                    const Divider(height: 32),
                    Text('作业与个人笔记',
                        style: Theme.of(context).textTheme.titleLarge),
                    for (final row in term.rows)
                      ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(row.title),
                          subtitle: Text(
                              '${row.course} · ${row.completed ? '已完成' : row.status == 'unknown' ? '提交未知' : '未完成'}'),
                          children: [
                            Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(row.deadline == null
                                          ? '截止时间未确认 / 无截止'
                                          : manualTime(row.deadline)),
                                      if (row.note.note.isNotEmpty)
                                        SelectableText(row.note.note),
                                      for (final step in row.note.steps)
                                        Text(
                                            '${step.done ? '已勾选' : '未勾选'} · ${step.text}'),
                                      for (final link in row.note.links)
                                        SelectableText(
                                            '${link.label}\n${link.url}'),
                                      if (row.note.note.isEmpty &&
                                          row.note.steps.isEmpty &&
                                          row.note.links.isEmpty)
                                        const Text('无个人笔记')
                                    ]))
                          ]),
                    const Divider(height: 32),
                    Text('个人安排', style: Theme.of(context).textTheme.titleLarge),
                    for (final entry in term.entries)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              '${entry.kind == 'exam' ? '考试' : '待办'} · ${entry.title}'),
                          subtitle: Text(
                              '${manualTime(entry.at)} · ${entry.done ? '个人已完成' : '未完成'}\n${entry.course} ${entry.location}\n${entry.note}')),
                    Text('计划记录', style: Theme.of(context).textTheme.titleLarge),
                    for (final plan in term.plans)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(term.rows
                                  .where((r) => r.id == plan.assignmentId)
                                  .firstOrNull
                                  ?.title ??
                              '快照外作业'),
                          subtitle: Text(
                              '${plan.day} · ${plan.minutes}分钟 · ${plan.done ? '已勾选' : '未勾选'}'))
                  ]));
      });
}
