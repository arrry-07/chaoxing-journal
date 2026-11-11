import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/completion_pie_chart.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
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
      work.copyWith(id: 'cx:work:1:2:submitted', status: 'submitted')
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
    expect(find.text('未设置截止时间'), findsOneWidget);
    expect(find.textContaining('已退回'), findsOneWidget);
    expect(t.takeException(), isNull);
    await show(CalendarScreen(store: store));
    await t.scrollUntilVisible(find.text('所选范围没有已知截止作业'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(title), findsNothing);
    expect(t.takeException(), isNull);
    await show(StatsScreen(store: store));
    expect(
        find.descendant(
            of: find.byType(CompletionPieChart), matching: find.text('50%')),
        findsOneWidget);
    expect(find.text('完成率'), findsOneWidget);
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
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );

    await show(value: assignment);
    expect(find.text('待确认'), findsOneWidget);

    await show(value: assignment.copyWith(deadlineTrusted: true));
    expect(find.text('无期限'), findsOneWidget);
  });
}
