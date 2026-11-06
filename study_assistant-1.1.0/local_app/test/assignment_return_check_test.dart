import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'review_core_remediation_test.dart' as f;

class TargetClient extends f.Client {
  int targets = 0;
  bool fail = false;
  String targetStatus = 'submitted';
  Completer<List<Assignment>>? fullGate;
  @override
  Future<List<Assignment>> fetchAssignments() =>
      fullGate?.future ?? super.fetchAssignments();
  @override
  Future<List<Assignment>> fetchAssignmentsForCourse(
      {required String courseId, required String clazzId}) async {
    targets++;
    if (fail) throw StateError('network timeout');
    return [f.sample('shared', status: targetStatus)];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('queued return uses the latest confirmed state from preceding full sync',
      () async {
    final client = TargetClient()
      ..targetStatus = 'pending'
      ..fullGate = Completer<List<Assignment>>();
    final store = f.makeStore(f.Session(), client: client);
    await store.restoreSession();
    store.replaceAssignmentsForTest([f.sample('shared')]);
    final full = store.syncAssignments();
    store.beginAssignmentVisit('cx:work:1:2:shared');
    store.markAssignmentVisitLeftApp();
    final checking = store.checkReturnedAssignment();
    client.fullGate!.complete([f.sample('shared', status: 'submitted')]);
    await full;
    await checking;
    expect(store.findAssignment('cx:work:1:2:shared')!.status, 'submitted');
    expect(store.returnCheckMessage, contains('未能确认'));
    store.dispose();
  });
  test('unknown target keeps its previous pending record', () async {
    final client = TargetClient()..targetStatus = 'unknown';
    final store = f.makeStore(f.Session(), client: client);
    await store.restoreSession();
    await store.repository.mergeAndSave([f.sample('shared')]);
    await store.refreshAssignments();
    store.beginAssignmentVisit('cx:work:1:2:shared');
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    expect(store.findAssignment('cx:work:1:2:shared')!.status, 'pending');
    expect(store.returnCheckMessage, contains('未能确认'));
    store.dispose();
  });
  test(
      'logout invalidates return results even while reminder update is awaiting',
      () async {
    final client = TargetClient();
    final n = f.Notifications();
    final store = f.makeStore(f.Session(), client: client, notifications: n);
    await store.restoreSession();
    store.replaceAssignmentsForTest([f.sample('shared')]);
    final gate = Completer<void>();
    n.gate = gate;
    n.started = Completer<void>();
    store.beginAssignmentVisit('cx:work:1:2:shared');
    store.markAssignmentVisitLeftApp();
    final checking = store.checkReturnedAssignment();
    await n.started!.future;
    final logout = store.logout();
    gate.complete();
    await checking;
    await logout;
    expect(store.isAuthenticated, isFalse);
    expect(store.returnCheckMessage, isNull);
    expect(store.changes, isEmpty);
    store.dispose();
  });
  test('return check only runs after leaving and confirms server result',
      () async {
    final client = TargetClient();
    final store = AssignmentStore(
        sessionStore: f.Session(),
        notificationService: f.Notifications(),
        widgetSnapshotService: f.WidgetService(),
        chaoxingClient: client);
    await store.restoreSession();
    store.replaceAssignmentsForTest([f.sample('shared')]);
    store.beginAssignmentVisit('cx:work:1:2:shared');
    await store.checkReturnedAssignment();
    expect(client.targets, 0);
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    expect(client.targets, 1);
    expect(store.returnCheckMessage, contains('已确认提交'));
    await store.checkReturnedAssignment();
    expect(client.targets, 1);
    store.dispose();
  });
  test('failed refresh preserves pending state and does not claim submission',
      () async {
    final client = TargetClient()..fail = true;
    final store = AssignmentStore(
        sessionStore: f.Session(),
        notificationService: f.Notifications(),
        widgetSnapshotService: f.WidgetService(),
        chaoxingClient: client);
    await store.restoreSession();
    store.replaceAssignmentsForTest([f.sample('shared')]);
    store.beginAssignmentVisit('cx:work:1:2:shared');
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    expect(store.findAssignment('cx:work:1:2:shared')!.isCompleted, isFalse);
    expect(store.returnCheckMessage, contains('未能确认'));
    store.dispose();
  });
}
