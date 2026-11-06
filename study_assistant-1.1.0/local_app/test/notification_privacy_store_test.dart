import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class Notifications extends LocalNotificationService {
  bool fail = true;
  int cleared = 0;
  final policies = <bool>[];
  @override
  Future<void> cancelPrivateSchedules() async {
    if (fail) throw StateError('synthetic cancel failure');
    cleared++;
  }

  @override
  Future<void> rescheduleAssignments(List<Assignment> a,
      {List<int>? offsetsMinutes}) async {
    policies.add(showDetails);
  }

  @override
  Future<void> rescheduleManual(List<ManualEntry> a) async {}
  @override
  Future<void> rescheduleSummary(
      List<Assignment> a, PersonalWorkspace p, DateTime? d) async {}
}

class Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> a) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('failed startup cleanup never reopens detailed scheduling and can retry',
      () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': false});
    final n = Notifications();
    final s = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: n,
        widgetSnapshotService: Snapshot());
    addTearDown(s.dispose);
    await s.restoreSession();
    expect(n.showDetails, false);
    expect(s.notificationPrivacyPending, true);
    expect(n.policies, isEmpty);
    n.fail = false;
    await s.refreshAssignments();
    expect(s.notificationPrivacyPending, false);
    expect(n.policies, [false]);
  });
  test(
      'failed privacy tightening preserves the old switch and durable preference',
      () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': true});
    final n = Notifications()..showDetails = true;
    final s = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: n,
        widgetSnapshotService: Snapshot());
    addTearDown(s.dispose);
    await s.saveNotificationDetails(false);
    expect(s.notificationDetails, true);
    expect(s.error, contains('尚未关闭'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notification_details_v1'), true);
    n.fail = false;
    await s.saveNotificationDetails(false);
    expect(s.notificationDetails, false);
    expect(prefs.getBool('notification_details_v1'), false);
    expect(n.cleared, 1);
    expect(s.error, isNull);
  });
}
