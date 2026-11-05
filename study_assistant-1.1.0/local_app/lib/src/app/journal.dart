import 'dart:math' as math;
import 'package:flutter/material.dart';

class Journal {
  static const paper = Color(0xFFF7F5EC);
  static const sheet = Color(0xFFFFFDF5);
  static const ink = Color(0xFF243E34);
  static const muted = Color(0xFF53645A);
  static const sage = Color(0xFFDFE8D8);
  static const rule = Color(0xFFD6D8C9);
  static const berry = Color(0xFF813E53);
  static const bodyFamily = 'LXGW WenKai Screen';
  static const titleFamily = bodyFamily;
  // One bundled handwriting face covers Chinese, Latin and numerals so native
  // controls and custom text share the same journal voice offline.
  static const bodyFallback = [bodyFamily];
  static const display = TextStyle(
    fontFamily: titleFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 32,
    fontWeight: FontWeight.w400,
    height: 1.3,
    color: ink,
  );
  static const section = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 20,
    color: ink,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const entryTitle = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: ink,
  );
  static const metadata = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14,
    height: 1.45,
    color: muted,
  );
  static const time = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 16,
    height: 1.5,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ink,
  );
}

class JournalHeading extends StatelessWidget {
  const JournalHeading(this.title,
      {super.key,
      required this.eyebrow,
      this.bookTitle = false,
      this.trailing,
      this.trailingWidth = 48});
  final String title;
  final String eyebrow;
  final bool bookTitle;
  final Widget? trailing;
  final double trailingWidth;
  @override
  Widget build(BuildContext context) => Stack(children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  EdgeInsets.only(right: trailing == null ? 0 : trailingWidth),
              child: Text(
                eyebrow,
                style: const TextStyle(
                  color: Journal.muted,
                  fontFamily: Journal.bodyFamily,
                  fontSize: 12,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: bookTitle
                  ? Journal.display
                  : Journal.section.copyWith(fontSize: 28),
            ),
          ],
        ),
        if (trailing != null) Positioned(top: 0, right: 0, child: trailing!),
      ]);
}

// Draw small margin illustrations in the same pen, keyed to the subject.
class CourseLabel extends StatelessWidget {
  const CourseLabel(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CourseMark(name, size: 40),
          const SizedBox(width: 8),
          Flexible(child: Text(name)),
        ],
      );
}

class CourseMark extends StatelessWidget {
  const CourseMark(this.name, {super.key, this.size = 28});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: SizedBox.square(
          dimension: size,
          child: FittedBox(
              child: CustomPaint(
                  size: const Size.square(40), painter: _CourseSketch(name)))));
}

class _CourseSketch extends CustomPainter {
  _CourseSketch(this.name);
  final String name;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Journal.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = Journal.sage;
    canvas.translate(20, 20);
    canvas.rotate(-0.09);
    void line(double x, double y, double a, double b) =>
        canvas.drawLine(Offset(x, y), Offset(a, b), pen);
    if (RegExp('数|代数|几何|统计').hasMatch(name)) {
      final ruler = Path()
        ..moveTo(-15, 11)
        ..lineTo(14, 11)
        ..lineTo(12, -12)
        ..close();
      canvas.drawPath(ruler, fill);
      canvas.drawPath(ruler, pen);
      for (var i = 0; i < 5; i++) {
        line(-6 + i * 4, 11, -6 + i * 4, 7);
      }
    } else if (RegExp('物理|天文|力学').hasMatch(name)) {
      canvas.drawCircle(Offset.zero, 9, fill);
      canvas.drawCircle(Offset.zero, 9, pen);
      canvas.rotate(-math.pi / 7);
      canvas.drawOval(const Rect.fromLTRB(-18, -4, 18, 4), pen);
      canvas.drawCircle(const Offset(14, -10), 1.5, pen);
    } else if (RegExp('化学|生物|实验').hasMatch(name)) {
      final flask = Path()
        ..moveTo(-4, -13)
        ..lineTo(-4, -5)
        ..lineTo(-13, 10)
        ..quadraticBezierTo(-14, 14, -8, 14)
        ..lineTo(10, 14)
        ..quadraticBezierTo(15, 14, 12, 9)
        ..lineTo(4, -5)
        ..lineTo(4, -13);
      canvas.drawPath(flask, fill);
      canvas.drawPath(flask, pen);
      line(-6, -13, 6, -13);
      line(-8, 5, 8, 5);
    } else if (RegExp('英语|外语|语言|写作|语文').hasMatch(name)) {
      final feather = Path()
        ..moveTo(-10, 12)
        ..quadraticBezierTo(-9, -9, 14, -14)
        ..quadraticBezierTo(16, 5, -10, 12)
        ..close();
      canvas.drawPath(feather, fill);
      canvas.drawPath(feather, pen);
      line(-14, 16, 9, -8);
      line(0, 4, 6, 4);
    } else {
      final cover = Path()
        ..moveTo(-13, -12)
        ..lineTo(9, -13)
        ..lineTo(13, 11)
        ..lineTo(-10, 14)
        ..close();
      fill.color = [
        Journal.sage,
        const Color(0xFFE8DDE6),
        const Color(0xFFECE3C9),
      ][name.runes.fold(0, (int a, b) => a + b) % 3];
      canvas.drawPath(cover, fill);
      canvas.drawPath(cover, pen);
      line(-8, -11, -5, 12);
      line(-3, -4, 6, -5);
      line(-2, 0, 4, -1);
    }
  }

  @override
  bool shouldRepaint(_CourseSketch oldDelegate) => oldDelegate.name != name;
}
