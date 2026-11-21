import 'dart:math' as math;
import 'package:flutter/material.dart';

class Journal {
  static JournalPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? JournalPalette.dark
          : JournalPalette.light;

  static const paper = Color(0xFFF6F6F4);
  static const sheet = Color(0xFFFFFFFF);
  static const parchment = Color(0xFFEFEFEC);
  static const ink = Color(0xFF1F2328);
  static const muted = Color(0xFF6B7280);
  static const sage = Color(0xFFEAF0FD);
  static const sageBorder = Color(0xFFC9D6F7);
  static const rule = Color(0xFFE5E5E2);
  static const ruleStrong = Color(0xFFD4D4D0);
  static const berry = Color(0xFF9F3A4F);
  static const berryBg = Color(0xFFFBEAEE);
  static const berryBorder = Color(0xFFEFC2CC);
  static const ochre = Color(0xFF8A5A12);
  static const ochreBg = Color(0xFFFBF1DD);
  static const ochreBorder = Color(0xFFEBD3A4);
  static const slate = Color(0xFF3D63DD);
  static const slateBg = Color(0xFFEAF0FD);
  static const slateBorder = Color(0xFFC9D6F7);

  static const displayFamily = 'LXGW WenKai Screen';
  static const bodyFamily = 'sans-serif';
  static const titleFamily = displayFamily;
  static const bodyFallback = ['sans-serif'];

  static const display = TextStyle(
    fontFamily: titleFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 30,
    fontWeight: FontWeight.w400,
    height: 1.25,
    color: ink,
  );
  static const dayHeading = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: muted,
  );
  static const section = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 19,
    color: ink,
    fontWeight: FontWeight.w600,
    height: 1.38,
  );
  static const entryTitle = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.38,
    color: ink,
  );
  static const metadata = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 13.5,
    height: 1.45,
    color: muted,
  );
  static const time = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ink,
  );
}

enum JournalPalette {
  light,
  dark;

  Color get paper => this == dark ? const Color(0xFF17181A) : Journal.paper;
  Color get sheet => this == dark ? const Color(0xFF202124) : Journal.sheet;
  Color get parchment =>
      this == dark ? const Color(0xFF2A2B2F) : Journal.parchment;
  Color get ink => this == dark ? const Color(0xFFE6E6E6) : Journal.ink;
  Color get muted => this == dark ? const Color(0xFF9AA0A6) : Journal.muted;
  Color get sage => this == dark ? const Color(0xFF26304A) : Journal.sage;
  Color get sageBorder =>
      this == dark ? const Color(0xFF3A4A73) : Journal.sageBorder;
  Color get rule => this == dark ? const Color(0xFF2E3034) : Journal.rule;
  Color get ruleStrong =>
      this == dark ? const Color(0xFF3A3C41) : Journal.ruleStrong;
  Color get berry => this == dark ? const Color(0xFFF08A9C) : Journal.berry;
  Color get berryBg => this == dark ? const Color(0xFF3A2228) : Journal.berryBg;
  Color get berryBorder =>
      this == dark ? const Color(0xFF6A3B46) : Journal.berryBorder;
  Color get ochre => this == dark ? const Color(0xFFE5B567) : Journal.ochre;
  Color get ochreBg => this == dark ? const Color(0xFF3A2E18) : Journal.ochreBg;
  Color get ochreBorder =>
      this == dark ? const Color(0xFF6B5530) : Journal.ochreBorder;
  Color get slate => this == dark ? const Color(0xFF8AA8FF) : Journal.slate;
  Color get slateBg => this == dark ? const Color(0xFF1F2A44) : Journal.slateBg;
  Color get slateBorder =>
      this == dark ? const Color(0xFF3A4A73) : Journal.slateBorder;
  Color get accent => slate;

  TextStyle get display =>
      this == dark ? Journal.display.copyWith(color: ink) : Journal.display;
  TextStyle get dayHeading => this == dark
      ? Journal.dayHeading.copyWith(color: muted)
      : Journal.dayHeading;
  TextStyle get section =>
      this == dark ? Journal.section.copyWith(color: ink) : Journal.section;
  TextStyle get entryTitle => this == dark
      ? Journal.entryTitle.copyWith(color: ink)
      : Journal.entryTitle;
  TextStyle get metadata =>
      this == dark ? Journal.metadata.copyWith(color: muted) : Journal.metadata;
  TextStyle get time =>
      this == dark ? Journal.time.copyWith(color: ink) : Journal.time;
}

class JournalLayout {
  const JournalLayout._();

  static bool isLargeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) >= 19.5;

  static Duration motionDuration(
    BuildContext context, [
    Duration normal = const Duration(milliseconds: 180),
  ]) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
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
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final rightPad = trailing == null ? 0.0 : trailingWidth;
    return Stack(children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(right: rightPad),
            child: Text(
              eyebrow,
              style: TextStyle(
                color: journal.muted,
                fontFamily: Journal.bodyFamily,
                fontFamilyFallback: Journal.bodyFallback,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.only(right: rightPad),
            child: Text(
              title,
              style: bookTitle
                  ? journal.display
                  : TextStyle(
                      fontFamily: Journal.titleFamily,
                      fontFamilyFallback: Journal.bodyFallback,
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                      height: 1.28,
                      color: journal.ink,
                    ),
            ),
          ),
        ],
      ),
      if (trailing != null) Positioned(top: 0, right: 0, child: trailing!),
    ]);
  }
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
                  size: const Size.square(40),
                  painter: _CourseSketch(name, Journal.of(context))))));
}

class _CourseSketch extends CustomPainter {
  _CourseSketch(this.name, this.journal);
  final JournalPalette journal;
  final String name;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = journal.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = journal.sage;
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
        journal.sage,
        journal == JournalPalette.dark
            ? journal.berryBg
            : const Color(0xFFE8DDE6),
        journal == JournalPalette.dark
            ? journal.ochreBg
            : const Color(0xFFECE3C9),
      ][name.runes.fold(0, (int a, b) => a + b) % 3];
      canvas.drawPath(cover, fill);
      canvas.drawPath(cover, pen);
      line(-8, -11, -5, 12);
      line(-3, -4, 6, -5);
      line(-2, 0, 4, -1);
    }
  }

  @override
  bool shouldRepaint(_CourseSketch oldDelegate) =>
      oldDelegate.name != name || oldDelegate.journal != journal;
}
