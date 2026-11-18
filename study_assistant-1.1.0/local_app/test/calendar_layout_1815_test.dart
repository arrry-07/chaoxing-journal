import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _Store extends AssignmentStore {
  _Store()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
        );
}

Assignment _work(
  String id, {
  required String title,
  required DateTime deadlineAt,
  String course = '课程',
  String courseId = 'c',
  String classId = 'k',
  bool trusted = true,
}) =>
    Assignment(
      id: 'cx:work:$courseId:$classId:$id',
      courseName: course,
      title: title,
      requirementsText: '',
      status: 'pending',
      deadlineAt: deadlineAt,
      deadlineTrusted: trusted,
      lastSyncedAt: DateTime.utc(2026, 11, 1),
    );

Assignment _exam(String id, {required DateTime start}) => Assignment(
      id: 'cx:exam:4:5:$id',
      source: AssignmentSource.exam,
      courseName: '考试课程',
      title: '考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'unknown',
      lastSyncedAt: DateTime.utc(2026, 11, 1),
      exam: ExamInfo(
        examId: id,
        courseId: '4',
        clazzId: '5',
        startAt: start,
        startTrusted: true,
        lifecycle: 'scheduled',
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  _Store store, {
  required DateTime now,
  Size size = const Size(320, 640),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
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
    home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
  ));
  await tester.pumpAndSettle();
}

Finder _daySemantics(int month, int day, {bool today = false}) =>
    find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        (widget.properties.label ?? '')
            .startsWith('$month月$day日${today ? '，今天' : ''}'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('calendar cells fit trusted font at 320dp across text scales',
      (tester) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    final now = DateTime.utc(2026, 11, 18, 2);
    for (final scale in [1.0, 1.38, 1.7, 2.0]) {
      final store = _Store()
        ..replaceAssignmentsForTest([
          _work(
            'today',
            title: '今日课业',
            deadlineAt: DateTime.utc(2026, 11, 18, 15, 59),
          ),
        ]);
      addTearDown(store.dispose);
      await _pump(tester, store, now: now, scale: scale);
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      expect(find.byKey(const ValueKey('calendar-count-18')), findsOneWidget);
      final cell = tester.getSize(_daySemantics(11, 18, today: true));
      expect(cell.height, greaterThanOrEqualTo(48), reason: 'scale $scale');
      if (scale == 1.0) {
        expect(cell.height, closeTo(48, 0.01));
        expect(
          find.byKey(const ValueKey('calendar-month-inline')),
          findsOneWidget,
        );
      }
      if (scale == 1.38) {
        expect(cell.height, greaterThan(48));
      }
      if (scale == 2.0) {
        expect(
          find.byKey(const ValueKey('calendar-month-stacked')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('calendar-month-inline')).evaluate().length +
            find
                .byKey(const ValueKey('calendar-month-stacked'))
                .evaluate()
                .length,
        1,
        reason: 'scale $scale',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('six-week month keeps the last row selectable and agenda scrolls',
      (tester) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    final now = DateTime.utc(2026, 8, 18, 2);
    final store = _Store()
      ..replaceAssignmentsForTest([
        for (var i = 1; i <= 7; i++)
          _work(
            'w$i',
            title: '作业$i',
            deadlineAt: DateTime.utc(2026, 8, 31, i, 0),
          ),
      ]);
    addTearDown(store.dispose);
    await _pump(tester, store, now: now, scale: 1.38);
    expect(tester.takeException(), isNull);

    final last = find.text('31');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(find.text('8月31日 · 议程'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('作业7'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('作业7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact and countdown preferences reach calendar cards',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final now = DateTime.utc(2026, 11, 18, 2);
      final store = _Store()
        ..display = const DisplayPreferences(compact: true, countdown: true)
        ..replaceAssignmentsForTest([
          _work(
            'today',
            title: '普通课业',
            deadlineAt: DateTime.utc(2026, 11, 18, 15, 59),
          ),
          _exam('exam', start: DateTime.utc(2026, 11, 18, 1)),
        ]);
      addTearDown(store.dispose);
      await _pump(
        tester,
        store,
        now: now,
        size: const Size(390, 900),
      );
      final cards = tester.widgetList<AssignmentCard>(
        find.byType(AssignmentCard),
      );
      expect(cards, hasLength(2));
      expect(cards.every((card) => card.compact), isTrue);
      expect(cards.every((card) => card.countdown), isTrue);

      final workLabel = tester
          .getSemantics(find.bySemanticsLabel(RegExp('^普通课业，课程，')))
          .getSemanticsData()
          .label;
      expect(workLabel, contains('截止 11月18日 23:59'));
      expect(workLabel, contains('剩余'));

      final examLabel = tester
          .getSemantics(find.bySemanticsLabel(RegExp('^考试，考试课程，')))
          .getSemanticsData()
          .label;
      expect(examLabel, isNot(contains('剩余')));
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'untrusted deadline card keeps its pending wording without countdown',
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
            assignment: _work(
              'pending',
              title: '待确认课业',
              deadlineAt: DateTime.utc(2026, 11, 20, 15, 59),
              trusted: false,
            ),
            now: DateTime.utc(2026, 11, 18, 2),
            countdown: true,
            onTap: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final label = tester
          .getSemantics(find.bySemanticsLabel(RegExp('^待确认课业，课程，')))
          .getSemanticsData()
          .label;
      expect(label, contains('截止时间待确认'));
      expect(label, isNot(contains('剩余')));
    } finally {
      semantics.dispose();
    }
  });
}
