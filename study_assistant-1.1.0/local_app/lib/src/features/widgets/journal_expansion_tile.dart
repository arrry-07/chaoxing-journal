import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';

/// Shared collapsible row tailored for [JournalGroupedCard] and detail cards:
/// obeys reduced-motion, supports lazy child mounting until expanded, and can
/// use controlled state or an explicit [PageStorageKey] to keep instances
/// isolated from unrelated tiles.
class JournalExpansionTile extends StatefulWidget {
  const JournalExpansionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.showChevron = true,
    this.children = const <Widget>[],
    this.initiallyExpanded = false,
    this.expanded,
    this.toggleKey,
    this.storageKey,
    this.maintainState = false,
    this.tilePadding,
    this.childrenPadding,
    this.dividerIndent,
    this.dividerEndIndent = 16,
    this.expandedCrossAxisAlignment = CrossAxisAlignment.stretch,
    this.onExpansionChanged,
  }) : assert(
          expanded == null || storageKey == null,
          'A controlled tile must not also persist its own expansion state.',
        );

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool showChevron;
  final List<Widget> children;
  final bool initiallyExpanded;
  final bool? expanded;
  final Key? toggleKey;
  final PageStorageKey<dynamic>? storageKey;
  final bool maintainState;
  final EdgeInsetsGeometry? tilePadding;
  final EdgeInsetsGeometry? childrenPadding;
  final double? dividerIndent;
  final double dividerEndIndent;
  final CrossAxisAlignment expandedCrossAxisAlignment;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<JournalExpansionTile> createState() => _JournalExpansionTileState();
}

class _JournalExpansionTileState extends State<JournalExpansionTile>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _initializedFromStorage = false;
  late final AnimationController _chevronController;

  @override
  void initState() {
    // AutomaticKeepAliveClientMixin.initState reads wantKeepAlive synchronously.
    _expanded = widget.initiallyExpanded;
    _chevronController = AnimationController.unbounded(
      vsync: this,
      value: _isExpanded ? 0.5 : 0.0,
    );
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.expanded == null && !_initializedFromStorage) {
      _initializedFromStorage = true;
      final bucket = PageStorage.maybeOf(context);
      final stored = widget.storageKey != null
          ? bucket?.readState(context, identifier: widget.storageKey)
          : bucket?.readState(context);
      if (stored is bool && stored != _expanded) {
        _expanded = stored;
        _chevronController.value = _isExpanded ? 0.5 : 0.0;
        updateKeepAlive();
      }
    }
    if (JournalMotion.isReducedMotion(context)) {
      final target = _isExpanded ? 0.5 : 0.0;
      if (_chevronController.isAnimating ||
          _chevronController.value != target) {
        _chevronController.stop();
        _chevronController.value = target;
      }
    }
  }

  @override
  void didUpdateWidget(covariant JournalExpansionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prevExpanded = oldWidget.expanded ?? _expanded;
    final nextExpanded = _isExpanded;
    if (widget.expanded != oldWidget.expanded) {
      updateKeepAlive();
    }
    if (prevExpanded != nextExpanded) {
      _animateChevron(nextExpanded);
    }
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  bool get _isExpanded => widget.expanded ?? _expanded;

  @override
  bool get wantKeepAlive => _isExpanded;

  void _animateChevron(bool expanded) {
    final target = expanded ? 0.5 : 0.0;
    if (JournalMotion.isReducedMotion(context)) {
      _chevronController.stop();
      _chevronController.value = target;
      return;
    }
    _chevronController.animateWith(
      JournalMotion.springFor(
        JournalMotion.criticalSpring,
        start: _chevronController.value,
        end: target,
        velocity: _chevronController.velocity,
      ),
    );
  }

  void _toggle() {
    final next = !_isExpanded;
    if (widget.expanded != null) {
      widget.onExpansionChanged?.call(next);
      return;
    }
    setState(() {
      _expanded = next;
      final bucket = PageStorage.maybeOf(context);
      if (widget.storageKey != null) {
        bucket?.writeState(context, next, identifier: widget.storageKey);
      } else {
        bucket?.writeState(context, next);
      }
      updateKeepAlive();
    });
    _animateChevron(next);
    widget.onExpansionChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final journal = Journal.of(context);
    final reduced = JournalMotion.isReducedMotion(context);
    final isExpanded = _isExpanded;

    final chevron = AnimatedBuilder(
      animation: _chevronController,
      builder: (context, child) {
        final turns =
            reduced ? (isExpanded ? 0.5 : 0.0) : _chevronController.value;
        return Transform.rotate(
          angle: turns * math.pi * 2,
          child: child,
        );
      },
      child: Icon(
        Icons.expand_more_rounded,
        size: 20,
        color: journal.muted,
      ),
    );

    final Widget childrenContent = Padding(
      padding: widget.childrenPadding ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: widget.expandedCrossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final child in widget.children) ...[
            if (widget.dividerIndent != null)
              Divider(
                height: 0.6,
                thickness: 0.6,
                indent: widget.dividerIndent,
                endIndent: widget.dividerEndIndent,
                color: journal.divider,
              ),
            child,
          ],
        ],
      ),
    );

    final Widget body = widget.maintainState
        ? Visibility(
            visible: isExpanded,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: false,
            child: childrenContent,
          )
        : (isExpanded ? childrenContent : const SizedBox.shrink());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: isExpanded,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: widget.toggleKey,
              onTap: _toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: widget.tilePadding ??
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DefaultTextStyle.merge(
                              style: journal.entryTitle,
                              child: widget.title,
                            ),
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 2),
                              DefaultTextStyle.merge(
                                style: journal.metadata,
                                child: widget.subtitle!,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.trailing != null) ...[
                        const SizedBox(width: 8),
                        widget.trailing!,
                      ],
                      if (widget.showChevron) ...[
                        SizedBox(width: widget.trailing != null ? 2 : 8),
                        chevron,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (reduced)
          body
        else
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: JournalMotion.easeDrawer,
            alignment: Alignment.topCenter,
            child: body,
          ),
      ],
    );
  }
}
