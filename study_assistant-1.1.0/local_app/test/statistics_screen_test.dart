import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/completion_pie_chart.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_statistics.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

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
}
