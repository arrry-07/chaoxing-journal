import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/local_record_query.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'review_core_remediation_test.dart' as f;

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _Widgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

void main() {
  testWidgets(
      'local records screen supports source tabs, status chips, reset banner and detail restore of hidden item',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final now = DateTime.utc(2026, 11, 17, 2);
    final pendingWork = Assignment(
      id: 'cx:work:1:2:w1',
      courseName: '大学物理',
      title: '牛顿力学实验',
      deadlineAt: now.add(const Duration(days: 2)),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    final completedWork = Assignment(
      id: 'cx:work:1:2:w2',
      courseName: '大学物理',
      title: '热学测验',
      deadlineAt: now.add(const Duration(days: 3)),
      requirementsText: '',
      status: 'submitted',
      lastSyncedAt: now,
    );
    final hiddenExam = Assignment(
      id: 'cx:exam:1:3:301',
      source: AssignmentSource.exam,
      courseName: '线性代数',
      title: '线代期中考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '301',
        courseId: '1',
        clazzId: '3',
        startAt: now.add(const Duration(days: 5)),
        startTrusted: true,
        lifecycle: 'scheduled',
      ),
    );
    final hiddenExamNotice = Assignment(
      id: 'cx:examNotice:inbox:901',
      source: AssignmentSource.exam,
      courseName: '线性代数',
      title: '线代期中考试通知',
      deadlineAt: null,
      requirementsText: '请到主教学楼201参加',
      status: 'unknown',
      lastSyncedAt: now,
      exam: const ExamInfo(
        examId: '901',
        relatedExamId: '301',
        courseId: '1',
        clazzId: '3',
        noticeOnly: true,
        location: '主教学楼201',
      ),
    );
    final unsupported = Assignment(
      id: 'cx:activity:1:2:999',
      source: AssignmentSource.classroomActivity,
      activityType: 99,
      courseName: '大学物理',
      title: '其他课堂活动',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );

    await store.repository.mergeAndSave([
      pendingWork,
      completedWork,
      hiddenExam,
      hiddenExamNotice,
      unsupported,
    ]);
    await store.refreshAssignments();
    await store
        .setAssignmentsHidden([hiddenExam.id, hiddenExamNotice.id], true);

    final router = GoRouter(
      initialLocation: '/records?from=stats&scope=followedStats&status=pending',
      routes: [
        ShellRoute(
          builder: (_, __, child) => AppShell(
            assignmentStore: store,
            child: child,
          ),
          routes: [
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
            GoRoute(
              path: '/assignments/:id',
              builder: (_, state) => AssignmentDetailScreen(
                store: store,
                assignmentId: state.pathParameters['id']!,
                clock: () => now,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: StudyAssistantTheme.light,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    // Scoped entry from stats keeps count 1 (pendingWork), hides completedWork & unsupported.
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('牛顿力学实验'), findsOneWidget);
    expect(find.text('热学测验'), findsNothing);
    expect(find.text('其他课堂活动'), findsNothing);
    expect(find.text('查看全部本机记录'), findsOneWidget);

    final listScrollable = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    );

    // Reset shows all 2 non-hidden coursework groups, still excluding unsupported.
    await tester.tap(find.text('查看全部本机记录'));
    await tester.pumpAndSettle();
    expect(find.text('2 条记录'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('热学测验'),
      150,
      scrollable: listScrollable,
    );
    expect(find.text('热学测验'), findsOneWidget);
    expect(find.text('其他课堂活动'), findsNothing);

    // Filter by status chip '已完成' shows only 热学测验.
    await tester.scrollUntilVisible(
      find.text('已完成'),
      -150,
      scrollable: listScrollable,
    );
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('热学测验'), findsOneWidget);
    expect(find.text('牛顿力学实验'), findsNothing);

    // Source isolation: unsupported only under 历史与其他来源.
    await tester.tap(find.text('历史与其他来源'));
    await tester.pumpAndSettle();
    expect(find.text('1 条记录'), findsOneWidget);
    expect(find.text('其他课堂活动'), findsOneWidget);

    // Hidden tab shows merged exam group, tapping opens detail with projection + restore.
    await tester.tap(find.text('已隐藏'));
    await tester.pumpAndSettle();
    expect(find.text('1 条记录'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('考试 · 2 条来源'),
      150,
      scrollable: listScrollable,
    );
    expect(find.text('线代期中考试'), findsOneWidget);
    expect(find.textContaining('考试 · 2 条来源'), findsOneWidget);

    await tester.tap(find.text('线代期中考试'));
    await tester.pumpAndSettle();

    expect(find.byType(AssignmentDetailScreen), findsOneWidget);
    expect(find.textContaining('当前课业已在本机隐藏'), findsOneWidget);
    expect(find.textContaining('地点 主教学楼201'), findsOneWidget);
    expect(find.text('安排每日计划'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('恢复到课业清单'),
      150,
      scrollable: listScrollable,
    );
    expect(find.text('恢复到课业清单'), findsOneWidget);
    await tester.tap(find.text('恢复到课业清单'));
    await tester.pumpAndSettle();

    expect(find.text('已恢复到课业清单'), findsOneWidget);
    expect(store.hiddenAssignments, isEmpty);
    expect(find.text('安排每日计划'), findsOneWidget);
  });

  testWidgets(
      'local records screen renders without overflow at 320w and 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final now = DateTime.utc(2026, 11, 17, 2);
    store.replaceAssignmentsForTest([
      Assignment(
        id: 'cx:work:1:2:w1',
        courseName: '概率论与数理统计（计算机类长课程名称）',
        title: '长标题用于测试窄屏二倍字号自动换行与零溢出展示',
        deadlineAt: now.add(const Duration(days: 2)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: LocalRecordsScreen(store: store, clock: () => now),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'local records screen clears scoped filters on account logout or change',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: LocalRecordsScreen(
          store: store,
          initialFilter: const LocalRecordFilterSpec(
            from: 'stats',
            scope: LocalRecordScopeFilter.followedStats,
            courseKey: '1:2',
            query: 'old-query',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看全部本机记录'), findsOneWidget);

    await store.logout();
    await tester.pumpAndSettle();
    expect(find.text('查看全部本机记录'), findsNothing);
    expect(find.text('0 条记录'), findsOneWidget);
  });
}
