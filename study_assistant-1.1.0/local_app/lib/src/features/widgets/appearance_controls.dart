import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../models/display_preferences.dart';
import '../../services/assignment_store.dart';
import '../../services/interaction_feedback_service.dart';

Future<void> saveDisplaySetting(BuildContext context, AssignmentStore store,
    DisplayPreferences next) async {
  final error = await store.saveDisplay(next);
  if (error != null && context.mounted && identical(store.display, next)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}

class AppearanceControls extends StatelessWidget {
  const AppearanceControls({super.key, required this.store, this.onMore});

  final AssignmentStore store;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final display = store.display;
    final largeText = JournalLayout.isLargeText(context);
    return Card(
      key: const ValueKey('appearance-and-interaction'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外观与交互', style: journal.entryTitle),
            const SizedBox(height: 8),
            SegmentedButton<JournalThemeMode>(
              key: const ValueKey('display-theme-mode-selector'),
              direction: largeText ? Axis.vertical : Axis.horizontal,
              expandedInsets: largeText ? null : EdgeInsets.zero,
              showSelectedIcon: false,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 48)),
              ),
              segments: [
                for (final mode in JournalThemeMode.values)
                  ButtonSegment(value: mode, label: Text(mode.label)),
              ],
              selected: {display.themeMode},
              onSelectionChanged: (modes) => saveDisplaySetting(
                context,
                store,
                store.display.copyWith(themeMode: modes.single),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('交互音效'),
                  tooltip: '静音或振动模式下不播放',
                  selected: display.soundEnabled,
                  onSelected: (value) {
                    final next = store.display.copyWith(soundEnabled: value);
                    if (value) {
                      InteractionFeedback.trigger(
                          next.copyWith(hapticsEnabled: false));
                    }
                    saveDisplaySetting(context, store, next);
                  },
                ),
                FilterChip(
                  label: const Text('触感反馈'),
                  selected: display.hapticsEnabled,
                  onSelected: (value) {
                    final next = store.display.copyWith(hapticsEnabled: value);
                    if (value) {
                      InteractionFeedback.trigger(
                          next.copyWith(soundEnabled: false));
                    }
                    saveDisplaySetting(context, store, next);
                  },
                ),
              ],
            ),
            if (onMore != null)
              TextButton(
                onPressed: onMore,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text('更多显示与小组件设置')),
                    Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
