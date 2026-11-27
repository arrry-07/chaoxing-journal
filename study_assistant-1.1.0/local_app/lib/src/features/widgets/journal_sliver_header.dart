import 'dart:ui' show ImageFilter;

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
    final isDark = journal.isDark;
    final topAlpha = reduced ? 0.97 : 0.95;
    final midAlpha = reduced ? 0.93 : (isDark ? 0.91 : 0.90);
    final baseAlpha = reduced ? 0.90 : (isDark ? 0.86 : 0.84);

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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.68, 1.0],
          colors: [
            journal.paper.withValues(alpha: topAlpha),
            journal.paper.withValues(alpha: midAlpha),
            journal.paper.withValues(alpha: baseAlpha),
          ],
        ),
      ),
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
      child: reduced
          ? bodyContainer
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: bodyContainer,
              ),
            ),
    );

    final feather = IgnorePointer(
      ignoring: true,
      child: SizedBox(
        height: 18.0,
        child: DecoratedBox(
          key: const ValueKey('journal-sliver-header-feather'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.22, 0.50, 0.78, 1.0],
              colors: [
                journal.paper.withValues(alpha: baseAlpha),
                journal.paper.withValues(alpha: baseAlpha * 0.78),
                journal.paper.withValues(alpha: baseAlpha * 0.42),
                journal.paper.withValues(alpha: baseAlpha * 0.14),
                journal.paper.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: progress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          feather,
        ],
      ),
    );
  }
}
