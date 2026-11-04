import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment sample(String id, {String status = 'pending', DateTime? due}) =>
    Assignment(
        id: 'cx:work:1:2:$id',
        title: '阅读材料与综合实验报告修订说明（2026）',
        courseName: '中国近现代史纲要与跨学科专题讨论课程',
        deadlineAt: due,
        requirementsText: '',
        status: status,
        lastSyncedAt: DateTime(2026, 11, 5));

void main() {
  testWidgets('home restores journal heading without losing sync actions',
      (t) async {
    final s = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(s.dispose);
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: AssignmentListScreen(store: s))));
    expect(find.text('课业手记'), findsOneWidget);
    expect(find.text('CAMPUS JOURNAL   /   01'), findsOneWidget);
    expect(find.byTooltip('刷新作业'), findsOneWidget);
    expect(find.byTooltip('同步详情'), findsOneWidget);
  });

  testWidgets('unknown submission keeps exact label and never claims overdue',
      (t) async {
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
            body: AssignmentCard(
                assignment: sample('unknown',
                    status: 'unknown', due: DateTime.utc(2026, 11, 4, 7, 49)),
                now: DateTime.utc(2026, 11, 5),
                onTap: () {}))));
    expect(find.text('提交状态未知'), findsOneWidget);
    expect(find.textContaining('已逾期'), findsNothing);
    expect(find.text('15:49'), findsOneWidget);
  });

  testWidgets('timeline time precedes title and remains usable at large sizes',
      (t) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    for (final scale in [1.0, 2.0]) {
      t.view.physicalSize = const Size(320, 900);
      var taps = 0;
      final a = sample('known', due: DateTime.utc(2026, 11, 6, 7, 49));
      await t.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: ListView(children: [
            AssignmentCard(
                assignment: a,
                now: DateTime.utc(2026, 11, 5),
                onTap: () => taps++)
          ]))));
      expect(t.takeException(), isNull);
      expect(find.text('15:49'), findsOneWidget);
      expect(t.getRect(find.text('15:49')).right,
          lessThan(t.getRect(find.text(a.title)).left));
      expect(find.textContaining('11月6日 15:49'), findsOneWidget);
      await t.tap(find.text(a.title));
      expect(taps, 1);
    }
  });
}
