import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
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
    expect(find.byType(LocalRecordsScreen), findsOneWidget);
    expect(find.text('2 条记录'), findsOneWidget);
    final nav = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.selectedIndex, 2);

    // Back to StatsScreen cleanly
    await t.tap(find.byTooltip('返回'));
    await t.pumpAndSettle();
    expect(find.byType(StatsScreen), findsOneWidget);

    // Switch to 未来 30 天 and drill down via 账号考试 card
    await t.tap(find.text('未来 30 天'));
    await t.pumpAndSettle();
    expect(find.text('共 3 项课业'), findsOneWidget);

    await t.scrollUntilVisible(find.text('账号考试'), 200);
    await t.tap(find.text('账号考试'));
    await t.pumpAndSettle();
    expect(find.byType(LocalRecordsScreen), findsOneWidget);
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('账号级测试考试'), findsOneWidget);

    // Verify HomeFilters were untouched.
    expect(store.homeFilters.deadline, initialFilters.deadline);
    expect(store.homeFilters.type, initialFilters.type);
    expect(store.homeFilters.query, initialFilters.query);
  });
}
