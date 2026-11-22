import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/features/course_study_hub_screen.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/account_identity.dart';
import 'package:study_assistant_mobile/src/services/assignment_change_log.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_check_settings.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _MemSessionStore extends SecureSessionStore {
  _MemSessionStore({this.account = 'account-a', this.password = 'pass-a'});

  String? account;
  String? password;
  String? displayName = '同学A';
  String? avatarUrl;

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingPassword() async => password;

  @override
  Future<String?> readChaoxingDisplayName() async => displayName;

  @override
  Future<String?> readChaoxingAvatarUrl() async => avatarUrl;

  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    this.account = account;
    this.password = password;
    this.displayName = displayName;
    this.avatarUrl = avatarUrl;
  }

  @override
  Future<void> clearWebSession() async {}

  @override
  Future<void> clear() async {
    account = null;
    password = null;
    displayName = null;
    avatarUrl = null;
  }
}

class _NoopNotifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> assignments,
    PersonalWorkspace personal,
    DateTime? lastSyncAt,
  ) async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}

  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;

  @override
  Future<void> removeLegacyAssignmentSchedules() async {}
}

class _RecordingWidgetSnapshot extends WidgetSnapshotService {
  final List<List<String>> savedTitles = [];

  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {
    savedTitles.add(assignments.map((a) => a.title).toList());
  }
}

class _FakeGateway extends BackgroundReminderGateway {
  _FakeGateway();

  int _epoch = 1;
  String? activeAccountHash;
  bool sessionCurrent = true;
  int writeAcquireCount = 0;
  int writeReleaseCount = 0;
  int activeWriteDepth = 0;
  Future<void> Function(int releaseNumber)? onWriteLeaseReleased;
  bool failWriteAcquire = false;
  Completer<void>? clearActiveAccountGate;
  Completer<void>? clearActiveAccountStarted;
  Completer<void>? releaseSyncLeaseGate;
  Completer<void>? releaseSyncLeaseStarted;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<int> ensureActiveAccount(String accountHash) async {
    activeAccountHash = accountHash;
    return _epoch;
  }

  @override
  Future<int> switchAccount({
    required String? previousAccountHash,
    required String accountHash,
  }) async {
    activeAccountHash = accountHash;
    return ++_epoch;
  }

  @override
  Future<int> rotateSessionEpoch(String accountHash) async {
    activeAccountHash = accountHash;
    return ++_epoch;
  }

  @override
  Future<int> clearActiveAccount(String accountHash) async {
    clearActiveAccountStarted?.complete();
    final gate = clearActiveAccountGate;
    if (gate != null) await gate.future;
    activeAccountHash = null;
    return ++_epoch;
  }

  @override
  Future<bool> isSessionCurrent(String accountHash, int sessionEpoch) async =>
      sessionCurrent &&
      activeAccountHash == accountHash &&
      sessionEpoch == _epoch;

  @override
  Future<bool> acquireWriteLease(String owner) async {
    if (failWriteAcquire) {
      throw const BackgroundReminderGatewayException(
          'acquireWriteLease', 'synthetic lease failure');
    }
    writeAcquireCount++;
    activeWriteDepth++;
    return true;
  }

  @override
  Future<void> releaseWriteLease(String owner) async {
    writeReleaseCount++;
    activeWriteDepth--;
    await onWriteLeaseReleased?.call(writeReleaseCount);
  }

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
  }) async {
    if (releaseSyncLeaseStarted != null &&
        !releaseSyncLeaseStarted!.isCompleted) {
      releaseSyncLeaseStarted!.complete();
    }
    final gate = releaseSyncLeaseGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> markPendingUpdate({
    required String accountHash,
    required int sessionEpoch,
  }) async {}

  @override
  Future<void> updateSettings(
    String accountHash,
    int sessionEpoch,
    BackgroundCheckSettings settings, {
    required bool showDetails,
    bool reconcileSchedules = true,
  }) async {}

  @override
  Future<void> reconcileDaytimeSchedule({
    required DateTime? targetAt,
    required bool enabled,
    required int intervalMinutes,
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
  Future<ReminderPlanState> loadPlanState({
    required String accountHash,
    required int sessionEpoch,
  }) async =>
      ReminderPlanState(
        accountHash: accountHash,
        sessionEpoch: sessionEpoch,
        baselineCompleted: true,
        knownAssignmentIds: const {},
        sentNewAssignmentIds: const {},
        lastAttemptAt: null,
        lastFullSuccessAt: null,
        pendingUpdate: false,
        mutationVersion: 0,
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
  }) async =>
      const ReminderPlanApplyResult(
        scheduledDeadlineCount: 0,
        pendingNewCount: 0,
        warning: null,
      );

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
  Future<void> cancelAssignmentDeliveryKeepEvents(String accountHash) async {}
}

class _FixedClient extends ChaoxingLocalClient {
  _FixedClient(this.items);

  final List<Assignment> items;

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      ChaoxingLoginResult(success: true, displayName: '用户-$account');

  @override
  Future<List<Assignment>> fetchAssignments() async {
    hasCourseResponse = true;
    courses = const [
      ChaoxingCourseRef(courseId: '1', clazzId: '2', courseName: '高等数学'),
    ];
    succeededCourses = 1;
    failedCourses = 0;
    issues = const [];
    sourceResults = const [
      SyncSourceResult(
        source: 'courseWork',
        phase: SyncSourcePhase.success,
        succeededCourses: 1,
      ),
    ];
    return items;
  }
}

Assignment _work(String id, String title) => Assignment(
      id: 'cx:work:1:2:$id',
      courseName: '高等数学',
      title: title,
      deadlineAt: DateTime(2030, 6, 1, 12, 0),
      requirementsText: '按时提交',
      status: 'pending',
      lastSyncedAt: DateTime(2026, 11, 22, 10, 0),
      deadlineTrusted: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Batch 1B P0-01: background sync tail lease and ownership isolation',
      () {
    test(
        'stale background sync tail after cross-engine account switch cannot pollute change log, sync metadata, or widget snapshot',
        () async {
      SharedPreferences.setMockInitialValues({
        'assignment_changes_v1': jsonEncode({
          'version': 1,
          'initialized': true,
          'events': const [],
        }),
      });
      final gateway = _FakeGateway();
      final widgetSnapshot = _RecordingWidgetSnapshot();
      final repo = LocalAssignmentRepository(
        backgroundReminderGateway: gateway,
        writeLeaseOwner: 'bg-worker',
      );
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: 'account-a'),
        repository: repo,
        chaoxingClient: _FixedClient([_work('a1', '账号A机密作业')]),
        notificationService: _NoopNotifications(),
        widgetSnapshotService: widgetSnapshot,
        backgroundReminderGateway: gateway,
        nativeReminderDeliveryEnabled: true,
        manageBackgroundSchedule: false,
        clock: () => DateTime(2026, 11, 22, 10, 0),
      );
      addTearDown(store.dispose);

      await store.restoreSession();
      widgetSnapshot.savedTitles.clear();

      // Simulate foreground switching from Account A to Account B right after
      // Account A's mergeAndSave finishes and releases its write lease.
      const accountBSyncDataAt = '2030-01-01T00:00:00.000Z';
      final accountBReport = jsonEncode(
        SyncReport(
          phase: SyncPhase.success,
          attemptedAt: DateTime.utc(2030, 1, 1),
          lastDataSuccessAt: DateTime.utc(2030, 1, 1),
          lastFullSuccessAt: DateTime.utc(2030, 1, 1),
        ).toJson(),
      );
      final accountBChanges = jsonEncode({
        'version': 1,
        'initialized': true,
        'events': [
          {
            'assignmentId': 'cx:work:9:9:b1',
            'title': '账号B原有记录',
            'courseName': '账号B课程',
            'kind': 'added',
            'detail': '原记录',
            'at': '2030-01-01T00:00:00.000Z',
          }
        ],
      });

      var switchedToAccountB = false;
      final repoBeforeSync = gateway.writeReleaseCount;
      gateway.onWriteLeaseReleased = (releaseNumber) async {
        // After mergeAndSave completes (courses + mergeAndSave = 2 repo writes
        // after sync start, or once sync_data_at is about to be written),
        // simulate foreground switching the active native session & prefs owner
        // to Account B.
        if (switchedToAccountB) return;
        final prefs = await SharedPreferences.getInstance();
        final rawJournal = prefs.getString('chaoxing_journal_v2');
        if (releaseNumber > repoBeforeSync &&
            rawJournal != null &&
            rawJournal.contains('账号A机密作业')) {
          switchedToAccountB = true;
          gateway.activeAccountHash = AccountIdentity.hash('account-b');
          gateway.sessionCurrent = false;
          await prefs.setString(
            'journal_account_owner',
            AccountIdentity.hash('account-b'),
          );
          await prefs.setString('sync_data_at', accountBSyncDataAt);
          await prefs.setString('sync_report_v1', accountBReport);
          await prefs.setString(AssignmentChangeLog.key, accountBChanges);
        }
      };

      await store.syncAssignments();

      expect(switchedToAccountB, isTrue,
          reason:
              'test hook must have simulated switch right after mergeAndSave');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync_data_at'), accountBSyncDataAt,
          reason:
              'stale Account A sync tail must not overwrite Account B sync_data_at');
      expect(prefs.getString('sync_report_v1'), accountBReport,
          reason:
              'stale Account A sync tail must not overwrite Account B sync_report_v1');
      expect(prefs.getString(AssignmentChangeLog.key), accountBChanges,
          reason:
              'stale Account A sync tail must not overwrite Account B change log');
      expect(
        widgetSnapshot.savedTitles.expand((t) => t),
        isNot(contains('账号A机密作业')),
        reason:
            'stale Account A sync tail must not publish Account A items to widget',
      );
      expect(gateway.activeWriteDepth, 0,
          reason: 'all write leases must be balanced');
    });
  });

  group('Batch 1B P0-03: serial queue self-healing and _loginRunning reset',
      () {
    test(
        'failing _updateServerBackoff inside sync catch block does not permanently poison _run queue',
        () async {
      SharedPreferences.setMockInitialValues({});
      final gateway = _FakeGateway();
      final client = _RateLimitedFailOnceClient(gateway);
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: 'account-a'),
        repository: LocalAssignmentRepository(
          backgroundReminderGateway: gateway,
        ),
        chaoxingClient: client,
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
        backgroundReminderGateway: gateway,
        nativeReminderDeliveryEnabled: true,
      );
      addTearDown(store.dispose);

      await store.restoreSession();

      // First sync throws with retryAfterSeconds and fails write lease during
      // catch-block _updateServerBackoff.
      await store.syncAssignments();
      gateway.failWriteAcquire = false;

      // Queue must still be alive for subsequent operations.
      await store.followCourse('1:2', false);
      expect(store.follows('1:2'), isFalse,
          reason:
              'subsequent _run task must execute after earlier catch failure');
    });

    test('_loginRunning resets in finally even when login fails unexpectedly',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: null, password: null),
        chaoxingClient: _ThrowingThenSucceedingLoginClient(),
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
      );
      addTearDown(store.dispose);

      // First login throws an uncaught synchronous/async error inside login.
      await store.loginChaoxing(
        account: 'account-a',
        password: 'pass-a',
        agreementAccepted: true,
      );
      expect(store.isAuthenticated, isFalse);

      // Next login must not be stuck behind _loginRunning == true.
      await store.loginChaoxing(
        account: 'account-b',
        password: 'pass-b',
        agreementAccepted: true,
      );
      expect(store.isAuthenticated, isTrue);
      expect(store.account, 'account-b');
    });
  });

  group('Batch 1B P1-04: logout async cleanup serialized with generation check',
      () {
    test('concurrent login during logout is not wiped by stale logout cleanup',
        () async {
      SharedPreferences.setMockInitialValues({});
      final session =
          _MemSessionStore(account: 'account-a', password: 'pass-a');
      final gateway = _FakeGateway();
      final store = AssignmentStore(
        sessionStore: session,
        repository: LocalAssignmentRepository(
          backgroundReminderGateway: gateway,
        ),
        chaoxingClient: _FixedClient([_work('b1', '账号B作业')]),
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
        backgroundReminderGateway: gateway,
        nativeReminderDeliveryEnabled: true,
      );
      addTearDown(store.dispose);

      await store.restoreSession();
      expect(store.account, 'account-a');

      final clearGate = Completer<void>();
      final clearStarted = Completer<void>();
      gateway.clearActiveAccountGate = clearGate;
      gateway.clearActiveAccountStarted = clearStarted;

      final logoutFuture = store.logout();
      await clearStarted.future;

      final loginFuture = store.loginChaoxing(
        account: 'account-b',
        password: 'pass-b',
        agreementAccepted: true,
      );
      clearGate.complete();
      await Future.wait([logoutFuture, loginFuture]);

      expect(store.isAuthenticated, isTrue,
          reason: 'stale logout must not clear a newer login');
      expect(store.account, 'account-b');
      expect(store.accountHash, AccountIdentity.hash('account-b'));
      expect(store.nativeSessionEpoch, greaterThan(0));
      expect(session.account, 'account-b');
    });
  });

  group('Batch 1B P1-05: CourseStudyHub notice sheet & StudyNotebook isolation',
      () {
    test('stale createReminderFromNotice cannot write into switched account',
        () async {
      SharedPreferences.setMockInitialValues({});
      final noticeA = CourseNotice(
        id: 'cx:notice:${'a' * 64}',
        courseId: '1',
        clazzId: '2',
        courseName: '高等数学',
        senderName: '张老师',
        title: '账号A私密通知',
        summary: '仅限账号A查看',
        publishedAt: DateTime.utc(2030, 5, 1, 8, 0),
        publishedTrusted: true,
        lastSyncedAt: DateTime.utc(2030, 5, 1, 8, 0),
      );
      final client = _NoticeClient([noticeA]);
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: 'account-a'),
        chaoxingClient: client,
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
      );
      addTearDown(store.dispose);

      await store.restoreSession();
      await store.syncAssignments();
      final epochA = store.accountEpoch;

      client.notices = const [];
      await store.loginChaoxing(
        account: 'account-b',
        password: 'pass-b',
        agreementAccepted: true,
      );
      expect(store.account, 'account-b');

      final created = await store.createReminderFromNotice(
        noticeA,
        remindAt: DateTime(2030, 6, 1, 10, 0),
        expectedEpoch: epochA,
      );
      expect(created, isNull);
      expect(store.notebook.entries, isEmpty);
    });

    testWidgets(
        'CourseStudyHubScreen notice detail sheet auto-closes when account switches',
        (tester) async {
      await initializeDateFormatting('zh_CN');
      SharedPreferences.setMockInitialValues({});
      final noticeA = CourseNotice(
        id: 'cx:notice:${'a' * 64}',
        courseId: '1',
        clazzId: '2',
        courseName: '高等数学',
        senderName: '张老师',
        title: '账号A课程通知详情',
        summary: '账号A正文内容',
        publishedAt: DateTime.utc(2030, 5, 1, 8, 0),
        publishedTrusted: true,
        lastSyncedAt: DateTime.utc(2030, 5, 1, 8, 0),
      );
      final client = _NoticeClient([noticeA]);
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: 'account-a'),
        chaoxingClient: client,
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
      );
      addTearDown(store.dispose);

      await store.restoreSession();
      await store.syncAssignments();

      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: CourseStudyHubScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('账号A课程通知详情'));
      await tester.pumpAndSettle();
      expect(find.text('设为本地提醒'), findsOneWidget);

      client.notices = const [];
      await store.loginChaoxing(
        account: 'account-b',
        password: 'pass-b',
        agreementAccepted: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('设为本地提醒'), findsNothing,
          reason: 'notice detail sheet must close when account changes');
      expect(find.text('账号A正文内容'), findsNothing);
    });
  });

  group(
      'Batch 1B P1-06: course follow and reminder settings epoch & lease guards',
      () {
    test(
        'followCourse, saveReminderRule and saveBackgroundCheckEnabled use write lease and reject stale account switch',
        () async {
      SharedPreferences.setMockInitialValues({});
      final gateway = _FakeGateway();
      final repo = LocalAssignmentRepository(
        backgroundReminderGateway: gateway,
      );
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: 'account-a'),
        repository: repo,
        chaoxingClient: _FixedClient([_work('a1', '作业1')]),
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
        backgroundReminderGateway: gateway,
        nativeReminderDeliveryEnabled: true,
      );
      addTearDown(store.dispose);

      await store.restoreSession();
      final acquiresBefore = gateway.writeAcquireCount;

      await store.followCourse('1:2', false);
      await store.saveReminderRule([45]);
      await store.saveBackgroundCheckEnabled(false);

      expect(
          gateway.writeAcquireCount, greaterThanOrEqualTo(acquiresBefore + 3),
          reason: 'all _scopedKeys preference writes must acquire write lease');
      expect(gateway.activeWriteDepth, 0);

      // Now simulate cross-engine session invalidation: stale writes must fail
      // closed and leave Account B's preferences untouched.
      gateway.sessionCurrent = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'journal_account_owner',
        AccountIdentity.hash('account-b'),
      );
      await prefs.setStringList('unfollowed_courses', const ['9:9']);
      await prefs.setStringList('reminder_offsets_minutes', const ['60']);
      await prefs.setBool('background_check_enabled_v1', true);

      await store.followCourse('1:2', true);
      expect(await store.saveReminderRule([15]), isFalse);
      expect(await store.saveBackgroundCheckEnabled(false), isFalse);

      expect(prefs.getStringList('unfollowed_courses'), ['9:9']);
      expect(prefs.getStringList('reminder_offsets_minutes'), ['60']);
      expect(prefs.getBool('background_check_enabled_v1'), isTrue);
    });

    testWidgets('CourseListScreen disables course follow switch while loading',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final blockClient = _BlockingFetchClient();
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: 'account-a'),
        chaoxingClient: blockClient,
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
      );
      addTearDown(store.dispose);

      await store.restoreSession();
      await store.repository.saveCourses(
        const [
          CourseRef(courseId: '1', clazzId: '2', name: '高等数学'),
        ],
        account: 'account-a',
      );
      await store.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: CourseListScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();

      final idleSwitch =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(idleSwitch.onChanged, isNotNull);

      final syncFuture = store.syncAssignments();
      await blockClient.started.future;
      await tester.pump();

      final busySwitch =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(busySwitch.onChanged, isNull,
          reason: 'course follow switch must be disabled while syncing');

      blockClient.release.complete(const []);
      await syncFuture;
      await tester.pumpAndSettle();
    });
  });

  group('Batch 1B P1-07: retryReminderRecovery serialized via _run', () {
    test(
        'retryReminderRecovery waits for active _run task, guards generation, and notifies listeners',
        () async {
      SharedPreferences.setMockInitialValues({});
      final notifications = _TrackingRecoveryNotifications();
      final blockClient = _BlockingFetchClient();
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: 'account-a'),
        chaoxingClient: blockClient,
        notificationService: notifications,
        widgetSnapshotService: _RecordingWidgetSnapshot(),
      );
      addTearDown(store.dispose);

      await store.restoreSession();

      // Start a blocking _run operation (syncAssignments).
      final syncFuture = store.syncAssignments();
      await blockClient.started.future;

      final recoveryFuture = store.retryReminderRecovery();
      await Future<void>.delayed(Duration.zero);
      expect(notifications.recoverCalls, 0,
          reason:
              'retryReminderRecovery must wait in _run queue behind active task');

      var notifiedAfterRecovery = false;
      void listener() {
        if (notifications.recoverCalls > 0) notifiedAfterRecovery = true;
      }

      store.addListener(listener);
      blockClient.release.complete(const []);
      await syncFuture;
      await recoveryFuture;
      store.removeListener(listener);

      expect(notifications.recoverCalls, 1);
      expect(notifiedAfterRecovery, isTrue);
    });
  });

  group(
      'Batch 1B P1-08: account switch sync detachment & session refresh guards',
      () {
    test(
        'switching account while previous sync is unwinding does not swallow new account first sync',
        () async {
      SharedPreferences.setMockInitialValues({});
      final gateway = _FakeGateway();
      final releaseLeaseGate = Completer<void>();
      final releaseLeaseStarted = Completer<void>();
      gateway.releaseSyncLeaseGate = releaseLeaseGate;
      gateway.releaseSyncLeaseStarted = releaseLeaseStarted;
      final client = _AccountAwareBlockingClient();
      final store = AssignmentStore(
        sessionStore: _MemSessionStore(account: 'account-a'),
        repository: LocalAssignmentRepository(
          backgroundReminderGateway: gateway,
        ),
        chaoxingClient: client,
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
        backgroundReminderGateway: gateway,
        nativeReminderDeliveryEnabled: true,
      );
      addTearDown(store.dispose);

      await store.restoreSession();

      // Start Account A sync and block its network request.
      final syncA = store.syncAssignments();
      await client.firstFetchStarted.future;

      // Switch to Account B: cancelActiveRequests unblocks syncA's _run, while
      // syncA's finally block stays suspended in releaseSyncLease.
      await store.loginChaoxing(
        account: 'account-b',
        password: 'pass-b',
        agreementAccepted: true,
      );
      await releaseLeaseStarted.future;

      // Account B's auto-triggered initial sync must start rather than getting
      // coalesced onto Account A's dying _syncInFlight.
      await client.secondFetchStarted.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail(
            'Account B initial sync was swallowed by Account A _syncInFlight'),
      );

      // Now finish Account A's lease release and wait for Account B's sync too.
      gateway.releaseSyncLeaseGate = null;
      releaseLeaseGate.complete();
      await syncA;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(store.account, 'account-b');
      expect(
        store.assignments.map((a) => a.title),
        contains('账号B首轮同步作业'),
      );
    });

    test(
        '_refreshChaoxingSession does not overwrite new account credentials after await',
        () async {
      SharedPreferences.setMockInitialValues({});
      final displayNameGate = Completer<void>();
      final displayNameStarted = Completer<void>();
      final session = _GatedSessionStore(
        account: 'account-a',
        password: 'pass-a',
        displayNameStarted: displayNameStarted,
        displayNameGate: displayNameGate,
      );
      final client = _NeedsInitRefreshClient();
      final store = AssignmentStore(
        sessionStore: session,
        chaoxingClient: client,
        notificationService: _NoopNotifications(),
        widgetSnapshotService: _RecordingWidgetSnapshot(),
      );
      addTearDown(store.dispose);

      await store.restoreSession();
      session.armNextDisplayNameRead();
      final syncA = store.syncAssignments();
      await displayNameStarted.future;

      // Logout while _refreshChaoxingSession is suspended reading profile.
      final savesBeforeLogout = session.saveCount;
      final logoutFuture = store.logout();
      displayNameGate.complete();
      await Future.wait([syncA, logoutFuture]);

      expect(session.saveCount, savesBeforeLogout,
          reason:
              'stale _refreshChaoxingSession must not call saveChaoxingAccount after generation changed');
      expect(session.account, isNull);
      expect(store.isAuthenticated, isFalse);
    });
  });
}

class _ThrowingThenSucceedingLoginClient extends ChaoxingLocalClient {
  var _failedOnce = false;

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    if (!_failedOnce) {
      _failedOnce = true;
      throw StateError('unexpected login error');
    }
    return ChaoxingLoginResult(success: true, displayName: '用户-$account');
  }

  @override
  Future<List<Assignment>> fetchAssignments() async => const [];
}

class _RateLimitedFailOnceClient extends ChaoxingLocalClient {
  _RateLimitedFailOnceClient(this.gateway);

  final _FakeGateway gateway;

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<List<Assignment>> fetchAssignments() async {
    issues = const [
      SyncIssue(
        SyncIssueKind.rateLimited,
        '请求受限',
        retryAfterSeconds: 120,
      ),
    ];
    gateway.failWriteAcquire = true;
    throw StateError('synthetic rate limit');
  }
}

class _NoticeClient extends ChaoxingLocalClient {
  _NoticeClient(this.notices);

  List<CourseNotice> notices;

  @override
  bool get needsSessionInitialization => false;

  @override
  List<CourseNotice> get lastFetchedNotices => notices;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      ChaoxingLoginResult(success: true, displayName: '用户-$account');

  @override
  Future<List<Assignment>> fetchAssignments() async {
    hasCourseResponse = true;
    courses = const [
      ChaoxingCourseRef(courseId: '1', clazzId: '2', courseName: '高等数学'),
    ];
    succeededCourses = 1;
    failedCourses = 0;
    issues = const [];
    sourceResults = const [
      SyncSourceResult(
        source: 'courseWork',
        phase: SyncSourcePhase.success,
        succeededCourses: 1,
      ),
      SyncSourceResult(
        source: 'courseNotice',
        phase: SyncSourcePhase.success,
        succeededCourses: 1,
        recordCount: 1,
      ),
    ];
    return const [];
  }
}

class _BlockingFetchClient extends ChaoxingLocalClient {
  final started = Completer<void>();
  final release = Completer<List<Assignment>>();

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      ChaoxingLoginResult(success: true, displayName: '用户-$account');

  @override
  Future<List<Assignment>> fetchAssignments() async {
    hasCourseResponse = true;
    courses = const [
      ChaoxingCourseRef(courseId: '1', clazzId: '2', courseName: '高等数学'),
    ];
    if (!started.isCompleted) started.complete();
    return release.future;
  }
}

class _TrackingRecoveryNotifications extends _NoopNotifications {
  int recoverCalls = 0;

  @override
  Future<void> recoverPendingSchedules() async {
    recoverCalls++;
  }
}

class _AccountAwareBlockingClient extends ChaoxingLocalClient {
  String _loggedInAccount = 'account-a';
  int _fetchCount = 0;
  final firstFetchStarted = Completer<void>();
  final firstFetchGate = Completer<List<Assignment>>();
  final secondFetchStarted = Completer<void>();

  @override
  bool get needsSessionInitialization => false;

  @override
  void cancelActiveRequests({bool reportCancelled = true}) {
    if (!firstFetchGate.isCompleted) {
      firstFetchGate.completeError(const SyncCancelledException());
    }
  }

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    _loggedInAccount = account;
    return ChaoxingLoginResult(success: true, displayName: '用户-$account');
  }

  @override
  Future<List<Assignment>> fetchAssignments() async {
    _fetchCount++;
    hasCourseResponse = true;
    courses = const [
      ChaoxingCourseRef(courseId: '1', clazzId: '2', courseName: '高等数学'),
    ];
    succeededCourses = 1;
    failedCourses = 0;
    issues = const [];
    sourceResults = const [
      SyncSourceResult(
        source: 'courseWork',
        phase: SyncSourcePhase.success,
        succeededCourses: 1,
      ),
    ];
    if (_fetchCount == 1) {
      firstFetchStarted.complete();
      return firstFetchGate.future;
    }
    if (!secondFetchStarted.isCompleted) secondFetchStarted.complete();
    return _loggedInAccount == 'account-b'
        ? [_work('b-init', '账号B首轮同步作业')]
        : const [];
  }
}

class _GatedSessionStore extends _MemSessionStore {
  _GatedSessionStore({
    required super.account,
    required super.password,
    required this.displayNameStarted,
    required this.displayNameGate,
  }) {
    displayName = null;
    avatarUrl = null;
  }

  final Completer<void> displayNameStarted;
  final Completer<void> displayNameGate;
  bool _blockNextRead = false;
  int saveCount = 0;

  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    saveCount++;
    await super.saveChaoxingAccount(
      account: account,
      password: password,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  @override
  Future<String?> readChaoxingDisplayName() async {
    if (_blockNextRead) {
      _blockNextRead = false;
      if (!displayNameStarted.isCompleted) displayNameStarted.complete();
      await displayNameGate.future;
    }
    return displayName;
  }

  void armNextDisplayNameRead() {
    _blockNextRead = true;
  }
}

class _NeedsInitRefreshClient extends ChaoxingLocalClient {
  bool _initialized = false;

  @override
  bool get needsSessionInitialization => !_initialized;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    _initialized = true;
    // Return avatarUrl != null and displayName == null so _refreshChaoxingSession
    // awaits sessionStore.readChaoxingDisplayName() before saveChaoxingAccount().
    return const ChaoxingLoginResult(
      success: true,
      displayName: null,
      avatarUrl: 'https://photo.chaoxing.com/a.jpg',
    );
  }

  @override
  Future<List<Assignment>> fetchAssignments() async => const [];
}
