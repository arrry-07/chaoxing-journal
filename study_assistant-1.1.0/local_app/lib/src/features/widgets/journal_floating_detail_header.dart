import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import 'journal_buttons.dart';

class JournalFloatingBackButton extends StatelessWidget {
  const JournalFloatingBackButton({
    super.key,
    this.buttonKey,
    required this.onPressed,
    this.scrollProgress = 0.0,
    this.tooltip = '返回',
  });

  final Key? buttonKey;
  final VoidCallback? onPressed;
  final double scrollProgress;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final p = scrollProgress.clamp(0.0, 1.0);
    final shadowOpacity = (journal.isDark ? 0.28 : 0.08) * (1.0 - p * 0.85);

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 48,
          height: 48,
          child: JournalPressableScale(
            enabled: onPressed != null,
            pressScale: 0.94,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: buttonKey,
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: Center(
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: journal.sheetElevated.withValues(
                        alpha: journal.isDark ? 0.88 : 0.92,
                      ),
                      border: Border.all(
                        color: journal.cardBorder,
                        width: 0.8,
                      ),
                      boxShadow: shadowOpacity <= 0.005
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: shadowOpacity,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 22,
                      color: onPressed == null ? journal.muted : journal.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JournalFloatingActionCapsule extends StatelessWidget {
  const JournalFloatingActionCapsule({
    super.key,
    this.buttonKey,
    required this.label,
    required this.onPressed,
    this.icon,
    this.active = false,
    this.enabled = true,
    this.scrollProgress = 0.0,
  });

  final Key? buttonKey;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool active;
  final bool enabled;
  final double scrollProgress;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final isEnabled = enabled && onPressed != null;
    final p = scrollProgress.clamp(0.0, 1.0);
    final shadowOpacity = (journal.isDark ? 0.28 : 0.08) * (1.0 - p * 0.85);
    final bg = active
        ? journal.sage.withValues(alpha: journal.isDark ? 0.92 : 0.96)
        : journal.sheetElevated.withValues(alpha: journal.isDark ? 0.88 : 0.92);
    final borderColor = active ? journal.sageBorder : journal.cardBorder;
    final fg = !isEnabled
        ? journal.muted
        : active
            ? journal.accent
            : journal.ink;

    return Semantics(
      button: true,
      enabled: isEnabled,
      selected: active,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Center(
          widthFactor: 1.0,
          child: JournalPressableScale(
            enabled: isEnabled,
            pressScale: 0.96,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: buttonKey,
                onTap: isEnabled ? onPressed : null,
                borderRadius: BorderRadius.circular(21),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(
                      color: borderColor,
                      width: active ? 0.9 : 0.8,
                    ),
                    boxShadow: shadowOpacity <= 0.005
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: shadowOpacity,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 17, color: fg),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: journal.pillLabel.copyWith(
                            color: fg,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JournalFloatingDetailHeader extends StatelessWidget {
  const JournalFloatingDetailHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.backKey,
    this.backTooltip = '返回',
    this.trailing,
    this.scrollProgress = 0.0,
    this.progressListenable,
    this.maxContentWidth = 540.0,
  });

  final String title;
  final VoidCallback? onBack;
  final Key? backKey;
  final String backTooltip;
  final Widget? trailing;
  final double scrollProgress;
  final ValueListenable<double>? progressListenable;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final listenable = progressListenable;
    if (listenable == null) {
      return _buildBar(context, scrollProgress);
    }
    return ValueListenableBuilder<double>(
      valueListenable: listenable,
      builder: (context, progress, _) => _buildBar(context, progress),
    );
  }

  Widget _buildBar(BuildContext context, double rawProgress) {
    final journal = Journal.of(context);
    final reduced = JournalMotion.isReducedMotion(context);
    final p = rawProgress.clamp(0.0, 1.0);
    final topInset = MediaQuery.paddingOf(context).top;

    final barContent = Padding(
      padding: EdgeInsets.only(top: topInset),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  JournalFloatingBackButton(
                    buttonKey: backKey,
                    tooltip: backTooltip,
                    scrollProgress: p,
                    onPressed: onBack,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        excluding: p < 0.05,
                        child: p <= 0.01
                            ? const SizedBox.shrink()
                            : Opacity(
                                opacity: p,
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style:
                                      journal.section.copyWith(fontSize: 16.5),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (trailing != null)
                    Flexible(
                      flex: 0,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 156),
                        child: trailing!,
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final surfaceAlpha = (reduced ? 1.0 : 0.98) * p;
    final backdropColor = journal.paper.withValues(alpha: surfaceAlpha);
    final borderColor = journal.divider.withValues(alpha: p);

    final Widget backdropLayer = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backdropColor,
          border: Border(
            bottom: BorderSide(color: borderColor, width: 0.6),
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: backdropLayer),
        barContent,
      ],
    );
  }
}
