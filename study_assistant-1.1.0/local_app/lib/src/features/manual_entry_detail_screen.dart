import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/journal.dart';
import '../app/journal_motion.dart';
import '../app/transient_feedback.dart';
import '../models/assignment.dart';
import '../models/study_notebook.dart';
import '../services/assignment_query.dart';
import '../services/assignment_store.dart';
import '../services/home_manual_timeline.dart';
import '../services/local_notification_service.dart';
import 'manual_agenda_screen.dart';
import 'reminder_status_screen.dart';
import 'widgets/coursework_status_pill.dart';
import 'widgets/journal_buttons.dart';
import 'widgets/journal_grouped_card.dart';
import 'widgets/manual_attachment_gallery.dart';

class ManualEntryDetailScreen extends StatefulWidget {
  const ManualEntryDetailScreen({
    super.key,
    required this.store,
    required this.entryId,
    this.clock,
  });

  final AssignmentStore store;
  final String entryId;
  final DateTime Function()? clock;

  @override
  State<ManualEntryDetailScreen> createState() =>
      _ManualEntryDetailScreenState();
}

class _ManualEntryDetailScreenState extends State<ManualEntryDetailScreen> {
  bool _busy = false;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  void _navigateBack(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/assignments');
      }
      return;
    }
    Navigator.of(context).maybePop();
  }

  Widget _buildCopyNoteButton(
    BuildContext context,
    JournalPalette journal,
    ManualEntry entry,
  ) {
    return Semantics(
      button: true,
      label: '复制备注',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('manual-detail-copy-note'),
          borderRadius: BorderRadius.circular(999),
          onTap: () async {
            try {
              await Clipboard.setData(ClipboardData(text: entry.note.trim()));
              if (context.mounted) {
                showJournalMessage(context, '已复制备注');
              }
            } catch (_) {
              if (context.mounted) {
                showJournalMessage(context, '无法写入剪贴板，请手动长按复制');
              }
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: journal.parchment,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.copy_outlined,
                      size: 14,
                      color: journal.ink,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '复制',
                      style: journal.metadata.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: journal.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, ManualEntry entry) async {
    if (_busy) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router
          .push('/assignments/manual/${Uri.encodeComponent(entry.id)}/edit');
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ManualEntryEditor(
          store: widget.store,
          entry: entry,
          routeScope: '/agenda',
        ),
      ),
    );
  }

  Future<void> _openReminderStatus(
      BuildContext context, ManualEntry entry) async {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push(
        '/reminder-status/manual/${Uri.encodeComponent(entry.id)}?unsaved=0',
      );
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ReminderStatusScreen(
          store: widget.store,
          kind: 'manual',
          id: entry.id,
          hasUnsavedEdits: false,
        ),
      ),
    );
  }

  Future<void> _toggleDone(ManualEntry entry) async {
    if (_busy) return;
    final epoch = widget.store.accountEpoch;
    setState(() => _busy = true);
    try {
      final targetDone = !entry.done;
      final ok = await widget.store.saveNotebook(
        (n) => n.withEntries([
          for (final item in n.entries)
            item.id == entry.id ? item.completed(targetDone) : item,
        ]),
        epoch,
      );
      if (!mounted) return;
      if (ok) {
        if (targetDone) JournalMotion.complete(widget.store.display);
        showJournalMessage(
          context,
          targetDone ? '已标记为完成' : '已恢复为未完成',
        );
      } else {
        showJournalMessage(
          context,
          widget.store.operationError ?? '保存失败，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteEntry(ManualEntry entry) async {
    if (_busy) return;
    final journal = Journal.of(context);
    final epoch = widget.store.accountEpoch;
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
    setState(() => _busy = true);
    var deleted = false;
    try {
      deleted = await widget.store.saveNotebook(
        (n) => n.withEntries([
          for (final item in n.entries)
            if (item.id != entry.id) item,
        ]),
        epoch,
      );
      if (!mounted) return;
      if (deleted) {
        showJournalMessage(context, '已删除个人安排');
        _navigateBack(context);
      } else {
        showJournalMessage(
          context,
          widget.store.operationError ?? '删除失败，请稍后重试',
        );
      }
    } finally {
      if (mounted && !deleted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final journal = Journal.of(context);
          final entry = widget.store.notebook.entries
              .where((item) => item.id == widget.entryId)
              .firstOrNull;
          final isExam = entry?.kind == ManualEntry.kindExam;

          return Scaffold(
            backgroundColor: journal.paper,
            appBar: AppBar(
              backgroundColor: journal.paper,
              scrolledUnderElevation: 0,
              leading: IconButton(
                key: const ValueKey('manual-detail-back'),
                tooltip: '返回',
                onPressed: () => _navigateBack(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: Text(
                entry == null ? '个人安排详情' : (isExam ? '考试详情' : '待办详情'),
                style: journal.section,
              ),
            ),
            body: entry == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: JournalGroupedCard(
                          padding: const EdgeInsets.all(20),
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '未找到这条个人安排',
                                  style: journal.section,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '该记录可能已被删除，或当前账号已切换。',
                                  style: journal.metadata,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                JournalSecondaryButton(
                                  label: '返回',
                                  outlined: true,
                                  height: 48,
                                  onPressed: () => _navigateBack(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _buildDetailBody(context, entry, journal),
          );
        },
      );

  Widget _buildDetailBody(
    BuildContext context,
    ManualEntry entry,
    JournalPalette journal,
  ) {
    final now = _now;
    final isExam = entry.kind == ManualEntry.kindExam;
    final bucket = HomeManualTimeline.manualBucketAt(entry, now);
    final overdue = !entry.done && bucket == AssignmentDeadlineBucket.overdue;
    final overdueDays =
        overdue && entry.at != null ? now.difference(entry.at!).inDays : 0;
    final overdueLabel = overdueDays > 0 ? '已逾期$overdueDays天' : '已逾期';
    final quietSkipped =
        LocalNotificationService.isManualReminderQuietHoursSkipped(
      entry,
      now: now,
      allowUrgentNightBreakthrough:
          widget.store.allowUrgentDeadlineNightBreakthrough,
    );
    final missedWindow = !quietSkipped &&
        !entry.done &&
        entry.remind &&
        entry.at != null &&
        !entry.at!.subtract(const Duration(minutes: 30)).isAfter(now);
    final reminderSummary = !entry.remind
        ? '未开启提前提醒'
        : entry.at == null
            ? '已开启提醒（需先设置时间）'
            : entry.done
                ? '已开启提醒（条目已完成）'
                : '开始前 30 分钟提醒';

    return ListView(
      padding: EdgeInsets.fromLTRB(
        18,
        8,
        18,
        JournalLayout.floatingNavClearance(context),
      ),
      children: [
        JournalGroupedCard(
          padding: const EdgeInsets.all(16),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title.trim(),
                  key: const ValueKey('manual-detail-title'),
                  style: journal.section.copyWith(
                    fontSize: 20.5,
                    height: 1.34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  key: const ValueKey('manual-detail-status'),
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CourseworkStatusPill(
                      label: isExam ? '考试' : '待办',
                      tone: isExam
                          ? CourseworkPillTone.exam
                          : CourseworkPillTone.todo,
                    ),
                    const CourseworkStatusPill(
                      label: '自己添加',
                      tone: CourseworkPillTone.neutral,
                    ),
                    if (entry.done)
                      const CourseworkStatusPill(
                        label: '已完成',
                        tone: CourseworkPillTone.completed,
                      )
                    else if (overdue)
                      CourseworkStatusPill(
                        label: overdueLabel,
                        tone: CourseworkPillTone.overdue,
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        JournalGroupedCard(
          title: '安排详情',
          padding: EdgeInsets.zero,
          dividerIndent: 16,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailMetaRow(
                    icon: Icons.schedule_rounded,
                    label: '时间',
                    value: entry.at == null
                        ? '无截止日期'
                        : '${DateFormat('yyyy年M月d日 HH:mm').format(AssignmentQuery.beijing(entry.at!))}（北京时间）',
                  ),
                  if (entry.course.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _DetailMetaRow(
                      icon: Icons.menu_book_outlined,
                      label: '课程',
                      value: entry.course.trim(),
                    ),
                  ],
                  if (entry.location.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _DetailMetaRow(
                      icon: Icons.location_on_outlined,
                      label: '地点',
                      value: entry.location.trim(),
                    ),
                  ],
                  if (entry.minutes > 0) ...[
                    const SizedBox(height: 10),
                    _DetailMetaRow(
                      icon: Icons.timer_outlined,
                      label: '预计耗时',
                      value: '${entry.minutes} 分钟',
                    ),
                  ],
                  const SizedBox(height: 10),
                  _DetailMetaRow(
                    icon: Icons.notifications_active_outlined,
                    label: '提醒',
                    value: reminderSummary,
                  ),
                  if (quietSkipped) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('manual-detail-quiet-hours-notice'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: journal.ochreBg.withValues(
                          alpha: journal.isDark ? 0.65 : 0.72,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: journal.ochreBorder,
                          width: 0.7,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.notifications_paused_outlined,
                              size: 16,
                              color: journal.ochre,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '当前提醒时间落在夜间静音时段（23:30–07:30），且无可用白天时段；本次不会发出有声提醒，可在编辑中调整时间或关闭提醒。',
                              style: journal.metadata.copyWith(
                                color: journal.ochre,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (missedWindow) ...[
                    const SizedBox(height: 8),
                    Text(
                      '提前 30 分钟提醒时间已过，不会再安排本次提醒。',
                      style: journal.metadata.copyWith(color: journal.ochre),
                    ),
                  ],
                ],
              ),
            ),
            JournalGroupTile(
              key: const ValueKey('manual-detail-reminder-status'),
              icon: Icons.tune_rounded,
              iconColor: journal.muted,
              title: '查看提醒状态',
              onTap: () => _openReminderStatus(context, entry),
            ),
          ],
        ),
        if (entry.note.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          JournalGroupedCard(
            title: '备注',
            trailing: _buildCopyNoteButton(context, journal, entry),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              SelectableText(
                entry.note.trim(),
                key: const ValueKey('manual-detail-note'),
                style: journal.entryTitle.copyWith(
                  fontWeight: FontWeight.w400,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ],
        ManualAttachmentGallery(
          attachments: entry.attachments,
          service: widget.store.manualAttachmentService,
        ),
        const SizedBox(height: 16),
        JournalPrimaryButton(
          buttonKey: const ValueKey('manual-detail-toggle-done'),
          loading: _busy,
          icon: entry.done
              ? Icons.undo_rounded
              : Icons.check_circle_outline_rounded,
          label: entry.done ? '标为未完成' : '标记完成',
          onPressed: _busy ? null : () => _toggleDone(entry),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackButtons = constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(14) >= 18.0;
            final editBtn = JournalSecondaryButton(
              buttonKey: const ValueKey('manual-detail-edit-button'),
              height: 48,
              outlined: true,
              icon: Icons.edit_outlined,
              label: '编辑',
              padding: stackButtons
                  ? null
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              singleLineLabel: !stackButtons,
              onPressed: _busy ? null : () => _openEditor(context, entry),
            );
            final deleteBtn = JournalSecondaryButton(
              buttonKey: const ValueKey('manual-detail-delete'),
              height: 48,
              outlined: true,
              icon: Icons.delete_outline_rounded,
              label: '删除',
              padding: stackButtons
                  ? null
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              singleLineLabel: !stackButtons,
              onPressed: _busy ? null : () => _deleteEntry(entry),
            );
            if (stackButtons) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  editBtn,
                  const SizedBox(height: 10),
                  deleteBtn,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: editBtn),
                  const SizedBox(width: 10),
                  Expanded(child: deleteBtn),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DetailMetaRow extends StatelessWidget {
  const _DetailMetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 17, color: journal.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: journal.metadata),
              const SizedBox(height: 2),
              Text(
                value,
                style: journal.entryTitle.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
