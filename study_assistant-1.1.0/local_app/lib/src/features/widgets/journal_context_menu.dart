import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';
import '../../models/display_preferences.dart';
import 'journal_grouped_card.dart';

@immutable
class JournalContextMenuAction {
  const JournalContextMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

Future<void> showJournalContextMenu({
  required BuildContext context,
  required Rect? anchorRect,
  required Widget previewCard,
  required List<JournalContextMenuAction> actions,
  DisplayPreferences displayPrefs = const DisplayPreferences(),
}) async {
  if (actions.isEmpty) return;
  JournalMotion.mediumThreshold(displayPrefs);
  final reduced = JournalMotion.isReducedMotion(context);
  final duration = reduced ? Duration.zero : const Duration(milliseconds: 210);

  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      reverseTransitionDuration:
          reduced ? Duration.zero : const Duration(milliseconds: 150),
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          _JournalContextMenuOverlay(
        animation: animation,
        anchorRect: anchorRect,
        previewCard: previewCard,
        actions: actions,
        displayPrefs: displayPrefs,
      ),
    ),
  );
}

class _JournalContextMenuOverlay extends StatelessWidget {
  const _JournalContextMenuOverlay({
    required this.animation,
    required this.anchorRect,
    required this.previewCard,
    required this.actions,
    required this.displayPrefs,
  });

  final Animation<double> animation;
  final Rect? anchorRect;
  final Widget previewCard;
  final List<JournalContextMenuAction> actions;
  final DisplayPreferences displayPrefs;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final media = MediaQuery.of(context);
    final size = media.size;
    final topSafe = media.padding.top + 12;
    final bottomSafe = media.padding.bottom + 16;
    final reduced = JournalMotion.isReducedMotion(context);
    final curved = CurvedAnimation(
      parent: animation,
      curve: JournalMotion.easeOut,
      reverseCurve: Curves.easeInCubic,
    );

    const horizontalPad = 18.0;
    final cardWidth = (size.width - horizontalPad * 2).clamp(240.0, 520.0);
    final menuHeight = actions.length * 48.0 + 12.0;
    final estCardHeight = (anchorRect?.height ?? 92.0).clamp(64.0, 220.0);
    final availableAbove = (anchorRect?.top ?? size.height * 0.35) - topSafe;
    final availableBelow =
        size.height - bottomSafe - (anchorRect?.bottom ?? size.height * 0.45);
    final placeBelow =
        availableBelow >= menuHeight + 12 || availableBelow >= availableAbove;

    double cardTop = anchorRect?.top ?? (size.height * 0.28);
    if (placeBelow) {
      final maxTop = size.height - bottomSafe - menuHeight - 12 - estCardHeight;
      cardTop = cardTop.clamp(topSafe, math.max(topSafe, maxTop));
    } else {
      final minTop = topSafe + menuHeight + 12;
      cardTop = cardTop.clamp(
        minTop,
        math.max(minTop, size.height - bottomSafe - estCardHeight),
      );
    }

    final menuTop = placeBelow
        ? cardTop + estCardHeight + 10
        : (cardTop - menuHeight - 10).clamp(topSafe, size.height - bottomSafe);

    final menuWidth = math.min(238.0, cardWidth);
    final cardLeft = anchorRect?.left ?? ((size.width - cardWidth) / 2);

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final t = curved.value;
          final sigma = reduced ? 0.0 : 12.0 * t;
          final scaleCard = reduced ? 1.0 : 1.0 + 0.02 * t;
          final menuScale = reduced ? 1.0 : 0.90 + 0.10 * t;

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: ColoredBox(
                      color: (journal.isDark
                              ? const Color(0xFF0B0A09)
                              : const Color(0xFF1F2328))
                          .withValues(
                              alpha: (journal.isDark ? 0.48 : 0.22) * t),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: cardLeft,
                top: cardTop,
                width: anchorRect?.width ?? cardWidth,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: scaleCard,
                    child: Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: journal.sheetElevated,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: journal.cardBorder,
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: journal.isDark ? 0.36 : 0.14,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: previewCard,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: cardLeft,
                top: menuTop,
                width: menuWidth,
                child: Transform.scale(
                  scale: menuScale,
                  alignment:
                      placeBelow ? Alignment.topLeft : Alignment.bottomLeft,
                  child: Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: journal.isDark ? 0.42 : 0.16,
                            ),
                            blurRadius: 26,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: JournalGroupedCard(
                        backgroundColor: journal.sheetElevated,
                        dividerIndent: 16,
                        children: [
                          for (final action in actions)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  JournalMotion.tap(displayPrefs);
                                  Navigator.of(context).pop();
                                  action.onSelected();
                                },
                                child: SizedBox(
                                  height: 47,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            action.label,
                                            style: journal.entryTitle.copyWith(
                                              fontSize: 15,
                                              color: action.destructive
                                                  ? journal.berry
                                                  : journal.ink,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          action.icon,
                                          size: 19,
                                          color: action.destructive
                                              ? journal.berry
                                              : journal.ink,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
    );
  }
}
