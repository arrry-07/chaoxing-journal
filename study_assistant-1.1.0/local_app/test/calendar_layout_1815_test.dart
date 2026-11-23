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
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
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
      expect(find.byKey(const ValueKey('calendar-dots-18')), findsOneWidget);
      final cell = tester.getSize(_daySemantics(11, 18, today: true));
      expect(cell.height, greaterThanOrEqualTo(48), reason: 'scale $scale');
      if (scale == 1.0) {
        expect(cell.height, closeTo(48, 0.01));
        expect(
          tester.getTopLeft(find.text('18')).dy,
          closeTo(tester.getTopLeft(find.text('19')).dy, 0.01),
        );
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

  testWidgets('calendar supports horizontal month swipe and week collapse',
      (tester) async {
    final now = DateTime.utc(2026, 11, 18, 2);
    final store = _Store();
    addTearDown(store.dispose);
    await _pump(tester, store, now: now, size: const Size(390, 840));

    expect(find.text('2026年11月'), findsOneWidget);
    final viewport = find.byKey(const ValueKey('calendar-grid-viewport'));
    final fullGridSize = tester.getSize(viewport);

    // Toggle week collapse: grid shrinks to a single row height.
    await tester.tap(find.byKey(const ValueKey('calendar-week-toggle')));
    await tester.pumpAndSettle();
    final collapsedSize = tester.getSize(viewport);
    expect(collapsedSize.height, lessThan(fullGridSize.height * 0.4));

    // Expand back to month view and swipe left to December 2026.
    await tester.tap(find.byKey(const ValueKey('calendar-week-toggle')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('2026年12月'), findsOneWidget);
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

  testWidgets(
      'Phase 5A calendar shows warm vermilion cell tint only at >= 3 items, preserves today/selected/week/month & large text across themes',
      (tester) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    final now = DateTime.utc(2026, 12, 28, 2); // Beijing Dec 28 10:00
    final day19TwoItems = DateTime.utc(2026, 12, 19, 1);
    final day28TodayThreeItems = DateTime.utc(2026, 12, 28, 3);
    final day29SelectedThreeItems = DateTime.utc(2026, 12, 29, 4);

    final store = _Store()
      ..replaceAssignmentsForTest([
        _work('d19-1', title: '两项之一', deadlineAt: day19TwoItems),
        _work('d19-2', title: '两项之二', deadlineAt: day19TwoItems),
        _work('d28-1', title: '今天三项之一', deadlineAt: day28TodayThreeItems),
        _work('d28-2', title: '今天三项之二', deadlineAt: day28TodayThreeItems),
        _work('d29-1', title: '明天三项之一', deadlineAt: day29SelectedThreeItems),
        _work('d29-2', title: '明天三项之二', deadlineAt: day29SelectedThreeItems),
        _exam('d29-3', start: day29SelectedThreeItems),
      ])
      ..notebook = StudyNotebook(entries: [
        ManualEntry(
          id: 'm28',
          title: '今天三项之三',
          kind: 'todo',
          at: day28TodayThreeItems,
        ),
      ]);
    addTearDown(store.dispose);

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = brightness == Brightness.light
          ? StudyAssistantTheme.light
          : StudyAssistantTheme.dark;
      final palette = brightness == Brightness.light
          ? JournalPalette.light
          : JournalPalette.dark;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Scaffold(body: CalendarScreen(store: store, clock: () => now)),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$brightness');
      expect(find.byKey(const ValueKey('calendar-busy-day-2026-12-19')),
          findsNothing);
      final busyToday =
          find.byKey(const ValueKey('calendar-busy-day-2026-12-28'));
      expect(busyToday, findsOneWidget);
      final busyDecoration =
          tester.widget<Container>(busyToday).decoration! as BoxDecoration;
      expect(busyDecoration.color, palette.berryBg);

      // Select day 29 (also busy): today still shows today border, day 29 stays busy + selected.
      final day29 = find.descendant(
        of: find.byKey(const ValueKey('calendar-grid-viewport')),
        matching: find.text('29'),
      );
      await tester.ensureVisible(day29);
      await tester.pumpAndSettle();
      await tester.tap(day29);
      await tester.pumpAndSettle();
      expect(find.text('12月29日 · 议程'), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-busy-day-2026-12-29')),
          findsOneWidget);

      // Week collapse toggle + cross-year navigation at 2.0x text scale.
      final weekToggle = find.byKey(const ValueKey('calendar-week-toggle'));
      await tester.ensureVisible(weekToggle);
      await tester.pumpAndSettle();
      await tester.tap(weekToggle);
      await tester.pumpAndSettle();
      final nextMonth = find.byTooltip('下个月');
      await tester.scrollUntilVisible(
        nextMonth,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(nextMonth);
      await tester.pumpAndSettle();
      expect(find.text('2027年1月'), findsOneWidget);
      final backToday = find.text('回今天');
      await tester.scrollUntilVisible(
        backToday,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(backToday);
      await tester.pumpAndSettle();
      expect(find.text('2026年12月'), findsOneWidget);
      await tester.scrollUntilVisible(
        weekToggle,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(weekToggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$brightness');
    }
  });
}
