import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/completion_pie_chart.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_statistics.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/local_record_query.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'review_core_remediation_test.dart' as f;

Assignment work(int id, String status, {DateTime? due}) => Assignment(
    id: 'cx:work:1:${id.isEven ? 2 : 3}:$id',
    courseName: '高等数学与统计课程',
    title: '作业$id',
    deadlineAt: due,
    requirementsText: '',
    status: status,
    lastSyncedAt: DateTime(2026));

void main() {
  testWidgets(
      'completion ring uses one sage arc and keeps 8/2/1 legend semantics',
      (t) async {
    final semantics = t.ensureSemantics();
    final now = DateTime.utc(2026, 11, 10, 2);
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([
      for (var i = 0; i < 8; i++) work(i * 2, 'submitted'),
      work(16, 'pending', due: now.add(const Duration(days: 2))),
      work(18, 'pending', due: now.add(const Duration(days: 4))),
      work(20, 'pending', due: now.subtract(const Duration(days: 2))),
    ]);

    await t.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: StatsScreen(store: store, clock: () => now)),
    ));

    final chart = find.byType(CompletionPieChart);
    expect(
      find.descendant(of: chart, matching: find.text('73%')),
      findsOneWidget,
    );
    expect(find.text('73%'), findsNWidgets(2));
    expect(find.text('18%'), findsOneWidget);
    expect(find.text('9%'), findsOneWidget);
    expect(find.text('8 份'), findsOneWidget);
    expect(find.text('2 份'), findsOneWidget);
    expect(find.text('1 份'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    final pendingNode = t.getSemantics(find.bySemanticsLabel('待完成 2 份，18%'));
    expect(
      pendingNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    final painter = t
        .widget<CustomPaint>(find.descendant(
          of: chart,
          matching: find.byType(CustomPaint),
        ))
        .painter as CompletionRingPainter;
    expect(painter.counts, [8, 2, 1, 0]);
    expect(
      CompletionPieChart.completedSweeps(painter.counts).single,
      closeTo(8 / 11 * math.pi * 2, 1e-9),
    );
    expect(CompletionPieChart.completedSweeps(painter.counts), hasLength(1));
    expect(CompletionPieChart.ringThickness, 10);

    final overview =
        t.widget<Card>(find.byKey(const ValueKey('stats-overview-card')));
    final course =
        t.widget<Card>(find.byKey(const ValueKey('stats-course-1:2')));
    expect(
      overview.color,
      Color.lerp(Journal.paper, Journal.sheet, .70),
    );
    expect(
      course.color,
      Color.lerp(Journal.paper, Journal.sheet, .50),
    );
    semantics.dispose();
  });

  testWidgets('legend separates expired from unknown and uses full row width',
      (t) async {
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([
      work(0, 'submitted'),
      work(1, 'pending'),
      work(2, 'pending', due: DateTime(2000)),
      work(3, 'unknown'),
    ]);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: StatsScreen(store: store))));
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('待完成'), findsOneWidget);
    expect(find.text('已逾期'), findsOneWidget);
    expect(find.text('提交未知'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(CompletionPieChart), matching: find.text('25%')),
        findsOneWidget);
    expect(find.text('完成率'), findsOneWidget);
    expect(find.text('待提交'), findsNothing);
    final label = t.getRect(find.text('已完成'));
    final value = t.getRect(find.text('25%').at(1));
    expect(value.top, greaterThan(label.top));
    expect(value.right, greaterThan(740));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('320 wide statistics remain readable at text scale $scale',
        (t) async {
      t.view.physicalSize = const Size(320, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final store = AssignmentStore(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService());
      addTearDown(store.dispose);
      store.replaceAssignmentsForTest([work(0, 'pending'), work(1, 'unknown')]);
      await t.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(body: StatsScreen(store: store))));
      expect(t.takeException(), isNull);
      if (scale == 2) {
        expect(t.getRect(find.text('已完成')).top,
            greaterThan(t.getRect(find.byType(CompletionPieChart)).bottom));
      } else {
        expect(t.getRect(find.text('已完成')).left,
            greaterThan(t.getRect(find.byType(CompletionPieChart)).right));
      }
      await t.drag(find.byType(ListView), const Offset(0, -1000));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
      'unknown-only chart does not present a definite zero completion rate',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CompletionPieChart(
                statistics: AssignmentStatistics([work(0, 'unknown')])))));
    expect(find.text('0%'), findsNothing);
    expect(find.text('待确认'), findsOneWidget);
    expect(CompletionPieChart.completedSweeps([0, 0, 0, 1]), isEmpty);
  });

  testWidgets('zero completion draws only the track while keeping a real 0%',
      (t) async {
    final stats = AssignmentStatistics([
      work(0, 'pending'),
      work(1, 'pending'),
      work(2, 'pending', due: DateTime(2000)),
    ]);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: CompletionPieChart(statistics: stats)),
    ));
    expect(find.text('0%'), findsOneWidget);
    expect(CompletionPieChart.completedSweeps([0, 2, 1, 0]), isEmpty);
  });

  testWidgets('empty statistics keep the original empty card and no chart',
      (t) async {
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(store.dispose);
    await t.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: StatsScreen(store: store)),
    ));
    expect(find.byType(CompletionPieChart), findsNothing);
    expect(find.byKey(const ValueKey('stats-empty-card')), findsOneWidget);
    expect(find.text('暂无可统计的作业'), findsOneWidget);
  });

  testWidgets('three primary legends remain visible when unknown is zero',
      (t) async {
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([work(0, 'submitted')]);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: StatsScreen(store: store))));
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('待完成'), findsOneWidget);
    expect(find.text('已逾期'), findsOneWidget);
    expect(find.text('提交未知'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(CompletionPieChart), matching: find.text('100%')),
        findsOneWidget);
    expect(CompletionPieChart.completedSweeps([1, 0, 0, 0]), [
      closeTo(math.pi * 2, 1e-9),
    ]);
    expect(find.text('当前没有待处理的课程'), findsOneWidget);
  });

  testWidgets('FB-001 account exam without course key renders its own row',
      (t) async {
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([
      work(0, 'pending', due: DateTime(2026, 12, 1)),
      Assignment(
        id: 'cx:exam:account:account:9001',
        source: AssignmentSource.exam,
        courseName: '账号考试',
        title: '账号级考试',
        deadlineAt: null,
        requirementsText: '以官方考试列表为准',
        status: 'pending',
        lastSyncedAt: DateTime(2026, 11, 16),
        exam: const ExamInfo(examId: '9001'),
      ),
    ]);

    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: StatsScreen(store: store))));

    expect(t.takeException(), isNull);
    expect(find.text('账号考试'), findsOneWidget);
    expect(find.text('共 2 项课业'), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });

  testWidgets(
      'stats range switching and interactive drill-down preserve HomeFilters and keep stats tab highlighted',
      (t) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final now = DateTime.utc(2026, 11, 10, 2); // Beijing 10:00
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: f.Notifications(),
      widgetSnapshotService: f.WidgetService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final initialFilters = const HomeFilters(
      deadline: AssignmentDeadlineFilter.overdue,
      type: AssignmentTypeFilter.exam,
      query: '保留首页搜索',
    );
    expect(
      await store.saveHomeFilters(initialFilters, store.accountEpoch),
      isTrue,
    );

    final nearPending =
        work(1, 'pending', due: now.add(const Duration(days: 2)));
    final laterPending =
        work(2, 'pending', due: now.add(const Duration(days: 20)));
    final undatedPending = work(3, 'pending', due: null);
    final accExam = Assignment(
      id: 'cx:exam:account:account:9001',
      source: AssignmentSource.exam,
      courseName: '账号考试',
      title: '账号级测试考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '9001',
        startAt: now.add(const Duration(days: 3)),
        startTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    store.replaceAssignmentsForTest(
      [nearPending, laterPending, undatedPending, accExam],
    );

    final router = GoRouter(
      initialLocation: '/stats',
      routes: [
        ShellRoute(
          builder: (_, __, child) => AppShell(
            assignmentStore: store,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/stats',
              builder: (_, __) => StatsScreen(store: store, clock: () => now),
            ),
            GoRoute(
              path: '/records',
              builder: (_, state) => LocalRecordsScreen(
                store: store,
                initialFilter: LocalRecordFilterSpec.fromQueryParameters(
                  state.uri.queryParameters,
                ),
                clock: () => now,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await t.pumpWidget(
      MaterialApp.router(
        theme: StudyAssistantTheme.light,
        routerConfig: router,
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('共 4 项课业'), findsOneWidget);

    // Switch to 未来 7 天: includes nearPending + accExam, excludes undatedPending.
    await t.tap(find.text('未来 7 天'));
    await t.pumpAndSettle();
    expect(find.text('共 2 项课业'), findsOneWidget);
    expect(find.text('不含 1 项无确定时间课业（切回“全部”可查看）'), findsOneWidget);

    // Drill down via pie legend ('待完成')
    await t.tap(find.text('待完成'));
    await t.pumpAndSettle();
    var spec = t
        .widget<LocalRecordsScreen>(find.byType(LocalRecordsScreen))
        .initialFilter;
    expect(spec.from, 'stats');
    expect(spec.scope, LocalRecordScopeFilter.followedStats);
    expect(spec.status, LocalRecordStatusFilter.pending);
    expect(spec.timeRange, StatsTimeRange.next7Days);
    expect(spec.courseKey, isNull);
    expect(find.byType(LocalRecordsScreen), findsOneWidget);
    expect(find.text('2 条记录'), findsOneWidget);
    final nav = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.selectedIndex, 2);

    // Back to StatsScreen cleanly
    await t.tap(find.byTooltip('返回'));
    await t.pumpAndSettle();
    expect(find.byType(StatsScreen), findsOneWidget);

    // Drill down from a course row and preserve the course identity.
    await t.scrollUntilVisible(find.text('高等数学与统计课程'), 200);
    await t.tap(find.text('高等数学与统计课程'));
    await t.pumpAndSettle();
    spec = t
        .widget<LocalRecordsScreen>(find.byType(LocalRecordsScreen))
        .initialFilter;
    expect(spec.from, 'stats');
    expect(spec.scope, LocalRecordScopeFilter.followedStats);
    expect(spec.status, LocalRecordStatusFilter.unfinished);
    expect(spec.timeRange, StatsTimeRange.next7Days);
    expect(spec.courseKey, '1:3');
    await t.tap(find.byTooltip('返回'));
    await t.pumpAndSettle();

    // Switch to 未来 30 天 and drill down via 账号考试 card
    await t.tap(find.text('未来 30 天'));
    await t.pumpAndSettle();
    expect(find.text('共 3 项课业'), findsOneWidget);

    final accountExamLabel = find.text('账号考试');
    await Scrollable.ensureVisible(
      t.element(accountExamLabel),
      alignment: 0.5,
    );
    await t.pumpAndSettle();
    await t.tap(accountExamLabel);
    await t.pumpAndSettle();
    spec = t
        .widget<LocalRecordsScreen>(find.byType(LocalRecordsScreen))
        .initialFilter;
    expect(spec.from, 'stats');
    expect(spec.scope, LocalRecordScopeFilter.accountExam);
    expect(spec.status, LocalRecordStatusFilter.unfinished);
    expect(spec.timeRange, StatsTimeRange.next30Days);
    expect(spec.courseKey, isNull);
    expect(find.byType(LocalRecordsScreen), findsOneWidget);
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('账号级测试考试'), findsOneWidget);

    // Verify HomeFilters were untouched.
    expect(store.homeFilters.deadline, initialFilters.deadline);
    expect(store.homeFilters.type, initialFilters.type);
    expect(store.homeFilters.query, initialFilters.query);
  });
}
