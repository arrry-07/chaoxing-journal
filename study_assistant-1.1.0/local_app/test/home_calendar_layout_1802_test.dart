import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';

class _Store extends AssignmentStore {
  _Store(this.records)
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  final List<Assignment> records;
  int saves = 0;
  @override
  List<Assignment> get homeDisplayAssignments => records;
  @override
  List<Assignment> get courseAssignments => records;
  @override
  List<Assignment> get homeCatalogAssignments => records;
  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    saves++;
    homeFilters = next;
    notifyListeners();
    return true;
  }
}

Assignment _exam(String id, {DateTime? start, String course = 'A'}) =>
    Assignment(
        id: 'cx:exam:c:k:$id',
        source: AssignmentSource.exam,
        courseName: course,
        title: id,
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.now(),
        exam: ExamInfo(
            examId: id,
            courseId: 'c',
            clazzId: 'k',
            startAt: start,
            startTrusted: start != null));

Assignment _work(String id, {DateTime? deadline}) => Assignment(
    id: 'cx:work:c:k:$id',
    courseName: 'A',
    title: id,
    deadlineAt: deadline,
    requirementsText: '',
    status: 'pending',
    deadlineReadFailed: deadline == null,
    lastSyncedAt: DateTime.now());

Future<void> _home(WidgetTester tester, _Store store,
    {double scale = 1}) async {
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(body: AssignmentListScreen(store: store))));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('notice-only wall date participates in chronological sorting',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notice = Assignment(
        id: 'cx:examNotice:inbox:n',
        source: AssignmentSource.exam,
        title: '通知合成考试',
        courseName: '合成课程',
        deadlineAt: null,
        requirementsText: '考试时间：11-16 07:06:00 至 11-30 07:06:31',
        status: 'unknown',
        lastSyncedAt: DateTime.now(),
        exam: ExamInfo(examId: 'n', noticeOnly: true));
    final store = _Store([
      _work('work', deadline: DateTime.now().add(const Duration(days: 1))),
      notice
    ]);
    addTearDown(store.dispose);
    await _home(tester, store);
    expect(find.text('11月16日–11月30日'), findsOneWidget);
    expect(find.text('07:06'), findsOneWidget);
    expect(find.textContaining('考试时间：'), findsNothing);
    final cards =
        tester.widgetList<AssignmentCard>(find.byType(AssignmentCard)).toList();
    expect(cards.map((c) => c.assignment.title), ['通知合成考试', 'work']);
    expect(notice.timelineAt, isNull);
    expect(notice.timelineTrusted, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final sort in [HomeSortOrder.deadlineAsc, HomeSortOrder.deadlineDesc]) {
    testWidgets('mixed exams keep unknown dates last for ${sort.name}',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final later = DateTime.now().add(const Duration(days: 2));
      final store = _Store([
        _exam('unknown'),
        _work('work', deadline: later),
        _exam('dated', start: later.subtract(const Duration(days: 1)))
      ])
        ..homeFilters = HomeFilters(sortOrder: sort);
      addTearDown(store.dispose);
      await _home(tester, store);
      expect(find.textContaining('考试时间未知'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('unknown'), findsOneWidget);
      final expected = sort == HomeSortOrder.deadlineAsc
          ? ['dated', 'work', 'unknown']
          : ['work', 'dated', 'unknown'];
      final cards = tester
          .widgetList<AssignmentCard>(find.byType(AssignmentCard))
          .toList();
      expect(cards.map((c) => c.assignment.title), expected);
      for (final card in cards) {
        expect(card.examSources, same(store.records));
      }
      expect(find.text('归档'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('course order precedes date certainty', (tester) async {
    final store = _Store([
      _exam('dated-B',
          course: 'B', start: DateTime.now().add(const Duration(days: 1))),
      _exam('unknown-A')
    ])
      ..homeFilters = const HomeFilters(sortOrder: HomeSortOrder.courseName);
    addTearDown(store.dispose);
    await _home(tester, store);
    expect(
        tester
            .widgetList<AssignmentCard>(find.byType(AssignmentCard))
            .map((c) => c.assignment.title),
        ['unknown-A', 'dated-B']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'legacy exam scope includes dated exams and never saves preferences',
      (tester) async {
    final store = _Store([
      _exam('unknown'),
      _exam('dated', start: DateTime.now().add(const Duration(days: 1))),
      _work('work')
    ])
      ..homeFilters = const HomeFilters(
          query: 'saved-search', type: AssignmentTypeFilter.homework);
    addTearDown(store.dispose);
    final saved = store.homeFilters.encode();
    final router =
        GoRouter(initialLocation: '/assignments?scope=examUnknown', routes: [
      GoRoute(
          path: '/assignments',
          builder: (_, __) =>
              Scaffold(body: AssignmentListScreen(store: store))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('assignment-recovery-scope'));
    expect(
        find.descendant(of: header, matching: find.text('考试')), findsOneWidget);
    expect(find.text('unknown'), findsOneWidget);
    expect(find.text('dated'), findsOneWidget);
    expect(find.text('work'), findsNothing);
    await tester.tap(find.text('返回全部'));
    await tester.pumpAndSettle();
    expect(header, findsNothing);
    expect(store.homeFilters.encode(), saved);
    expect(store.saves, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'calendar removes unknown exam entry but retains homework recovery',
      (tester) async {
    final store = _Store([_exam('unknown'), _work('uncertain')]);
    addTearDown(store.dispose);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CalendarScreen(store: store))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('calendar-deadline-pending-scope')), 200);
    expect(find.byKey(const ValueKey('calendar-deadline-pending-scope')),
        findsOneWidget);
    expect(find.textContaining('考试时间未知'), findsNothing);
    expect(find.text('查看考试'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final completed in [0, 1, 2]) {
    testWidgets(
        'plan summary counts all today plans at narrow large text ($completed)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = PersonalWorkspace.dayKey(DateTime.now());
      final store = _Store([])
        ..personal = PersonalWorkspace(plans: [
          DailyPlanItem('a', today, 20, done: completed >= 1),
          DailyPlanItem('b', today, 30, done: completed >= 2),
          const DailyPlanItem('past', '2000-01-01', 15),
        ])
        ..homeFilters = const HomeFilters(query: 'unmatched');
      addTearDown(store.dispose);
      await _home(tester, store, scale: 2);
      expect(find.text('今日计划 · 已完成$completed/2'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-plan-entry')), findsNothing);
      expect(find.textContaining('预计'), findsNothing);
      expect(find.textContaining('选两三份'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('empty plan has a 48dp toolbar entry which opens plan',
      (tester) async {
    final store = _Store([]);
    addTearDown(store.dispose);
    final router = GoRouter(initialLocation: '/assignments', routes: [
      GoRoute(
          path: '/assignments',
          builder: (_, __) =>
              Scaffold(body: AssignmentListScreen(store: store))),
      GoRoute(
          path: '/plan',
          builder: (_, __) => const Scaffold(body: Text('plan-page'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('home-plan-entry'));
    expect(tester.getSize(entry).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(entry).height, greaterThanOrEqualTo(48));
    expect(find.byKey(const ValueKey('home-plan-summary')), findsNothing);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('plan-page'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
