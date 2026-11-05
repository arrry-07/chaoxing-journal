import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Store extends AssignmentStore {
  _Store()
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  int calls = 0;
  String? warning;
  @override
  String? get error => warning ?? super.error;
  @override
  Future<void> syncAssignments() async {
    calls++;
  }
}

void main() {
  testWidgets('manual refresh still syncs when reminders have a warning',
      (t) async {
    final s = _Store()
      ..syncReport = const SyncReport(phase: SyncPhase.success)
      ..warning = '提醒权限需要处理';
    addTearDown(s.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.tap(find.byTooltip('刷新作业'));
    expect(t.takeException(), isNull);
    expect(s.calls, 1);
  });
  testWidgets(
      'home prioritizes upcoming and shows all expired without headings',
      (t) async {
    final now = DateTime.now();
    final s = _Store()
      ..replaceAssignmentsForTest([
        for (var i = 0; i < 5; i++)
          Assignment(
              id: 'cx:work:1:2:old$i',
              courseName: '样例课程',
              title: '过去作业$i',
              deadlineAt: now.subtract(Duration(days: i + 1)),
              requirementsText: '',
              status: 'pending',
              lastSyncedAt: now),
        Assignment(
            id: 'cx:work:1:2:soon',
            courseName: '样例课程',
            title: '下一份作业',
            deadlineAt: now.add(const Duration(days: 1)),
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now),
      ]);
    addTearDown(s.dispose);
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: AssignmentListScreen(store: s))));
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.text('待办作业'), findsNothing);
    expect(find.textContaining('近期截止'), findsNothing);
    expect(find.textContaining('查看全部 5'), findsNothing);
    expect(
        t
            .widget<AssignmentCard>(find.byType(AssignmentCard).first)
            .assignment
            .title,
        '下一份作业');
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 5; i++) {
      await t.scrollUntilVisible(find.text('过去作业$i'), 200, scrollable: list);
      expect(find.text('过去作业$i'), findsOneWidget);
    }
    expect(s.calls, 0);
  });

  testWidgets('scrolling never syncs and explicit refresh remains available',
      (t) async {
    final s = _Store();
    addTearDown(s.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.drag(find.byType(ListView), const Offset(0, 350));
    await t.pumpAndSettle();
    expect(s.calls, 0);
    await t.tap(find.byTooltip('刷新作业'));
    expect(s.calls, 1);
  });

  testWidgets('homework entry has a transparent paper surface', (t) async {
    final a = Assignment(
        id: 'cx:work:1:2:1',
        courseName: '大学物理',
        title: '练习',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.now());
    await t.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
            body: AssignmentCard(
                assignment: a, now: DateTime.now(), onTap: () {}))));
    expect(find.byType(Card), findsNothing);
  });
}
