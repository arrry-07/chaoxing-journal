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

  test('courseIconFor prefers the first matching subject rule', () {
    const overlaps = {
      '高等数学与大学物理': Icons.functions_rounded,
      '物理化学': Icons.bolt_outlined,
      '生物与 Python': Icons.science_outlined,
      'Python 与英语': Icons.terminal_rounded,
      '英语与历史': Icons.translate_rounded,
      '历史与建筑': Icons.account_balance_outlined,
      '建筑与金融': Icons.architecture_outlined,
      '体育经济': Icons.trending_up_rounded,
    };

    for (final entry in overlaps.entries) {
      expect(courseIconFor(entry.key), entry.value, reason: entry.key);
    }
  });

  testWidgets('CourseMark renders clean linear icon without grey box',
      (tester) async {
    Future<(int containerCount, Color? iconColor, IconData? icon)> renderMark(
        ThemeData theme, String name) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: CourseMark(name, size: 30)),
        ),
      );
      final containers = find.descendant(
        of: find.byType(CourseMark),
        matching: find.byType(Container),
      );
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byType(CourseMark),
        matching: find.byType(Icon),
      ));
      return (
        containers.evaluate().length,
        icon.color,
        icon.icon,
      );
    }

    final light = await renderMark(StudyAssistantTheme.light, '大学物理B（下）');
    expect(light.$1, 0);
    expect(light.$2, JournalPalette.light.ink);
    expect(light.$3, Icons.bolt_outlined);

    final dark = await renderMark(StudyAssistantTheme.dark, '大学物理B（下）');
    expect(dark.$1, 0);
    expect(dark.$2, JournalPalette.dark.ink);
    expect(dark.$3, Icons.bolt_outlined);
  });
}
