import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment sample(String id, {String status = 'pending', DateTime? due}) =>
    Assignment(
        id: 'cx:work:1:2:$id',
        title: '阅读材料与综合实验报告修订说明（2026）',
        courseName: '中国近现代史纲要与跨学科专题讨论课程',
        deadlineAt: due,
        requirementsText: '',
        status: status,
        lastSyncedAt: DateTime(2026, 11, 5));

void main() {
  testWidgets('home restores journal heading without losing sync actions',
      (t) async {
    final s = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(s.dispose);
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: AssignmentListScreen(store: s))));
    expect(find.text('课业手记'), findsOneWidget);
    expect(find.text('CAMPUS JOURNAL   /   01'), findsNothing);
    expect(t.widget<Text>(find.text('课业手记')).style, Journal.display);
    expect(find.byTooltip('刷新作业'), findsOneWidget);
    expect(find.byTooltip('更多'), findsOneWidget);
    await t.tap(find.byTooltip('更多'));
    await t.pumpAndSettle();
    expect(find.text('复制近 7 天待办'), findsOneWidget);
    expect(find.text('同步详情'), findsOneWidget);
  });

  testWidgets('unknown submission keeps exact label and never claims overdue',
      (t) async {
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
            body: AssignmentCard(
                assignment: sample('unknown',
                    status: 'unknown', due: DateTime.utc(2026, 11, 4, 7, 49)),
                now: DateTime.utc(2026, 11, 5),
                onTap: () {}))));
    expect(find.text('提交状态未知'), findsOneWidget);
    expect(find.textContaining('已逾期'), findsNothing);
    expect(find.text('15:49'), findsOneWidget);
  });

  testWidgets('timeline time precedes title and remains usable at large sizes',
      (t) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    for (final scale in [1.0, 2.0]) {
      t.view.physicalSize = const Size(320, 900);
      var taps = 0;
      final a = sample('known', due: DateTime.utc(2026, 11, 6, 7, 49));
      await t.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: ListView(children: [
            AssignmentCard(
                assignment: a,
                now: DateTime.utc(2026, 11, 5),
                onTap: () => taps++)
          ]))));
      expect(t.takeException(), isNull);
      expect(find.text('15:49'), findsOneWidget);
      expect(t.getRect(find.text('15:49')).right,
          lessThan(t.getRect(find.text(a.title)).left));
      expect(find.textContaining('11月6日 15:49'), findsOneWidget);
      await t.tap(find.text(a.title));
      expect(taps, 1);
    }
  });

  group('Phase 1A semantic vermilion & secondary readability', () {
    double linearChannel(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

    double luminance(Color color) =>
        0.2126 * linearChannel(color.r) +
        0.7152 * linearChannel(color.g) +
        0.0722 * linearChannel(color.b);

    double contrastRatio(Color fg, Color bg) {
      final l1 = luminance(fg);
      final l2 = luminance(bg);
      return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
    }

    test('JournalPalette syncs vermilion and muted tokens across light & dark',
        () {
      const light = JournalPalette.light;
      const dark = JournalPalette.dark;

      expect(Journal.berry, const Color(0xFFB5493A));
      expect(Journal.berryBg, const Color(0xFFFBF2EF));
      expect(Journal.berryBorder, const Color(0xFFECD0C8));
      expect(Journal.muted, const Color(0xFF434951));
      expect(Journal.examOrange, const Color(0xFFAD4E0E));
      expect(Journal.todoGreen, const Color(0xFF2A7A4B));

      expect(light.berry, Journal.berry);
      expect(light.berryBg, Journal.berryBg);
      expect(light.berryBorder, Journal.berryBorder);
      expect(light.muted, Journal.muted);
      expect(light.examOrange, Journal.examOrange);
      expect(light.todoGreen, Journal.todoGreen);

      expect(dark.berry, const Color(0xFFE27D70));
      expect(dark.berryBg, const Color(0xFF342222));
      expect(dark.berryBorder, const Color(0xFF61403C));
      expect(dark.muted, const Color(0xFFC4BFB6));
      expect(dark.examOrange, const Color(0xFFF0A05A));
      expect(dark.todoGreen, const Color(0xFF63C58A));

      expect(
          contrastRatio(light.berry, light.berryBg), greaterThanOrEqualTo(4.5));
      expect(
          contrastRatio(light.berry, light.sheet), greaterThanOrEqualTo(4.5));
      expect(
          contrastRatio(light.muted, light.paper), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(light.muted, light.parchment),
          greaterThanOrEqualTo(4.5));
      expect(contrastRatio(light.examOrange, light.examOrangeBg),
          greaterThanOrEqualTo(4.5));
      expect(contrastRatio(light.examOrange, light.sheet),
          greaterThanOrEqualTo(3.0));
      expect(contrastRatio(light.todoGreen, light.todoGreenBg),
          greaterThanOrEqualTo(4.5));
      expect(contrastRatio(light.todoGreen, light.sheet),
          greaterThanOrEqualTo(3.0));

      expect(
          contrastRatio(dark.berry, dark.berryBg), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(dark.berry, dark.sheet), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(dark.muted, dark.paper), greaterThanOrEqualTo(4.5));
      expect(
          contrastRatio(dark.muted, dark.parchment), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(dark.examOrange, dark.examOrangeBg),
          greaterThanOrEqualTo(4.5));
      expect(contrastRatio(dark.examOrange, dark.sheet),
          greaterThanOrEqualTo(3.0));
      expect(contrastRatio(dark.todoGreen, dark.todoGreenBg),
          greaterThanOrEqualTo(4.5));
      expect(
          contrastRatio(dark.todoGreen, dark.sheet), greaterThanOrEqualTo(3.0));

      final copied = light.copyWith(
        berryBorder: const Color(0xFF112233),
        berryBg: const Color(0xFF445566),
        muted: const Color(0xFF778899),
        examOrange: const Color(0xFFAA5500),
        todoGreen: const Color(0xFF116633),
      );
      expect(copied.berryBorder, const Color(0xFF112233));
      expect(copied.berryBg, const Color(0xFF445566));
      expect(copied.muted, const Color(0xFF778899));
      expect(copied.examOrange, const Color(0xFFAA5500));
      expect(copied.todoGreen, const Color(0xFF116633));
      expect(copied, isNot(equals(light)));
      expect(copied.dayHeading.color, const Color(0xFF778899));
      expect(copied.metadata.color, const Color(0xFF778899));

      final mid = light.lerp(dark, 0.5);
      expect(
        mid.berryBorder,
        Color.lerp(light.berryBorder, dark.berryBorder, 0.5),
      );
      expect(mid.berryBg, Color.lerp(light.berryBg, dark.berryBg, 0.5));
      expect(mid.muted, Color.lerp(light.muted, dark.muted, 0.5));
      expect(
        mid.examOrange,
        Color.lerp(light.examOrange, dark.examOrange, 0.5),
      );
      expect(
        mid.todoGreen,
        Color.lerp(light.todoGreen, dark.todoGreen, 0.5),
      );
    });
  });
}
