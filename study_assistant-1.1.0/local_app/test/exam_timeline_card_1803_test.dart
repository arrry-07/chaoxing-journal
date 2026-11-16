import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

final _now = DateTime.utc(2026, 11, 15);
final _start = DateTime.utc(2026, 11, 16, 0, 30);
final _end = DateTime.utc(2026, 11, 16, 2);
const _range = '考试时间：11-16 07:06:00 至 11-30 07:06:31';

Assignment _exam({
  bool notice = false,
  String body = '',
  DateTime? start,
  DateTime? end,
  bool startTrusted = false,
  bool endTrusted = false,
  String location = '',
  String title = '合成考试',
}) =>
    Assignment(
      id: notice ? 'cx:examNotice:inbox:n' : 'cx:exam:1:2:3',
      source: AssignmentSource.exam,
      courseName: '合成课程',
      title: title,
      deadlineAt: end,
      requirementsText: body,
      status: 'pending',
      lastSyncedAt: _now,
      exam: ExamInfo(
        examId: notice ? 'n' : '3',
        relatedExamId: notice ? '3' : null,
        courseId: '1',
        clazzId: '2',
        noticeOnly: notice,
        startAt: start,
        endAt: end,
        startTrusted: startTrusted,
        endTrusted: endTrusted,
        durationMinutes: 90,
        location: location,
      ),
    );

Future<void> _pump(
  WidgetTester t,
  Assignment a, {
  List<Assignment> sources = const [],
  bool openButton = false,
  double scale = 1,
}) async {
  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AssignmentCard(
            assignment: a,
            examSources: sources,
            now: _now,
            onTap: () {},
            onOpenAssignment: openButton ? () {} : null,
          ),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('trusted start occupies left rail without full visual range',
      (t) async {
    await _pump(
        t,
        _exam(
          start: _start,
          end: _end,
          startTrusted: true,
          endTrusted: true,
          location: '教学楼101',
        ));
    expect(find.text('08:30'), findsOneWidget);
    expect(t.getTopLeft(find.text('08:30')).dx, 16);
    expect(t.getTopLeft(find.text('合成考试')).dx, greaterThan(16));
    expect(find.text('考试 · 未开始 · 待参加'), findsOneWidget);
    expect(find.text('时长 90 分钟'), findsOneWidget);
    expect(find.text('地点 教学楼101'), findsOneWidget);
    expect(find.textContaining('开考 '), findsNothing);
    expect(find.textContaining('结束 '), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('linked yearless start supplies display clock without trust',
      (t) async {
    final a = _exam();
    final n = _exam(notice: true, body: _range);
    final before = a.toJson();
    await _pump(t, a, sources: [a, n]);
    expect(find.text('07:06'), findsOneWidget);
    expect(t.getTopLeft(find.text('07:06')).dx, 16);
    expect(t.getTopLeft(find.text('合成考试')).dx, greaterThan(16));
    expect(find.text(_range), findsNothing);
    expect(a.toJson(), before);
    expect(a.exam!.startAt, isNull);
    expect(a.exam!.startTrusted, isFalse);
    expect(a.reminderAnchorAt, isNull);
    expect(t.takeException(), isNull);
  });

  for (final scenario in [
    'unknown',
    'untrusted instant',
    'end only',
    'notice end only',
  ]) {
    testWidgets('$scenario has no clock rail or placeholder', (t) async {
      final a = switch (scenario) {
        'untrusted instant' => _exam(start: _start),
        'end only' => _exam(end: _end, endTrusted: true),
        'notice end only' => _exam(notice: true, body: '结束时间：11-16 10:00'),
        _ => _exam(),
      };
      await _pump(t, a);
      expect(t.getTopLeft(find.text('合成考试')).dx, 16);
      expect(find.text('—'), findsNothing);
      expect(find.textContaining(RegExp(r'\d{2}:\d{2}')), findsNothing);
      expect(find.textContaining('地点'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('semantics retains full trusted range hidden visually',
      (t) async {
    final semantics = t.ensureSemantics();
    await _pump(
        t,
        _exam(
          start: _start,
          end: _end,
          startTrusted: true,
          endTrusted: true,
        ));
    expect(
      find.bySemanticsLabel(
          RegExp(r'合成考试.*开考 2026年11月16日 08:30.*结束 2026年11月16日 10:00.*北京时间')),
      findsOneWidget,
    );
    expect(find.textContaining('2026年'), findsNothing);
    semantics.dispose();
  });

  testWidgets('semantics retains complete linked notice range', (t) async {
    final semantics = t.ensureSemantics();
    final a = _exam();
    await _pump(t, a, sources: [a, _exam(notice: true, body: _range)]);
    expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_range))), findsOneWidget);
    expect(find.text(_range), findsNothing);
    semantics.dispose();
  });

  for (final openButton in [false, true]) {
    testWidgets('320 wide at 2x text fits with open button $openButton',
        (t) async {
      await t.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      for (final trusted in [true, false]) {
        final a = _exam(
          start: trusted ? _start : null,
          end: trusted ? _end : null,
          startTrusted: trusted,
          endTrusted: trusted,
          title: '合成考试名称很长需要在窄屏下自动换行',
          location: '教学楼第一考场三层教室101',
        );
        await _pump(t, a,
            sources: trusted ? [] : [a, _exam(notice: true, body: _range)],
            scale: 2,
            openButton: openButton);
        final clock = find.text(trusted ? '08:30' : '07:06');
        expect(clock, findsOneWidget);
        expect(t.getRect(clock).right, lessThanOrEqualTo(304));
        expect(t.getRect(find.text(a.title)).right, lessThanOrEqualTo(304));
        expect(find.text('时长 90 分钟'), findsOneWidget);
        expect(find.text('地点 教学楼第一考场三层教室101'), findsOneWidget);
        expect(t.takeException(), isNull);
      }
    });
  }
}
