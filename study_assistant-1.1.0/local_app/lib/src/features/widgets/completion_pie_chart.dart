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
  static const colors = [
    Journal.ink,
    Color(0xFF9A6230),
    Journal.berry,
    Journal.muted
  ];
  static const labels = ['已完成', '待完成', '已逾期', '提交未知'];

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
            painter: _Ring(statistics.counts),
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

class _Ring extends CustomPainter {
  _Ring(this.counts);
  final List<int> counts;
  @override
  void paint(Canvas canvas, Size size) {
    final total = counts.fold(0, (a, b) => a + b);
    const thickness = 17.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;
    if (total == 0) {
      canvas.drawCircle(center, radius, pen..color = Journal.rule);
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      final sweep = counts[i] / total * math.pi * 2;
      canvas.drawArc(bounds, start, sweep, false,
          pen..color = CompletionPieChart.colors[i]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Ring old) => !listEquals(counts, old.counts);
}
