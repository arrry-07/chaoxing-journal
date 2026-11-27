import 'dart:math' as math;

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
  static const muted = Color(0xFF363C44);
  static const sage = Color(0xFFEAF0FD);
  static const sageBorder = Color(0xFFC9D6F7);
  static const rule = Color(0xFFE6E5E0);
  static const ruleStrong = Color(0xFFD6D5CE);
  static const divider = Color(0xFFECEBE6);
  static const berry = Color(0xFFB5493A);
  static const berryBg = Color(0xFFFBF2EF);
  static const berryBorder = Color(0xFFECD0C8);
  static const overdueSky = Color(0xFF0369A1);
  static const overdueSkyBg = Color(0xFFE0F2FE);
  static const examOrange = Color(0xFFAD4E0E);
  static const examOrangeBg = Color(0xFFFDF2E6);
  static const examOrangeBorder = Color(0xFFEED3B6);
  static const todoGreen = Color(0xFF2A7A4B);
  static const todoGreenBg = Color(0xFFEAF6EE);
  static const todoGreenBorder = Color(0xFFC1E0CC);
  static const ochre = Color(0xFF4F5D73);
  static const ochreBg = Color(0xFFEFF2F6);
  static const ochreBorder = Color(0xFFD8DEE8);
  static const slate = Color(0xFF3D63DD);
  static const slateBg = Color(0xFFEAF0FD);

  static const displayFamily = 'LXGW WenKai Screen';
  static const titleFamily = displayFamily;
  static const bodyFamily = displayFamily;
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
    fontWeight: FontWeight.w400,
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
    fontWeight: FontWeight.w400,
    height: 1.38,
    color: ink,
  );
  static const metadata = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 13.5,
    height: 1.45,
    fontFeatures: [FontFeature.tabularFigures()],
    color: muted,
  );
  static const time = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
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
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ink,
  );
}

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
    required this.subtle,
    required this.sage,
    required this.sageBorder,
    required this.rule,
    required this.ruleStrong,
    required this.cardBorder,
    required this.divider,
    required this.berry,
    required this.berryBg,
    required this.berryBorder,
    required this.overdueSky,
    required this.overdueSkyBg,
    required this.examOrange,
    required this.examOrangeBg,
    required this.examOrangeBorder,
    required this.todoGreen,
    required this.todoGreenBg,
    required this.todoGreenBorder,
    required this.ochre,
    required this.ochreBg,
    required this.ochreBorder,
    required this.slate,
    required this.slateBg,
    required this.navGlassFill,
    required this.navGlassBorder,
    required this.navGlassHighlight,
    required this.ambientPrimaryGlow,
    required this.ambientWarmGlow,
    required this.cardShadowContact,
    required this.cardShadowAmbient,
    required this.cardTopHighlight,
    required this.cardEmphasisTintStart,
    required this.cardEmphasisTintEnd,
    required this.cardEmphasisBar,
    required this.cardEmphasisBarGlow,
  });

  static const light = JournalPalette(
    isDark: false,
    paper: Journal.paper,
    sheet: Journal.sheet,
    sheetElevated: Color(0xFFFFFFFF),
    parchment: Journal.parchment,
    ink: Journal.ink,
    primaryFill: Journal.slate,
    onPrimaryFill: Color(0xFFFFFFFF),
    muted: Journal.muted,
    subtle: Color(0xFF565E69),
    sage: Journal.sage,
    sageBorder: Journal.sageBorder,
    rule: Journal.rule,
    ruleStrong: Journal.ruleStrong,
    cardBorder: Journal.rule,
    divider: Journal.divider,
    berry: Journal.berry,
    berryBg: Journal.berryBg,
    berryBorder: Journal.berryBorder,
    overdueSky: Journal.overdueSky,
    overdueSkyBg: Journal.overdueSkyBg,
    examOrange: Journal.examOrange,
    examOrangeBg: Journal.examOrangeBg,
    examOrangeBorder: Journal.examOrangeBorder,
    todoGreen: Journal.todoGreen,
    todoGreenBg: Journal.todoGreenBg,
    todoGreenBorder: Journal.todoGreenBorder,
    ochre: Journal.ochre,
    ochreBg: Journal.ochreBg,
    ochreBorder: Journal.ochreBorder,
    slate: Journal.slate,
    slateBg: Journal.slateBg,
    navGlassFill: Color(0xD9FFFFFF),
    navGlassBorder: Color(0xB3E5E5E0),
    navGlassHighlight: Color(0x80FFFFFF),
    ambientPrimaryGlow: Color(0x163D63DD),
    ambientWarmGlow: Color(0x12D97757),
    cardShadowContact: Color(0x071F2328),
    cardShadowAmbient: Color(0x0A1F2328),
    cardTopHighlight: Color(0xB8FFFFFF),
    cardEmphasisTintStart: Color(0x0F3D63DD),
    cardEmphasisTintEnd: Color(0x003D63DD),
    cardEmphasisBar: Color(0xCC3D63DD),
    cardEmphasisBarGlow: Color(0x2E3D63DD),
  );

  // "深夜台灯纸感" warm charcoal paper palette: avoids pure #000/#FFF glare.
  static const dark = JournalPalette(
    isDark: true,
    paper: Color(0xFF191816),
    sheet: Color(0xFF23221F),
    sheetElevated: Color(0xFF2B2A26),
    parchment: Color(0xFF2E2D29),
    ink: Color(0xFFEAE6DF),
    primaryFill: Color(0xFF88A8F8),
    onPrimaryFill: Color(0xFF1A1917),
    muted: Color(0xFFC4BFB6),
    subtle: Color(0xFFA5A096),
    sage: Color(0xFF252B3B),
    sageBorder: Color(0xFF3D4C6E),
    rule: Color(0xFF32302B),
    ruleStrong: Color(0xFF403E38),
    cardBorder: Color(0x14FFF8EB),
    divider: Color(0x10FFF8EB),
    berry: Color(0xFFE27D70),
    berryBg: Color(0xFF342222),
    berryBorder: Color(0xFF61403C),
    overdueSky: Color(0xFF5CC8FF),
    overdueSkyBg: Color(0xFF152B3A),
    examOrange: Color(0xFFF0A05A),
    examOrangeBg: Color(0xFF33271D),
    examOrangeBorder: Color(0xFF5D432E),
    todoGreen: Color(0xFF63C58A),
    todoGreenBg: Color(0xFF1F3026),
    todoGreenBorder: Color(0xFF345742),
    ochre: Color(0xFFAEBACB),
    ochreBg: Color(0xFF272B32),
    ochreBorder: Color(0xFF3D434F),
    slate: Color(0xFF88A8F8),
    slateBg: Color(0xFF252B3B),
    navGlassFill: Color(0xCC242320),
    navGlassBorder: Color(0x16FFF8EB),
    navGlassHighlight: Color(0x26FFF8EB),
    ambientPrimaryGlow: Color(0x1C88A8F8),
    ambientWarmGlow: Color(0x1AE5896B),
    cardShadowContact: Color(0x24000000),
    cardShadowAmbient: Color(0x38000000),
    cardTopHighlight: Color(0x18FFF8EB),
    cardEmphasisTintStart: Color(0x1888A8F8),
    cardEmphasisTintEnd: Color(0x0488A8F8),
    cardEmphasisBar: Color(0xCC88A8F8),
    cardEmphasisBarGlow: Color(0x3688A8F8),
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
  final Color subtle;
  final Color sage;
  final Color sageBorder;
  final Color rule;
  final Color ruleStrong;
  final Color cardBorder;
  final Color divider;
  final Color berry;
  final Color berryBg;
  final Color berryBorder;
  final Color overdueSky;
  final Color overdueSkyBg;
  final Color examOrange;
  final Color examOrangeBg;
  final Color examOrangeBorder;
  final Color todoGreen;
  final Color todoGreenBg;
  final Color todoGreenBorder;
  final Color ochre;
  final Color ochreBg;
  final Color ochreBorder;
  final Color slate;
  final Color slateBg;
  final Color navGlassFill;
  final Color navGlassBorder;
  final Color navGlassHighlight;
  final Color ambientPrimaryGlow;
  final Color ambientWarmGlow;
  final Color cardShadowContact;
  final Color cardShadowAmbient;
  final Color cardTopHighlight;
  final Color cardEmphasisTintStart;
  final Color cardEmphasisTintEnd;
  final Color cardEmphasisBar;
  final Color cardEmphasisBarGlow;

  Color get accent => slate;

  Color get onInvertedSurface =>
      isDark ? const Color(0xFF1A1917) : const Color(0xFFFFFFFF);

  /// Action text on the inverted (ink-filled) snackbar. Dark mode inverts the
  /// fill to warm ivory, so the action needs a deep blue to stay >= 4.5:1.
  Color get snackActionColor => isDark ? const Color(0xFF2B4EB8) : slateBg;

  /// Segmented control track/thumb: the thumb must read as raised above the
  /// track in both themes (dark: lighter elevated thumb on a deeper track).
  Color get segmentTrack => isDark ? const Color(0xFF21201D) : parchment;
  Color get segmentThumb => isDark ? sheetElevated : sheet;
  Border? get segmentBorder =>
      isDark ? Border.all(color: cardBorder, width: 0.7) : null;

  Color get sectionHeaderFill => Color.lerp(sheet, parchment, 0.34)!;

  TextStyle get display => Journal.display.copyWith(color: ink);
  TextStyle get pageTitle => Journal.pageTitle.copyWith(color: ink);
  TextStyle get dayHeading => Journal.dayHeading.copyWith(color: muted);
  TextStyle get section => Journal.section.copyWith(color: ink);
  TextStyle get entryTitle => Journal.entryTitle.copyWith(color: ink);
  TextStyle get metadata => Journal.metadata.copyWith(color: muted);
  TextStyle get time => Journal.time.copyWith(color: ink);
  TextStyle get statHero => Journal.statHero.copyWith(color: ink);
  TextStyle get pillLabel => Journal.pillLabel.copyWith(color: ink);

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
    Color? subtle,
    Color? sage,
    Color? sageBorder,
    Color? rule,
    Color? ruleStrong,
    Color? cardBorder,
    Color? divider,
    Color? berry,
    Color? berryBg,
    Color? berryBorder,
    Color? overdueSky,
    Color? overdueSkyBg,
    Color? examOrange,
    Color? examOrangeBg,
    Color? examOrangeBorder,
    Color? todoGreen,
    Color? todoGreenBg,
    Color? todoGreenBorder,
    Color? ochre,
    Color? ochreBg,
    Color? ochreBorder,
    Color? slate,
    Color? slateBg,
    Color? navGlassFill,
    Color? navGlassBorder,
    Color? navGlassHighlight,
    Color? ambientPrimaryGlow,
    Color? ambientWarmGlow,
    Color? cardShadowContact,
    Color? cardShadowAmbient,
    Color? cardTopHighlight,
    Color? cardEmphasisTintStart,
    Color? cardEmphasisTintEnd,
    Color? cardEmphasisBar,
    Color? cardEmphasisBarGlow,
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
        subtle: subtle ?? this.subtle,
        sage: sage ?? this.sage,
        sageBorder: sageBorder ?? this.sageBorder,
        rule: rule ?? this.rule,
        ruleStrong: ruleStrong ?? this.ruleStrong,
        cardBorder: cardBorder ?? this.cardBorder,
        divider: divider ?? this.divider,
        berry: berry ?? this.berry,
        berryBg: berryBg ?? this.berryBg,
        berryBorder: berryBorder ?? this.berryBorder,
        overdueSky: overdueSky ?? this.overdueSky,
        overdueSkyBg: overdueSkyBg ?? this.overdueSkyBg,
        examOrange: examOrange ?? this.examOrange,
        examOrangeBg: examOrangeBg ?? this.examOrangeBg,
        examOrangeBorder: examOrangeBorder ?? this.examOrangeBorder,
        todoGreen: todoGreen ?? this.todoGreen,
        todoGreenBg: todoGreenBg ?? this.todoGreenBg,
        todoGreenBorder: todoGreenBorder ?? this.todoGreenBorder,
        ochre: ochre ?? this.ochre,
        ochreBg: ochreBg ?? this.ochreBg,
        ochreBorder: ochreBorder ?? this.ochreBorder,
        slate: slate ?? this.slate,
        slateBg: slateBg ?? this.slateBg,
        navGlassFill: navGlassFill ?? this.navGlassFill,
        navGlassBorder: navGlassBorder ?? this.navGlassBorder,
        navGlassHighlight: navGlassHighlight ?? this.navGlassHighlight,
        ambientPrimaryGlow: ambientPrimaryGlow ?? this.ambientPrimaryGlow,
        ambientWarmGlow: ambientWarmGlow ?? this.ambientWarmGlow,
        cardShadowContact: cardShadowContact ?? this.cardShadowContact,
        cardShadowAmbient: cardShadowAmbient ?? this.cardShadowAmbient,
        cardTopHighlight: cardTopHighlight ?? this.cardTopHighlight,
        cardEmphasisTintStart:
            cardEmphasisTintStart ?? this.cardEmphasisTintStart,
        cardEmphasisTintEnd: cardEmphasisTintEnd ?? this.cardEmphasisTintEnd,
        cardEmphasisBar: cardEmphasisBar ?? this.cardEmphasisBar,
        cardEmphasisBarGlow: cardEmphasisBarGlow ?? this.cardEmphasisBarGlow,
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
      subtle: Color.lerp(subtle, other.subtle, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      sageBorder: Color.lerp(sageBorder, other.sageBorder, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      ruleStrong: Color.lerp(ruleStrong, other.ruleStrong, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      berry: Color.lerp(berry, other.berry, t)!,
      berryBg: Color.lerp(berryBg, other.berryBg, t)!,
      berryBorder: Color.lerp(berryBorder, other.berryBorder, t)!,
      overdueSky: Color.lerp(overdueSky, other.overdueSky, t)!,
      overdueSkyBg: Color.lerp(overdueSkyBg, other.overdueSkyBg, t)!,
      examOrange: Color.lerp(examOrange, other.examOrange, t)!,
      examOrangeBg: Color.lerp(examOrangeBg, other.examOrangeBg, t)!,
      examOrangeBorder:
          Color.lerp(examOrangeBorder, other.examOrangeBorder, t)!,
      todoGreen: Color.lerp(todoGreen, other.todoGreen, t)!,
      todoGreenBg: Color.lerp(todoGreenBg, other.todoGreenBg, t)!,
      todoGreenBorder: Color.lerp(todoGreenBorder, other.todoGreenBorder, t)!,
      ochre: Color.lerp(ochre, other.ochre, t)!,
      ochreBg: Color.lerp(ochreBg, other.ochreBg, t)!,
      ochreBorder: Color.lerp(ochreBorder, other.ochreBorder, t)!,
      slate: Color.lerp(slate, other.slate, t)!,
      slateBg: Color.lerp(slateBg, other.slateBg, t)!,
      navGlassFill: Color.lerp(navGlassFill, other.navGlassFill, t)!,
      navGlassBorder: Color.lerp(navGlassBorder, other.navGlassBorder, t)!,
      navGlassHighlight:
          Color.lerp(navGlassHighlight, other.navGlassHighlight, t)!,
      ambientPrimaryGlow:
          Color.lerp(ambientPrimaryGlow, other.ambientPrimaryGlow, t)!,
      ambientWarmGlow: Color.lerp(ambientWarmGlow, other.ambientWarmGlow, t)!,
      cardShadowContact:
          Color.lerp(cardShadowContact, other.cardShadowContact, t)!,
      cardShadowAmbient:
          Color.lerp(cardShadowAmbient, other.cardShadowAmbient, t)!,
      cardTopHighlight:
          Color.lerp(cardTopHighlight, other.cardTopHighlight, t)!,
      cardEmphasisTintStart:
          Color.lerp(cardEmphasisTintStart, other.cardEmphasisTintStart, t)!,
      cardEmphasisTintEnd:
          Color.lerp(cardEmphasisTintEnd, other.cardEmphasisTintEnd, t)!,
      cardEmphasisBar: Color.lerp(cardEmphasisBar, other.cardEmphasisBar, t)!,
      cardEmphasisBarGlow:
          Color.lerp(cardEmphasisBarGlow, other.cardEmphasisBarGlow, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalPalette &&
          isDark == other.isDark &&
          paper == other.paper &&
          sheet == other.sheet &&
          sheetElevated == other.sheetElevated &&
          parchment == other.parchment &&
          ink == other.ink &&
          primaryFill == other.primaryFill &&
          onPrimaryFill == other.onPrimaryFill &&
          muted == other.muted &&
          subtle == other.subtle &&
          sage == other.sage &&
          sageBorder == other.sageBorder &&
          rule == other.rule &&
          ruleStrong == other.ruleStrong &&
          cardBorder == other.cardBorder &&
          divider == other.divider &&
          berry == other.berry &&
          berryBg == other.berryBg &&
          berryBorder == other.berryBorder &&
          overdueSky == other.overdueSky &&
          overdueSkyBg == other.overdueSkyBg &&
          examOrange == other.examOrange &&
          examOrangeBg == other.examOrangeBg &&
          examOrangeBorder == other.examOrangeBorder &&
          todoGreen == other.todoGreen &&
          todoGreenBg == other.todoGreenBg &&
          todoGreenBorder == other.todoGreenBorder &&
          ochre == other.ochre &&
          ochreBg == other.ochreBg &&
          ochreBorder == other.ochreBorder &&
          slate == other.slate &&
          slateBg == other.slateBg &&
          navGlassFill == other.navGlassFill &&
          navGlassBorder == other.navGlassBorder &&
          navGlassHighlight == other.navGlassHighlight &&
          ambientPrimaryGlow == other.ambientPrimaryGlow &&
          ambientWarmGlow == other.ambientWarmGlow &&
          cardShadowContact == other.cardShadowContact &&
          cardShadowAmbient == other.cardShadowAmbient &&
          cardTopHighlight == other.cardTopHighlight &&
          cardEmphasisTintStart == other.cardEmphasisTintStart &&
          cardEmphasisTintEnd == other.cardEmphasisTintEnd &&
          cardEmphasisBar == other.cardEmphasisBar &&
          cardEmphasisBarGlow == other.cardEmphasisBarGlow;

  @override
  int get hashCode => Object.hashAll([
        isDark,
        paper,
        sheet,
        sheetElevated,
        parchment,
        ink,
        primaryFill,
        onPrimaryFill,
        muted,
        subtle,
        sage,
        sageBorder,
        rule,
        ruleStrong,
        cardBorder,
        divider,
        berry,
        berryBg,
        berryBorder,
        overdueSky,
        overdueSkyBg,
        examOrange,
        examOrangeBg,
        examOrangeBorder,
        todoGreen,
        todoGreenBg,
        todoGreenBorder,
        ochre,
        ochreBg,
        ochreBorder,
        slate,
        slateBg,
        navGlassFill,
        navGlassBorder,
        navGlassHighlight,
        ambientPrimaryGlow,
        ambientWarmGlow,
        cardShadowContact,
        cardShadowAmbient,
        cardTopHighlight,
        cardEmphasisTintStart,
        cardEmphasisTintEnd,
        cardEmphasisBar,
        cardEmphasisBarGlow,
      ]);
}

class JournalLayout {
  const JournalLayout._();

  static const double floatingNavHeight = 62.0;

  /// Bottom inset that keeps the last row clear of the floating nav bar.
  /// Inside AppShell (`Scaffold.extendBody`) `padding.bottom` already includes
  /// the nav bar and any banners above it, so only a small gap is added; when
  /// a tab is rendered standalone the device inset plus 94dp is the floor.
  static double floatingNavClearance(BuildContext context) {
    final media = MediaQuery.of(context);
    return math.max(
      media.padding.bottom + 14.0,
      media.viewPadding.bottom + 94.0,
    );
  }

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
      this.bookTitle = false,
      this.trailing,
      this.trailingWidth = 48});
  final String title;
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
final _courseIconRules = <(RegExp, IconData)>[
  (RegExp(r'数|微积分|代数|几何|概率|统计|离散'), Icons.functions_rounded),
  (RegExp(r'物理|力学|电磁|光学|天文|电路|模电|数电'), Icons.bolt_outlined),
  (RegExp(r'化学|生物|医学|实验|药'), Icons.science_outlined),
  (
    RegExp(r'计算机|信息|安全|软件|数据|程序|编程|算法|网络|人工智能|AI|ai|Python|Java|C\+\+'),
    Icons.terminal_rounded
  ),
  (RegExp(r'英语|外语|口语|听力|语言|写作|语文|文学'), Icons.translate_rounded),
  (RegExp(r'史|纲要|马原|毛概|习概|思政|政治|法|哲学|思想'), Icons.account_balance_outlined),
  (RegExp(r'制图|机械|工程|建筑|设计|艺术|音乐|美术|影视'), Icons.architecture_outlined),
  (RegExp(r'经济|管理|金融|会计|市场|财务'), Icons.trending_up_rounded),
  (RegExp(r'体育|运动|健美|武术|篮球|足球|游泳'), Icons.directions_run_rounded),
];

IconData courseIconFor(String name) {
  for (final (pattern, icon) in _courseIconRules) {
    if (pattern.hasMatch(name)) return icon;
  }
  return Icons.menu_book_outlined;
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
