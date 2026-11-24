import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';

class JournalPrimaryButton extends StatelessWidget {
  const JournalPrimaryButton({
    super.key,
    this.buttonKey,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.destructive = false,
    this.expanded = true,
    this.height = 48.0,
    this.padding,
    this.singleLineLabel = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final Key? buttonKey;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool destructive;
  final bool expanded;
  final double height;
  final EdgeInsetsGeometry? padding;
  final bool singleLineLabel;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final enabled = onPressed != null && !loading;
    final bg =
        backgroundColor ?? (destructive ? journal.berry : journal.primaryFill);
    final fg = foregroundColor ?? journal.onPrimaryFill;

    final labelText = Text(
      label,
      maxLines: singleLineLabel ? 1 : null,
      softWrap: !singleLineLabel,
      style: journal.entryTitle.copyWith(
        color: enabled ? fg : journal.muted,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
    );
    final child = loading
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: enabled ? fg : journal.muted,
            ),
          )
        : (singleLineLabel
            ? FittedBox(fit: BoxFit.scaleDown, child: labelText)
            : labelText);

    final style = FilledButton.styleFrom(
      minimumSize: Size(expanded ? double.infinity : 0, height),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: journal.parchment,
      disabledForegroundColor: journal.muted,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    final Widget button = icon != null && !loading
        ? FilledButton.icon(
            key: buttonKey,
            onPressed: enabled ? onPressed : null,
            style: style,
            icon: Icon(icon, size: 18),
            label: child,
          )
        : FilledButton(
            key: buttonKey,
            onPressed: enabled ? onPressed : null,
            style: style,
            child: child,
          );

    return _PressableScale(enabled: enabled, pressScale: 0.98, child: button);
  }
}

class JournalSecondaryButton extends StatelessWidget {
  const JournalSecondaryButton({
    super.key,
    this.buttonKey,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    this.height = 46.0,
    this.outlined = false,
    this.padding,
    this.singleLineLabel = false,
  });

  final Key? buttonKey;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final double height;
  final bool outlined;
  final EdgeInsetsGeometry? padding;
  final bool singleLineLabel;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final style = OutlinedButton.styleFrom(
      minimumSize: Size(expanded ? double.infinity : 0, height),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      backgroundColor: outlined ? Colors.transparent : journal.parchment,
      foregroundColor: journal.ink,
      disabledForegroundColor: journal.muted,
      side: outlined
          ? BorderSide(color: journal.ruleStrong, width: 1.0)
          : BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: journal.entryTitle.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
      ),
    );

    final rawText = Text(
      label,
      maxLines: singleLineLabel ? 1 : null,
      softWrap: !singleLineLabel,
    );
    final labelWidget = singleLineLabel
        ? FittedBox(fit: BoxFit.scaleDown, child: rawText)
        : rawText;

    final Widget button = icon != null
        ? OutlinedButton.icon(
            key: buttonKey,
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 17),
            label: labelWidget,
          )
        : OutlinedButton(
            key: buttonKey,
            onPressed: onPressed,
            style: style,
            child: labelWidget,
          );

    return _PressableScale(
      enabled: onPressed != null,
      pressScale: 0.97,
      child: button,
    );
  }
}

class JournalPillButton extends StatelessWidget {
  const JournalPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.active = false,
    this.trailingIcon,
    this.textKey,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool active;
  final IconData? trailingIcon;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final bg = active ? journal.sage : journal.parchment;
    final fg = active && !journal.isDark
        ? journal.ink
        : active
            ? journal.accent
            : journal.ink;
    final border = active
        ? Border.all(color: journal.sageBorder, width: 0.9)
        : Border.all(color: Colors.transparent, width: 0.9);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Center(
        widthFactor: 1.0,
        child: _PressableScale(
          enabled: onPressed != null,
          pressScale: 0.97,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: active ? border.top.color : Colors.transparent,
                width: 0.9,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 16,
                        color: active ? journal.accent : journal.muted,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        key: textKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: journal.pillLabel.copyWith(color: fg),
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 4),
                      Icon(trailingIcon, size: 16, color: journal.muted),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.enabled,
    required this.pressScale,
    required this.child,
  });

  final bool enabled;
  final double pressScale;
  final Widget child;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = JournalMotion.isReducedMotion(context);
    return Listener(
      onPointerDown:
          widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onPointerCancel: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      child: AnimatedScale(
        scale: _pressed && widget.enabled && !reduced ? widget.pressScale : 1.0,
        duration: JournalMotion.duration(
          context,
          const Duration(milliseconds: 120),
        ),
        curve: JournalMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}
