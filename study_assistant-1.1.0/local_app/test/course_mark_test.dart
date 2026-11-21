import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';

void main() {
  test('courseMonogram extracts first Chinese character or uppercase letter',
      () {
    expect(courseMonogram('2026全国大学生AI答题'), '全');
    expect(courseMonogram('AI导论'), 'A');
    expect(courseMonogram('（上）大学物理'), '大');
    expect(courseMonogram('电磁学（上）练习'), '电');
    expect(courseMonogram('中国近现代史纲要'), '中');
    expect(courseMonogram(''), '课');
    expect(courseMonogram('2026 '), '课');
  });

  testWidgets('CourseMark assigns deterministic colors for the same course',
      (tester) async {
    Future<(Color? bg, Color? fg)> renderColor(String name) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(body: CourseMark(name, size: 30)),
        ),
      );
      final box = tester.widget<Container>(find.descendant(
        of: find.byType(CourseMark),
        matching: find.byType(Container),
      ));
      final text = tester.widget<Text>(find.descendant(
        of: find.byType(CourseMark),
        matching: find.byType(Text),
      ));
      return ((box.decoration! as BoxDecoration).color, text.style?.color);
    }

    final first = await renderColor('中国近现代史纲要');
    await renderColor('AI导论');
    final second = await renderColor('中国近现代史纲要');
    expect(second, first);
    expect(first.$1, isNotNull);
    expect(first.$2, isNotNull);
  });
}
