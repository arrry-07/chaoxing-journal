import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/manual_home_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets(
      'undated returned work remains readable without date or countdown',
      (t) async {
    await initializeDateFormatting('zh_CN');
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 720);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(store.dispose);
    const title = '学期末综合实验报告修订稿及补充说明材料';
    final work = Assignment(
        id: 'cx:work:1:2:task',
        courseName: '计算机课程综合实践与应用专题研讨班',
        title: title,
        deadlineAt: null,
        requirementsText: '见批注',
        status: 'returned',
        lastSyncedAt: DateTime.now());
    store.replaceAssignmentsForTest([
      work,
      work.copyWith(
          id: 'cx:work:1:2:submitted', title: '已提交综合实验报告', status: 'submitted')
    ]);
    Future<void> show(Widget page) async {
      await t.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: Scaffold(body: page))));
      await t.pumpAndSettle();
    }

    await show(AssignmentListScreen(store: store));
    expect(find.text('下一份要交'), findsNothing);
    await t.scrollUntilVisible(find.text(title), 150);
    await t.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    expect(find.textContaining('已退回'), findsOneWidget);
    expect(t.takeException(), isNull);
    await show(
        AssignmentDetailScreen(store: store, assignmentId: 'cx:work:1:2:task'));
    expect(find.text('无截止日期'), findsOneWidget);
    expect(find.textContaining('已退回'), findsOneWidget);
    expect(t.takeException(), isNull);
    await show(CalendarScreen(store: store));
    await t.scrollUntilVisible(find.text('当天暂无课业'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('当天暂无课业'), findsOneWidget);
    expect(find.text(title), findsNothing);
    expect(t.takeException(), isNull);
    await show(StatsScreen(store: store));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('stats-overview-card')),
            matching: find.text('50%')),
        findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(t.takeException(), isNull);
    store.replaceAssignmentsForTest([
      work.copyWith(
          deadlineAt: DateTime.now().add(const Duration(days: 3)),
          deadlineReadFailed: true)
    ]);
    await show(AssignmentListScreen(store: store));
    await t.scrollUntilVisible(find.textContaining('截止时间为上次读取记录'), 150);
    expect(find.textContaining('截止时间为上次读取记录'), findsWidgets);
    await show(
        AssignmentDetailScreen(store: store, assignmentId: 'cx:work:1:2:task'));
    expect(find.textContaining('截止时间为上次读取记录'), findsOneWidget);
    await show(CalendarScreen(store: store));
    expect(find.text(title), findsNothing);
  });

  testWidgets('card distinguishes confirming, unknown and unlimited deadlines',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    final assignment = Assignment(
      id: 'cx:work:1:2:task',
      courseName: '课程',
      title: '作业',
      deadlineAt: null,
      deadlineTrusted: false,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.now(),
    );
    Future<void> show({
      required Assignment value,
      bool deadlinePending = false,
      bool previewOnly = false,
      bool previewSaving = false,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AssignmentCard(
            assignment: value,
            now: DateTime.now(),
            onTap: () {},
            onOpenAssignment: () {},
            deadlinePending: deadlinePending,
            previewOnly: previewOnly,
            previewSaving: previewSaving,
          ),
        ),
      ));
    }

    await show(value: assignment, deadlinePending: true, previewOnly: true);
    expect(find.text('正在确认截止时间'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('待保存预览'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
              find.byKey(const ValueKey('open-assignment-cx:work:1:2:task')))
          .onPressed,
      isNull,
    );

    await show(value: assignment);
    expect(find.text('截止时间待确认'), findsOneWidget);

    await show(value: assignment.copyWith(deadlineTrusted: true));
    expect(find.text('无截止日期'), findsOneWidget);

    await show(
      value: assignment.copyWith(
        deadlineTrusted: true,
        availableFromAt: DateTime.utc(2026, 11, 16, 16),
      ),
    );
    expect(find.text('开始 11月17日 00:00 · 无截止日期'), findsOneWidget);

    await show(
      value: assignment.copyWith(
        availableFromAt: DateTime.utc(2026, 11, 16, 16),
      ),
    );
    expect(find.text('开始 11月17日 00:00 · 截止时间待确认'), findsOneWidget);
  });

  testWidgets('card keeps only time in the left rail with full semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await initializeDateFormatting('zh_CN');
    final now = DateTime.utc(2026, 11, 28, 10);
    final assignment = Assignment(
      id: 'cx:work:1:2:rail-date',
      courseName: '大学物理B（下）',
      title: '电磁学（上）练习一',
      deadlineAt: DateTime.utc(2026, 11, 28, 14, 50),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentCard(
          assignment: assignment,
          now: now,
          onTap: () {},
          onOpenAssignment: () {},
          showFullDeadline: false,
          countdown: true,
        ),
      ),
    ));

    final time = find.text('22:50');
    final title = find.text('电磁学（上）练习一');
    expect(find.text('11/28'), findsNothing);
    expect(time, findsOneWidget);
    expect(find.textContaining('截止 11月28日'), findsNothing);
    expect(tester.getTopLeft(time).dx, lessThan(tester.getTopLeft(title).dx));
    expect(tester.getTopLeft(time).dy,
        lessThanOrEqualTo(tester.getTopLeft(title).dy));
    expect(
      find.bySemanticsLabel(RegExp('截止 11月28日 22:50')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('undated card keeps placeholder rail and aligned column',
      (tester) async {
    final assignment = Assignment(
      id: 'cx:work:1:2:no-time',
      courseName: '课程',
      title: '无时间作业',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.utc(2026, 11, 13),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentCard(
          assignment: assignment,
          now: DateTime.utc(2026, 11, 13, 4),
          onTap: () {},
          onOpenAssignment: () {},
        ),
      ),
    ));

    expect(find.text('—'), findsOneWidget);
    expect(find.text('无截止日期'), findsOneWidget);
    final title = find.text('无时间作业');
    final course = find.text('课程');
    final deadline = find.text('无截止日期');
    expect(title, findsOneWidget);
    expect(course, findsOneWidget);
    final cardLeft = tester.getTopLeft(find.byType(AssignmentCard)).dx;
    expect(tester.getTopLeft(title).dx, greaterThan(cardLeft));
    expect(tester.getTopLeft(course).dx, tester.getTopLeft(title).dx);
    expect(tester.getTopLeft(deadline).dx, tester.getTopLeft(title).dx);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card marks the exact deadline instant as overdue',
      (tester) async {
    final now = DateTime.utc(2026, 11, 13, 4);
    final assignment = Assignment(
      id: 'cx:work:1:2:exact',
      courseName: '课程',
      title: '恰好到期作业',
      deadlineAt: now,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentCard(
          assignment: assignment,
          now: now,
          onTap: () {},
          onOpenAssignment: () {},
        ),
      ),
    ));

    expect(find.textContaining('已逾期'), findsOneWidget);
  });

  testWidgets('card does not present conflicting status as confirmed overdue',
      (tester) async {
    final now = DateTime.utc(2026, 11, 13, 4);
    final assignment = Assignment(
      id: 'cx:work:1:2:conflict',
      courseName: '课程',
      title: '状态冲突作业',
      deadlineAt: now.add(const Duration(hours: 1)),
      requirementsText: '',
      status: 'overdue',
      lastSyncedAt: now,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentCard(
          assignment: assignment,
          now: now,
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('状态或截止待确认'), findsOneWidget);
    expect(find.text('已逾期'), findsNothing);
    expect(find.text('今天截止'), findsNothing);
  });

  testWidgets('undated overdue status is pending instead of unlimited',
      (tester) async {
    final now = DateTime.utc(2026, 11, 13, 4);
    final assignment = Assignment(
      id: 'cx:work:1:2:overdue-undated',
      courseName: '课程',
      title: '无日期冲突作业',
      deadlineAt: null,
      requirementsText: '',
      status: 'overdue',
      lastSyncedAt: now,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentCard(
          assignment: assignment,
          now: now,
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('无截止日期'), findsNothing);
    expect(find.text('截止信息待确认'), findsOneWidget);
  });

  testWidgets('card reserves four logical pixels before its divider',
      (tester) async {
    final now = DateTime.utc(2026, 11, 13, 4);
    final assignment = Assignment(
      id: 'cx:work:1:2:gap',
      courseName: '课程',
      title: '留白作业',
      deadlineAt: now.add(const Duration(days: 1)),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentCard(
          assignment: assignment,
          now: now,
          onTap: () {},
        ),
      ),
    ));
    final gap =
        find.byKey(const ValueKey('assignment-card-gap-cx:work:1:2:gap'));
    expect(gap, findsOneWidget);
    expect(tester.getSize(gap).height, 4);
  });

  testWidgets(
      'mixed timeline cards align title left edge across upcoming, overdue, and manual entries',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    final now = DateTime.utc(2026, 11, 13, 4);
    final upcomingWork = Assignment(
      id: 'cx:work:1:2:upcoming',
      courseName: '高等数学',
      title: '未逾期作业',
      deadlineAt: now.add(const Duration(hours: 5)),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    final overdueWork = Assignment(
      id: 'cx:work:1:2:overdue',
      courseName: '高等数学',
      title: '已逾期作业',
      deadlineAt: now.subtract(const Duration(days: 2)),
      requirementsText: '',
      status: 'overdue',
      lastSyncedAt: now,
    );
    final manualEntry = ManualEntry(
      id: 'm-align',
      title: '手动待办',
      kind: ManualEntry.kindTodo,
      course: '高等数学',
      at: now.subtract(const Duration(hours: 4)),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              AssignmentCard(
                assignment: upcomingWork,
                now: now,
                onTap: () {},
                onOpenAssignment: () {},
                showFullDeadline: false,
                countdown: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              AssignmentCard(
                assignment: overdueWork,
                now: now,
                onTap: () {},
                onOpenAssignment: () {},
                showFullDeadline: false,
                countdown: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              ManualHomeCard(
                entry: manualEntry,
                now: now,
                onTap: () {},
                onToggleDone: () {},
                countdown: true,
              ),
            ],
          ),
        ),
      ),
    ));

    final upcomingDx = tester.getTopLeft(find.text('未逾期作业')).dx;
    final overdueDx = tester.getTopLeft(find.text('已逾期作业')).dx;
    final manualDx = tester.getTopLeft(find.text('手动待办')).dx;

    expect(overdueDx, closeTo(upcomingDx, 0.01));
    expect(manualDx, closeTo(upcomingDx, 0.01));
    expect(tester.takeException(), isNull);
  });
}
