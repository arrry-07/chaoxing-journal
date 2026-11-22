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
      reverseCurve: JournalMotion.easeOut,
    );

    const horizontalPad = 18.0;
    const edgeInset = 8.0;
    const gap = 10.0;
    final largeText = JournalLayout.isLargeText(context);
    // Rows grow with the text scale; 48dp stays the touch-target floor.
    final itemHeight = math.max(48.0, media.textScaler.scale(15) * 1.38 + 20.0);
    final naturalMenuHeight =
        actions.length * itemHeight + (actions.length - 1) * 0.6;
    final usableHeight = math.max(0.0, size.height - topSafe - bottomSafe);

    final maxCardWidth = math.max(0.0, size.width - edgeInset * 2);
    final cardWidth = math.min(
      anchorRect?.width ??
          (size.width - horizontalPad * 2).clamp(240.0, 520.0).toDouble(),
      maxCardWidth,
    );
    final naturalCardHeight = anchorRect?.height ?? 92.0;

    // One shared vertical budget: the menu keeps at least two rows (scrolling
    // beyond that), the preview is clipped rather than drawn under the menu.
    final minCardShown = math.min(naturalCardHeight, 96.0);
    final menuHeight = math.min(
      naturalMenuHeight,
      math.max(itemHeight * 2, usableHeight - gap - minCardShown),
    );
    final cardHeight = math.max(
      0.0,
      math.min(naturalCardHeight, usableHeight - gap - menuHeight),
    );
    final stackHeight = cardHeight + gap + menuHeight;

    final anchorTop = anchorRect?.top ?? (size.height * 0.28);
    final availableAbove = anchorTop - topSafe;
    final availableBelow =
        size.height - bottomSafe - (anchorRect?.bottom ?? size.height * 0.45);
    final fitsBelow = anchorTop + stackHeight <= size.height - bottomSafe;
    final placeBelow = fitsBelow || availableBelow >= availableAbove;

    final double cardTop;
    if (placeBelow) {
      final maxTop = size.height - bottomSafe - stackHeight;
      cardTop = anchorTop.clamp(topSafe, math.max(topSafe, maxTop)).toDouble();
    } else {
      final minTop = topSafe + menuHeight + gap;
      cardTop = anchorTop
          .clamp(
              minTop, math.max(minTop, size.height - bottomSafe - cardHeight))
          .toDouble();
    }

    final cardLeft = (anchorRect?.left ?? ((size.width - cardWidth) / 2))
        .clamp(
            edgeInset, math.max(edgeInset, size.width - edgeInset - cardWidth))
        .toDouble();
    final menuWidth = math.min(largeText ? 300.0 : 238.0, cardWidth);
    final menuLeft = cardLeft
        .clamp(
            edgeInset, math.max(edgeInset, size.width - edgeInset - menuWidth))
        .toDouble();

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
                width: cardWidth,
                height: cardHeight,
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
                          // Clip (never overflow) a preview taller than its
                          // share of the screen budget.
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: previewCard,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: menuLeft,
                top: placeBelow ? cardTop + cardHeight + gap : null,
                bottom: placeBelow ? null : size.height - (cardTop - gap),
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
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: menuHeight),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SingleChildScrollView(
                            child: JournalGroupedCard(
                              backgroundColor: journal.sheetElevated,
                              dividerIndent: 16,
                              children: [
                                for (final action in actions)
                                  _ContextMenuRow(
                                    action: action,
                                    journal: journal,
                                    onTap: () {
                                      JournalMotion.tap(displayPrefs);
                                      Navigator.of(context).pop();
                                      action.onSelected();
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
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

class _ContextMenuRow extends StatelessWidget {
  const _ContextMenuRow({
    required this.action,
    required this.journal,
    required this.onTap,
  });

  final JournalContextMenuAction action;
  final JournalPalette journal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? journal.berry : journal.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    action.label,
                    style: journal.entryTitle.copyWith(
                      fontSize: 15,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(action.icon, size: 19, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
