import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';

/// Shared collapsible row tailored for [JournalGroupedCard] and detail cards:
/// omits internal hairline dividers, obeys reduced-motion, and supports lazy
/// child mounting until expanded.
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
    this.maintainState = false,
    this.tilePadding,
    this.childrenPadding,
    this.expandedCrossAxisAlignment = CrossAxisAlignment.stretch,
    this.onExpansionChanged,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool showChevron;
  final List<Widget> children;
  final bool initiallyExpanded;
  final bool maintainState;
  final EdgeInsetsGeometry? tilePadding;
  final EdgeInsetsGeometry? childrenPadding;
  final CrossAxisAlignment expandedCrossAxisAlignment;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<JournalExpansionTile> createState() => _JournalExpansionTileState();
}

class _JournalExpansionTileState extends State<JournalExpansionTile>
    with AutomaticKeepAliveClientMixin {
  bool _expanded = false;
  bool _initializedFromStorage = false;

  @override
  void initState() {
    // AutomaticKeepAliveClientMixin.initState reads wantKeepAlive synchronously.
    _expanded = widget.initiallyExpanded;
    super.initState();
  }

  Object? _storageIdentifier(BuildContext context) {
    final ancestor = context.findAncestorWidgetOfExactType<KeyedSubtree>();
    if (ancestor?.key is PageStorageKey) return ancestor!.key;
    if (widget.key is PageStorageKey) return widget.key;
    return widget.key;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedFromStorage) return;
    _initializedFromStorage = true;
    final stored = PageStorage.maybeOf(context)?.readState(
      context,
      identifier: _storageIdentifier(context),
    );
    if (stored is bool && stored != _expanded) {
      _expanded = stored;
      updateKeepAlive();
    }
  }

  @override
  bool get wantKeepAlive => _expanded;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      PageStorage.maybeOf(context)?.writeState(
        context,
        _expanded,
        identifier: _storageIdentifier(context),
      );
      updateKeepAlive();
    });
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final journal = Journal.of(context);
    final reduced = JournalMotion.isReducedMotion(context);

    final chevron = AnimatedRotation(
      turns: _expanded ? 0.5 : 0.0,
      duration: JournalMotion.duration(
        context,
        const Duration(milliseconds: 200),
      ),
      curve: JournalMotion.easeOut,
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
        children: widget.children,
      ),
    );

    final Widget body = widget.maintainState
        ? Visibility(
            visible: _expanded,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: false,
            child: childrenContent,
          )
        : (_expanded ? childrenContent : const SizedBox.shrink());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
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
