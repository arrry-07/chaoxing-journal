import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../models/study_notebook.dart';
import '../../services/assignment_store.dart';
import '../manual_agenda_screen.dart';
import '../manual_entry_detail_screen.dart';
import 'journal_context_menu.dart';
import 'journal_swipe_tile.dart';
import 'manual_home_card.dart';

typedef HomeManualFeedback = void Function(
  String message, {
  VoidCallback? action,
  String? actionLabel,
});

/// Manual-entry operations shared by the home list and its context menu.
///
/// Keeping dialogs, undo and pin feedback here leaves the home screen to
/// compose layout only.
class HomeManualActions {
  HomeManualActions({
    required this.store,
    required this.feedback,
    required this.isMounted,
    this.onBouncePulse,
    this.onCompletingStart,
    this.onCompletingCommit,
    this.onCompletingCancel,
  });

  final AssignmentStore store;
  final HomeManualFeedback feedback;
  final bool Function() isMounted;
  final ValueChanged<String>? onBouncePulse;
  final ValueChanged<String>? onCompletingStart;
  final ValueChanged<String>? onCompletingCommit;
  final ValueChanged<String>? onCompletingCancel;

  Future<void> openDetail(
    BuildContext context,
    ManualEntry entry,
  ) async {
    if (!isMounted()) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push('/assignments/manual/${Uri.encodeComponent(entry.id)}');
      return;
    }
    if (!isMounted()) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ManualEntryDetailScreen(
          store: store,
          entryId: entry.id,
        ),
      ),
    );
  }

  Future<void> openEditor(
    BuildContext context, {
    ManualEntry? entry,
    String? initialCourse,
    String? initialKind,
  }) async {
    if (!isMounted()) return;
    if (entry == null && store.notebook.entries.length >= 500) {
      feedback('待办已达 500 条上限，请清理后再添加');
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      final course = initialCourse?.trim() ?? '';
      final kindParam = initialKind?.trim() ?? '';
      final queryParams = <String, String>{
        if (course.isNotEmpty) 'course': course,
        if (kindParam.isNotEmpty) 'kind': kindParam,
      };
      await router.push(
        entry != null
            ? '/assignments/manual/${Uri.encodeComponent(entry.id)}/edit'
            : queryParams.isEmpty
                ? '/assignments/new'
                : Uri(
                    path: '/assignments/new',
                    queryParameters: queryParams,
                  ).toString(),
      );
      return;
    }
    if (!isMounted()) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ManualEntryEditor(
          store: store,
          entry: entry,
          initialCourse: initialCourse,
          initialKind: initialKind,
          routeScope: '/assignments',
        ),
      ),
    );
  }

  Future<void> completeWithUndo(ManualEntry entry) async {
    if (entry.done) return;
    final epoch = store.accountEpoch;
    onCompletingStart?.call(entry.id);
    final ok = await store.saveNotebook(
      (n) => n.withEntries([
        for (final item in n.entries)
          item.id == entry.id ? item.completed(true) : item,
      ]),
      epoch,
    );
    if (!isMounted() || !ok) {
      onCompletingCancel?.call(entry.id);
      return;
    }
    JournalMotion.complete(store.display);
    onCompletingCommit?.call(entry.id);
    onBouncePulse?.call(AssignmentStore.manualPinKeyOf(entry));
    feedback(
      '已完成「${entry.title}」，可在待办列表查看',
      actionLabel: '撤销',
      action: () {
        onCompletingCancel?.call(entry.id);
        if (store.accountEpoch != epoch) return;
        unawaited(store.saveNotebook(
          (n) => n.withEntries([
            for (final item in n.entries)
              item.id == entry.id ? item.completed(false) : item,
          ]),
          epoch,
        ));
      },
    );
  }

  Future<void> deleteWithConfirm(
    BuildContext context,
    ManualEntry entry,
  ) async {
    final journal = Journal.of(context);
    final epoch = store.accountEpoch;
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
    if (confirmed != true || !isMounted()) return;
    final ok = await store.saveNotebook(
      (n) => n.withEntries([
        for (final item in n.entries)
          if (item.id != entry.id) item,
      ]),
      epoch,
    );
    if (!isMounted() || !ok) return;
    feedback('已删除个人安排');
  }

  Future<void> togglePin(ManualEntry entry) async {
    if (!store.canToggleManualPin(entry)) return;
    final ok = await store.toggleManualPin(entry);
    if (!isMounted() || !ok) return;
    final pinned = store.isManualPinned(entry);
    JournalMotion.pin(store.display, pinned: pinned);
    onBouncePulse?.call(AssignmentStore.manualPinKeyOf(entry));
    feedback(pinned ? '已置顶' : '已取消置顶');
  }

  Future<void> openContextMenu(
    BuildContext context,
    BuildContext itemContext,
    ManualEntry entry,
    Widget previewCard, {
    bool pinned = false,
    List<String> pinnedVisibleKeys = const [],
  }) async {
    final box = itemContext.findRenderObject() as RenderBox?;
    Rect? anchorRect;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      anchorRect = topLeft & box.size;
    }
    final canPin = store.canToggleManualPin(entry);
    final isPinned = store.isManualPinned(entry);
    final pinKey = AssignmentStore.manualPinKeyOf(entry);
    final pinIndex = pinnedVisibleKeys.indexOf(pinKey);
    final actions = <JournalContextMenuAction>[
      JournalContextMenuAction(
        label: '编辑',
        icon: Icons.edit_outlined,
        onSelected: () => openEditor(context, entry: entry),
      ),
      if (pinned && pinnedVisibleKeys.length >= 2 && pinIndex > 0)
        JournalContextMenuAction(
          label: '置顶上移',
          icon: Icons.arrow_upward_rounded,
          onSelected: () {
            final next = List<String>.of(pinnedVisibleKeys);
            final moved = next.removeAt(pinIndex);
            next.insert(pinIndex - 1, moved);
            JournalMotion.selectionTick(store.display);
            unawaited(store.reorderPinned(next));
          },
        ),
      if (pinned &&
          pinnedVisibleKeys.length >= 2 &&
          pinIndex >= 0 &&
          pinIndex < pinnedVisibleKeys.length - 1)
        JournalContextMenuAction(
          label: '置顶下移',
          icon: Icons.arrow_downward_rounded,
          onSelected: () {
            final next = List<String>.of(pinnedVisibleKeys);
            final moved = next.removeAt(pinIndex);
            next.insert(pinIndex + 1, moved);
            JournalMotion.selectionTick(store.display);
            unawaited(store.reorderPinned(next));
          },
        ),
      if (canPin)
        JournalContextMenuAction(
          label: isPinned ? '取消置顶' : '置顶',
          icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          onSelected: () => togglePin(entry),
        ),
      if (!entry.done)
        JournalContextMenuAction(
          label: '标记完成',
          icon: Icons.check_circle_outline_rounded,
          onSelected: () => completeWithUndo(entry),
        ),
      JournalContextMenuAction(
        label: '删除',
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onSelected: () => deleteWithConfirm(context, entry),
      ),
    ];
    await showJournalContextMenu(
      context: context,
      anchorRect: anchorRect,
      previewCard: previewCard,
      actions: actions,
      displayPrefs: store.display,
    );
  }
}

/// Swipe tile for one manual entry in the mixed home timeline.
Widget buildHomeManualTile({
  required AssignmentStore store,
  required DateTime now,
  required ManualEntry entry,
  required HomeManualActions actions,
  bool pinned = false,
  Widget? dragHandle,
  List<String> pinnedVisibleKeys = const [],
  int bouncePulse = 0,
}) {
  final isPinned = store.isManualPinned(entry);
  final canPin = store.canToggleManualPin(entry);
  final pinKey = AssignmentStore.manualPinKeyOf(entry);
  return Builder(
    key: ValueKey('home-timeline-item-$pinKey'),
    builder: (itemContext) {
      final journal = Journal.of(itemContext);
      final preview = IgnorePointer(
        child: ManualHomeCard(
          entry: entry,
          now: now,
          onTap: () {},
          onToggleDone: () {},
          inPinnedSection: pinned,
          compact: store.display.compact,
          countdown: store.display.countdown,
          allowUrgentNightBreakthrough:
              store.allowUrgentDeadlineNightBreakthrough,
        ),
      );
      return JournalSwipeTile(
        key: ValueKey('manual-swipe-${entry.id}'),
        displayPrefs: store.display,
        rightAction: entry.done
            ? null
            : JournalSwipeAction(
                label: '标记完成',
                icon: Icons.check_rounded,
                color: journal.ink,
                backgroundColor: journal.sage,
                onTrigger: () => unawaited(actions.completeWithUndo(entry)),
              ),
        leftAction: !canPin
            ? null
            : JournalSwipeAction(
                label: isPinned ? '取消置顶' : '置顶',
                icon:
                    isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: journal.ink,
                backgroundColor: journal.parchment,
                onTrigger: () => unawaited(actions.togglePin(entry)),
              ),
        child: ManualHomeCard(
          key: ValueKey('manual-${entry.id}'),
          entry: entry,
          now: now,
          inPinnedSection: pinned,
          compact: store.display.compact,
          countdown: store.display.countdown,
          allowUrgentNightBreakthrough:
              store.allowUrgentDeadlineNightBreakthrough,
          dragHandle: dragHandle,
          bouncePulse: bouncePulse,
          onTap: () => actions.openDetail(itemContext, entry),
          onToggleDone: entry.done
              ? () {}
              : () => unawaited(actions.completeWithUndo(entry)),
          onLongPress: () => actions.openContextMenu(
            itemContext,
            itemContext,
            entry,
            preview,
            pinned: pinned,
            pinnedVisibleKeys: pinnedVisibleKeys,
          ),
        ),
      );
    },
  );
}
