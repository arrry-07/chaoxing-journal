import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/journal.dart';
import '../../app/journal_motion.dart';

enum JournalNavTab {
  home('首页'),
  calendar('日历'),
  stats('统计'),
  profile('我的');

  const JournalNavTab(this.label);
  final String label;
}

class JournalFloatingNavBar extends StatefulWidget {
  const JournalFloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<JournalFloatingNavBar> createState() => _JournalFloatingNavBarState();
}

class _JournalFloatingNavBarState extends State<JournalFloatingNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController.unbounded(
      vsync: this,
      value: widget.selectedIndex.toDouble(),
    );
  }

  @override
  void didUpdateWidget(JournalFloatingNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final target = widget.selectedIndex.toDouble();
      if (JournalMotion.isReducedMotion(context)) {
        _slideController.value = target;
      } else {
        _slideController.animateWith(
          JournalMotion.springFor(
            JournalMotion.interactiveSpring,
            start: _slideController.value,
            end: target,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final tabs = JournalNavTab.values;
    final indicatorColor =
        journal.isDark ? journal.accent.withValues(alpha: 0.20) : journal.sage;
    final activeForeground = journal.isDark ? journal.accent : journal.ink;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            journal.paper.withValues(alpha: 0.0),
            journal.paper.withValues(alpha: 0.78),
            journal.paper,
          ],
          stops: const [0.0, 0.56, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(31),
                boxShadow: [
                  BoxShadow(
                    color: journal.isDark
                        ? const Color(0x4D000000)
                        : const Color(0x161F2328),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(31),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: JournalLayout.floatingNavHeight,
                    decoration: BoxDecoration(
                      color: journal.navGlassFill,
                      borderRadius: BorderRadius.circular(31),
                      border: Border.all(
                        color: journal.navGlassBorder,
                        width: 0.8,
                      ),
                    ),
                    foregroundDecoration: journal.isDark
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(31),
                            border: Border(
                              top: BorderSide(
                                color: journal.navGlassHighlight,
                                width: 0.8,
                              ),
                            ),
                          )
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final slotWidth = constraints.maxWidth / tabs.length;
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            AnimatedBuilder(
                              animation: _slideController,
                              builder: (context, _) {
                                final clamped = _slideController.value
                                    .clamp(0.0, (tabs.length - 1).toDouble());
                                return Transform.translate(
                                  offset: Offset(clamped * slotWidth, 0),
                                  child: SizedBox(
                                    width: slotWidth,
                                    height: 48,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: indicatorColor,
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < tabs.length; i++)
                                  Expanded(
                                    child: _NavDestinationItem(
                                      tab: tabs[i],
                                      selected: i == widget.selectedIndex,
                                      activeColor: activeForeground,
                                      inactiveColor: journal.muted,
                                      accentColor: journal.accent,
                                      onTap: () => widget.onSelected(i),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavDestinationItem extends StatefulWidget {
  const _NavDestinationItem({
    required this.tab,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.accentColor,
    required this.onTap,
  });

  final JournalNavTab tab;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  State<_NavDestinationItem> createState() => _NavDestinationItemState();
}

class _NavDestinationItemState extends State<_NavDestinationItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.selected ? widget.activeColor : widget.inactiveColor;
    final reduced = JournalMotion.isReducedMotion(context);
    final iconScale = _pressed && !reduced
        ? 0.94
        : widget.selected && !reduced
            ? 1.06
            : 1.0;

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: widget.tab.label,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) {
          if (_pressed) setState(() => _pressed = false);
        },
        onPointerCancel: (_) {
          if (_pressed) setState(() => _pressed = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            height: JournalLayout.floatingNavHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: iconScale,
                  duration: JournalMotion.duration(
                    context,
                    Duration(milliseconds: _pressed ? 120 : 180),
                  ),
                  curve: JournalMotion.easeOut,
                  child: JournalNavIcon(
                    tab: widget.tab,
                    selected: widget.selected,
                    color: fg,
                    accentColor: widget.accentColor,
                  ),
                ),
                const SizedBox(height: 3),
                ExcludeSemantics(
                  child: Text(
                    widget.tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Journal.bodyFamily,
                      fontFamilyFallback: Journal.bodyFallback,
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class JournalNavIcon extends StatelessWidget {
  const JournalNavIcon({
    super.key,
    required this.tab,
    required this.selected,
    required this.color,
    required this.accentColor,
    this.size = 21.0,
  });

  final JournalNavTab tab;
  final bool selected;
  final Color color;
  final Color accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _JournalNavIconPainter(
        tab: tab,
        selected: selected,
        color: color,
        accentColor: accentColor,
      ),
    );
  }
}

class _JournalNavIconPainter extends CustomPainter {
  const _JournalNavIconPainter({
    required this.tab,
    required this.selected,
    required this.color,
    required this.accentColor,
  });

  final JournalNavTab tab;
  final bool selected;
  final Color color;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (tab) {
      case JournalNavTab.home:
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.16, s * 0.16, s * 0.68, s * 0.70),
          Radius.circular(s * 0.18),
        );
        canvas.drawRRect(rect, stroke);
        // Top notebook tab / clip
        canvas.drawLine(
          Offset(s * 0.36, s * 0.16),
          Offset(s * 0.64, s * 0.16),
          stroke,
        );
        // Clean checklist lines
        canvas.drawLine(
          Offset(s * 0.32, s * 0.42),
          Offset(s * 0.68, s * 0.42),
          stroke..color = selected ? accentColor : color,
        );
        canvas.drawLine(
          Offset(s * 0.32, s * 0.61),
          Offset(s * 0.56, s * 0.61),
          stroke..color = color,
        );
      case JournalNavTab.calendar:
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.15, s * 0.21, s * 0.70, s * 0.64),
          Radius.circular(s * 0.18),
        );
        canvas.drawRRect(rect, stroke);
        canvas.drawLine(
          Offset(s * 0.34, s * 0.13),
          Offset(s * 0.34, s * 0.24),
          stroke,
        );
        canvas.drawLine(
          Offset(s * 0.66, s * 0.13),
          Offset(s * 0.66, s * 0.24),
          stroke,
        );
        canvas.drawLine(
          Offset(s * 0.16, s * 0.42),
          Offset(s * 0.84, s * 0.42),
          stroke,
        );
        final dotPaint = Paint()
          ..color = selected ? accentColor : color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(s * 0.38, s * 0.62), s * 0.065, dotPaint);
        canvas.drawCircle(
          Offset(s * 0.62, s * 0.62),
          s * 0.065,
          dotPaint..color = color,
        );
      case JournalNavTab.stats:
        final barPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(s * 0.24, s * 0.76),
          Offset(s * 0.24, s * 0.48),
          barPaint,
        );
        canvas.drawLine(
          Offset(s * 0.50, s * 0.76),
          Offset(s * 0.50, s * 0.24),
          barPaint..color = selected ? accentColor : color,
        );
        canvas.drawLine(
          Offset(s * 0.76, s * 0.76),
          Offset(s * 0.76, s * 0.38),
          barPaint..color = color,
        );
      case JournalNavTab.profile:
        canvas.drawCircle(
          Offset(s * 0.50, s * 0.34),
          s * 0.17,
          stroke,
        );
        final arc = Path()
          ..moveTo(s * 0.20, s * 0.80)
          ..quadraticBezierTo(s * 0.24, s * 0.58, s * 0.50, s * 0.58)
          ..quadraticBezierTo(s * 0.76, s * 0.58, s * 0.80, s * 0.80);
        canvas.drawPath(
          arc,
          stroke..color = selected ? accentColor : color,
        );
    }
  }

  @override
  bool shouldRepaint(_JournalNavIconPainter oldDelegate) =>
      tab != oldDelegate.tab ||
      selected != oldDelegate.selected ||
      color != oldDelegate.color ||
      accentColor != oldDelegate.accentColor;
}
