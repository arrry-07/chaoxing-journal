import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/personal_workspace.dart';
import '../services/assignment_store.dart';

class DailyPlanScreen extends StatefulWidget {
  const DailyPlanScreen({super.key, required this.store});
  final AssignmentStore store;
  @override
  State<DailyPlanScreen> createState() => _DailyPlanState();
}

class _DailyPlanState extends State<DailyPlanScreen> {
  late String day;
  late final int epoch;
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    epoch = widget.store.accountEpoch;
    day = PersonalWorkspace.dayKey(DateTime.now());
  }

  Future<void> update(
      List<DailyPlanItem> Function(List<DailyPlanItem>) action) async {
    if (busy) return;
    setState(() => busy = true);
    final ok = await widget.store
        .savePersonal((w) => w.withPlans(action(w.plans)), epoch);
    if (mounted) {
      setState(() {
        busy = false;
        message = ok ? null : '保存失败，请检查账号后重试';
      });
    }
  }

  Future<void> add() async {
    final candidates = widget.store.formalAssignments
        .where((a) =>
            !a.isCompleted &&
            !widget.store.personal.plans
                .any((p) => p.day == day && p.assignmentId == a.id))
        .toList();
    if (candidates.isEmpty) {
      setState(() => message = '没有可添加的作业，请先同步，或查看其他日期。');
      return;
    }
    final id = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(c).height * 0.65,
                child: Column(children: [
                  const Padding(
                      padding: EdgeInsets.all(16), child: Text('选择准备完成的作业')),
                  Expanded(
                      child: ListView(children: [
                    for (final a in candidates)
                      ListTile(
                          title: Text(a.title),
                          subtitle: Text(a.courseName),
                          onTap: () => Navigator.pop(c, a.id))
                  ]))
                ]))));
    if (!mounted || id == null) return;
    await minutes(id);
  }

  Future<void> minutes(String id, {DailyPlanItem? existing}) async {
    final controller =
        TextEditingController(text: '${existing?.minutes ?? 30}');
    String? error;
    final value = await showDialog<int>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: Text(existing == null ? '预计需要多久？' : '调整预计耗时'),
                    content: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: '分钟（1–1440）', errorText: error)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () {
                            final v = int.tryParse(controller.text.trim());
                            if (v == null || v < 1 || v > 1440) {
                              set(() => error = '请输入1–1440之间的整数');
                              return;
                            }
                            Navigator.pop(c, v);
                          },
                          child: const Text('保存'))
                    ])));
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (!mounted || value == null) return;
    await update((plans) => [
          ...plans.where((p) => p.day != day || p.assignmentId != id),
          DailyPlanItem(id, day, value, done: existing?.done ?? false)
        ]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final plans =
            widget.store.personal.plans.where((p) => p.day == day).toList();
        final remaining =
            plans.where((p) => !p.done).fold<int>(0, (v, p) => v + p.minutes);
        return Scaffold(
            appBar: AppBar(title: const Text('每日计划')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final d = DateTime.parse(day);
                          final selected = await showDatePicker(
                              context: context,
                              initialDate: d,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2200, 12, 31));
                          if (mounted && selected != null) {
                            setState(() => day =
                                '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}');
                          }
                        },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('$day · 选择日期')),
              Text(
                  '${plans.where((p) => p.done).length}/${plans.length} 项个人计划已完成 · 预计剩余 $remaining 分钟',
                  style: Theme.of(context).textTheme.titleMedium),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      '完成勾选只记录你的计划进度，不表示学习通作业已提交。未完成的计划会保留在原日期，不会自动转成逾期作业。')),
              if (plans.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('这一天还没有计划。选两三份作业，给自己留出完成的时间。')),
              for (final p in plans)
                Column(children: [
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: p.done,
                      onChanged: busy
                          ? null
                          : (v) => update((items) => items
                              .map((q) => q.day == day &&
                                      q.assignmentId == p.assignmentId
                                  ? DailyPlanItem(
                                      q.assignmentId, q.day, q.minutes,
                                      done: v ?? false)
                                  : q)
                              .toList()),
                      title: Text(
                          widget.store.findAssignment(p.assignmentId)?.title ??
                              '本机未找到此作业，请同步核对'),
                      subtitle: Text(
                          '${widget.store.findAssignment(p.assignmentId)?.courseName ?? ''}\n预计 ${p.minutes} 分钟 · 平台：${widget.store.findAssignment(p.assignmentId)?.statusLabel ?? '待核对'}')),
                  Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => context.push(
                                '/assignments/${Uri.encodeComponent(p.assignmentId)}'),
                        child: const Text('查看作业')),
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => minutes(p.assignmentId, existing: p),
                        child: const Text('调整耗时')),
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => update((items) => items
                                .where((q) =>
                                    q.day != day ||
                                    q.assignmentId != p.assignmentId)
                                .toList()),
                        child: const Text('移出计划'))
                  ]),
                  const Divider(),
                ]),
              if (message != null) Text(message!),
              FilledButton.icon(
                  onPressed: busy ? null : add,
                  icon: const Icon(Icons.add),
                  label: const Text('添加作业到计划')),
            ]));
      });
}
