import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';

class JournalSliverHeader extends StatelessWidget {
  const JournalSliverHeader({
    super.key,
    required this.title,
    required this.scrollOffset,
    required this.actions,
    this.titleTrailing,
    this.statusContent,
  });

  final String title;
  final double scrollOffset;
  final List<Widget> actions;
  final Widget? titleTrailing;
  final Widget? statusContent;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final progress = ((scrollOffset - 18.0) / 36.0).clamp(0.0, 1.0);
    if (progress <= 0.01) {
      return const SizedBox.shrink();
    }
    final reduced = JournalMotion.isReducedMotion(context);
    final surfaceColor =
        reduced ? journal.paper : journal.paper.withValues(alpha: 0.98);

    final titleBar = SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: journal.pageTitle.copyWith(fontSize: 19.5),
                    ),
                  ),
                ),
                if (titleTrailing != null) ...[
                  const SizedBox(width: 5),
                  titleTrailing!,
                ],
              ],
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ),
    );

    final bodyContainer = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: surfaceColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBar,
          if (statusContent != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: statusContent!,
            ),
        ],
      ),
    );

    final body = IgnorePointer(
      ignoring: progress < 0.35,
      child: bodyContainer,
    );

    final divider = IgnorePointer(
      ignoring: true,
      child: Divider(
        key: const ValueKey('journal-sliver-header-divider'),
        height: 0.8,
        thickness: 0.8,
        color: journal.divider,
      ),
    );

    return Opacity(
      opacity: progress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          divider,
        ],
      ),
    );
  }
}
