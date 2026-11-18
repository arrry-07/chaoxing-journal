import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../app/journal.dart';
import '../../services/assignment_statistics.dart';

class CompletionPieChart extends StatelessWidget {
  const CompletionPieChart(
      {super.key, required this.statistics, this.diameter = 176});
  final AssignmentStatistics statistics;
  final double diameter;
  static const ringThickness = 10.0;
  static const trackColor = Journal.rule;
  static final completedColor = Color.lerp(Journal.ink, Journal.sage, .30)!;
  static const _semanticColors = [
    Journal.ink,
    Color(0xFF9A6230),
    Journal.berry,
    Journal.muted
  ];
  static final legendColors = <Color>[
    completedColor,
    for (var i = 1; i < _semanticColors.length; i++)
      Color.lerp(_semanticColors[i], Journal.paper, .12)!,
  ];
  static const labels = ['已完成', '待完成', '已逾期', '提交未知'];

  @visibleForTesting
  static List<double> completedSweeps(List<int> counts) {
    final total = counts.fold(0, (sum, count) => sum + count);
    if (total == 0 || counts.first <= 0) return const [];
    return [counts.first / total * math.pi * 2];
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
    final total = counts.fold(0, (a, b) => a + b);
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
    final sweeps = CompletionPieChart.completedSweeps(counts);
    if (sweeps.isEmpty) return;
    pen.color = CompletionPieChart.completedColor;
    if (counts.first == total) {
      canvas.drawCircle(center, radius, pen);
    } else {
      canvas.drawArc(bounds, -math.pi / 2, sweeps.single, false, pen);
    }
  }

  @override
  bool shouldRepaint(covariant CompletionRingPainter old) =>
      !listEquals(counts, old.counts);
}
