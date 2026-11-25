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
  Widget? previewCard,
  required List<JournalContextMenuAction> actions,
  DisplayPreferences displayPrefs = const DisplayPreferences(),
}) async {
  if (actions.isEmpty) return;
  JournalMotion.mediumThreshold(displayPrefs);
  final reduced = JournalMotion.isReducedMotion(context);
  final duration = reduced ? Duration.zero : const Duration(milliseconds: 190);

  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      reverseTransitionDuration:
          reduced ? Duration.zero : const Duration(milliseconds: 110),
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

class _JournalContextMenuOverlay extends StatefulWidget {
  const _JournalContextMenuOverlay({
    required this.animation,
    required this.anchorRect,
    required this.previewCard,
    required this.actions,
    required this.displayPrefs,
  });

  final Animation<double> animation;
  final Rect? anchorRect;
  final Widget? previewCard;
  final List<JournalContextMenuAction> actions;
  final DisplayPreferences displayPrefs;

  @override
  State<_JournalContextMenuOverlay> createState() =>
      _JournalContextMenuOverlayState();
}

class _JournalContextMenuOverlayState
    extends State<_JournalContextMenuOverlay> {
  late final CurvedAnimation _curved;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: JournalMotion.easeOut,
      reverseCurve: JournalMotion.easeOut,
    );
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  void _dismiss({VoidCallback? afterDismiss}) {
    if (_dismissed) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _dismissed = true;
    Navigator.of(context).pop();
    afterDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final media = MediaQuery.of(context);
    final size = media.size;
    final topSafe = media.padding.top + 12;
    final bottomSafe = media.padding.bottom + 16;
    final reduced = JournalMotion.isReducedMotion(context);
    final actions = widget.actions;
    final anchorRect = widget.anchorRect;

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
    final naturalCardHeight =
        widget.previewCard == null ? 0.0 : (anchorRect?.height ?? 92.0);
    final hasPreview = widget.previewCard != null;

    // One shared vertical budget: with preview keeps up to two rows when space
    // permits; without preview places the menu directly near the anchor.
    final minCardShown = hasPreview ? math.min(naturalCardHeight, 96.0) : 0.0;
    final desiredFloor = math.min(itemHeight * 2, usableHeight);
    final menuBudget = hasPreview
        ? math.max(desiredFloor, usableHeight - gap - minCardShown)
        : usableHeight;
    final cardHeight = hasPreview
        ? math.max(
            0.0,
            math.min(
              naturalCardHeight,
              usableHeight -
                  gap -
                  math.min(
                    naturalMenuHeight,
                    math.min(usableHeight, menuBudget),
                  ),
            ),
          )
        : 0.0;

    final anchorTop = anchorRect?.top ?? (size.height * 0.28);
    final anchorBottom = anchorRect?.bottom ?? size.height * 0.45;
    final availableAbove = anchorTop - topSafe - (hasPreview ? 0.0 : 6.0);
    final availableBelow =
        size.height - bottomSafe - anchorBottom - (hasPreview ? 0.0 : 6.0);
    final double menuHeight;
    final bool placeBelow;
    if (hasPreview) {
      menuHeight = math.min(
        naturalMenuHeight,
        math.min(usableHeight, menuBudget),
      );
      final stackHeight = cardHeight + gap + menuHeight;
      final fitsBelow = anchorTop + stackHeight <= size.height - bottomSafe;
      placeBelow = fitsBelow || availableBelow >= availableAbove;
    } else {
      placeBelow = naturalMenuHeight <= availableBelow ||
          availableBelow >= availableAbove;
      final verticalRoom =
          math.max(0.0, placeBelow ? availableBelow : availableAbove);
      menuHeight = math.min(naturalMenuHeight, verticalRoom);
    }
    final stackHeight = hasPreview ? cardHeight + gap + menuHeight : menuHeight;

    final double cardTop;
    if (!hasPreview) {
      cardTop = anchorTop;
    } else if (placeBelow) {
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
    final menuWidth = math.min(
      largeText ? 300.0 : 238.0,
      hasPreview ? cardWidth : maxCardWidth,
    );
    final alignRight = !hasPreview &&
        anchorRect != null &&
        anchorRect.center.dx > size.width / 2;
    final rawMenuLeft = hasPreview
        ? cardLeft
        : anchorRect == null
            ? (size.width - menuWidth) / 2
            : (alignRight ? anchorRect.right - menuWidth : anchorRect.left);
    final menuLeft = rawMenuLeft
        .clamp(
            edgeInset, math.max(edgeInset, size.width - edgeInset - menuWidth))
        .toDouble();
    final double? menuTop = hasPreview
        ? (placeBelow ? cardTop + cardHeight + gap : null)
        : (placeBelow
            ? (anchorBottom + 6)
                .clamp(topSafe,
                    math.max(topSafe, size.height - bottomSafe - menuHeight))
                .toDouble()
            : null);
    final double? menuBottom = hasPreview
        ? (placeBelow ? null : size.height - (cardTop - gap))
        : (placeBelow
            ? null
            : (size.height - (anchorTop - 6))
                .clamp(bottomSafe,
                    math.max(bottomSafe, size.height - topSafe - menuHeight))
                .toDouble());
    final Alignment scaleAlignment = switch ((placeBelow, alignRight)) {
      (true, true) => Alignment.topRight,
      (true, false) => Alignment.topLeft,
      (false, true) => Alignment.bottomRight,
      (false, false) => Alignment.bottomLeft,
    };

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _curved,
        builder: (context, _) {
          final t = _curved.value;
          final sigma = reduced ? 0.0 : 12.0 * t;
          final scaleCard = reduced ? 1.0 : 1.0 + 0.02 * t;
          final menuScale = reduced ? 1.0 : 0.94 + 0.06 * t;
          final backdrop = ColoredBox(
            color: (journal.isDark
                    ? const Color(0xFF0B0A09)
                    : const Color(0xFF1F2328))
                .withValues(alpha: (journal.isDark ? 0.48 : 0.22) * t),
          );

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismiss,
                  child: sigma < 0.4
                      ? backdrop
                      : BackdropFilter(
                          filter:
                              ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                          child: backdrop,
                        ),
                ),
              ),
              if (widget.previewCard != null && cardHeight > 0)
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
                              child: widget.previewCard,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: menuLeft,
                top: menuTop,
                bottom: menuBottom,
                width: menuWidth,
                child: Transform.scale(
                  scale: menuScale,
                  alignment: scaleAlignment,
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
                                    onTap: () => _dismiss(
                                      afterDismiss: action.onSelected,
                                    ),
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
