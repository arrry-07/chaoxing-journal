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
import 'package:study_assistant_mobile/src/features/widgets/journal_floating_nav_bar.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_grouped_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
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
      'minimal overview card shows ratio, multi-segment bar, and 8/2/1 semantics',
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
    await t.pumpAndSettle();

    expect(find.text('73%'), findsOneWidget);
    expect(find.text('已完成 8 / 11'), findsOneWidget);
    expect(find.text('全部学期'), findsOneWidget);
    expect(find.text('不限时间'), findsOneWidget);
    expect(find.text('8 份'), findsOneWidget);
    expect(find.text('2 份'), findsOneWidget);
    expect(find.text('1 份'), findsOneWidget);
    expect(find.text(' · 73%'), findsOneWidget);
    expect(find.text(' · 18%'), findsOneWidget);
    expect(find.text(' · 9%'), findsOneWidget);

    final courseMark = t.widget<CourseMark>(find.byType(CourseMark));
    expect(courseMark.size, 28);
    final pendingNode = t.getSemantics(find.bySemanticsLabel('待完成 2 份，18%'));
    expect(
      pendingNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    final overview = t.widget<JournalGroupedCard>(
      find.byKey(const ValueKey('stats-overview-card')),
    );
    expect(overview.backgroundColor, isNull);
    final overviewMaterial = t.widget<Material>(
      find
          .descendant(
            of: find.byKey(const ValueKey('stats-overview-card')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(overviewMaterial.color, Journal.sheet);

    expect(
      find.text('统计范围：已关注课程的课业与账号考试'),
      findsNothing,
    );
    await t.tap(find.byTooltip('查看说明'));
    await t.pumpAndSettle();
    expect(find.text('统计口径说明'), findsOneWidget);
    await t.tap(find.text('知道了'));
    await t.pumpAndSettle();

    semantics.dispose();
  });

  testWidgets('status rows separate expired from unknown inside one card',
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
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store))));
    await t.pumpAndSettle();
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('待完成'), findsOneWidget);
    expect(find.text('已逾期'), findsOneWidget);
    expect(find.text('提交未知'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('待提交'), findsNothing);

    // Course breakdown rows sit inside one grouped white card, not per-row Card boxes.
    expect(find.byKey(const ValueKey('stats-course-1:2')), findsOneWidget);
    expect(find.text('待完成 1'), findsOneWidget);
    expect(find.text('已逾期 1'), findsOneWidget);
    expect(find.text('待核对 1'), findsOneWidget);
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
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(body: StatsScreen(store: store))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('课业统计'), findsOneWidget);
      expect(find.textContaining('/ 2'), findsOneWidget);
      expect(find.textContaining('高等数学与统计课程'), findsWidgets);
      await t.drag(find.byType(ListView), const Offset(0, -1000));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
      'unknown-only stats do not present a definite zero completion rate while pending-only renders real 0%',
      (t) async {
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([work(0, 'unknown')]);

    await t.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: StatsScreen(store: store)),
    ));
    await t.pumpAndSettle();

    expect(find.text('0%'), findsNothing);
    expect(find.text('待确认'), findsOneWidget);

    store.replaceAssignmentsForTest([
      work(0, 'pending', due: DateTime(2026, 12, 1)),
      work(1, 'pending', due: DateTime(2026, 12, 2)),
    ]);
    await t.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: StatsScreen(store: store)),
    ));
    await t.pumpAndSettle();

    expect(find.text('0%'), findsOneWidget);
    expect(find.text('待确认'), findsNothing);
    expect(find.textContaining('/ 2'), findsOneWidget);
  });

  testWidgets(
      'multi-segment stats bar renders proportional segment widths and light/dark palette colors',
      (t) async {
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

    for (final dark in [false, true]) {
      await t.pumpWidget(MaterialApp(
        theme: dark ? StudyAssistantTheme.dark : StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store, clock: () => now)),
      ));
      await t.pumpAndSettle();

      final expectedColors = CompletionPieChart.colorsFor(
        dark ? JournalPalette.dark : JournalPalette.light,
      );
      final seg0 = find.byKey(const ValueKey('stats-bar-seg-0'));
      final seg1 = find.byKey(const ValueKey('stats-bar-seg-1'));
      final seg2 = find.byKey(const ValueKey('stats-bar-seg-2'));
      final seg3 = find.byKey(const ValueKey('stats-bar-seg-3'));

      expect(seg0, findsOneWidget);
      expect(seg1, findsOneWidget);
      expect(seg2, findsOneWidget);
      expect(seg3, findsNothing, reason: 'zero-count unknown segment skipped');

      expect(t.widget<Container>(seg0).color, expectedColors[0]);
      expect(t.widget<Container>(seg1).color, expectedColors[1]);
      expect(t.widget<Container>(seg2).color, expectedColors[2]);
      expect(
        find.byKey(const ValueKey('stats-bar-overdue-stripes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('stats-dot-overdue-stripes')),
        findsOneWidget,
      );
      if (dark) {
        expect(expectedColors[1], const Color(0xFF57534B));
        expect(expectedColors[3], const Color(0xFF3A3833));
      } else {
        expect(expectedColors[1], const Color(0xFFCFCBC2));
        expect(expectedColors[3], const Color(0xFFE6E4DE));
      }

      final w0 = t.getSize(seg0).width;
      final w1 = t.getSize(seg1).width;
      final w2 = t.getSize(seg2).width;
      expect(w0 / w1, closeTo(4.0, 0.15));
      expect(w1 / w2, closeTo(2.0, 0.15));
    }
  });

  testWidgets('empty statistics keep the empty card and no overview bar',
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
    expect(find.byKey(const ValueKey('stats-overview-card')), findsNothing);
    expect(find.byKey(const ValueKey('stats-empty-card')), findsOneWidget);
    expect(find.text('暂无可统计的作业'), findsOneWidget);
  });

  testWidgets('three primary rows remain visible when unknown is zero',
      (t) async {
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([work(0, 'submitted')]);
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store))));
    await t.pumpAndSettle();
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('待完成'), findsOneWidget);
    expect(find.text('已逾期'), findsOneWidget);
    expect(find.text('提交未知'), findsNothing);
    expect(find.text('100%'), findsOneWidget);
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

    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: StatsScreen(store: store))));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.textContaining('/ 2'), findsOneWidget);
    expect(find.text('高等数学与统计课程'), findsOneWidget);
    expect(find.text('账号考试'), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });

  testWidgets(
      'stats range switching and interactive drill-down preserve HomeFilters and restore nav on back',
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

    const initialFilters = HomeFilters(
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

    expect(find.byType(JournalFloatingNavBar), findsOneWidget);
    expect(find.textContaining('/ 4'), findsOneWidget);

    // Switch to 未来 7 天: includes nearPending + accExam, excludes undatedPending.
    await t.tap(find.text('未来 7 天'));
    await t.pumpAndSettle();
    expect(find.textContaining('/ 2'), findsOneWidget);
    expect(find.text('不含 1 项无确定时间课业'), findsOneWidget);

    // Drill down via status row ('待完成')
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
    expect(find.byType(JournalFloatingNavBar), findsNothing);

    // Back to StatsScreen cleanly
    await t.tap(find.byTooltip('返回'));
    await t.pumpAndSettle();
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.byType(JournalFloatingNavBar), findsOneWidget);

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
    expect(find.textContaining('/ 3'), findsOneWidget);

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

  testWidgets(
      'StatsScreen filters across currentTerm, currentAcademicYear, pastTerms, and allTerms and splits recalled courses cleanly',
      (t) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final now = DateTime.utc(2026, 11, 20, 4); // 2026-2027 fall
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: f.Notifications(),
      widgetSnapshotService: f.WidgetService(),
      clock: () => now,
    );
    addTearDown(store.dispose);
    await store.repository.activateAccount('A');
    await store.repository.saveCourses(const [
      CourseRef(
          courseId: '1', clazzId: '10', name: '本学期算法', folderName: '2026年秋'),
      CourseRef(
          courseId: '2', clazzId: '20', name: '往期微积分', folderName: '2025年秋'),
    ], account: 'A');
    await store.repository.mergeAndSave([
      Assignment(
        id: 'cx:work:1:10:1',
        courseName: '本学期算法',
        title: '在学作业',
        deadlineAt: now.add(const Duration(days: 2)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
      Assignment(
        id: 'cx:work:2:20:1',
        courseName: '往期微积分',
        title: '去年已完成作业',
        deadlineAt: DateTime.utc(2025, 11, 10),
        requirementsText: '',
        status: 'submitted',
        lastSyncedAt: now,
      ),
      // Pending future extension recalls course 2:20 cleanly for currentTerm only.
      Assignment(
        id: 'cx:work:2:20:2',
        courseName: '往期微积分',
        title: '补交扩展任务',
        deadlineAt: now.add(const Duration(days: 3)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ], completeSync: true);
    await store.restoreSession();

    final router = GoRouter(
      initialLocation: '/stats',
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
    );
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
    ));
    await t.pumpAndSettle();

    // Default 本学期: currentWork (pending) + recalled extension (pending) = 2 total, 0% done.
    expect(find.textContaining('/ 2'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    // Switch to 往期: historical submitted record stays in past terms (1 total, 100%).
    await t.tap(find
        .byKey(ValueKey('stats-term-scope-${CourseTermScope.pastTerms.name}')));
    await t.pumpAndSettle();
    expect(find.textContaining('/ 1'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    // Past-term drill-down keeps the term scope and the archived record.
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('stats-status-0')),
      100,
    );
    await t.tap(find.byKey(const ValueKey('stats-status-0')));
    await t.pumpAndSettle();
    expect(
      find.byType(LocalRecordsScreen),
      findsOneWidget,
      reason: 'router uri: ${router.state.uri}',
    );
    final recordsSpec = t
        .widget<LocalRecordsScreen>(find.byType(LocalRecordsScreen))
        .initialFilter;
    expect(recordsSpec.termScope, CourseTermScope.pastTerms);
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('去年已完成作业'), findsOneWidget);
    await t.tap(find.byTooltip('返回'));
    await t.pumpAndSettle();

    // Switch to 全部学期: all 3 records = 1/3 = 33%.
    await t.tap(find
        .byKey(ValueKey('stats-term-scope-${CourseTermScope.allTerms.name}')));
    await t.pumpAndSettle();
    expect(find.textContaining('/ 3'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
  });

  testWidgets(
      'StatsScreen top 4-scope bar stays on one horizontal row with zero overflow at 320dp@2x',
      (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final now = DateTime.utc(2026, 11, 20, 4);
    final s = f.makeStore(f.Session());
    addTearDown(s.dispose);
    await s.restoreSession();

    await t.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
      home: Scaffold(body: StatsScreen(store: s, clock: () => now)),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    final keys = [
      for (final scope in CourseTermScope.values)
        find.byKey(ValueKey('stats-term-scope-${scope.name}')),
    ];
    for (final k in keys) {
      expect(k, findsOneWidget);
    }
    final rects = keys.map(t.getRect).toList(growable: false);
    final baseY = rects.first.center.dy;
    for (var i = 1; i < rects.length; i++) {
      expect((rects[i].center.dy - baseY).abs(), lessThanOrEqualTo(1.0));
      expect(rects[i].left, greaterThan(rects[i - 1].left));
    }
  });

  testWidgets(
      'StatsScreen empty range copy references 不限时间 and fits 360dp@1.3x',
      (t) async {
    t.view.physicalSize = const Size(360, 760);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final now = DateTime.utc(2026, 11, 20, 4);
    final s = f.makeStore(f.Session());
    addTearDown(s.dispose);
    await s.restoreSession();

    await t.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(body: StatsScreen(store: s, clock: () => now)),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('未来 7 天'));
    await t.pumpAndSettle();
    expect(
      find.text('未来 7 天内暂无带确定时间的课业记录，可切回“不限时间”查看。'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
