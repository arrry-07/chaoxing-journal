import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/coursework_status_pill.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  Assignment buildWork(
    String id, {
    required String title,
    required String course,
    String courseId = 'c1',
    String clazzId = 'k1',
    DateTime? due,
    bool trusted = true,
    String requirements = '',
    String? rawDeadline,
    String? url = 'https://mooc1.chaoxing.com/mooc-ans/work/task?courseId=1',
  }) =>
      Assignment(
        id: 'cx:work:$courseId:$clazzId:$id',
        courseName: course,
        title: title,
        deadlineAt: due,
        deadlineTrusted: trusted,
        deadlineRawText: rawDeadline,
        requirementsText: requirements,
        status: 'pending',
        submitUrl: url,
        lastSyncedAt: DateTime.utc(2026, 11, 18, 5),
      );

  testWidgets(
      'Direction A renders semantic pills and announces bottom overdue tier without altering FB-005 order',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final store = _PilotStore()
      ..replaceAssignmentsForTest([
        buildWork(
          'overdue',
          title: '第二次理论作业（办公自动化）',
          course: '人工智能导论',
          due: now.subtract(const Duration(days: 12)),
        ),
        buildWork(
          'future',
          title: '赣鄱文化调研微视频脚本初稿',
          course: '思想道德与法治',
          due: now.add(const Duration(days: 5)),
        ),
        buildWork(
          'unconfirmed',
          title: '组合体三视图测绘练习',
          course: '工程制图基础',
          due: now.add(const Duration(days: 2)),
          trusted: false,
        ),
      ]);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: AssignmentListScreen(store: store)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CourseworkStatusPill), findsWidgets);
    expect(find.text('无日期与待确认'), findsOneWidget);
    expect(find.text('已逾期置底'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);

    final futureY = tester.getTopLeft(find.text('赣鄱文化调研微视频脚本初稿')).dy;
    final unconfirmedY = tester.getTopLeft(find.text('组合体三视图测绘练习')).dy;
    final overdueY = tester.getTopLeft(find.text('第二次理论作业（办公自动化）')).dy;
    expect(futureY, lessThan(unconfirmedY));
    expect(unconfirmedY, lessThan(overdueY));
  });

  testWidgets(
      'active filter chips display explicit conditions and support one-tap single removal',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final store = _PilotStore()
      ..replaceAssignmentsForTest([
        buildWork(
          'w1',
          title: '数字逻辑综合实验报告',
          course: '数字逻辑',
          due: now.add(const Duration(days: 3)),
        ),
      ]);
    addTearDown(store.dispose);
    await store.saveHomeFilters(
      const HomeFilters(
        type: AssignmentTypeFilter.exam,
        deadline: AssignmentDeadlineFilter.next7Days,
        sortOrder: HomeSortOrder.deadlineDesc,
      ),
      store.accountEpoch,
    );

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: AssignmentListScreen(store: store)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('已筛选'), findsOneWidget);
    expect(find.text('类型：考试'), findsOneWidget);
    expect(find.text('期限：7天内'), findsOneWidget);
    expect(find.text('没有符合搜索、类型或期限条件的记录'), findsOneWidget);

    await tester.tap(find.text('类型：考试'));
    await tester.pumpAndSettle();

    expect(store.homeFilters.type, AssignmentTypeFilter.all);
    expect(store.homeFilters.deadline, AssignmentDeadlineFilter.next7Days);
    expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
    expect(find.text('数字逻辑综合实验报告'), findsOneWidget);
  });

  testWidgets(
      'reduce motion degrades loading spinners to static indicators without active tickers',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _PilotStore()
      ..syncing = true
      ..customReport = const SyncReport(phase: SyncPhase.running)
      ..replaceAssignmentsForTest([
        buildWork('p1',
            title: '核对中作业', course: '高等数学', due: null, trusted: false),
      ]);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: AssignmentListScreen(store: store)),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsWidgets);
  });

  testWidgets(
      'detail hides bottom NavigationBar, shows overdue badge, deduplicates title requirements, and restores bar on pop',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final item = buildWork(
      'ov1',
      title: '第二次理论作业（办公自动化）',
      course: '人工智能导论',
      due: now.subtract(const Duration(days: 10)),
      rawDeadline: '09-23 23:55',
      requirements: '第二次理论作业（办公自动化）',
    );
    final store = _PilotStore()..replaceAssignmentsForTest([item]);
    addTearDown(store.dispose);

    final router = GoRouter(
      initialLocation: '/assignments',
      routes: [
        ShellRoute(
          builder: (_, __, child) =>
              AppShell(assignmentStore: store, child: child),
          routes: [
            GoRoute(
              path: '/assignments',
              builder: (_, __) => AssignmentListScreen(store: store),
            ),
            GoRoute(
              path: '/assignments/:id',
              builder: (_, state) => AssignmentDetailScreen(
                store: store,
                assignmentId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('第二次理论作业（办公自动化）'));
    await tester.pumpAndSettle();

    expect(find.byType(AssignmentDetailScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.textContaining('已逾期'), findsOneWidget);
    expect(find.text('第二次理论作业（办公自动化）'), findsOneWidget);
    expect(find.text('09-23 23:55'), findsNothing);

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentListScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets(
      '320dp at 2.0x text scale preserves multi-class suffixes in filter sheet without overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime.now();
    final store = _PilotStore()
      ..replaceAssignmentsForTest([
        buildWork(
          'c1w',
          title: '第4章综合实验：基于有限状态机的交通信号灯控制器设计与仿真波形验证报告',
          course: '毛泽东思想和中国特色社会主义理论体系概论',
          courseId: 'm1',
          clazzId: 'classA',
          due: now.add(const Duration(days: 2)),
        ),
        buildWork(
          'c2w',
          title: '专题社会实践调研报告与小组展示材料归档提交',
          course: '毛泽东思想和中国特色社会主义理论体系概论',
          courseId: 'm1',
          clazzId: 'classB',
          due: now.add(const Duration(days: 4)),
        ),
      ]);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
      home: Scaffold(body: AssignmentListScreen(store: store)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('搜索与筛选'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('期限'), findsOneWidget);

    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('（1班）'), findsWidgets);
    expect(find.textContaining('（2班）'), findsWidgets);
  });
}

class _PilotStore extends AssignmentStore {
  _PilotStore()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  bool syncing = false;
  SyncReport customReport = const SyncReport();

  @override
  SyncReport get syncReport => customReport;

  @override
  bool get isLoading => syncing || super.isLoading;

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    homeFilters = next;
    notifyListeners();
    return true;
  }
}
