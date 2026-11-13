import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
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

  for (final fullSuccess in [true, false]) {
    test(
        fullSuccess
            ? 'waitedSuccessReleasesSyncLease'
            : 'waitedFailureReleasesSyncLease', () async {
      SharedPreferences.setMockInitialValues({});
      final gateway = _FakeGateway()..waitedResult = fullSuccess;
      final client = _ClientQueue([<Assignment>[]]);
      final store = _store(gateway: gateway, client: client);
      addTearDown(store.dispose);
      await store.restoreSession();
      await store.syncAssignments();
      expect(client.calls, 0);
      expect(gateway.syncReleases, gateway.syncAcquisitions);
      expect(gateway.syncReleases, hasLength(1));
      await store.syncAssignments();
      expect(gateway.syncReleases, hasLength(2));
      expect(gateway.syncAcquisitions, hasLength(2));
      expect(gateway.syncAcquisitions.toSet(), hasLength(2),
          reason: '每次同步必须使用唯一的原生 requestId');
    });
  }

  test('reloadFailureStillReleasesLease', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway()..waitedResult = true;
    final repository = _FailingReloadRepository(gateway);
    final store = _store(
        gateway: gateway, client: _ClientQueue([[]]), repository: repository);
    addTearDown(store.dispose);
    await store.restoreSession();
    repository.failReload = true;
    await store.syncAssignments();
    expect(store.error, contains('synthetic reload failure'));
    expect(gateway.syncReleases, gateway.syncAcquisitions);
  });

  test('unacquiredSyncLeaseIsNotReleased', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway()..syncAcquired = false;
    final store = _store(gateway: gateway, client: _ClientQueue([[]]));
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(gateway.syncReleases, isEmpty);
  });

  test('nativeSettingsFailureDoesNotReportAppliedOrApplyPlan', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final store = _store(gateway: gateway, client: _ClientQueue([[]]));
    addTearDown(store.dispose);
    await store.restoreSession();
    gateway.plans.clear();
    gateway.failSettings = true;
    expect(await store.saveBackgroundCheckEnabled(false), isFalse);
    expect(store.error, contains('已保存'));
    await store.saveReminderRule([60]);
    expect(gateway.plans, isEmpty);
    expect(store.backgroundWarning, contains('未确认'));
    gateway.failSettings = false;
    await store.refreshAssignments();
    expect(gateway.plans, isNotEmpty);
  });

  test('daytimeScheduleFailureIsVisible', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final store = _store(gateway: gateway, client: _ClientQueue([[]]));
    addTearDown(store.dispose);
    await store.restoreSession();
    gateway.failDaytime = true;
    expect(await store.saveBackgroundCheckEnabled(false), isFalse);
    expect(store.backgroundWarning, contains('未确认'));
  });

  test('nativePrivacyFailureKeepsCleanupPending', () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': true});
    final gateway = _FakeGateway();
    final store = _store(gateway: gateway, client: _ClientQueue([[]]));
    addTearDown(store.dispose);
    await store.restoreSession();
    gateway.failPrivacy = true;
    await store.saveNotificationDetails(false);
    final prefs = await SharedPreferences.getInstance();
    expect(store.notificationPrivacyPending, isTrue);
    expect(prefs.getBool('notification_privacy_cleanup_pending_v1'), isTrue);
    expect(store.notificationDetails, isTrue);
    gateway.failPrivacy = false;
    await store.saveNotificationDetails(false);
    expect(store.notificationPrivacyPending, isFalse);
  });

  test('logoutRetriesNativeCleanupAfterIdentityRemoved', () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': true});
    final session = _MemorySessionStore();
    final gateway = _FakeGateway();
    final store =
        _store(gateway: gateway, client: _ClientQueue([[]]), session: session);
    addTearDown(store.dispose);
    await store.restoreSession();
    final oldHash = store.accountHash;
    gateway.failClear = true;
    await store.logout();
    expect(store.isAuthenticated, isFalse);
    expect(session.account, isNull);
    expect(store.notificationPrivacyPending, isTrue);
    expect(store.error, contains('账号已退出'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('native_account_cleanup_pending_v1'),
        contains(oldHash));
    gateway.failClear = false;
    final restarted =
        _store(gateway: gateway, client: _ClientQueue([[]]), session: session);
    addTearDown(restarted.dispose);
    await restarted.restoreSession();
    expect(gateway.clearedAccounts, contains(oldHash));
    expect(prefs.getStringList('native_account_cleanup_pending_v1'), isNull);
  });

  test('nativeSwitchFailureNeverCommitsNewIdentity', () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': true});
    final gateway = _FakeGateway();
    final session = _MemorySessionStore();
    final client = _LoginClient();
    final store = _store(gateway: gateway, client: client, session: session);
    addTearDown(store.dispose);
    await store.restoreSession();
    final epochBeforeFailedSwitch = store.nativeSessionEpoch;
    gateway.failSwitch = true;
    await store.loginChaoxing(
        account: 'new-student', password: 'dummy', agreementAccepted: true);
    expect(store.account, isNot('new-student'));
    expect(session.account, isNot('new-student'));
    expect(client.clearCalls, greaterThan(0));
    expect(store.nativeSessionEpoch, epochBeforeFailedSwitch,
        reason: 'failed switch cannot claim old native session restored');
    expect(store.error, contains('synthetic switch failure'));
  });

  test('legacyV1MarkerDoesNotSkipV2Cleanup', () async {
    SharedPreferences.setMockInitialValues(
        {'legacy_assignment_schedule_cleanup_v1': true});
    final notifications = _NoopNotificationService();
    final store = _store(
        gateway: _FakeGateway(),
        client: _ClientQueue([[]]),
        notifications: notifications);
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    expect(notifications.legacyCleanupCalls, 1);
    expect(prefs.getBool('legacy_assignment_schedule_cleanup_v2'), isTrue);
  });

  test('failedLegacyMigrationKeepsV2PendingAndRetries', () async {
    SharedPreferences.setMockInitialValues(
        {'legacy_assignment_schedule_cleanup_v1': true});
    final notifications = _NoopNotificationService()..failLegacyCleanup = true;
    final store = _store(
        gateway: _FakeGateway(),
        client: _ClientQueue([[]]),
        notifications: notifications);
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('legacy_assignment_schedule_cleanup_v2'), isNot(true));
    notifications.failLegacyCleanup = false;
    await store.refreshAssignments();
    expect(prefs.getBool('legacy_assignment_schedule_cleanup_v2'), isTrue);
  });

  test('cancelled sync never advances full success', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final client = _BlockingClient();
    final store = _store(gateway: gateway, client: client);
    addTearDown(store.dispose);
    await store.restoreSession();
    final plansBefore = gateway.plans.length;

    final sync = store.syncAssignments();
    await client.started.future;
    store.cancelSynchronization();
    await sync;

    expect(store.syncReport.phase, SyncPhase.cancelled);
    expect(store.syncReport.lastFullSuccessAt, isNull);
    expect(store.error, contains('取消'));
    expect(gateway.plans.length, plansBefore);
  });

  test('failed legacy migration blocks native plan until retry', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final notifications = _NoopNotificationService()..failLegacyCleanup = true;
    final store = _store(
      gateway: gateway,
      client: _ClientQueue([<Assignment>[]]),
      notifications: notifications,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(gateway.plans, isEmpty);
    expect(store.error, contains('迁移'));

    notifications.failLegacyCleanup = false;
    await store.refreshAssignments();
    expect(gateway.plans, isNotEmpty);
  });

  test('legacy assignment cleanup runs once per install', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final notifications = _NoopNotificationService();
    final store = _store(
      gateway: gateway,
      client: _ClientQueue([
        [_assignment('legacy', DateTime.now().add(const Duration(days: 2)))],
      ]),
      notifications: notifications,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('legacy_assignment_schedule_cleanup_v2');
    notifications.legacyCleanupCalls = 0;

    await store.saveReminderRule([60]);
    await store.saveReminderRule([120]);

    // The native revision is authoritative: removing only the Flutter mirror
    // must not run the one-time migration again.
    expect(notifications.legacyCleanupCalls, 0);
    expect(notifications.legacyMigrationComplete, isTrue);
  });
}

AssignmentStore _store({
  required _FakeGateway gateway,
  required ChaoxingLocalClient client,
  LocalNotificationService? notifications,
  LocalAssignmentRepository? repository,
  SecureSessionStore? session,
}) =>
    AssignmentStore(
      sessionStore: session ?? _MemorySessionStore(),
      notificationService: notifications ?? _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
      backgroundReminderGateway: gateway,
      repository: repository ??
          LocalAssignmentRepository(
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
      deadlineTrusted: true,
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

class _BlockingClient extends ChaoxingLocalClient {
  final started = Completer<void>();
  final result = Completer<List<Assignment>>();

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<List<Assignment>> fetchAssignments() {
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  void cancelActiveRequests({bool reportCancelled = true}) {
    if (!result.isCompleted) {
      result.completeError(const SyncReadException(SyncIssue(
        SyncIssueKind.cancelled,
        '本次同步已取消',
        stage: 'request',
      )));
    }
  }
}

class _MemorySessionStore extends SecureSessionStore {
  String? account = 'student';

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingPassword() async => null;

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;

  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    this.account = account;
  }

  @override
  Future<void> clear() async {
    account = null;
  }
}

class _LoginClient extends ChaoxingLocalClient {
  int clearCalls = 0;

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true, displayName: '合成账号');

  @override
  void clearSession() {
    clearCalls++;
    super.clearSession();
  }
}

class _FailingReloadRepository extends LocalAssignmentRepository {
  _FailingReloadRepository(_FakeGateway gateway)
      : super(backgroundReminderGateway: gateway);

  bool failReload = false;

  @override
  Future<List<Assignment>> loadJournal() async {
    if (failReload) throw StateError('synthetic reload failure');
    return super.loadJournal();
  }
}

class _NoopNotificationService extends LocalNotificationService {
  int legacyCleanupCalls = 0;
  bool failLegacyCleanup = false;
  bool legacyMigrationComplete = false;

  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async =>
      legacyMigrationComplete;

  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> removeLegacyAssignmentSchedules() async {
    legacyCleanupCalls++;
    if (failLegacyCleanup) {
      throw StateError('synthetic legacy migration failure');
    }
    legacyMigrationComplete = true;
  }

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
  final syncAcquisitions = <String>[];
  final syncReleases = <String>[];
  final clearedAccounts = <String>[];
  bool baseline = false;
  int mutationVersion = 0;
  Set<String> known = {};
  Set<String> sentNew = {};
  DateTime? lastAttempt;
  DateTime? lastFull;
  bool? waitedResult;
  bool syncAcquired = true;
  bool failSettings = false;
  bool failDaytime = false;
  bool failPrivacy = false;
  bool failClear = false;
  bool failSwitch = false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<int> ensureActiveAccount(String accountHash) async => 1;

  @override
  Future<int> switchAccount({
    required String? previousAccountHash,
    required String accountHash,
  }) async {
    if (failSwitch) throw StateError('synthetic switch failure');
    return 2;
  }

  @override
  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
  }) async {
    if (failSettings) throw StateError('synthetic settings failure');
    mutationVersion++;
  }

  @override
  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
  }) async {
    if (failDaytime) throw StateError('synthetic daytime failure');
  }

  @override
  Future<SyncLeaseResult> acquireSyncLease({
    required String accountHash,
    required String requestId,
    required DateTime requestedAt,
  }) async {
    syncAcquisitions.add(requestId);
    if (!syncAcquired) {
      return const SyncLeaseResult(
        acquired: false,
        waited: true,
        lastAttemptAt: null,
        lastFullSuccessAt: null,
      );
    }
    final waited = waitedResult;
    final timestamp = requestedAt.add(const Duration(milliseconds: 1));
    return SyncLeaseResult(
      acquired: true,
      waited: waited != null,
      lastAttemptAt: waited == null ? null : timestamp,
      lastFullSuccessAt: waited == true ? timestamp : null,
    );
  }

  @override
  Future<void> releaseSyncLease({
    required String accountHash,
    required String requestId,
  }) async {
    syncReleases.add(requestId);
  }

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
  Future<int> clearActiveAccount(String accountHash) async {
    if (failClear) throw StateError('synthetic clear failure');
    clearedAccounts.add(accountHash);
    return 3;
  }

  @override
  Future<void> cancelAssignmentDeliveryKeepEvents(String accountHash) async {
    if (failPrivacy) throw StateError('synthetic privacy failure');
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
