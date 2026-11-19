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
  static const trackColor = Journal.rule;
  static final completedColor = Color.lerp(Journal.ink, Journal.sage, .30)!;
  static final categoryColors = <Color>[
    completedColor,
    Color.lerp(Journal.ochre, Journal.paper, .18)!,
    Color.lerp(Journal.berry, Journal.paper, .18)!,
    Color.lerp(Journal.muted, Journal.paper, .12)!,
  ];
  static final legendColors = categoryColors;
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
            painter: CompletionRingPainter(statistics.counts),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(uncertain ? '待确认' : '${statistics.percentages[0]}%',
                    style: Journal.section
                        .copyWith(fontSize: uncertain ? 20 : 30)),
                const SizedBox(height: 2),
                const Text('完成率', style: Journal.metadata),
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
  CompletionRingPainter(this.counts);
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
      ..color = CompletionPieChart.trackColor;
    canvas.drawCircle(center, radius, pen);
    for (final segment in CompletionPieChart.segments(counts)) {
      pen.color = segment.color;
      if (segment.sweep >= math.pi * 2 - 1e-9) {
        canvas.drawCircle(center, radius, pen);
      } else {
        canvas.drawArc(bounds, segment.start, segment.sweep, false, pen);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CompletionRingPainter old) =>
      !listEquals(counts, old.counts);
}
