import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/assignment_changes_screen.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/features/daily_plan_screen.dart';
import 'package:study_assistant_mobile/src/features/display_settings_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'review_core_remediation_test.dart' as f;

class _NoopNotifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets(
      'changes, courses, display settings and daily plan picker use Journal styling at 320w and 2x text without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});

    final now = DateTime.now();
    final store = AssignmentStore(
      sessionStore: f.Session(),
      notificationService: _NoopNotifications(),
      widgetSnapshotService: _NoopWidgets(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.repository.saveCourses(
      const [
        CourseRef(courseId: '1', clazzId: '2', name: '高等数学（一）'),
      ],
      account: 'A',
    );
    await store.restoreSession();

    store.changes = [
      AssignmentChange(
        assignmentId: 'cx:work:1:2:10',
        title: '每周积分计算与讨论总结',
        courseName: '高等数学（一）',
        kind: AssignmentChangeKind.deadline,
        at: now,
        before: now.add(const Duration(days: 1)).toUtc().toIso8601String(),
        after: now.add(const Duration(days: 3)).toUtc().toIso8601String(),
      ),
    ];
    store.replaceAssignmentsForTest([
      Assignment(
        id: 'cx:work:1:2:10',
        courseName: '高等数学（一）',
        title: '逾期候选任务',
        deadlineAt: now.subtract(const Duration(hours: 2)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ]);

    Widget wrap(Widget child) => MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: inner!,
          ),
          home: child,
        );

    // 1. AssignmentChangesScreen
    await tester.pumpWidget(
        wrap(Scaffold(body: AssignmentChangesScreen(store: store))));
    await tester.pumpAndSettle();
    expect(find.text('作业变化'), findsOneWidget);
    expect(find.text('截止调整'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 2. CourseListScreen displays CourseMark & SwitchListTile
    await tester.pumpWidget(wrap(CourseListScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('我的课程'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('高等数学（一）'), 150);
    expect(find.byType(CourseMark), findsOneWidget);
    expect(find.byIcon(Icons.functions_rounded), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 3. DisplaySettingsScreen updated responsive widget & info sheet copy
    await tester.pumpWidget(wrap(DisplaySettingsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('显示与小组件'), findsOneWidget);
    final widgetInfoBtn = find.byTooltip('查看说明');
    await tester.scrollUntilVisible(widgetInfoBtn, 150);
    await tester.ensureVisible(widgetInfoBtn);
    await tester.tap(widgetInfoBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('2、4 或 6 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    // 4. DailyPlanScreen candidate picker bottom sheet renders overdue marker
    await tester.pumpWidget(wrap(DailyPlanScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('添加作业到计划'), 150);
    await tester.ensureVisible(find.text('添加作业到计划'));
    await tester.tap(find.text('添加作业到计划'));
    await tester.pumpAndSettle();
    expect(find.text('选择准备完成的作业'), findsOneWidget);
    expect(find.textContaining('已逾期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
