import 'dart:ui' show SemanticsAction;
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets('history folds and unknown work never takes next recommendation',
      (t) async {
    final semantics = t.ensureSemantics();
    await initializeDateFormatting('zh_CN');
    final s = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    addTearDown(s.dispose);
    Assignment a(String id, String title, int days, String status) =>
        Assignment(
            id: id,
            courseName: '课',
            title: title,
            deadlineAt: DateTime.now().add(Duration(days: days)),
            requirementsText: '',
            status: status,
            lastSyncedAt: DateTime.now());
    s.replaceAssignmentsForTest([
      a('cx:work:1:2:1', '近期待交题', 1, 'pending'),
      a('cx:work:1:2:2', '三月旧题', -200, 'pending'),
      a('cx:work:1:2:3', '待确认题', 2, 'unknown'),
      a('cx:activity:1:2:4', '课堂题', 1, 'pending')
    ]);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    expect(
        t
            .getSemantics(find.byType(AssignmentCard).first)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    expect(find.textContaining('近期截止'), findsNothing);
    expect(
        t
            .widget<AssignmentCard>(find.byType(AssignmentCard).first)
            .assignment
            .title,
        '近期待交题');
    expect(find.text('三月旧题'), findsOneWidget);
    expect(find.text('课堂题'), findsNothing);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: CalendarScreen(store: s))));
    expect(find.text('回今天'), findsOneWidget);
    expect(find.text('三月旧题'), findsNothing);
    semantics.dispose();
  });
}
