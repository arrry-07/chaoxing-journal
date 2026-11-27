import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/transient_feedback.dart';
import '../../models/display_preferences.dart';
import '../../services/assignment_store.dart';
import '../../services/interaction_feedback_service.dart';

Future<void> saveDisplaySetting(BuildContext context, AssignmentStore store,
    DisplayPreferences next) async {
  final error = await store.saveDisplay(next);
  if (error != null && context.mounted && identical(store.display, next)) {
    showJournalMessage(context, error);
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
    final subtitleStyle = journal.metadata.copyWith(
      fontSize: 12,
      height: 1.4,
      color: journal.muted,
    );

    return Card(
      key: const ValueKey('appearance-and-interaction'),
      clipBehavior: Clip.antiAlias,
      child: IconTheme.merge(
        data: IconThemeData(color: journal.ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: journal.sectionHeaderFill,
                border: Border(
                  bottom: BorderSide(color: journal.divider, width: 0.6),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                '外观与交互',
                style: journal.section.copyWith(
                  color: journal.ink,
                  fontSize: 17,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题', style: journal.metadata),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: const ValueKey('display-theme-mode-selector'),
                    child: largeText
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0;
                                  i < JournalThemeMode.values.length;
                                  i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                _ThemeSwatch(
                                  mode: JournalThemeMode.values[i],
                                  selected: display.themeMode ==
                                      JournalThemeMode.values[i],
                                  largeText: true,
                                  journal: journal,
                                  onTap: () => saveDisplaySetting(
                                    context,
                                    store,
                                    store.display.copyWith(
                                      themeMode: JournalThemeMode.values[i],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          )
                        : Row(
                            children: [
                              for (var i = 0;
                                  i < JournalThemeMode.values.length;
                                  i++) ...[
                                if (i > 0) const SizedBox(width: 10),
                                Expanded(
                                  child: _ThemeSwatch(
                                    mode: JournalThemeMode.values[i],
                                    selected: display.themeMode ==
                                        JournalThemeMode.values[i],
                                    largeText: false,
                                    journal: journal,
                                    onTap: () => saveDisplaySetting(
                                      context,
                                      store,
                                      store.display.copyWith(
                                        themeMode: JournalThemeMode.values[i],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, indent: 16, endIndent: 16, color: journal.rule),
            SwitchListTile(
              secondary: Icon(
                Icons.volume_up_outlined,
                color: journal.ink,
                size: 22,
              ),
              title: Text('交互音效', style: journal.entryTitle),
              subtitle: Text('跟随媒体音量', style: subtitleStyle),
              value: display.soundEnabled,
              enableFeedback: false,
              onChanged: (value) {
                final next = store.display.copyWith(soundEnabled: value);
                if (value) {
                  InteractionFeedback.trigger(
                    next.copyWith(hapticsEnabled: false),
                    preview: true,
                  );
                }
                saveDisplaySetting(context, store, next);
              },
            ),
            Divider(height: 1, indent: 56, endIndent: 16, color: journal.rule),
            SwitchListTile(
              secondary: Icon(
                Icons.vibration_rounded,
                color: journal.ink,
                size: 22,
              ),
              title: Text('触感反馈', style: journal.entryTitle),
              subtitle: Text('轻触按钮时短振一下', style: subtitleStyle),
              value: display.hapticsEnabled,
              enableFeedback: false,
              onChanged: (value) {
                final next = store.display.copyWith(hapticsEnabled: value);
                if (value) {
                  InteractionFeedback.trigger(
                    next.copyWith(soundEnabled: false),
                    preview: true,
                  );
                }
                saveDisplaySetting(context, store, next);
              },
            ),
            if (onMore != null) ...[
              Divider(
                  height: 1, indent: 56, endIndent: 16, color: journal.rule),
              ListTile(
                leading: Icon(
                  Icons.widgets_outlined,
                  color: journal.ink,
                  size: 22,
                ),
                title: Text('显示与小组件', style: journal.entryTitle),
                subtitle: Text('时间轴密度、倒计时、桌面小组件', style: subtitleStyle),
                trailing: Icon(Icons.chevron_right, color: journal.muted),
                onTap: onMore,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.mode,
    required this.selected,
    required this.largeText,
    required this.journal,
    required this.onTap,
  });

  final JournalThemeMode mode;
  final bool selected;
  final bool largeText;
  final JournalPalette journal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelStyle =
        (selected ? journal.entryTitle : journal.metadata).copyWith(
      fontSize: largeText ? null : 13.5,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      color: selected ? journal.ink : journal.muted,
    );

    final preview = _SwatchPreview(
      mode: mode,
      selected: selected,
      compact: largeText,
      journal: journal,
      showBadge: !largeText && selected,
    );

    return Semantics(
      key: ValueKey('theme-swatch-${mode.name}'),
      button: true,
      selected: selected,
      label: mode.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: largeText
              ? ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 56, height: 40, child: preview),
                        const SizedBox(width: 12),
                        Expanded(child: Text(mode.label, style: labelStyle)),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          _SelectedBadge(journal: journal),
                        ],
                      ],
                    ),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: preview,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        mode.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: labelStyle,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _SwatchPreview extends StatelessWidget {
  const _SwatchPreview({
    required this.mode,
    required this.selected,
    required this.compact,
    required this.journal,
    required this.showBadge,
  });

  final JournalThemeMode mode;
  final bool selected;
  final bool compact;
  final JournalPalette journal;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final Widget surface = switch (mode) {
      JournalThemeMode.light => _miniPage(JournalPalette.light),
      JournalThemeMode.dark => _miniPage(JournalPalette.dark),
      JournalThemeMode.system => Stack(
          fit: StackFit.expand,
          children: [
            _miniPage(JournalPalette.dark),
            ClipPath(
              clipper: const _TopLeftDiagonalClipper(),
              child: _miniPage(JournalPalette.light),
            ),
          ],
        ),
    };

    return Container(
      decoration: BoxDecoration(borderRadius: radius),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: selected ? journal.accent : journal.rule,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          surface,
          if (showBadge)
            Positioned(
              top: 5,
              right: 5,
              child: _SelectedBadge(journal: journal),
            ),
        ],
      ),
    );
  }

  Widget _miniPage(JournalPalette palette) {
    return ColoredBox(
      color: palette.paper,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FractionallySizedBox(
              widthFactor: 0.68,
              child: Container(
                height: compact ? 3 : 3.5,
                decoration: BoxDecoration(
                  color: palette.ink,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: compact ? 5 : 7),
            FractionallySizedBox(
              widthFactor: 0.44,
              child: Container(
                height: compact ? 2.5 : 3,
                decoration: BoxDecoration(
                  color: palette.muted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.journal});

  final JournalPalette journal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: journal.accent,
        shape: BoxShape.circle,
        border: Border.all(color: journal.sheet, width: 1),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.check_rounded,
        size: 12,
        color: journal == JournalPalette.dark
            ? JournalPalette.dark.paper
            : journal.sheet,
      ),
    );
  }
}

class _TopLeftDiagonalClipper extends CustomClipper<Path> {
  const _TopLeftDiagonalClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_TopLeftDiagonalClipper oldClipper) => false;
}
