import 'package:flutter/material.dart';

import '../../app/journal.dart';

/// One-line course picker entry for the home filter sheet: "课程 全部课程 ▾".
///
/// The value sits right after the label; a selected course gets a clear
/// button at the end of the row.
class HomeCourseFilterRow extends StatelessWidget {
  const HomeCourseFilterRow({
    super.key,
    required this.value,
    required this.selected,
    required this.onTap,
    required this.onClear,
    this.tapKey,
  });

  final String value;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Material(
      color: journal.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: journal.cardBorder, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '课程：$value，点按选择',
              child: ExcludeSemantics(
                child: InkWell(
                  key: tapKey,
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 50),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text('课程', style: journal.dayHeading),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: journal.entryTitle.copyWith(
                                fontSize: 14.5,
                                color: selected ? journal.accent : journal.ink,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 22,
                            color: journal.ink,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            IconButton(
              key: const ValueKey('home-course-filter-clear'),
              tooltip: '清除课程筛选',
              onPressed: onClear,
              icon: Icon(Icons.close_rounded, size: 19, color: journal.ink),
            ),
        ],
      ),
    );
  }
}
