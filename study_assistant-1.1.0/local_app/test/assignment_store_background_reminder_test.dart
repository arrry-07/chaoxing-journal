import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/reminder_history.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/account_identity.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  test('background engine mirrors settings without reconciling schedules',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final store = _store(
      gateway: gateway,
      client: _ClientQueue([[]]),
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);

    await store.restoreSession();

    expect(gateway.reconcileSettings, isNotEmpty);
    expect(gateway.reconcileSettings.last, isFalse);
  });

  test('notification signal outside the window reports skip reason', () async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'background_check_enabled_v1': false,
      'background_check_interval_minutes_v1': 240,
      'notification_listener_enabled_v1': true,
      'new_assignment_reminder_enabled_v1': true,
      'background_check_legacy_migration_v1': true,
    });
    final gateway = _FakeGateway();
    final client = _ClientQueue([[]]);
    final store = _store(
      gateway: gateway,
      client: client,
      clock: () => DateTime(2026, 11, 17, 0, 30),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final result = await store.runBackgroundAutomaticCheck(
      BackgroundSyncTrigger.notificationSignal,
    );

    expect(result.success, false);
    expect(result.skipped, true);
    expect(result.skipReason, BackgroundCheckResult.outsideWindowSkipReason);
    expect(result.nextTargetAt, DateTime(2026, 11, 17, 8));
    expect(client.calls, 0);
  });

  test('notification signal cannot read remotely before native authorization',
      () async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'background_check_enabled_v1': true,
      'background_check_interval_minutes_v1': 240,
      'notification_listener_enabled_v1': true,
      'new_assignment_reminder_enabled_v1': true,
      'background_check_legacy_migration_v1': true,
    });
    final gateway = _FakeGateway()
      ..remoteAuthorization = NotificationRemoteAuthorization.outsideWindow;
    final client = _ClientQueue([[]]);
    final store = _store(
      gateway: gateway,
      client: client,
      clock: () => DateTime(2026, 11, 18, 10),
      remoteStart: const NotificationRemoteStartContext(
        accountHash: 'unused',
        sessionEpoch: 1,
        claimToken: 'claim',
        workerId: 'work',
      ),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final result = await store.runBackgroundAutomaticCheck(
      BackgroundSyncTrigger.notificationSignal,
    );

    expect(gateway.authorizations, 1);
    expect(client.calls, 0);
    expect(result.skipped, isTrue);
    expect(result.skipReason, BackgroundCheckResult.outsideWindowSkipReason);
    expect(result.remoteReadInvoked, isFalse);
  });

  test('granted remote authorization is visible in the sync result', () async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'background_check_enabled_v1': true,
      'background_check_interval_minutes_v1': 240,
      'notification_listener_enabled_v1': true,
      'new_assignment_reminder_enabled_v1': true,
      'background_check_legacy_migration_v1': true,
    });
    final gateway = _FakeGateway()
      ..remoteAuthorization = NotificationRemoteAuthorization.granted;
    final client = _ClientQueue([[]]);
    final store = _store(
      gateway: gateway,
      client: client,
      clock: () => DateTime(2026, 11, 18, 10),
      remoteStart: const NotificationRemoteStartContext(
        accountHash: 'unused',
        sessionEpoch: 1,
        claimToken: 'claim',
        workerId: 'work',
      ),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final result = await store.runBackgroundAutomaticCheck(
      BackgroundSyncTrigger.notificationSignal,
    );

    expect(gateway.authorizations, 1);
    expect(client.calls, 1);
    expect(result.remoteReadInvoked, isTrue);
  });

  test('lease wait crossing midnight preserves outside-window reason',
      () async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_interval_minutes': 0,
      'background_check_enabled_v1': true,
      'background_check_interval_minutes_v1': 240,
      'notification_listener_enabled_v1': true,
      'new_assignment_reminder_enabled_v1': true,
      'background_check_legacy_migration_v1': true,
    });
    var now = DateTime(2026, 11, 17, 23, 59);
    final gateway = _FakeGateway()
      ..onAcquire = () => now = DateTime(2026, 11, 18, 0, 1);
    final client = _ClientQueue([[]]);
    final store = _store(
      gateway: gateway,
      client: client,
      clock: () => now,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final result = await store.runBackgroundAutomaticCheck(
      BackgroundSyncTrigger.notificationSignal,
    );

    expect(result.skipReason, BackgroundCheckResult.outsideWindowSkipReason);
    expect(result.success, false);
    expect(result.skipped, true);
    expect(client.calls, 0);
  });

  test('store baselines new sources silently and retains formal new reminders',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway()
      ..baseline = true
      ..baselinedSources = {'courseWork'};
    final deadline = DateTime.now().add(const Duration(days: 2));
    final task = _assignment('task', deadline).copyWith(
      id: 'cx:activity:1:2:task',
      source: AssignmentSource.classroomActivity,
      activityType: 35,
    );
    final quiz = _assignment('quiz', deadline).copyWith(
      id: 'cx:activity:1:2:quiz',
      source: AssignmentSource.classroomActivity,
      activityType: 42,
    );
    final nextTask = task.copyWith(id: 'cx:activity:1:2:next-task');
    final client = _ClientQueue([
      [_assignment('formal-new', deadline), task, quiz],
      [_assignment('formal-new', deadline), task, nextTask, quiz],
    ], sourceResultsBySync: const [
      [
        SyncSourceResult(source: 'courseWork', phase: SyncSourcePhase.success),
        SyncSourceResult(
            source: 'classroomActivity:35', phase: SyncSourcePhase.success),
        SyncSourceResult(
            source: 'classroomActivity:42', phase: SyncSourcePhase.partial),
      ],
      [
        SyncSourceResult(
            source: 'classroomActivity:35', phase: SyncSourcePhase.partial),
        SyncSourceResult(
            source: 'classroomActivity:42', phase: SyncSourcePhase.success),
      ],
    ]);
    final store = _store(gateway: gateway, client: client);
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(gateway.plans.last.newEvents.map((e) => e.assignmentId),
        ['cx:work:1:2:formal-new']);
    expect(gateway.baselinedSources, {'courseWork', 'classroomActivity:35'});
    expect(gateway.plans.last.deadlineEvents.map((e) => e.assignmentId),
        contains(task.id));
    await store.syncAssignments();
    expect(
        gateway.plans.last.newEvents.map((e) => e.assignmentId), [nextTask.id]);
    expect(gateway.baselinedSources,
        {'courseWork', 'classroomActivity:35', 'classroomActivity:42'});
  });

  test(
      'local reminder rebuild cannot establish stale successful source baseline',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final client = _ClientQueue([[]])
      ..sourceResults = const [
        SyncSourceResult(
            source: 'classroomActivity:35', phase: SyncSourcePhase.success),
      ];
    final store = _store(gateway: gateway, client: client);
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.refreshAssignments();
    expect(gateway.plans, isNotEmpty);
    expect(gateway.baselinedSources, isEmpty);
  });

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

  test('stale native session rejects a late group hide without a write',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final assignment =
        _assignment('stale-hide', DateTime.now().add(const Duration(days: 2)));
    final store = _store(
      gateway: gateway,
      client: _ClientQueue([
        [assignment],
      ]),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    gateway.sessionCurrent = false;

    final saved = await store.setAssignmentsHidden([assignment.id], true);

    expect(saved, isFalse);
    expect(store.hiddenAssignments, isEmpty);
    expect(store.assignments.map((item) => item.id), contains(assignment.id));
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

  test('same account relogin rotates native session epoch', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final store = _store(
      gateway: gateway,
      client: _LoginClient(),
      session: _MemorySessionStore()..account = 'student',
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.loginChaoxing(
      account: 'student',
      password: 'secret',
      agreementAccepted: true,
    );

    expect(gateway.rotatedAccounts, [AccountIdentity.hash('student')]);
    expect(gateway.switchedPairs, isEmpty);
  });

  test(
      'background observation skips quiet daytime coalesce and records outsideWindow as deferred with stable key',
      () async {
    SharedPreferences.setMockInitialValues({
      'background_check_enabled_v1': true,
      'background_check_interval_minutes_v1': 240,
      'notification_listener_enabled_v1': true,
      'new_assignment_reminder_enabled_v1': true,
      'background_check_legacy_migration_v1': true,
    });
    final gateway = _FakeGateway();
    var currentNow = DateTime(2026, 11, 18, 9, 0);
    final quietStore = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _ClientQueue([[]]),
      backgroundReminderGateway: gateway,
      repository: LocalAssignmentRepository(backgroundReminderGateway: gateway),
      nativeReminderDeliveryEnabled: true,
      reminderHistoryEnabled: true,
      manageBackgroundSchedule: false,
      clock: () => currentNow,
    );
    addTearDown(quietStore.dispose);
    await quietStore.restoreSession();

    await quietStore.runBackgroundAutomaticCheck(
      BackgroundSyncTrigger.daytime,
    );
    gateway.recordedObservations.clear();
    currentNow = DateTime(2026, 11, 18, 9, 30);
    final quietResult = await quietStore.runBackgroundAutomaticCheck(
      BackgroundSyncTrigger.daytime,
    );
    expect(quietResult.skipped, isTrue);
    expect(quietResult.success, isTrue);
    expect(gateway.recordedObservations, isEmpty);

    final nightStore = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _ClientQueue([[]]),
      backgroundReminderGateway: gateway,
      repository: LocalAssignmentRepository(backgroundReminderGateway: gateway),
      nativeReminderDeliveryEnabled: true,
      reminderHistoryEnabled: true,
      manageBackgroundSchedule: false,
      clock: () => DateTime(2026, 11, 18, 2, 0),
    );
    addTearDown(nightStore.dispose);
    await nightStore.restoreSession();

    final nightResult = await nightStore.runBackgroundAutomaticCheck(
      BackgroundSyncTrigger.notificationSignal,
    );
    expect(
        nightResult.skipReason, BackgroundCheckResult.outsideWindowSkipReason);
    expect(gateway.recordedObservations, hasLength(1));
    final obs = gateway.recordedObservations.single;
    expect(obs.stage, 'deferred');
    expect(obs.reasonCode, BackgroundCheckResult.outsideWindowSkipReason);
    expect(obs.logicalKey, 'background:notificationSignal:0');
  });

  test(
      'manual reschedule failure records cancelFailed and completion records completed',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final notifications = _NoopNotificationService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _ClientQueue([[]]),
      backgroundReminderGateway: gateway,
      repository: LocalAssignmentRepository(backgroundReminderGateway: gateway),
      nativeReminderDeliveryEnabled: true,
      reminderHistoryEnabled: true,
      manageBackgroundSchedule: true,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final due = DateTime.now().add(const Duration(days: 2));
    await store.saveNotebook(
      (nb) => StudyNotebook(
        terms: nb.terms,
        entries: [
          ManualEntry(
            id: 'm-fail',
            title: '测失败',
            kind: 'todo',
            at: due,
            remind: true,
            done: false,
          ),
          ManualEntry(
            id: 'm-done',
            title: '测完成',
            kind: 'todo',
            at: due,
            remind: true,
            done: false,
          ),
        ],
      ),
      store.accountEpoch,
    );

    gateway.recordedOutcomes.clear();
    notifications.failManualReschedule = true;
    await store.saveNotebook(
      (nb) => StudyNotebook(
        terms: nb.terms,
        entries: [
          ManualEntry(
            id: 'm-done',
            title: '测完成',
            kind: 'todo',
            at: due,
            remind: true,
            done: true,
          ),
        ],
      ),
      store.accountEpoch,
    );
    final failOutcomes = gateway.recordedOutcomes
        .where((o) => o.subjectId == 'm-fail' || o.subjectId == 'm-done')
        .toList();
    expect(failOutcomes, hasLength(2));
    expect(
      failOutcomes.every(
        (o) =>
            o.stage == 'cancelFailed' &&
            o.reasonCode == 'scheduleBatchFailed' &&
            o.evidenceState == 'recoveryPending',
      ),
      isTrue,
    );

    gateway.recordedOutcomes.clear();
    notifications.failManualReschedule = false;
    await store.saveNotebook(
      (nb) => StudyNotebook(
        terms: nb.terms,
        entries: [
          ManualEntry(
            id: 'm-done-2',
            title: '测完成2',
            kind: 'todo',
            at: due,
            remind: true,
            done: false,
          ),
        ],
      ),
      store.accountEpoch,
    );
    gateway.recordedOutcomes.clear();
    await store.saveNotebook(
      (nb) => StudyNotebook(
        terms: nb.terms,
        entries: [
          ManualEntry(
            id: 'm-done-2',
            title: '测完成2',
            kind: 'todo',
            at: due,
            remind: true,
            done: true,
          ),
        ],
      ),
      store.accountEpoch,
    );
    final completedOutcome = gateway.recordedOutcomes.singleWhere(
      (o) => o.subjectId == 'm-done-2' && o.stage == 'cancelled',
    );
    expect(completedOutcome.reasonCode, 'completed');
  });

  test(
      'explainReminder surfaces health query failure as queryFailed and batches >50 refs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = _FakeGateway();
    final notifications = _NoopNotificationService()..failInspectHealth = true;
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _ClientQueue([[]]),
      backgroundReminderGateway: gateway,
      repository: LocalAssignmentRepository(backgroundReminderGateway: gateway),
      nativeReminderDeliveryEnabled: true,
      reminderHistoryEnabled: true,
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final refs = List.generate(
      75,
      (i) => ReminderSubjectRef('assignment', 'cx:work:1:2:$i'),
    );
    await store.inspectReminderSubjects(refs);
    expect(gateway.inspectedBatches, [50, 25]);

    await store.saveNotebook(
      (nb) => StudyNotebook(
        terms: nb.terms,
        entries: [
          ManualEntry(
            id: 'm-q',
            title: '测查询',
            kind: 'todo',
            at: DateTime.now().add(const Duration(days: 2)),
            remind: true,
            done: false,
          ),
        ],
      ),
      store.accountEpoch,
    );
    final manualExplanation = await store.explainReminder(
      kind: 'manual',
      id: 'm-q',
    );
    expect(manualExplanation.queryWarnings, isNotEmpty);
    expect(
      manualExplanation.categories.single.status,
      ReminderExplanationStatus.queryFailed,
    );
  });

  test('B1: native privacy cleanup runs once until details are re-enabled',
      () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': false});
    final gateway1 = _FakeGateway();
    final store1 = _store(gateway: gateway1, client: _ClientQueue([[]]));
    addTearDown(store1.dispose);
    await store1.restoreSession();
    expect(gateway1.cancelDeliveryCalls, 1);

    // Second cold start must not repeat native delivery cancellation.
    final gateway2 = _FakeGateway();
    final store2 = _store(gateway: gateway2, client: _ClientQueue([[]]));
    addTearDown(store2.dispose);
    await store2.restoreSession();
    expect(gateway2.cancelDeliveryCalls, 0);

    // Headless background worker must not set or repeat startup privacy cleanup.
    final gateway3 = _FakeGateway();
    final headless = _store(
      gateway: gateway3,
      client: _ClientQueue([[]]),
      manageBackgroundSchedule: false,
    );
    addTearDown(headless.dispose);
    await headless.restoreSession();
    expect(gateway3.cancelDeliveryCalls, 0);
  });

  test(
      'H2: logout retains reminder history cleanup failure warning in store error',
      () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': true});
    final gateway = _FakeGateway()..failFinishLogout = true;
    final notifications = _NoopNotificationService()..showDetails = true;
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _ClientQueue([[]]),
      backgroundReminderGateway: gateway,
      repository: LocalAssignmentRepository(backgroundReminderGateway: gateway),
      nativeReminderDeliveryEnabled: true,
      reminderHistoryEnabled: true,
      manageBackgroundSchedule: true,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.logout();

    expect(store.isAuthenticated, isFalse);
    expect(store.error, contains('退出时提醒记录清理未确认'));
  });

  test(
      'H3: cross-account login rollback preserves old history and same-account rollback re-enables session',
      () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': true});
    final gateway = _FakeGateway();
    final session = _MemorySessionStore()
      ..account = 'acct-old'
      ..password = 'saved-pw';
    final notifications = _NoopNotificationService()..showDetails = true;
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _LoginClient(),
      backgroundReminderGateway: gateway,
      repository: LocalAssignmentRepository(backgroundReminderGateway: gateway),
      nativeReminderDeliveryEnabled: true,
      reminderHistoryEnabled: true,
      manageBackgroundSchedule: true,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    // Cross-account switch fails while saving credentials -> rolls back.
    session.failSave = true;
    await store.loginChaoxing(
      account: 'acct-new',
      password: 'pw',
      agreementAccepted: true,
    );
    expect(store.error, contains('synthetic credential save failure'));
    expect(store.account, 'acct-old');
    expect(gateway.beginLogoutCalls, 0);

    // Same-account reauth fails while saving credentials -> rotated epoch re-synced.
    gateway.lastEnabledEpoch = 0;
    session.failSave = true;
    await store.loginChaoxing(
      account: 'acct-old',
      password: 'pw',
      agreementAccepted: true,
    );
    expect(store.error, contains('synthetic credential save failure'));
    expect(gateway.lastEnabledEpoch, 3);
  });

  test(
      'H6: skipped manual reschedule under privacy pending records cancelFailed not cancelled',
      () async {
    SharedPreferences.setMockInitialValues({'notification_details_v1': true});
    final gateway = _FakeGateway();
    final notifications = _NoopNotificationService()..showDetails = true;
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _ClientQueue([[]]),
      backgroundReminderGateway: gateway,
      repository: LocalAssignmentRepository(backgroundReminderGateway: gateway),
      nativeReminderDeliveryEnabled: true,
      reminderHistoryEnabled: true,
      manageBackgroundSchedule: true,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final due = DateTime.now().add(const Duration(days: 2));
    await store.saveNotebook(
      (nb) => StudyNotebook(
        terms: nb.terms,
        entries: [
          ManualEntry(
            id: 'm-skip',
            title: '隐私阻断个人安排',
            kind: 'todo',
            at: due,
            remind: true,
            done: false,
          ),
        ],
      ),
      store.accountEpoch,
    );

    // Make _afterAssignmentsChanged hit _privacyCleanupPending by leaving cleanup pending.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_details_v1', false);
    await prefs.remove('notification_privacy_verified_hidden_v1');
    notifications.failCancelPrivate = true;
    await store.restoreSession();
    expect(store.notificationPrivacyPending, isTrue);

    gateway.recordedOutcomes.clear();
    await store.saveNotebook(
      (nb) => StudyNotebook(),
      store.accountEpoch,
    );
    final outcome = gateway.recordedOutcomes.singleWhere(
      (item) => item.subjectId == 'm-skip',
    );
    expect(outcome.stage, 'cancelFailed');
    expect(outcome.evidenceState, 'recoveryPending');
  });

  test(
      'M6: rescheduleSummary emits cancelled outcomes for replaced or disabled future summary keys',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final pending = <Map<String, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'getNotificationChannels':
          return <Map<String, Object?>>[];
        case 'pendingNotificationRequests':
          return pending.toList();
        case 'getActiveNotifications':
          return <Map<String, Object?>>[];
        case 'zonedSchedule':
          final args = call.arguments as Map;
          pending.add({
            'id': args['id'],
            'title': args['title'],
            'body': args['body'],
            'payload': args['payload'],
          });
          return true;
        case 'cancel':
          final id = (call.arguments as Map)['id'];
          pending.removeWhere((n) => n['id'] == id);
          return true;
        default:
          return true;
      }
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    SharedPreferences.setMockInitialValues({});
    final service = LocalNotificationService();

    await service.rescheduleSummary(
      const [],
      PersonalWorkspace(summaryEnabled: true, summaryHour: 9, summaryMinute: 0),
      null,
    );
    final firstKeys = service.lastScheduleOutcomes
        .where((o) => o.stage == 'scheduled')
        .map((o) => o.logicalKey)
        .toSet();
    expect(firstKeys, hasLength(7));

    await service.rescheduleSummary(
      const [],
      PersonalWorkspace(
          summaryEnabled: true, summaryHour: 21, summaryMinute: 0),
      null,
    );
    final replacedCancelled = service.lastScheduleOutcomes
        .where((o) => o.stage == 'cancelled')
        .toList();
    expect(replacedCancelled, hasLength(7));
    expect(
      replacedCancelled.every(
        (o) =>
            o.reasonCode == 'scheduleReplaced' &&
            o.evidenceState == 'removed' &&
            firstKeys.contains(o.logicalKey),
      ),
      isTrue,
    );

    final secondKeys = service.lastScheduleOutcomes
        .where((o) => o.stage == 'scheduled')
        .map((o) => o.logicalKey)
        .toSet();
    await service.rescheduleSummary(
      const [],
      PersonalWorkspace(
          summaryEnabled: false, summaryHour: 21, summaryMinute: 0),
      null,
    );
    final disabledCancelled = service.lastScheduleOutcomes
        .where((o) => o.stage == 'cancelled')
        .toList();
    expect(disabledCancelled, hasLength(7));
    expect(
      disabledCancelled.every(
        (o) =>
            o.reasonCode == 'reminderDisabled' &&
            o.evidenceState == 'removed' &&
            secondKeys.contains(o.logicalKey),
      ),
      isTrue,
    );
  });
}

AssignmentStore _store({
  required _FakeGateway gateway,
  required ChaoxingLocalClient client,
  LocalNotificationService? notifications,
  LocalAssignmentRepository? repository,
  SecureSessionStore? session,
  bool manageBackgroundSchedule = true,
  DateTime Function()? clock,
  NotificationRemoteStartContext? remoteStart,
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
      notificationRemoteStart: remoteStart,
      manageBackgroundSchedule: manageBackgroundSchedule,
      clock: clock,
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
  _ClientQueue(this.results, {this.sourceResultsBySync});

  final List<List<Assignment>> results;
  final List<List<SyncSourceResult>>? sourceResultsBySync;
  int calls = 0;

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<List<Assignment>> fetchAssignments() async {
    final result = results[calls.clamp(0, results.length - 1)];
    final sources = sourceResultsBySync;
    sourceResults = sources == null
        ? const [
            SyncSourceResult(
                source: 'courseWork', phase: SyncSourcePhase.success)
          ]
        : sources[calls.clamp(0, sources.length - 1)];
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
  String? password;
  bool failSave = false;

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingPassword() async => password;

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
    if (failSave) {
      failSave = false;
      throw StateError('synthetic credential save failure');
    }
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
  bool failCancelPrivate = false;
  bool legacyMigrationComplete = false;
  bool failManualReschedule = false;
  bool failInspectHealth = false;
  bool failReadEvidence = false;

  @override
  Future<ReminderHealth> inspectHealth() async {
    if (failInspectHealth) throw StateError('synthetic health failure');
    return const ReminderHealth(
      notifications: true,
      assignmentChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
      manualChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
      summaryChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
      scheduleRecoveryPending: false,
    );
  }

  @override
  Future<PluginScheduleEvidenceSnapshot> readScheduleEvidence() async {
    if (failReadEvidence) throw StateError('synthetic evidence failure');
    return PluginScheduleEvidenceSnapshot(
      items: const [],
      error: null,
      checkedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async =>
      legacyMigrationComplete;

  @override
  Future<void> cancelPrivateSchedules() async {
    if (failCancelPrivate) throw StateError('synthetic cancel private failure');
  }

  @override
  Future<void> removeLegacyAssignmentSchedules() async {
    legacyCleanupCalls++;
    if (failLegacyCleanup) {
      throw StateError('synthetic legacy migration failure');
    }
    legacyMigrationComplete = true;
  }

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {
    if (failManualReschedule) {
      throw StateError('synthetic manual reschedule failure');
    }
  }

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
  final rotatedAccounts = <String>[];
  final switchedPairs = <(String?, String)>[];
  final recordedObservations = <ReminderObservation>[];
  final recordedOutcomes = <ReminderScheduleOutcome>[];
  final inspectedBatches = <int>[];
  bool baseline = false;
  Set<String> baselinedSources = {};
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
  bool failFinishLogout = false;
  int cancelDeliveryCalls = 0;
  int beginLogoutCalls = 0;
  int lastEnabledEpoch = 0;
  int authorizations = 0;
  NotificationRemoteAuthorization remoteAuthorization =
      NotificationRemoteAuthorization.granted;
  bool sessionCurrent = true;
  final reconcileSettings = <bool>[];
  void Function()? onAcquire;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<int> ensureActiveAccount(String accountHash) async => 1;

  @override
  Future<bool> isSessionCurrent(String accountHash, int sessionEpoch) async =>
      sessionCurrent;

  @override
  Future<NotificationRemoteAuthorization> authorizeNotificationRemoteStart(
    NotificationRemoteStartContext context,
  ) async {
    authorizations++;
    return remoteAuthorization;
  }

  @override
  Future<int> switchAccount({
    required String? previousAccountHash,
    required String accountHash,
  }) async {
    if (failSwitch) throw StateError('synthetic switch failure');
    switchedPairs.add((previousAccountHash, accountHash));
    return 2;
  }

  @override
  Future<int> rotateSessionEpoch(String accountHash) async {
    rotatedAccounts.add(accountHash);
    return 3;
  }

  @override
  Future<ReminderHistoryControl> getReminderHistoryControl({
    String? accountHash,
    int? sessionEpoch,
  }) async =>
      const ReminderHistoryControl(
        historyGeneration: 1,
        recordingEnabled: true,
        ownerMatches: true,
        purgePending: false,
        purgeToken: null,
      );

  @override
  Future<int> enableReminderHistorySession({
    required String accountHash,
    required int sessionEpoch,
    required int expectedHistoryGeneration,
  }) async {
    lastEnabledEpoch = sessionEpoch;
    return 1;
  }

  @override
  Future<ReminderHistoryLogoutStart> beginReminderHistoryLogout({
    required int expectedHistoryGeneration,
    required String requestId,
    required String accountHash,
    required int sessionEpoch,
  }) async {
    beginLogoutCalls++;
    return const ReminderHistoryLogoutStart(
      historyGeneration: 2,
      purgeToken: 'purge-token-1',
    );
  }

  @override
  Future<ReminderHistoryLogoutFinish> finishReminderHistoryLogout(
    String purgeToken,
  ) async {
    if (failFinishLogout) {
      throw const ReminderHistoryException('history_unavailable', '退出清理超时');
    }
    return const ReminderHistoryLogoutFinish(
      cleared: true,
      historyGeneration: 2,
    );
  }

  @override
  Future<ReminderObservationContext> acquireReminderObservationContext({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      ReminderObservationContext(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
        historyGeneration: 1,
        operationSequence:
            recordedObservations.length + recordedOutcomes.length + 1,
      );

  @override
  Future<String> appendReminderObservation({
    required ReminderObservationContext context,
    required ReminderObservation observation,
  }) async {
    recordedObservations.add(observation);
    return 'inserted';
  }

  @override
  Future<ReminderScheduleOutcomeResult> recordReminderScheduleOutcome({
    required ReminderObservationContext context,
    required List<ReminderScheduleOutcome> outcomes,
  }) async {
    recordedOutcomes.addAll(outcomes);
    return const ReminderScheduleOutcomeResult(
      evidenceUpdated: 1,
      evidenceIgnored: 0,
      inserted: 1,
      duplicate: 0,
      expired: 0,
      warning: null,
    );
  }

  @override
  Future<ReminderSubjectEvidence> inspectReminderSubjects({
    required ReminderObservationContext context,
    required List<ReminderSubjectRef> subjectRefs,
  }) async {
    inspectedBatches.add(subjectRefs.length);
    return ReminderSubjectEvidence(
      checkedAt: DateTime.now(),
      nativeEvents: const [],
      pluginEvidence: const [],
      queryWarnings: const [],
      historyGeneration: 1,
    );
  }

  @override
  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
    bool reconcileSchedules = true,
  }) async {
    if (failSettings) throw StateError('synthetic settings failure');
    reconcileSettings.add(reconcileSchedules);
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
    onAcquire?.call();
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
    cancelDeliveryCalls++;
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
        baselinedSources: {...baselinedSources},
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
    baselinedSources = {...plan.baselinedSources};
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
