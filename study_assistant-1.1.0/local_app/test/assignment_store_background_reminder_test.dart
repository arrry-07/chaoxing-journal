import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  test('complete sync builds a silent baseline then emits one new event',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final client = _ClientQueue([
      [_assignment('old', DateTime.now().add(const Duration(days: 2)))],
      [
        _assignment('old', DateTime.now().add(const Duration(days: 2))),
        _assignment('new', null),
      ],
      [
        _assignment('old', DateTime.now().add(const Duration(days: 2))),
        _assignment('new', null),
      ],
    ]);
    final store = _store(gateway: gateway, client: client);
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();
    expect(gateway.plans.last.baselineCompleted, isTrue);
    expect(gateway.plans.last.newEvents, isEmpty);

    await store.syncAssignments();
    expect(gateway.plans.last.newEvents, hasLength(1));
    expect(gateway.plans.last.newEvents.single.assignmentId, 'cx:work:1:2:new');

    await store.syncAssignments();
    expect(gateway.plans.last.newEvents, isEmpty,
        reason: 'known assignments must not be re-alerted');
  });

  test('hiding a pending assignment removes its deadline plan immediately',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final assignment =
        _assignment('deadline', DateTime.now().add(const Duration(days: 2)));
    final store = _store(
      gateway: gateway,
      client: _ClientQueue([
        [assignment],
        [assignment],
      ]),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();
    await store.syncAssignments();
    expect(gateway.plans.last.deadlineEvents, isNotEmpty);

    await store.hideAssignment(assignment.id);
    expect(gateway.plans.last.deadlineEvents, isEmpty);
    expect(gateway.plans.last.newEvents, isEmpty);
  });
}

AssignmentStore _store({
  required _FakeGateway gateway,
  required ChaoxingLocalClient client,
}) =>
    AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
      backgroundReminderGateway: gateway,
      repository: LocalAssignmentRepository(
        backgroundReminderGateway: gateway,
      ),
      nativeReminderDeliveryEnabled: true,
    );

Assignment _assignment(String suffix, DateTime? deadline) => Assignment(
      id: 'cx:work:1:2:$suffix',
      courseName: '合成课程',
      title: '作业 $suffix',
      deadlineAt: deadline,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.now(),
      deadlineTrusted: deadline != null,
    );

class _ClientQueue extends ChaoxingLocalClient {
  _ClientQueue(this.results);

  final List<List<Assignment>> results;
  int calls = 0;

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<List<Assignment>> fetchAssignments() async {
    final result = results[calls.clamp(0, results.length - 1)];
    calls++;
    succeededCourses = 1;
    failedCourses = 0;
    issues = [];
    lastSyncWarning = null;
    return result;
  }
}

class _MemorySessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student';

  @override
  Future<String?> readChaoxingPassword() async => null;

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> removeLegacyAssignmentSchedules() async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> assignments,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _FakeGateway extends BackgroundReminderGateway {
  _FakeGateway() : super();

  final plans = <AssignmentReminderPlan>[];
  bool baseline = false;
  int mutationVersion = 0;
  Set<String> known = {};
  Set<String> sentNew = {};
  DateTime? lastAttempt;
  DateTime? lastFull;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<int> ensureActiveAccount(String accountHash) async => 1;

  @override
  Future<int> switchAccount({
    required String? previousAccountHash,
    required String accountHash,
  }) async =>
      2;

  @override
  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
  }) async {
    mutationVersion++;
  }

  @override
  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
  }) async {}

  @override
  Future<SyncLeaseResult> acquireSyncLease({
    required String accountHash,
    required String requestId,
    required DateTime requestedAt,
  }) async =>
      const SyncLeaseResult(
        acquired: true,
        waited: false,
        lastAttemptAt: null,
        lastFullSuccessAt: null,
      );

  @override
  Future<void> releaseSyncLease({
    required String accountHash,
    required String requestId,
  }) async {}

  @override
  Future<bool> acquireWriteLease(String owner) async => true;

  @override
  Future<void> releaseWriteLease(String owner) async {}

  @override
  Future<bool> isSessionCurrent(String accountHash, int sessionEpoch) async =>
      true;

  @override
  Future<void> markPendingUpdate({
    required String accountHash,
    required int sessionEpoch,
  }) async {
    mutationVersion++;
  }

  @override
  Future<ReminderPlanState> loadPlanState({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      ReminderPlanState(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
        baselineCompleted: baseline,
        knownAssignmentIds: {...known},
        sentNewAssignmentIds: {...sentNew},
        lastAttemptAt: lastAttempt,
        lastFullSuccessAt: lastFull,
        pendingUpdate: true,
        mutationVersion: mutationVersion,
      );

  @override
  Future<ReminderPlanApplyResult> applyPlan({
    required String accountHash,
    required int sessionEpoch,
    required AssignmentReminderPlan plan,
    required DateTime completedAt,
    required String? failure,
    required bool syncCompleted,
    required int expectedMutationVersion,
  }) async {
    expect(expectedMutationVersion, mutationVersion);
    plans.add(plan);
    baseline = plan.baselineCompleted;
    known = {...plan.knownAssignmentIds};
    sentNew.addAll(plan.newEvents.map((event) => event.assignmentId));
    if (syncCompleted) {
      lastAttempt = completedAt;
      if (failure == null) lastFull = completedAt;
    }
    return ReminderPlanApplyResult(
      scheduledDeadlineCount: plan.deadlineEvents.length,
      pendingNewCount: plan.newEvents.length,
      warning: null,
    );
  }

  @override
  Future<void> recordAttempt({
    required String accountHash,
    required int sessionEpoch,
    required DateTime attemptedAt,
    required bool dataSucceeded,
    required bool fullSucceeded,
    required String? failure,
  }) async {}

  @override
  Future<BackgroundReminderHealth> inspectHealth({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      const BackgroundReminderHealth(
        backgroundEnabled: true,
        intervalMinutes: 240,
        newAssignmentReminderEnabled: true,
        notificationListenerEnabled: false,
        notificationListenerGranted: false,
        nextCheckAt: null,
        pendingNewCount: 0,
        pendingDeadlineCount: 0,
        baselineCompleted: true,
        pendingSignalCount: 0,
        migrationPending: false,
        lastFailure: null,
      );

  @override
  Future<void> cancelAssignmentReminders(String accountHash) async {}
}
