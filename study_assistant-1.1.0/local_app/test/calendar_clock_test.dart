import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Session extends SecureSessionStore {}

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class _Widgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

void main() {
  testWidgets('calendar refreshes the overdue boundary without leaving',
      (tester) async {
    var now = DateTime.utc(2026, 11, 13, 4);
    final store = AssignmentStore(
      sessionStore: _Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([
      Assignment(
        id: 'cx:work:1:2:soon',
        courseName: '课程',
        title: '一分钟后到期',
        deadlineAt: now.add(const Duration(minutes: 1)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: CalendarScreen(store: store, clock: () => now),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('已逾期'), findsNothing);

    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(find.textContaining('已逾期'), findsOneWidget);
  });

  testWidgets('statistics refresh the overdue boundary without leaving',
      (tester) async {
    var now = DateTime.utc(2026, 11, 13, 4);
    final store = AssignmentStore(
      sessionStore: _Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Widgets(),
    );
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([
      Assignment(
        id: 'cx:work:1:2:soon',
        courseName: '课程',
        title: '一分钟后到期',
        deadlineAt: now.add(const Duration(minutes: 1)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: StatsScreen(store: store, clock: () => now),
    ));
    await tester.pumpAndSettle();
    expect(find.text('待完成 1 份'), findsOneWidget);
    expect(find.text('已逾期 0 份'), findsOneWidget);

    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(find.text('待完成 0 份'), findsOneWidget);
    expect(find.text('已逾期 1 份'), findsOneWidget);
  });
}
