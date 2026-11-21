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
  });

  final String title;
  final double scrollOffset;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final progress = ((scrollOffset - 18.0) / 36.0).clamp(0.0, 1.0);
    if (progress <= 0.01) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      ignoring: progress < 0.35,
      child: Opacity(
        opacity: progress,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: JournalMotion.isReducedMotion(context) ? 0 : 14,
              sigmaY: JournalMotion.isReducedMotion(context) ? 0 : 14,
            ),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: journal.paper.withValues(alpha: 0.86),
                border: Border(
                  bottom: BorderSide(color: journal.divider, width: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: journal.pageTitle.copyWith(fontSize: 19.5),
                    ),
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: actions),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
