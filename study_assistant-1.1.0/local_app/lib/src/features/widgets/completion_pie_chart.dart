import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/journal.dart';
import '../../services/assignment_statistics.dart';

class CompletionPieChart extends StatelessWidget {
  const CompletionPieChart({super.key, required this.statistics});
  final AssignmentStatistics statistics;
  static const colors = [Journal.ink, Color(0xFF9A6230), Journal.muted];
  @override
  Widget build(BuildContext context) => Semantics(
      label:
          '已完成 ${statistics.completed} 份，${statistics.percentages[0]}%；待提交 ${statistics.pending} 份，${statistics.percentages[1]}%；状态待确认 ${statistics.unknown} 份，${statistics.percentages[2]}%；总计 ${statistics.total} 份',
      image: true,
      child: ExcludeSemantics(
          child: CustomPaint(
              size: const Size.square(152), painter: _Pie(statistics.counts))));
}

class _Pie extends CustomPainter {
  _Pie(this.counts);
  final List<int> counts;
  @override
  void paint(Canvas canvas, Size size) {
    final total = counts.fold(0, (a, b) => a + b);
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2),
        radius = math.min(size.width, size.height) / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      final paint = Paint()..color = CompletionPieChart.colors[i];
      final sweep = counts[i] / total * math.pi * 2;
      if (counts[i] == total) {
        canvas.drawCircle(center, radius, paint);
      } else {
        canvas.drawArc(bounds, start, sweep, true, paint);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Pie old) =>
      List.generate(3, (i) => counts[i] != old.counts[i]).any((b) => b);
}
