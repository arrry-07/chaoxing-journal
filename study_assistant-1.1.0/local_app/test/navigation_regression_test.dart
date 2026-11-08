import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/login_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_RouterStore> launch(WidgetTester tester, String location,
      {bool authenticated = false}) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    final store = _RouterStore()..authenticated = authenticated;
    addTearDown(store.dispose);
    await tester.pumpWidget(StudyAssistantApp(
        assignmentStore: store,
        notificationService: LocalNotificationService()));
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'synthetic-student');
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tester.pump();
    // Agreement defaults to unchecked after F07. Keep this helper compatible
    // while the independently owned login screen is being updated.
    final checkbox = find.byType(Checkbox);
    if (checkbox.evaluate().isNotEmpty &&
        tester.widget<Checkbox>(checkbox).value != true) {
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
    }
    final button = find.text('登录学习通');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('real app router retains incoming assignment through login',
      (tester) async {
    await launch(tester, 'studyassistant:///assignments/cx%3Awork%3A1%3A2%3A3');
    expect(find.byType(LoginScreen), findsOneWidget);
    await login(tester);
    expect(find.byType(AssignmentDetailScreen), findsOneWidget);
    expect(
        tester
            .widget<AssignmentDetailScreen>(find.byType(AssignmentDetailScreen))
            .assignmentId,
        'cx:work:1:2:3');
  });

  testWidgets('real app router refuses external login return target',
      (tester) async {
    await launch(
        tester, '/login?from=https%3A%2F%2Fevil.example%2Fassignments%2F3');
    await login(tester);
    expect(find.byType(AssignmentListScreen), findsOneWidget);
  });

  testWidgets('ordinary login goes to assignment home', (tester) async {
    await launch(tester, '/login');
    await login(tester);
    expect(find.byType(AssignmentListScreen), findsOneWidget);
  });

  testWidgets(
      'malformed encoded internal login target falls back without crashing',
      (tester) async {
    await launch(tester, '/login?from=%2Fassignments%2F%25FF');
    expect(tester.takeException(), isNull);
    await login(tester);
    expect(find.byType(AssignmentListScreen), findsOneWidget);
  });

  for (final location in ['/courses', '/records', '/help']) {
    testWidgets('profile subpage $location selects my navigation destination',
        (tester) async {
      await launch(tester, location, authenticated: true);
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          3);
    });
  }
}

class _RouterStore extends AssignmentStore {
  _RouterStore()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  bool authenticated = false;
  @override
  bool get isAuthenticated => authenticated;
  @override
  Future<void> loginChaoxing(
      {required String account,
      required String password,
      required bool agreementAccepted}) async {
    if (!agreementAccepted) return;
    authenticated = true;
    notifyListeners();
  }

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
  @override
  Assignment? findAssignment(String id) => Assignment(
      id: id,
      courseName: '合成课程',
      title: '合成作业',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.utc(2026));
}
