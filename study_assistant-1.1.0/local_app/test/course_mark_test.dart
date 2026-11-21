import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';

void main() {
  test('courseIconFor maps subject keywords and defaults to menu_book_outlined',
      () {
    expect(courseIconFor('线性代数'), Icons.functions_rounded);
    expect(courseIconFor('大学物理B（下）'), Icons.bolt_outlined);
    expect(courseIconFor('有机化学实验'), Icons.science_outlined);
    expect(courseIconFor('2026全国大学生AI答题实践竞赛'), Icons.terminal_rounded);
    expect(courseIconFor('信息安全基础'), Icons.terminal_rounded);
    expect(courseIconFor('大学英语听说'), Icons.translate_rounded);
    expect(courseIconFor('中国近现代史纲要'), Icons.account_balance_outlined);
    expect(courseIconFor('机械制图与CAD'), Icons.architecture_outlined);
    expect(courseIconFor('宏观经济学'), Icons.trending_up_rounded);
    expect(courseIconFor('大学生体育'), Icons.directions_run_rounded);
    expect(courseIconFor('未知专题研讨'), Icons.menu_book_outlined);
  });

  testWidgets('CourseMark renders bordered minimal icon in light and dark mode',
      (tester) async {
    Future<(Color? bg, Color? border, Color? iconColor, IconData? icon)>
        renderMark(ThemeData theme, String name) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: CourseMark(name, size: 30)),
        ),
      );
      final box = tester.widget<Container>(find.descendant(
        of: find.byType(CourseMark),
        matching: find.byType(Container),
      ));
      final decoration = box.decoration! as BoxDecoration;
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byType(CourseMark),
        matching: find.byType(Icon),
      ));
      return (
        decoration.color,
        (decoration.border! as Border).top.color,
        icon.color,
        icon.icon,
      );
    }

    final light = await renderMark(StudyAssistantTheme.light, '大学物理B（下）');
    expect(light.$1, JournalPalette.light.paper);
    expect(light.$2, JournalPalette.light.rule);
    expect(light.$3, JournalPalette.light.ink);
    expect(light.$4, Icons.bolt_outlined);

    final dark = await renderMark(StudyAssistantTheme.dark, '大学物理B（下）');
    expect(dark.$1, JournalPalette.dark.paper);
    expect(dark.$2, JournalPalette.dark.rule);
    expect(dark.$3, JournalPalette.dark.ink);
    expect(dark.$4, Icons.bolt_outlined);
  });
}
