import 'package:flutter/material.dart';

class Journal {
  static JournalPalette of(BuildContext context) =>
      Theme.of(context).extension<JournalPalette>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? JournalPalette.dark
          : JournalPalette.light);

  static const paper = Color(0xFFF5F5F2);
  static const sheet = Color(0xFFFFFFFF);
  static const parchment = Color(0xFFEFEFEA);
  static const ink = Color(0xFF1F2328);
  static const muted = Color(0xFF6B7280);
  static const sage = Color(0xFFEAF0FD);
  static const sageBorder = Color(0xFFC9D6F7);
  static const rule = Color(0xFFE6E5E0);
  static const ruleStrong = Color(0xFFD6D5CE);
  static const divider = Color(0xFFECEBE6);
  static const berry = Color(0xFFC53B3B);
  static const berryBg = Color(0xFFFDF2F2);
  static const berryBorder = Color(0xFFF3D1D1);
  static const ochre = Color(0xFF4F5D73);
  static const ochreBg = Color(0xFFEFF2F6);
  static const ochreBorder = Color(0xFFD8DEE8);
  static const slate = Color(0xFF3D63DD);
  static const slateBg = Color(0xFFEAF0FD);
  static const slateBorder = Color(0xFFC9D6F7);

  static const displayFamily = 'LXGW WenKai Screen';
  static const titleFamily = displayFamily;
  static const bodyFamily = 'sans-serif';
  static const bodyFallback = [
    'HarmonyOS Sans SC',
    'MiSans',
    'PingFang SC',
    'Roboto',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static const display = TextStyle(
    fontFamily: titleFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 30,
    fontWeight: FontWeight.w400,
    height: 1.25,
    color: ink,
  );
  static const pageTitle = TextStyle(
    fontFamily: titleFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 21,
    fontWeight: FontWeight.w400,
    height: 1.28,
    color: ink,
  );
  static const dayHeading = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.35,
    fontFeatures: [FontFeature.tabularFigures()],
    color: muted,
  );
  static const section = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 17,
    color: ink,
    fontWeight: FontWeight.w600,
    height: 1.38,
  );
  static const entryTitle = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 15.5,
    fontWeight: FontWeight.w500,
    height: 1.38,
    color: ink,
  );
  static const metadata = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 13,
    height: 1.45,
    fontFeatures: [FontFeature.tabularFigures()],
    color: muted,
  );
  static const time = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ink,
  );
  static const statHero = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.12,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ink,
  );
  static const pillLabel = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ink,
  );
}

typedef JournalThemeTokens = JournalPalette;

@immutable
class JournalPalette extends ThemeExtension<JournalPalette> {
  const JournalPalette({
    required this.isDark,
    required this.paper,
    required this.sheet,
    required this.sheetElevated,
    required this.parchment,
    required this.ink,
    required this.primaryFill,
    required this.onPrimaryFill,
    required this.muted,
    required this.sage,
    required this.sageBorder,
    required this.rule,
    required this.ruleStrong,
    required this.cardBorder,
    required this.divider,
    required this.berry,
    required this.berryBg,
    required this.berryBorder,
    required this.ochre,
    required this.ochreBg,
    required this.ochreBorder,
    required this.slate,
    required this.slateBg,
    required this.slateBorder,
    required this.navGlassFill,
    required this.navGlassBorder,
    required this.navGlassHighlight,
  });

  static const light = JournalPalette(
    isDark: false,
    paper: Journal.paper,
    sheet: Journal.sheet,
    sheetElevated: Color(0xFFFFFFFF),
    parchment: Journal.parchment,
    ink: Journal.ink,
    primaryFill: Journal.ink,
    onPrimaryFill: Color(0xFFFFFFFF),
    muted: Journal.muted,
    sage: Journal.sage,
    sageBorder: Journal.sageBorder,
    rule: Journal.rule,
    ruleStrong: Journal.ruleStrong,
    cardBorder: Journal.rule,
    divider: Journal.divider,
    berry: Journal.berry,
    berryBg: Journal.berryBg,
    berryBorder: Journal.berryBorder,
    ochre: Journal.ochre,
    ochreBg: Journal.ochreBg,
    ochreBorder: Journal.ochreBorder,
    slate: Journal.slate,
    slateBg: Journal.slateBg,
    slateBorder: Journal.slateBorder,
    navGlassFill: Color(0xD9FFFFFF),
    navGlassBorder: Color(0xB3E5E5E0),
    navGlassHighlight: Color(0x80FFFFFF),
  );

  // "深夜台灯纸感" warm charcoal paper palette: avoids pure #000/#FFF glare.
  static const dark = JournalPalette(
    isDark: true,
    paper: Color(0xFF191816),
    sheet: Color(0xFF23221F),
    sheetElevated: Color(0xFF2B2A26),
    parchment: Color(0xFF2E2D29),
    ink: Color(0xFFEAE6DF),
    primaryFill: Color(0xFFEAE6DF),
    onPrimaryFill: Color(0xFF1A1917),
    muted: Color(0xFFA09B93),
    sage: Color(0xFF252B3B),
    sageBorder: Color(0xFF3D4C6E),
    rule: Color(0xFF32302B),
    ruleStrong: Color(0xFF403E38),
    cardBorder: Color(0x14FFF8EB),
    divider: Color(0x10FFF8EB),
    berry: Color(0xFFE8827D),
    berryBg: Color(0xFF342222),
    berryBorder: Color(0xFF5A3636),
    ochre: Color(0xFFAEBACB),
    ochreBg: Color(0xFF272B32),
    ochreBorder: Color(0xFF3D434F),
    slate: Color(0xFF88A8F8),
    slateBg: Color(0xFF252B3B),
    slateBorder: Color(0xFF3D4C6E),
    navGlassFill: Color(0xCC242320),
    navGlassBorder: Color(0x16FFF8EB),
    navGlassHighlight: Color(0x26FFF8EB),
  );

  final bool isDark;
  final Color paper;
  final Color sheet;
  final Color sheetElevated;
  final Color parchment;
  final Color ink;
  final Color primaryFill;
  final Color onPrimaryFill;
  final Color muted;
  final Color sage;
  final Color sageBorder;
  final Color rule;
  final Color ruleStrong;
  final Color cardBorder;
  final Color divider;
  final Color berry;
  final Color berryBg;
  final Color berryBorder;
  final Color ochre;
  final Color ochreBg;
  final Color ochreBorder;
  final Color slate;
  final Color slateBg;
  final Color slateBorder;
  final Color navGlassFill;
  final Color navGlassBorder;
  final Color navGlassHighlight;

  Color get accent => slate;

  TextStyle get display =>
      isDark ? Journal.display.copyWith(color: ink) : Journal.display;
  TextStyle get pageTitle =>
      isDark ? Journal.pageTitle.copyWith(color: ink) : Journal.pageTitle;
  TextStyle get dayHeading =>
      isDark ? Journal.dayHeading.copyWith(color: muted) : Journal.dayHeading;
  TextStyle get section =>
      isDark ? Journal.section.copyWith(color: ink) : Journal.section;
  TextStyle get entryTitle =>
      isDark ? Journal.entryTitle.copyWith(color: ink) : Journal.entryTitle;
  TextStyle get metadata =>
      isDark ? Journal.metadata.copyWith(color: muted) : Journal.metadata;
  TextStyle get time =>
      isDark ? Journal.time.copyWith(color: ink) : Journal.time;
  TextStyle get statHero =>
      isDark ? Journal.statHero.copyWith(color: ink) : Journal.statHero;
  TextStyle get pillLabel =>
      isDark ? Journal.pillLabel.copyWith(color: ink) : Journal.pillLabel;

  @override
  JournalPalette copyWith({
    bool? isDark,
    Color? paper,
    Color? sheet,
    Color? sheetElevated,
    Color? parchment,
    Color? ink,
    Color? primaryFill,
    Color? onPrimaryFill,
    Color? muted,
    Color? sage,
    Color? sageBorder,
    Color? rule,
    Color? ruleStrong,
    Color? cardBorder,
    Color? divider,
    Color? berry,
    Color? berryBg,
    Color? berryBorder,
    Color? ochre,
    Color? ochreBg,
    Color? ochreBorder,
    Color? slate,
    Color? slateBg,
    Color? slateBorder,
    Color? navGlassFill,
    Color? navGlassBorder,
    Color? navGlassHighlight,
  }) =>
      JournalPalette(
        isDark: isDark ?? this.isDark,
        paper: paper ?? this.paper,
        sheet: sheet ?? this.sheet,
        sheetElevated: sheetElevated ?? this.sheetElevated,
        parchment: parchment ?? this.parchment,
        ink: ink ?? this.ink,
        primaryFill: primaryFill ?? this.primaryFill,
        onPrimaryFill: onPrimaryFill ?? this.onPrimaryFill,
        muted: muted ?? this.muted,
        sage: sage ?? this.sage,
        sageBorder: sageBorder ?? this.sageBorder,
        rule: rule ?? this.rule,
        ruleStrong: ruleStrong ?? this.ruleStrong,
        cardBorder: cardBorder ?? this.cardBorder,
        divider: divider ?? this.divider,
        berry: berry ?? this.berry,
        berryBg: berryBg ?? this.berryBg,
        berryBorder: berryBorder ?? this.berryBorder,
        ochre: ochre ?? this.ochre,
        ochreBg: ochreBg ?? this.ochreBg,
        ochreBorder: ochreBorder ?? this.ochreBorder,
        slate: slate ?? this.slate,
        slateBg: slateBg ?? this.slateBg,
        slateBorder: slateBorder ?? this.slateBorder,
        navGlassFill: navGlassFill ?? this.navGlassFill,
        navGlassBorder: navGlassBorder ?? this.navGlassBorder,
        navGlassHighlight: navGlassHighlight ?? this.navGlassHighlight,
      );

  @override
  JournalPalette lerp(covariant JournalPalette? other, double t) {
    if (other == null) return this;
    if (t <= 0) return this;
    if (t >= 1) return other;
    return JournalPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      paper: Color.lerp(paper, other.paper, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      sheetElevated: Color.lerp(sheetElevated, other.sheetElevated, t)!,
      parchment: Color.lerp(parchment, other.parchment, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      primaryFill: Color.lerp(primaryFill, other.primaryFill, t)!,
      onPrimaryFill: Color.lerp(onPrimaryFill, other.onPrimaryFill, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      sageBorder: Color.lerp(sageBorder, other.sageBorder, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      ruleStrong: Color.lerp(ruleStrong, other.ruleStrong, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      berry: Color.lerp(berry, other.berry, t)!,
      berryBg: Color.lerp(berryBg, other.berryBg, t)!,
      berryBorder: Color.lerp(berryBorder, other.berryBorder, t)!,
      ochre: Color.lerp(ochre, other.ochre, t)!,
      ochreBg: Color.lerp(ochreBg, other.ochreBg, t)!,
      ochreBorder: Color.lerp(ochreBorder, other.ochreBorder, t)!,
      slate: Color.lerp(slate, other.slate, t)!,
      slateBg: Color.lerp(slateBg, other.slateBg, t)!,
      slateBorder: Color.lerp(slateBorder, other.slateBorder, t)!,
      navGlassFill: Color.lerp(navGlassFill, other.navGlassFill, t)!,
      navGlassBorder: Color.lerp(navGlassBorder, other.navGlassBorder, t)!,
      navGlassHighlight:
          Color.lerp(navGlassHighlight, other.navGlassHighlight, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalPalette &&
          isDark == other.isDark &&
          paper == other.paper &&
          sheet == other.sheet &&
          ink == other.ink &&
          slate == other.slate &&
          berry == other.berry;

  @override
  int get hashCode => Object.hash(isDark, paper, sheet, ink, slate, berry);
}

class JournalLayout {
  const JournalLayout._();

  static const double floatingNavHeight = 62.0;

  static double floatingNavClearance(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 94.0;

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
      this.eyebrow,
      this.bookTitle = false,
      this.trailing,
      this.trailingWidth = 48});
  final String title;
  final String? eyebrow;
  final bool bookTitle;
  final Widget? trailing;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    final rightPad = trailing == null ? 0.0 : trailingWidth;
    return Stack(children: [
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
      if (trailing != null) Positioned(top: 0, right: 0, child: trailing!),
    ]);
  }
}

// Map subject keywords to quiet single-tone linear icons.
IconData courseIconFor(String name) {
  if (RegExp(r'数|微积分|代数|几何|概率|统计|离散').hasMatch(name)) {
    return Icons.functions_rounded;
  }
  if (RegExp(r'物理|力学|电磁|光学|天文|电路|模电|数电').hasMatch(name)) {
    return Icons.bolt_outlined;
  }
  if (RegExp(r'化学|生物|医学|实验|药').hasMatch(name)) {
    return Icons.science_outlined;
  }
  if (RegExp(r'计算机|信息|安全|软件|数据|程序|编程|算法|网络|人工智能|AI|ai|Python|Java|C\+\+')
      .hasMatch(name)) {
    return Icons.terminal_rounded;
  }
  if (RegExp(r'英语|外语|口语|听力|语言|写作|语文|文学').hasMatch(name)) {
    return Icons.translate_rounded;
  }
  if (RegExp(r'史|纲要|马原|毛概|习概|思政|政治|法|哲学|思想').hasMatch(name)) {
    return Icons.account_balance_outlined;
  }
  if (RegExp(r'制图|机械|工程|建筑|设计|艺术|音乐|美术|影视').hasMatch(name)) {
    return Icons.architecture_outlined;
  }
  if (RegExp(r'经济|管理|金融|会计|市场|财务').hasMatch(name)) {
    return Icons.trending_up_rounded;
  }
  if (RegExp(r'体育|运动|健美|武术|篮球|足球|游泳').hasMatch(name)) {
    return Icons.directions_run_rounded;
  }
  return Icons.menu_book_outlined;
}

class CourseLabel extends StatelessWidget {
  const CourseLabel(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CourseMark(name, size: 28),
          const SizedBox(width: 8),
          Flexible(child: Text(name)),
        ],
      );
}

class CourseMark extends StatelessWidget {
  const CourseMark(this.name, {super.key, this.size = 28, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Icon(
            courseIconFor(name),
            size: (size * 0.72).clamp(18.0, 22.0),
            color: color ?? journal.ink,
          ),
        ),
      ),
    );
  }
}
