import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../models/display_preferences.dart';

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
}) {
  final enableSearch = searchable ?? options.length > 6;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
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
    ),
  );
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final bottomPad = bottomInset > 0 ? 14.0 : 14.0 + bottomSafe;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    final filtered = _filtered;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: journal.sheetElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: journal.cardBorder, width: 0.8),
            ),
          ),
          padding: EdgeInsets.fromLTRB(18, 12, 18, bottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
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
                          selected:
                              _activeFilterId == widget.filterOptions[i].id,
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
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          widget.emptyText,
                          textAlign: TextAlign.center,
                          style: journal.metadata,
                        ),
                      )
                    : Material(
                        color: journal.sheet,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side:
                              BorderSide(color: journal.cardBorder, width: 0.8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.builder(
                          shrinkWrap: true,
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
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 10, 16, 4),
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
                                      constraints:
                                          const BoxConstraints(minHeight: 48),
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
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: journal.entryTitle
                                                        .copyWith(
                                                      color: selected
                                                          ? journal.ink
                                                          : journal.ink,
                                                      fontWeight: selected
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (opt.subtitle != null &&
                                                      opt.subtitle!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      opt.subtitle!,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: journal.metadata
                                                          .copyWith(
                                                              fontSize: 12),
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
                                                    .copyWith(
                                                        color: journal.ink),
                                              ),
                                            ],
                                            if (selected)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 8),
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
              ),
            ],
          ),
        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    );
  }
}
