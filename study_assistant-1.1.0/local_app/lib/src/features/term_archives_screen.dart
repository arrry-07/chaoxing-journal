import 'package:flutter/material.dart';

import '../app/journal.dart';
import '../models/study_notebook.dart';
import '../services/assignment_store.dart';
import 'manual_agenda_screen.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/journal_info_popover.dart';

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '将当前账号本机作业、个人笔记、计划与手动安排存为只读快照，原记录保持不变。',
                style: Journal.of(c).metadata,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '名称，例如 2026秋季学期'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                Navigator.pop(c, name.text.trim());
              }
            },
            child: const Text('保存快照'),
          ),
        ],
      ),
    );
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
            ...widget.store.hiddenAssignments,
          ].where((a) => a.hasCourseTaskIdentity).toList(),
          personal: widget.store.personal,
          entries: n.entries,
        ),
      ]),
      epoch,
    );
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
      builder: (c) {
        final journal = Journal.of(c);
        return AlertDialog(
          title: const Text('删除这份学期快照？'),
          content: Text('${term.label}\n只删除快照，当前作业与个人记录保持原样。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: journal.berry,
                foregroundColor: journal.onPrimaryFill,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除快照'),
            ),
          ],
        );
      },
    );
    if (!mounted || yes != true) return;
    setState(() => busy = true);
    final ok = await widget.store.saveNotebook(
      (n) => n.withTerms(n.terms.where((v) => v.id != term.id).toList()),
      epoch,
    );
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
        builder: (context, _) {
          final journal = Journal.of(context);
          final terms = widget.store.notebook.terms.reversed.toList();
          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              title: const Text('学期归档'),
              actions: const [
                JournalInfoButton(
                  title: '学期快照说明',
                  items: [
                    '按你命名的学期保存只读本机快照，不会随后续同步变化，也不是服务端提交证明。',
                    '最多保存 12 份快照；快照不保存作业访问链接、说明正文或本地文件关联。',
                    '个人资料链接会保留并纳入加密备份。',
                  ],
                ),
                SizedBox(width: 4),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                if (terms.isEmpty)
                  JournalGroupedCard(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Text(
                        '还没有学期快照。保存前建议先完成一次同步。',
                        style: journal.metadata,
                      ),
                    ],
                  )
                else
                  JournalGroupedCard(
                    children: [
                      for (final term in terms)
                        ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(
                            16,
                            6,
                            8,
                            6,
                          ),
                          title: Text(term.label, style: journal.entryTitle),
                          subtitle: Text(
                            '${manualTime(term.createdAt)} · ${term.rows.length} 份作业 · ${term.entries.length} 项安排',
                            style: journal.metadata.copyWith(fontSize: 12.5),
                          ),
                          onTap: busy
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => TermArchiveDetail(
                                        store: widget.store,
                                        id: term.id,
                                      ),
                                    ),
                                  ),
                          trailing: IconButton(
                            tooltip: '删除学期快照',
                            onPressed: busy ? null : () => remove(term),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: journal.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: journal.sage,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message!,
                        style: journal.metadata.copyWith(color: journal.ink),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                JournalPrimaryButton(
                  icon: Icons.inventory_2_outlined,
                  label: '保存当前学期快照',
                  onPressed: busy || widget.store.notebook.terms.length >= 12
                      ? null
                      : create,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '只读快照不作提交证明，最多保留 12 份，且不含作业链接与本地文件关联。',
                    style: journal.metadata.copyWith(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class TermArchiveDetail extends StatelessWidget {
  const TermArchiveDetail({super.key, required this.store, required this.id});
  final AssignmentStore store;
  final String id;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final journal = Journal.of(context);
          final term =
              store.notebook.terms.where((t) => t.id == id).firstOrNull;
          final estimatedMinutes = term == null
              ? 0
              : term.plans.fold<int>(0, (v, p) => v + p.minutes) +
                  term.entries.fold<int>(0, (v, e) => v + e.minutes);
          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              title: Text(term?.label ?? '学期快照'),
            ),
            body: term == null
                ? Center(
                    child: Text(
                      '当前账号未找到这份快照，请返回核对。',
                      style: journal.metadata,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    children: [
                      JournalGroupedCard(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '只读快照 · ${manualTime(term.createdAt)}',
                                style: journal.entryTitle,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '作业 ${term.rows.length} 份 · 已完成 ${term.rows.where((r) => r.completed).length} 份 · 提交未知 ${term.rows.where((r) => r.status == 'unknown').length} 份',
                                style: journal.metadata
                                    .copyWith(color: journal.ink),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '个人安排 ${term.entries.length} 项 · 计划 ${term.plans.length} 项 · 预计总计 $estimatedMinutes 分钟',
                                style: journal.metadata
                                    .copyWith(color: journal.ink),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '预计耗时来自手动填写，平台状态为保存时的本机记录。',
                                style:
                                    journal.metadata.copyWith(fontSize: 12.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      JournalGroupedCard(
                        title: '作业与个人笔记（${term.rows.length}）',
                        children: term.rows.isEmpty
                            ? [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text('无作业记录', style: journal.metadata),
                                ),
                              ]
                            : [
                                for (final row in term.rows)
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      title: Text(
                                        row.title,
                                        style: journal.entryTitle,
                                      ),
                                      subtitle: Text(
                                        '${row.course} · ${row.completed ? '已完成' : row.status == 'unknown' ? '提交未知' : '未完成'}',
                                        style: journal.metadata,
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            0,
                                            16,
                                            14,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                row.deadline == null
                                                    ? '截止时间未确认 / 无截止'
                                                    : manualTime(row.deadline),
                                                style: journal.metadata,
                                              ),
                                              if (row.note.note.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                SelectableText(
                                                  row.note.note,
                                                  style: journal.metadata
                                                      .copyWith(
                                                          color: journal.ink),
                                                ),
                                              ],
                                              for (final step in row.note.steps)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Text(
                                                    '${step.done ? '已勾选' : '未勾选'} · ${step.text}',
                                                    style: journal.metadata,
                                                  ),
                                                ),
                                              for (final link in row.note.links)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 6),
                                                  child: SelectableText(
                                                    '${link.label}\n${link.url}',
                                                    style: journal.metadata,
                                                  ),
                                                ),
                                              if (row.note.note.isEmpty &&
                                                  row.note.steps.isEmpty &&
                                                  row.note.links.isEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Text(
                                                    '无个人笔记',
                                                    style: journal.metadata,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                      ),
                      if (term.entries.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        JournalGroupedCard(
                          title: '个人安排（${term.entries.length}）',
                          children: [
                            for (final entry in term.entries)
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                title: Text(
                                  '${entry.kind == 'exam' ? '考试' : '待办'} · ${entry.title}',
                                  style: journal.entryTitle,
                                ),
                                subtitle: Text(
                                  [
                                    '${manualTime(entry.at)} · ${entry.done ? '个人已完成' : '未完成'}',
                                    if (entry.course.isNotEmpty ||
                                        entry.location.isNotEmpty)
                                      '${entry.course} ${entry.location}'
                                          .trim(),
                                    if (entry.note.isNotEmpty) entry.note,
                                  ].join('\n'),
                                  style: journal.metadata,
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (term.plans.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        JournalGroupedCard(
                          title: '计划记录（${term.plans.length}）',
                          children: [
                            for (final plan in term.plans)
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 2,
                                ),
                                title: Text(
                                  term.rows
                                          .where(
                                              (r) => r.id == plan.assignmentId)
                                          .firstOrNull
                                          ?.title ??
                                      '快照外作业',
                                  style: journal.entryTitle,
                                ),
                                subtitle: Text(
                                  '${plan.day} · ${plan.minutes} 分钟 · ${plan.done ? '已勾选' : '未勾选'}',
                                  style: journal.metadata,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
          );
        },
      );
}
