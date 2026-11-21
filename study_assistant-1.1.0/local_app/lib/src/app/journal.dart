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
  static const berry = Color(0xFFC53B3B);
  static const berryBg = Color(0xFFFDF2F2);
  static const berryBorder = Color(0xFFF3D1D1);
  static const ochre = Color(0xFF4F5D73);
  static const ochreBg = Color(0xFFEFF1F5);
  static const ochreBorder = Color(0xFFD8DEE8);
  static const slate = Color(0xFF3D63DD);
  static const slateBg = Color(0xFFEAF0FD);
  static const slateBorder = Color(0xFFC9D6F7);

  static const displayFamily = 'LXGW WenKai Screen';
  static const bodyFamily = displayFamily;
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
    fontWeight: FontWeight.w400,
    height: 1.38,
  );
  static const entryTitle = TextStyle(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
    fontSize: 16,
    fontWeight: FontWeight.w400,
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
  Color get berry => this == dark ? const Color(0xFFEF7A7A) : Journal.berry;
  Color get berryBg => this == dark ? const Color(0xFF332022) : Journal.berryBg;
  Color get berryBorder =>
      this == dark ? const Color(0xFF5C3438) : Journal.berryBorder;
  Color get ochre => this == dark ? const Color(0xFFA3B1C6) : Journal.ochre;
  Color get ochreBg => this == dark ? const Color(0xFF262A33) : Journal.ochreBg;
  Color get ochreBorder =>
      this == dark ? const Color(0xFF3C424F) : Journal.ochreBorder;
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

// Map subject keywords to quiet single-tone line icons matching the settings list.
@visibleForTesting
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
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: journal.paper,
          borderRadius: BorderRadius.circular(size * .28),
          border: Border.all(color: journal.rule, width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(
          courseIconFor(name),
          size: size * .56,
          color: journal.ink,
        ),
      ),
    );
  }
}
