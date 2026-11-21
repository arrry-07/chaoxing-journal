import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';

class JournalPrimaryButton extends StatefulWidget {
  const JournalPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.destructive = false,
    this.expanded = true,
    this.height = 48.0,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool destructive;
  final bool expanded;
  final double height;

  @override
  State<JournalPrimaryButton> createState() => _JournalPrimaryButtonState();
}

class _JournalPrimaryButtonState extends State<JournalPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final enabled = widget.onPressed != null && !widget.loading;
    final reduced = JournalMotion.isReducedMotion(context);
    final bg = widget.destructive ? journal.berry : journal.primaryFill;
    final fg =
        widget.destructive ? journal.onPrimaryFill : journal.onPrimaryFill;

    final child = widget.loading
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: enabled ? fg : journal.muted,
            ),
          )
        : Text(
            widget.label,
            style: journal.entryTitle.copyWith(
              color: enabled ? fg : journal.muted,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          );

    final style = FilledButton.styleFrom(
      minimumSize: Size(widget.expanded ? double.infinity : 0, widget.height),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: journal.parchment,
      disabledForegroundColor: journal.muted,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    final Widget button = widget.icon != null && !widget.loading
        ? FilledButton.icon(
            onPressed: enabled ? widget.onPressed : null,
            style: style,
            icon: Icon(widget.icon, size: 18),
            label: child,
          )
        : FilledButton(
            onPressed: enabled ? widget.onPressed : null,
            style: style,
            child: child,
          );

    return Listener(
      onPointerDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onPointerCancel: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      child: AnimatedScale(
        scale: _pressed && enabled && !reduced ? 0.98 : 1.0,
        duration: JournalMotion.duration(
          context,
          const Duration(milliseconds: 110),
        ),
        curve: JournalMotion.easeOut,
        child: button,
      ),
    );
  }
}

class JournalSecondaryButton extends StatelessWidget {
  const JournalSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    this.height = 46.0,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final double height;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final style = OutlinedButton.styleFrom(
      minimumSize: Size(expanded ? double.infinity : 0, height),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      backgroundColor: journal.parchment,
      foregroundColor: journal.ink,
      disabledForegroundColor: journal.muted,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: journal.entryTitle.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
      ),
    );

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
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
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
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
    );
  }
}
