import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../app/journal.dart';
import '../models/assignment.dart';
import '../models/personal_workspace.dart';
import '../services/assignment_store.dart';
import '../services/assignment_query.dart';
import '../services/rule_planning_service.dart';
import 'widgets/data_recovery_warning.dart';

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
        message = widget.store.saveFeedback(
          ok,
          successMessage: '个人计划已保存',
          failureMessage: '个人计划保存失败，请检查账号后重试',
        );
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

  Future<void> openPlanner() async {
    if (busy) return;
    if (widget.store.accountEpoch != epoch) {
      setState(() => message = '账号已变化，请重新打开每日计划');
      return;
    }
    final candidates = widget.store.visibleAssignments;
    if (candidates.isEmpty) {
      setState(() => message = '没有可规划作业，请先同步或查看其他日期。');
      return;
    }
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PlannerSheet(
        store: widget.store,
        day: day,
      ),
    );
    if (mounted && result != null) {
      setState(() => message = result);
    }
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
              if (widget.store.recoveryWarning case final warning?) ...[
                DataRecoveryWarning(warning: warning),
                const SizedBox(height: 12),
              ],
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
                  child: Text('计划完成不代表学习通已提交。未完成的计划会保留在原日期，不会自动移动。')),
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
              if (message != null)
                Semantics(liveRegion: true, child: Text(message!)),
              _PlannerEntry(
                onPressed: busy ? null : openPlanner,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                  onPressed: busy ? null : add,
                  icon: const Icon(Icons.add),
                  label: const Text('添加作业到计划')),
            ]));
      });
}

class _PlannerEntry extends StatelessWidget {
  const _PlannerEntry({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: Journal.ink,
        disabledForegroundColor: Journal.muted,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        side: const BorderSide(color: Journal.rule),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          const Icon(Icons.edit_calendar_outlined),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('安排学习时间', style: Journal.entryTitle),
                SizedBox(height: 3),
                Text('选作业、填预计耗时，根据可用时间生成安排。'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _PlannerSectionHeader extends StatelessWidget {
  const _PlannerSectionHeader({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Icon(icon, size: 20, color: Journal.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Journal.section.copyWith(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlannerSheet extends StatefulWidget {
  const _PlannerSheet({
    required this.store,
    required this.day,
  });

  final AssignmentStore store;
  final String day;

  @override
  State<_PlannerSheet> createState() => _PlannerSheetState();
}

class _PlannerSheetState extends State<_PlannerSheet> {
  late final List<Assignment> candidates;
  late final TextEditingController budgetController;
  late final String? openingAccount;
  final estimates = <String, TextEditingController>{};
  final selected = <String>{};
  PlanningPreview? preview;
  final accepted = <String>{};
  String? error;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    candidates = widget.store.visibleAssignments;
    openingAccount = widget.store.account;
    budgetController = TextEditingController(text: '120');
    for (final assignment in candidates) {
      estimates[assignment.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    budgetController.dispose();
    for (final controller in estimates.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void generate() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (selected.isEmpty) {
      setState(() => error = '请先勾选要规划的作业，再填写预计耗时。');
      return;
    }
    final budget = int.tryParse(budgetController.text.trim());
    if (budget == null || budget < 1 || budget > 1440) {
      setState(() => error = '当天可用时间应为1至1440分钟');
      return;
    }
    final minutes = <String, int>{};
    for (final id in selected) {
      final raw = estimates[id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final value = int.tryParse(raw);
      if (value == null || value < 1 || value > 1440) {
        setState(() => error = '预计耗时应为1至1440分钟；未填写的作业不会被自动安排');
        return;
      }
      minutes[id] = value;
    }
    try {
      final next = RulePlanningService.preview(
        assignments: widget.store.visibleAssignments,
        selectedIds: selected,
        estimates: minutes,
        existingPlans: widget.store.personal.plans,
        day: widget.day,
        budgetMinutes: budget,
        now: DateTime.now(),
        accountEpoch: widget.store.accountEpoch,
      );
      setState(() {
        preview = next;
        accepted
          ..clear()
          ..addAll(next.suggested.map((item) => item.assignment.id));
        error = null;
      });
    } on ArgumentError catch (value) {
      setState(() => error = value.message?.toString() ?? '规划条件无效');
    }
  }

  void invalidatePreview() {
    if (preview == null && accepted.isEmpty && error == null) return;
    setState(() {
      preview = null;
      accepted.clear();
      error = null;
    });
  }

  Future<void> save() async {
    final currentPreview = preview;
    if (currentPreview == null || accepted.isEmpty || saving) return;
    if (widget.store.account != openingAccount) {
      setState(() => error = '账号已变化，请重新生成安排');
      return;
    }
    try {
      currentPreview.ensureCurrentEpoch(widget.store.accountEpoch);
    } on StateError {
      setState(() => error = '账号已变化，请重新生成安排');
      return;
    }
    final assignments = {
      for (final assignment in widget.store.visibleAssignments)
        assignment.id: assignment
    };
    final chosen = currentPreview.suggested
        .where((item) => accepted.contains(item.assignment.id))
        .toList();
    var stale = false;
    void validate(PersonalWorkspace workspace) {
      currentPreview.ensureCurrentEpoch(widget.store.accountEpoch);
      final refreshed = RulePlanningService.preview(
        assignments: widget.store.visibleAssignments,
        selectedIds: chosen.map((item) => item.assignment.id).toSet(),
        estimates: {
          for (final item in chosen) item.assignment.id: item.minutes,
        },
        existingPlans: workspace.plans,
        day: widget.day,
        budgetMinutes: currentPreview.budgetMinutes,
        now: DateTime.now(),
        accountEpoch: currentPreview.accountEpoch,
      );
      if (refreshed.suggested.length != chosen.length) {
        stale = true;
        throw StateError('作业或当天计划已变化，请重新生成安排');
      }
    }

    for (final item in chosen) {
      final current = assignments[item.assignment.id];
      if (current == null ||
          current.isCompleted ||
          current.status != item.assignment.status ||
          current.title != item.assignment.title ||
          current.courseName != item.assignment.courseName ||
          current.deadlineAt != item.assignment.deadlineAt) {
        setState(() => error = '作业信息已变化，请重新生成安排');
        return;
      }
    }
    try {
      validate(widget.store.personal);
    } on StateError catch (value) {
      setState(() => error = value.message.toString());
      return;
    } on ArgumentError {
      setState(() => error = '安排条件已变化，请重新生成安排');
      return;
    }
    setState(() => saving = true);
    try {
      final ok = await widget.store.savePersonal((workspace) {
        // Recheck inside the serialized write too: another save or sync may
        // have completed while this operation was waiting for the store.
        validate(workspace);
        final existing = workspace.plans
            .where((plan) => plan.day == widget.day)
            .map((plan) => plan.assignmentId)
            .toSet();
        return workspace.withPlans([
          ...workspace.plans,
          for (final item in chosen)
            if (!existing.contains(item.assignment.id))
              DailyPlanItem(item.assignment.id, widget.day, item.minutes)
        ]);
      }, currentPreview.accountEpoch);
      if (!mounted) return;
      final feedback = widget.store.saveFeedback(
        ok,
        successMessage: '已加入当天计划',
        failureMessage: stale ? '作业或当天计划已变化，请重新生成安排' : '加入当天计划失败，请检查账号后重试',
      );
      if (ok) {
        Navigator.pop(context, feedback);
      } else {
        setState(() {
          saving = false;
          error = feedback;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '加入当天计划失败，请检查账号后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPreview = preview;
    final needsPreview =
        currentPreview == null || currentPreview.suggested.isEmpty;
    final selectedAssignments = [
      for (final assignment in candidates)
        if (selected.contains(assignment.id)) assignment,
    ];
    final guidance = error ??
        (currentPreview == null
            ? '选择作业并填写可用时间与预计耗时，然后生成安排。'
            : currentPreview.suggested.isEmpty
                ? currentPreview.manual.isNotEmpty
                    ? '暂不能加入当天计划：${currentPreview.manual.map((item) => _planningReason(item.reason)).toSet().join('；')}。请调整条件后重新生成安排。'
                    : '没有可加入的作业，请检查作业是否已在当天计划中，或调整条件后重新生成安排。'
                : accepted.isEmpty
                    ? '请至少选择一项建议，再加入当天计划。'
                    : '已选择 ${accepted.length} 项建议，确认后加入当天计划。');
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '安排学习时间',
                          style: Journal.section,
                        ),
                        SizedBox(height: 4),
                        Text('选作业、填预计耗时，根据可用时间生成安排。'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭安排学习时间',
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  const _PlannerSectionHeader(
                    icon: Icons.checklist_rtl,
                    title: '选择作业',
                  ),
                  Text(
                    '目标日期：${widget.day}',
                    style: Journal.metadata,
                  ),
                  const SizedBox(height: 8),
                  for (final assignment in candidates) _candidate(assignment),
                  if (candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('当前没有可选择的作业，请先同步。'),
                    ),
                  const Divider(height: 32),
                  const _PlannerSectionHeader(
                    icon: Icons.schedule_outlined,
                    title: '填写可用时间与耗时',
                  ),
                  TextField(
                    key: const ValueKey('planning-budget'),
                    controller: budgetController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => invalidatePreview(),
                    decoration: const InputDecoration(
                      labelText: '当天可用时间（分钟）',
                      helperText: '当天已有未完成计划会先占用可用时间',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Icon(Icons.lightbulb_outline, size: 20),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '示例：今天有 60 分钟，两份作业预计各 30 分钟，可生成安排后再确认。',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (selectedAssignments.isEmpty)
                    const Text('勾选作业后可填写预计耗时。')
                  else
                    for (final assignment in selectedAssignments)
                      _estimateField(assignment),
                  const Divider(height: 32),
                  const _PlannerSectionHeader(
                    icon: Icons.event_note_outlined,
                    title: '查看安排',
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('planning-generate'),
                    onPressed: selected.isEmpty || saving ? null : generate,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(currentPreview == null ? '生成安排' : '重新生成安排'),
                  ),
                  if (currentPreview != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '当天可用时间 ${currentPreview.budgetMinutes} 分钟',
                      style: Journal.time,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已有未完成计划占用 ${currentPreview.existingMinutes} 分钟',
                      style: Journal.metadata,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentPreview.remainingMinutes == null
                          ? '已有计划耗时未确认，剩余可用时间暂不能确定'
                          : '预计剩余 ${currentPreview.remainingMinutes} 分钟',
                      style: Journal.entryTitle,
                    ),
                    if (currentPreview.suggested.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('自动纳入', style: Journal.entryTitle),
                      for (final item in currentPreview.suggested)
                        CheckboxListTile(
                          key: ValueKey(
                              'planning-suggested-${item.assignment.id}'),
                          contentPadding: EdgeInsets.zero,
                          value: accepted.contains(item.assignment.id),
                          onChanged: saving
                              ? null
                              : (value) => setState(() {
                                    if (value ?? false) {
                                      accepted.add(item.assignment.id);
                                    } else {
                                      accepted.remove(item.assignment.id);
                                    }
                                  }),
                          title: Text(item.assignment.title),
                          subtitle: Text(
                              '${item.assignment.courseName} · ${item.minutes} 分钟'),
                        ),
                    ],
                    if (currentPreview.manual.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('需要人工处理', style: Journal.entryTitle),
                      for (final item in currentPreview.manual)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.assignment.title),
                          subtitle: Text(
                              '${item.assignment.courseName} · ${_planningReason(item.reason)}'),
                        ),
                    ],
                    if (currentPreview.unavailableIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                            '${currentPreview.unavailableIds.length} 项选择已在本机记录中失效，请重新选择。'),
                      ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Semantics(
                      liveRegion: true,
                      child: Text(
                        guidance,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: error == null
                                ? null
                                : Theme.of(context).colorScheme.error),
                      )),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('planning-save'),
                      onPressed: saving
                          ? null
                          : needsPreview
                              ? generate
                              : accepted.isEmpty
                                  ? null
                                  : save,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(needsPreview
                              ? Icons.auto_awesome_outlined
                              : Icons.playlist_add_check),
                      label: Text(
                        saving
                            ? '正在加入…'
                            : needsPreview
                                ? currentPreview == null
                                    ? '生成安排'
                                    : '重新生成安排'
                                : '加入当天计划',
                      ),
                    ),
                  )
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidate(Assignment assignment) {
    final chosen = selected.contains(assignment.id);
    final deadline = assignment.deadlineAt;
    final deadlineText = deadline != null &&
            assignment.deadlineTrusted &&
            !assignment.deadlineReadFailed
        ? '截止 ${DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(deadline))}'
        : assignment.deadlineLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          key: ValueKey('planning-candidate-${assignment.id}'),
          contentPadding: EdgeInsets.zero,
          value: chosen,
          onChanged: saving
              ? null
              : (value) => setState(() {
                    if (value ?? false) {
                      selected.add(assignment.id);
                    } else {
                      selected.remove(assignment.id);
                    }
                    preview = null;
                    accepted.clear();
                    error = null;
                  }),
          title: Text(assignment.title),
          subtitle: Text(
              '${assignment.courseName} · ${assignment.statusLabel} · $deadlineText'),
        ),
      ],
    );
  }

  Widget _estimateField(Assignment assignment) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(assignment.title, style: Journal.entryTitle),
          const SizedBox(height: 2),
          Text(assignment.courseName, style: Journal.metadata),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('planning-estimate-${assignment.id}'),
            controller: estimates[assignment.id],
            enabled: !saving,
            keyboardType: TextInputType.number,
            onChanged: (_) => invalidatePreview(),
            decoration: const InputDecoration(
              labelText: '预计耗时（分钟）',
              helperText: '未填写时列为人工处理，不会按 0 分钟安排',
            ),
          ),
        ],
      ),
    );
  }
}

String _planningReason(PlanningReason reason) => switch (reason) {
      PlanningReason.statusUnknown => '提交状态未知，请先核对',
      PlanningReason.deadlineReadFailed => '截止时间读取失败',
      PlanningReason.deadlineUntrusted => '截止时间待确认',
      PlanningReason.noDeadline => '没有可信截止时间',
      PlanningReason.overdue => '已经超过截止时间',
      PlanningReason.deadlineBeforeTarget => '截止时间早于目标日期',
      PlanningReason.missingEstimate => '需要填写预计耗时',
      PlanningReason.insufficientBudget => '预计耗时超过当天剩余可用时间',
      PlanningReason.existingBudgetUnknown => '已有计划耗时未确认',
      PlanningReason.existingBudgetExceeded => '已有计划已超过当天可用时间',
    };
