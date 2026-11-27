import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

Assignment _item() => Assignment(
    id: 'cx:work:1:2:3',
    title: '作业',
    courseName: '课程',
    requirementsText: '',
    status: 'pending',
    deadlineAt: DateTime.utc(2026, 11, 20, 15, 59),
    deadlineTrusted: true,
    lastSyncedAt: DateTime.utc(2026, 11, 18));

Future<void> _pump(
  WidgetTester tester, {
  required double scale,
  required VoidCallback onTap,
  required VoidCallback onOpen,
  bool opening = false,
  bool previewOnly = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: StudyAssistantTheme.light,
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AssignmentCard(
            assignment: _item(),
            now: DateTime.utc(2026, 11, 18),
            opening: opening,
            previewOnly: previewOnly,
            onTap: onTap,
            onOpenAssignment: onOpen,
          ),
        ],
      ),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('external link is one actionable semantics node at 1x and 2x',
      (tester) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    final semantics = tester.ensureSemantics();
    try {
      for (final scale in [1.0, 2.0]) {
        var details = 0, opens = 0;
        await _pump(tester,
            scale: scale, onTap: () => details++, onOpen: () => opens++);

        final link = find.semantics.byLabel('在学习通内打开作业');
        expect(link, findsOneWidget, reason: 'scale $scale');
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('在学习通内打开作业'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'scale $scale',
        );
        tester.semantics.tap(link);
        await tester.pump();
        expect(opens, 1, reason: 'scale $scale');
        expect(details, 0, reason: 'scale $scale');

        final body = find.semantics.byLabel(RegExp('^作业，课程，'));
        expect(body, findsOneWidget, reason: 'scale $scale');
        tester.semantics.tap(body);
        await tester.pump();
        expect(details, 1, reason: 'scale $scale');
        expect(opens, 1, reason: 'scale $scale');

        final button =
            find.byKey(const ValueKey('open-assignment-cx:work:1:2:3'));
        await tester.tap(button);
        await tester.pump();
        expect(opens, 2, reason: 'scale $scale');
        expect(details, 1, reason: 'scale $scale');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('opening and preview states expose no activation action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final state in [
        (opening: true, previewOnly: false, label: '正在打开…'),
        (opening: false, previewOnly: true, label: '保存后可打开'),
      ]) {
        var opens = 0;
        await _pump(
          tester,
          scale: 2,
          opening: state.opening,
          previewOnly: state.previewOnly,
          settle: !state.opening,
          onTap: () {},
          onOpen: () => opens++,
        );
        final link = find.semantics.byLabel(state.label);
        expect(link, findsOneWidget);
        final data = tester
            .getSemantics(find.bySemanticsLabel(state.label))
            .getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        final semanticsWidget = tester.widget<Semantics>(find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == state.label));
        expect(semanticsWidget.properties.enabled, isFalse);
        expect(opens, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('countdown keeps the absolute deadline in the card label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: AssignmentCard(
            assignment: _item(),
            now: DateTime.utc(2026, 11, 18),
            countdown: true,
            onTap: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel(
          RegExp(r'截止 11月20日 23:59，后天'),
        ),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
}
