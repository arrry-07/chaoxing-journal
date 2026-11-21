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
                color: journal.muted.withValues(alpha: .75),
                fontFamily: Journal.bodyFamily,
                fontFamilyFallback: Journal.bodyFallback,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.6,
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

// Render a calm monogram badge keyed deterministically to the course name.
@visibleForTesting
String courseMonogram(String name) {
  var s = name.trim();
  final prefix = RegExp(
    r'^(?:\s+|\d+|\([^)]*\)|（[^）]*）|\[[^\]]*\]|【[^】]*】|[·\-—_:：./]+)',
  );
  while (true) {
    final m = prefix.firstMatch(s);
    if (m == null) break;
    s = s.substring(m.end);
  }
  final match = RegExp(r'[\u4e00-\u9fffA-Za-z]').firstMatch(s);
  if (match == null) return '课';
  return match.group(0)!.toUpperCase();
}

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

  static const _swatches = <(Color bg, Color fg)>[
    (Color(0xFFE8EEFD), Color(0xFF3456B8)),
    (Color(0xFFE3F4F1), Color(0xFF1F7A6C)),
    (Color(0xFFEFEAFB), Color(0xFF6246B5)),
    (Color(0xFFFBF1DE), Color(0xFF8A5A12)),
    (Color(0xFFFBE9EE), Color(0xFF9F3A4F)),
    (Color(0xFFE7F3E6), Color(0xFF3C7A35)),
    (Color(0xFFECEFF3), Color(0xFF4B5563)),
    (Color(0xFFE3F1F8), Color(0xFF1F6B8E)),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Journal.of(context) == JournalPalette.dark;
    final pair = _swatches[name.runes.fold(0, (int a, b) => a + b) % 8];
    final bg = dark
        ? Color.alphaBlend(
            pair.$2.withValues(alpha: .22),
            JournalPalette.dark.sheet,
          )
        : pair.$1;
    final fg = dark ? Color.lerp(pair.$2, Colors.white, .45)! : pair.$2;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size * .28),
        ),
        alignment: Alignment.center,
        child: Text(
          courseMonogram(name),
          style: TextStyle(
            color: fg,
            fontSize: size * .5,
            fontWeight: FontWeight.w600,
            fontFamily: Journal.bodyFamily,
            fontFamilyFallback: Journal.bodyFallback,
            height: 1,
          ),
        ),
      ),
    );
  }
}
