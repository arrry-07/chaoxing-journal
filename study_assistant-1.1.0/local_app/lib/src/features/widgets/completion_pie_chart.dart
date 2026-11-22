import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../app/journal.dart';
import '../../services/assignment_statistics.dart';

class CompletionRingSegment {
  const CompletionRingSegment({
    required this.index,
    required this.start,
    required this.sweep,
  });

  final int index;
  final double start;
  final double sweep;

  Color get color => CompletionPieChart.categoryColors[index];
}

class CompletionPieChart extends StatelessWidget {
  const CompletionPieChart(
      {super.key, required this.statistics, this.diameter = 176});
  final AssignmentStatistics statistics;
  final double diameter;
  static const ringThickness = 10.0;
  static final categoryColors = colorsFor(JournalPalette.light);
  static final legendColors = categoryColors;

  static List<Color> colorsFor(JournalPalette journal) => journal.isDark
      ? const [
          Color(0xFF88A8F8),
          Color(0xFF5F7DB8),
          Color(0xFFE8827D),
          Color(0xFF6E6A63),
        ]
      : const [
          Color(0xFF4B6CB7),
          Color(0xFF9EB5E5),
          Color(0xFFD47474),
          Color(0xFFD8DCE2),
        ];
  static const labels = ['已完成', '待完成', '已逾期', '提交未知'];

  @visibleForTesting
  static List<CompletionRingSegment> segments(List<int> counts) {
    final total = counts.fold(0, (sum, count) => sum + count);
    if (total == 0) return const [];
    var start = -math.pi / 2;
    final result = <CompletionRingSegment>[];
    for (var index = 0; index < counts.length; index++) {
      final count = counts[index];
      if (count <= 0) continue;
      final sweep = count / total * math.pi * 2;
      result.add(CompletionRingSegment(
        index: index,
        start: start,
        sweep: sweep,
      ));
      start += sweep;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final uncertain =
        statistics.total == 0 || statistics.unknown == statistics.total;
    final scaled = MediaQuery.textScalerOf(context).scale(24) / 24;
    final scaledDiameter = diameter + (scaled - 1).clamp(0, 1) * 80;
    return Semantics(
      label: '${[
        for (var i = 0; i < labels.length; i++)
          '${labels[i]} ${statistics.counts[i]} 份，${statistics.percentages[i]}%'
      ].join('；')}；总计 ${statistics.total} 份${uncertain ? '；完成率待确认' : ''}',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: scaledDiameter,
          child: CustomPaint(
            painter: CompletionRingPainter(statistics.counts, journal: journal),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  uncertain ? '待确认' : '${statistics.percentages[0]}%',
                  style: journal.section.copyWith(
                    fontSize: uncertain ? 19 : 28,
                    height: 1.08,
                    letterSpacing: -0.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '完成率',
                  style: journal.metadata.copyWith(fontSize: 12.5),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class CompletionRingPainter extends CustomPainter {
  CompletionRingPainter(this.counts, {this.journal = JournalPalette.light});
  final JournalPalette journal;
  final List<int> counts;

  @override
  void paint(Canvas canvas, Size size) {
    const thickness = CompletionPieChart.ringThickness;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt
      ..color = journal.rule.withValues(alpha: 0.7);
    canvas.drawCircle(center, radius, pen);
    final innerRadius = radius - thickness / 2 - 4;
    if (innerRadius > 12) {
      canvas.drawCircle(
        center,
        innerRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = journal.rule.withValues(alpha: 0.65),
      );
    }
    final colors = CompletionPieChart.colorsFor(journal);
    final activeSegments = CompletionPieChart.segments(counts);
    for (final segment in activeSegments) {
      pen.color = colors[segment.index];
      if (segment.sweep >= math.pi * 2 - 1e-9) {
        canvas.drawCircle(center, radius, pen);
      } else {
        canvas.drawArc(bounds, segment.start, segment.sweep, false, pen);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CompletionRingPainter old) =>
      journal != old.journal || !listEquals(counts, old.counts);
}
