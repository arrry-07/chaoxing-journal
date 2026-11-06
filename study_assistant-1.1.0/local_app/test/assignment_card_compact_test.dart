import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

void main() {
  testWidgets('compact actions stay tappable and reflow with narrow large text',
      (t) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    for (final width in [320.0, 393.0]) {
      for (final scale in [1.0, 2.0]) {
        var details = 0, opens = 0;
        t.view.physicalSize = Size(width, 850);
        final key = GlobalKey();
        final item = Assignment(
            id: 'cx:work:1:2:3',
            title: '综合实验与分析报告（样例）',
            courseName: '计算方法与实践',
            requirementsText: '',
            status: 'pending',
            deadlineAt: DateTime.utc(2026, 11, 7, 7, 23),
            deadlineTrusted: true,
            lastSyncedAt: DateTime.utc(2026, 11, 6));
        await t.pumpWidget(RepaintBoundary(
            child: MaterialApp(
          theme: StudyAssistantTheme.light,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: ListView(padding: const EdgeInsets.all(16), children: [
            RepaintBoundary(
                key: key,
                child: ColoredBox(
                    color: Journal.paper,
                    child: AssignmentCard(
                        assignment: item,
                        now: DateTime.utc(2026, 11, 6),
                        showFullDeadline: false,
                        onTap: () => details++,
                        onOpenAssignment: () => opens++))),
          ])),
        )));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$width/$scale');
        final action = find.text('去学习通完成');
        expect(t.getSize(find.widgetWithText(TextButton, '去学习通完成')).height,
            greaterThanOrEqualTo(48));
        await t.tap(action);
        expect(opens, 1);
        expect(details, 0);
        await t.tap(find.text(item.title));
        expect(details, 1);
        await t.tap(find.text('待提交'));
        expect(details, 2);
        await t.pumpAndSettle();
        if (width == 393 && scale == 1) {
          expect(
              (t.getCenter(find.text('待提交')).dy - t.getCenter(action).dy).abs(),
              lessThan(4));
        }
        if (const bool.fromEnvironment('CAPTURE_UI')) {
          await t.runAsync(() async {
            final out = Directory(
                '${Directory.current.resolveSymbolicLinksSync()}/../../artifacts/current/compact-assignment');
            await out.create(recursive: true);
            final picture = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
            final bytes =
                (await picture.toByteData(format: ui.ImageByteFormat.png))!
                    .buffer
                    .asUint8List();
            await File('${out.path}/card-${width.toInt()}-$scale.png')
                .writeAsBytes(bytes);
            picture.dispose();
          });
        }
      }
    }
  });
}
