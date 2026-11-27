import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../models/display_preferences.dart';
import 'journal_buttons.dart';
import 'journal_modal_sheet.dart';

@immutable
class JournalPickerFilterOption {
  const JournalPickerFilterOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

@immutable
class JournalPickerOption<T> {
  const JournalPickerOption({
    this.key,
    required this.value,
    required this.label,
    this.subtitle,
    this.group,
    this.icon,
    this.keywords,
    this.trailingText,
  });

  final Key? key;
  final T value;
  final String label;
  final String? subtitle;
  final String? group;
  final IconData? icon;
  final String? keywords;

  /// Short status shown before the check mark, such as an item count.
  final String? trailingText;
}

Future<T?> showJournalPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<JournalPickerOption<T>> options,
  T? selectedValue,
  bool? searchable,
  String searchHint = '搜索选项...',
  String emptyText = '没有找到匹配项',
  DisplayPreferences? displayPrefs,
  List<JournalPickerFilterOption> filterOptions = const [],
  String? initialFilterId,
  bool Function(JournalPickerOption<T> option, String filterId)?
      filterPredicate,
  String? Function(
          String? activeFilterId, List<JournalPickerOption<T>> filtered)?
      filterNoticeBuilder,
}) {
  final enableSearch = searchable ?? options.length > 6;
  return showJournalModalSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _JournalPickerSheetBody<T>(
      title: title,
      options: options,
      selectedValue: selectedValue,
      enableSearch: enableSearch,
      searchHint: searchHint,
      emptyText: emptyText,
      displayPrefs: displayPrefs,
      filterOptions: filterOptions,
      initialFilterId: initialFilterId,
      filterPredicate: filterPredicate,
      filterNoticeBuilder: filterNoticeBuilder,
    ),
  );
}

typedef JournalSheetGrabWrapper = Widget Function(Widget child);

/// Shared upward rubber-band drag and critical-spring rebound wrapper for modal sheets.
///
/// Keeps a constant two-child [Stack] structure inside [AnimatedBuilder] so
/// [dy] crossing 0.0 never unmounts or rebuilds the sheet content subtree.
class JournalSheetRubberBand extends StatefulWidget {
  const JournalSheetRubberBand({
    super.key,
    required this.fillColor,
    required this.builder,
  });

  final Color fillColor;
  final Widget Function(
    BuildContext context,
    JournalSheetGrabWrapper wrapGrabArea,
  ) builder;

  @override
  State<JournalSheetRubberBand> createState() => _JournalSheetRubberBandState();
}

class _JournalSheetRubberBandState extends State<JournalSheetRubberBand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pullController;
  int? _activeHandlePointer;
  double _rawHandleDragDy = 0.0;

  @override
  void initState() {
    super.initState();
    _pullController = AnimationController.unbounded(vsync: this, value: 0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (JournalMotion.isReducedMotion(context) &&
        (_pullController.isAnimating || _pullController.value != 0.0)) {
      _pullController.stop();
      _pullController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pullController.dispose();
    super.dispose();
  }

  static double _rubberBandUpOffset(double upwardPull) {
    if (upwardPull <= 0.0) return 0.0;
    return -(upwardPull * 0.36) / (1.0 + upwardPull / 56.0);
  }

  void _handleGrabDown(PointerDownEvent event) {
    _activeHandlePointer = event.pointer;
    if (JournalMotion.isReducedMotion(context)) {
      _rawHandleDragDy = 0.0;
      _pullController.stop();
      _pullController.value = 0.0;
      return;
    }
    if (_pullController.value < 0.0) {
      final u = (-_pullController.value).clamp(0.0, 19.5);
      final denom = (0.36 - u / 56.0).clamp(0.01, 0.36);
      _rawHandleDragDy = -(u / denom);
      _pullController.stop();
    } else {
      _rawHandleDragDy = 0.0;
    }
  }

  void _handleGrabMove(PointerMoveEvent event) {
    if (event.pointer != _activeHandlePointer) return;
    if (JournalMotion.isReducedMotion(context)) return;
    _rawHandleDragDy += event.delta.dy;
    if (_rawHandleDragDy < 0.0) {
      _pullController.stop();
      _pullController.value = _rubberBandUpOffset(-_rawHandleDragDy);
    } else if (_pullController.value != 0.0) {
      _pullController.stop();
      _pullController.value = 0.0;
    }
  }

  void _handleGrabEnd(PointerEvent event) {
    if (event.pointer != _activeHandlePointer) return;
    _activeHandlePointer = null;
    _rawHandleDragDy = 0.0;
    if (_pullController.value == 0.0 && !_pullController.isAnimating) return;
    if (JournalMotion.isReducedMotion(context)) {
      _pullController.stop();
      _pullController.value = 0.0;
      return;
    }
    _pullController.animateWith(
      JournalMotion.springFor(
        JournalMotion.criticalSpring,
        start: _pullController.value,
        end: 0.0,
        velocity: _pullController.velocity,
      ),
    );
  }

  Widget _wrapGrabArea(Widget child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleGrabDown,
        onPointerMove: _handleGrabMove,
        onPointerUp: _handleGrabEnd,
        onPointerCancel: _handleGrabEnd,
        child: child,
      );

  static const double _maxUpwardHeadroom = 22.0;

  @override
  Widget build(BuildContext context) {
    final reduced = JournalMotion.isReducedMotion(context);
    final content = widget.builder(context, _wrapGrabArea);
    return AnimatedBuilder(
      animation: _pullController,
      builder: (context, child) {
        final dy = reduced ? 0.0 : _pullController.value;
        // Reserve transparent top headroom >= max rubber-band displacement
        // (~20.16dp) inside the sheet's own layout box so strong upward pulls
        // never shift the drag handle outside ancestor BottomSheet/Padding
        // hit-test bounds. At rest (dy == 0), taps in the transparent headroom
        // hit the background dismiss detector and close the modal sheet cleanly,
        // while during upward pulls the lifted child sits above it and catches
        // re-grabs.
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _maxUpwardHeadroom,
              child: GestureDetector(
                key: const ValueKey('journal-sheet-top-dismiss-strip'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: dy < 0.0 ? (-dy).ceilToDouble() + 1.0 : 0.0,
              child: IgnorePointer(
                child: ColoredBox(color: widget.fillColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: _maxUpwardHeadroom),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: child,
              ),
            ),
          ],
        );
      },
      child: content,
    );
  }
}

class _JournalPickerSheetBody<T> extends StatefulWidget {
  const _JournalPickerSheetBody({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.enableSearch,
    required this.searchHint,
    required this.emptyText,
    this.displayPrefs,
    this.filterOptions = const [],
    this.initialFilterId,
    this.filterPredicate,
    this.filterNoticeBuilder,
  });

  final String title;
  final List<JournalPickerOption<T>> options;
  final T? selectedValue;
  final bool enableSearch;
  final String searchHint;
  final String emptyText;
  final DisplayPreferences? displayPrefs;
  final List<JournalPickerFilterOption> filterOptions;
  final String? initialFilterId;
  final bool Function(JournalPickerOption<T> option, String filterId)?
      filterPredicate;
  final String? Function(
          String? activeFilterId, List<JournalPickerOption<T>> filtered)?
      filterNoticeBuilder;

  @override
  State<_JournalPickerSheetBody<T>> createState() =>
      _JournalPickerSheetBodyState<T>();
}

class _JournalPickerSheetBodyState<T>
    extends State<_JournalPickerSheetBody<T>> {
  final _controller = TextEditingController();
  String _query = '';
  String? _activeFilterId;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    if (widget.filterOptions.isNotEmpty) {
      _activeFilterId = widget.initialFilterId ?? widget.filterOptions.first.id;
    }
  }

  void _close([T? result]) {
    if (_popped) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _popped = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<JournalPickerOption<T>> get _filtered {
    final activeFilter = _activeFilterId;
    final scoped = (widget.filterOptions.isNotEmpty &&
            activeFilter != null &&
            widget.filterPredicate != null)
        ? widget.options
            .where((o) =>
                (widget.selectedValue != null &&
                    o.value == widget.selectedValue) ||
                widget.filterPredicate!(o, activeFilter))
            .toList(growable: false)
        : widget.options;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return scoped;
    return scoped.where((o) {
      if (o.label.toLowerCase().contains(q)) return true;
      if (o.subtitle != null && o.subtitle!.toLowerCase().contains(q)) {
        return true;
      }
      if (o.keywords != null && o.keywords!.toLowerCase().contains(q)) {
        return true;
      }
      return false;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    final topSafe = media.padding.top;
    final bottomInset = media.viewInsets.bottom;
    final bottomSafe = media.padding.bottom;
    final bottomPad = bottomInset > 0 ? 14.0 : 14.0 + bottomSafe;
    final useFixedHeight =
        widget.filterOptions.isNotEmpty || widget.enableSearch;
    final scale = media.textScaler.scale(1.0);
    final filtered = _filtered;
    final filterNotice = widget.filterNoticeBuilder?.call(
      _activeFilterId,
      filtered,
    );
    final hasNotice =
        filtered.isNotEmpty && filterNotice != null && filterNotice.isNotEmpty;

    Widget buildListBody({required bool scrollableFallback}) {
      return KeyedSubtree(
        key: ValueKey(_activeFilterId),
        child: filtered.isEmpty
            ? (scrollableFallback
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      widget.emptyText,
                      textAlign: TextAlign.center,
                      style: journal.metadata,
                    ),
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        widget.emptyText,
                        textAlign: TextAlign.center,
                        style: journal.metadata,
                      ),
                    ),
                  ))
            : Material(
                color: journal.sheet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: journal.cardBorder, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  shrinkWrap: !useFixedHeight || scrollableFallback,
                  physics: scrollableFallback
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final opt = filtered[index];
                    final selected = opt.value == widget.selectedValue;
                    final prevGroup =
                        index > 0 ? filtered[index - 1].group : null;
                    final showGroup =
                        opt.group != null && opt.group != prevGroup;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (index > 0 && !showGroup)
                          Divider(
                            height: 0.6,
                            thickness: 0.6,
                            indent: opt.icon != null ? 50 : 16,
                            endIndent: 16,
                            color: journal.divider,
                          ),
                        if (showGroup) ...[
                          if (index > 0)
                            Divider(
                              height: 0.6,
                              thickness: 0.6,
                              color: journal.divider,
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Text(
                              opt.group!,
                              style: journal.dayHeading,
                            ),
                          ),
                        ],
                        Material(
                          key: opt.key,
                          color: selected
                              ? journal.sage.withValues(alpha: 0.65)
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              if (_popped) return;
                              if (widget.displayPrefs != null) {
                                JournalMotion.tap(widget.displayPrefs!);
                              }
                              _close(opt.value);
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    if (opt.icon != null) ...[
                                      Icon(
                                        opt.icon,
                                        size: 20,
                                        color: selected
                                            ? journal.accent
                                            : journal.ink,
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            opt.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: journal.entryTitle.copyWith(
                                              color: journal.ink,
                                              fontWeight: selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                          if (opt.subtitle != null &&
                                              opt.subtitle!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              opt.subtitle!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: journal.metadata
                                                  .copyWith(fontSize: 12),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (opt.trailingText != null) ...[
                                      const SizedBox(width: 10),
                                      Text(
                                        opt.trailingText!,
                                        style: journal.metadata
                                            .copyWith(color: journal.ink),
                                      ),
                                    ],
                                    if (selected)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Icon(
                                          Icons.check_rounded,
                                          size: 20,
                                          color: journal.accent,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      );
    }

    Widget buildAnimatedList({required bool scrollableFallback}) {
      return AnimatedSwitcher(
        duration: JournalMotion.duration(
          context,
          const Duration(milliseconds: 160),
        ),
        switchInCurve: JournalMotion.easeOut,
        switchOutCurve: JournalMotion.easeOut,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: buildListBody(scrollableFallback: scrollableFallback),
      );
    }

    List<Widget> buildHeaderWidgets(JournalSheetGrabWrapper wrapGrabArea) => [
          wrapGrabArea(
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  key: const ValueKey('journal-picker-drag-handle'),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: journal.ruleStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.title, style: journal.section),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded,
                          size: 20, color: journal.muted),
                      onPressed: _close,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.filterOptions.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < widget.filterOptions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    ChoiceChip(
                      key: ValueKey(
                          'picker-filter-${widget.filterOptions[i].id}'),
                      selected: _activeFilterId == widget.filterOptions[i].id,
                      onSelected: (_) {
                        if (widget.displayPrefs != null) {
                          JournalMotion.tap(widget.displayPrefs!);
                        }
                        setState(() {
                          _activeFilterId = widget.filterOptions[i].id;
                        });
                      },
                      label: Text(widget.filterOptions[i].label),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (widget.enableSearch) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              onChanged: (value) => setState(() => _query = value),
              style: journal.entryTitle.copyWith(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: journal.metadata,
                filled: true,
                fillColor: journal.parchment,
                isDense: true,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: journal.muted,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        tooltip: '清空',
                        icon: Icon(Icons.close_rounded,
                            size: 17, color: journal.muted),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: journal.accent, width: 1.1),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ];

    final noticeWidget = hasNotice
        ? Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              filterNotice,
              textAlign: TextAlign.center,
              style: journal.metadata,
            ),
          )
        : null;

    final minChromeForFixed = 100.0 +
        36.0 * scale +
        (widget.filterOptions.isNotEmpty ? 46.0 + 10.0 * scale : 0.0) +
        (widget.enableSearch ? 44.0 + 16.0 * scale : 0.0) +
        (hasNotice ? 16.0 + 32.0 * scale : 0.0);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: JournalSheetRubberBand(
        fillColor: journal.sheetElevated,
        builder: (context, wrapGrabArea) {
          final headerWidgets = buildHeaderWidgets(wrapGrabArea);
          return LayoutBuilder(
            builder: (context, outerConstraints) {
              // Outer Padding(bottom: bottomInset) and JournalSheetRubberBand's
              // 22dp top headroom already bound outerConstraints.maxHeight; only
              // subtract bottomInset when falling back to full screenHeight.
              final availableHeight = outerConstraints.hasBoundedHeight
                  ? math.max(0.0, outerConstraints.maxHeight)
                  : math.max(
                      0.0,
                      screenHeight - topSafe - bottomInset - 22.0,
                    );
              final targetHeight =
                  math.min(screenHeight * 0.74, availableHeight);
              final maxHeight = useFixedHeight
                  ? targetHeight
                  : math.min(screenHeight * 0.78, availableHeight);

              final sheetContainer = Container(
                decoration: BoxDecoration(
                  color: journal.sheetElevated,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: journal.cardBorder, width: 0.8),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(18, 12, 18, bottomPad),
                child: LayoutBuilder(
                  builder: (context, innerConstraints) {
                    final scrollableFallback =
                        innerConstraints.maxHeight < minChromeForFixed;
                    if (scrollableFallback) {
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...headerWidgets,
                            widget.filterOptions.isNotEmpty
                                ? buildAnimatedList(scrollableFallback: true)
                                : buildListBody(scrollableFallback: true),
                            if (noticeWidget != null) noticeWidget,
                          ],
                        ),
                      );
                    }
                    return Column(
                      mainAxisSize:
                          useFixedHeight ? MainAxisSize.max : MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...headerWidgets,
                        if (useFixedHeight)
                          Expanded(
                            child: widget.filterOptions.isNotEmpty
                                ? buildAnimatedList(scrollableFallback: false)
                                : buildListBody(scrollableFallback: false),
                          )
                        else
                          Flexible(
                            child: buildListBody(scrollableFallback: false),
                          ),
                        if (noticeWidget != null) noticeWidget,
                      ],
                    );
                  },
                ),
              );

              return useFixedHeight
                  ? SizedBox(height: targetHeight, child: sheetContainer)
                  : ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: sheetContainer,
                    );
            },
          );
        },
      ),
    );
  }
}

class JournalFilterPill extends StatelessWidget {
  const JournalFilterPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Center(
        widthFactor: 1.0,
        child: JournalPressableScale(
          pressScale: 0.97,
          child: Material(
            color: active ? journal.sage : journal.parchment,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: active ? journal.sageBorder : Colors.transparent,
                width: 0.9,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: journal.pillLabel.copyWith(
                          color: active && journal.isDark
                              ? journal.accent
                              : journal.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 17,
                      color: active ? journal.accent : journal.muted,
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
}
