import 'package:flutter/material.dart';

import '../../app/journal.dart';

class JournalSliverGroupedCard extends StatelessWidget {
  const JournalSliverGroupedCard({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.dividerIndent = 16.0,
    this.findChildIndexCallback,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double dividerIndent;
  final ChildIndexGetter? findChildIndexCallback;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final edge = BorderSide(color: journal.cardBorder, width: 0.8);
    const corner = Radius.circular(16);
    final findIndex = findChildIndexCallback;
    return SliverList.builder(
      itemCount: itemCount,
      findChildIndexCallback: findIndex == null
          ? null
          : (key) => key is ValueKey<Key> ? findIndex(key.value) : null,
      itemBuilder: (context, index) {
        final item = itemBuilder(context, index);
        final itemKey = item.key;
        final first = index == 0;
        final last = index == itemCount - 1;
        final radius = BorderRadius.vertical(
          top: first ? corner : Radius.zero,
          bottom: last ? corner : Radius.zero,
        );
        return Material(
          // Keep the item's key for its subtree and pass it back to the
          // caller's index lookup when the sliver moves a row.
          key: itemKey == null ? null : ValueKey<Key>(itemKey),
          color: journal.sheet,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border(
                top: first ? edge : BorderSide.none,
                right: edge,
                bottom: last ? edge : BorderSide.none,
                left: edge,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!first)
                  Divider(
                    height: 0.6,
                    thickness: 0.6,
                    indent: dividerIndent,
                    endIndent: 16,
                    color: journal.divider,
                  ),
                item,
              ],
            ),
          ),
        );
      },
    );
  }
}
