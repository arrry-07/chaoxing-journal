import 'dart:convert';

import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Failure injection into the persistence boundary used by SharedPreferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  test('cold session authenticates before requesting courses', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _ColdClient();
    final store = AssignmentStore(
        sessionStore:
            _MemorySessionStore(account: 'student', password: 'dummy'),
        notificationService: _RecordingNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: client);
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(client.events, ['login', 'fetch']);
    expect(store.error, isNull);
  });
  test('network failure does not trigger credential login', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _OfflineClient();
    final store = AssignmentStore(
        sessionStore:
            _MemorySessionStore(account: 'student', password: 'dummy'),
        notificationService: _RecordingNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: client);
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(client.logins, 0);
    expect(store.error, isNotNull);
  });
  test('partial sync attempt cools down repeated foreground refresh', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _PartialClient();
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: _RecordingNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: client);
    addTearDown(store.dispose);
    await store.restoreSession();
    final now = DateTime.now();
    await store.runDueAutoSync(now: now);
    expect(store.lastSyncAt, isNull);
    expect(client.calls, 1);
    expect(await store.runDueAutoSync(now: now.add(const Duration(minutes: 1))),
        isFalse);
    expect(client.calls, 1);
    await store.runDueAutoSync(now: now.add(const Duration(minutes: 31)));
    expect(client.calls, 2);
  });
  test(
    'auto sync updates changed deadlines and reschedules reminders',
    () async {
      SharedPreferences.setMockInitialValues({});
      final initialDeadline = DateTime(2026, 5, 7, 8);
      final updatedDeadline = DateTime(2026, 5, 8, 20);
      final client = _QueuedChaoxingClient([
        [_assignment(deadlineAt: initialDeadline)],
        [_assignment(deadlineAt: updatedDeadline)],
      ]);
      final notificationService = _RecordingNotificationService();
      final store = AssignmentStore(
        sessionStore: _MemorySessionStore(
          account: 'student',
          password: 'password',
        ),
        notificationService: notificationService,
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: client,
      );
      addTearDown(store.dispose);
      await store.restoreSession();

      await store.syncAssignments();
      expect(store.findAssignment('cx:work:1:2:work-1')?.deadlineAt,
          initialDeadline);
      expect(notificationService.lastAssignments.single.deadlineAt,
          initialDeadline);

      await store.saveAutoSyncIntervalMinutes(15);
      final ran = await store.runDueAutoSync(
        now: store.lastSyncAt!.add(const Duration(minutes: 16)),
      );

      expect(ran, isTrue);
      expect(store.findAssignment('cx:work:1:2:work-1')?.deadlineAt,
          updatedDeadline);
      expect(notificationService.lastAssignments.single.deadlineAt,
          updatedDeadline);
      expect(client.fetchCount, 2);
    },
  );

  test('custom auto sync interval is saved and used by due checks', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _QueuedChaoxingClient([
      [_assignment(deadlineAt: DateTime(2026, 5, 7, 8))],
      [_assignment(deadlineAt: DateTime(2026, 5, 7, 20))],
    ]);
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(
        account: 'student',
        password: 'password',
      ),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();

    await store.saveAutoSyncIntervalMinutes(7);

    expect(store.autoSyncIntervalMinutes, 7);
    expect(
      await store.runDueAutoSync(
        now: store.lastSyncAt!.add(const Duration(minutes: 6)),
      ),
      isFalse,
    );
    expect(
      await store.runDueAutoSync(
        now: store.lastSyncAt!.add(const Duration(minutes: 7)),
      ),
      isTrue,
    );

    final restored = AssignmentStore(
      sessionStore: _MemorySessionStore(account: 'student'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(restored.dispose);
    await restored.restoreSession();

    expect(restored.autoSyncIntervalMinutes, 7);
  });

  test('failed reminder write keeps old offsets and schedules unchanged',
      () async {
    SharedPreferences.setMockInitialValues({
      'reminder_offsets_minutes': ['1440']
    });
    final notificationService = _RecordingNotificationService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: 'student'),
      notificationService: notificationService,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final callsBefore = notificationService.rescheduleCalls;
    final prefs = await SharedPreferences.getInstance();
    _installFailingStore(prefs, {'flutter.reminder_offsets_minutes'});
    await prefs.reload();

    await store.saveReminderRule([5]);

    expect(store.reminderOffsetsMinutes, [1440]);
    expect(notificationService.rescheduleCalls, callsBefore);
    expect(store.error, contains('提醒设置未能保存'));
    await prefs.reload();
    expect(prefs.getStringList('reminder_offsets_minutes'), ['1440']);
  });

  test('failed auto sync write keeps old interval in memory and on disk',
      () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 30});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: 'student'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    _installFailingStore(prefs, {'flutter.auto_sync_interval_minutes'});
    await prefs.reload();

    await store.saveAutoSyncIntervalMinutes(7);

    expect(store.autoSyncIntervalMinutes, 30);
    expect(store.error, contains('自动同步设置未能保存'));
    await prefs.reload();
    expect(prefs.getInt('auto_sync_interval_minutes'), 30);
  });

  test(
      'sync timestamp mirror failures are visible and canonical report survives',
      () async {
    SharedPreferences.setMockInitialValues({});
    final client = _QueuedChaoxingClient([
      [_assignment(deadlineAt: DateTime.now().add(const Duration(days: 2)))],
    ]);
    final store = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    _installFailingStore(
        prefs, {'flutter.sync_attempt_at', 'flutter.sync_data_at'});
    await prefs.reload();
    expect(await prefs.setString('sync_attempt_at', 'probe'), isFalse,
        reason: 'failure injection must target the legacy attempt timestamp');
    await prefs.reload();

    await store.syncAssignments();

    expect(client.fetchCount, 1,
        reason:
            'a failed legacy mirror must not discard a successful data read');
    expect(store.findAssignment('cx:work:1:2:work-1'), isNotNull);
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(store.syncReport.lastDataSuccessAt, isNotNull);
    expect(store.syncReport.lastFullSuccessAt, isNotNull);
    expect(
        store.syncReport.issues,
        contains(predicate<SyncIssue>((issue) =>
            issue.kind == SyncIssueKind.storage &&
            issue.stage == 'persistence')));
    expect(store.syncReport.summary, contains('状态记录需要处理'));
    expect(store.error, contains('同步时间记录'));

    await prefs.reload();
    final persisted = SyncReport.fromJson(
        jsonDecode(prefs.getString('sync_report_v1')!) as Map<String, dynamic>);
    expect(persisted.phase, SyncPhase.partial);
    expect(persisted.attemptedAt, isNotNull);
    expect(persisted.lastDataSuccessAt, isNotNull);
    expect(prefs.getString('sync_attempt_at'), isNull);
    expect(prefs.getString('sync_data_at'), isNull);

    final restored = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(restored.dispose);
    await restored.restoreSession();
    expect(restored.syncReport.attemptedAt, persisted.attemptedAt);
    expect(restored.syncReport.lastDataSuccessAt, persisted.lastDataSuccessAt);
    expect(
        await restored.runDueAutoSync(
            now: persisted.attemptedAt!.add(const Duration(minutes: 1))),
        isFalse,
        reason: 'cooldown falls back to the canonical report timestamp');
  });
  test('manual schedule degradation warning is surfaced by the store',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _ManualScheduleWarningService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _QueuedChaoxingClient([[]]),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.error, contains('个人日程'));
    expect(store.error, contains('近似时间'));
  });
  test(
      'startup reconciles a running report with a newer durable data timestamp',
      () async {
    final attempted = DateTime.now().subtract(const Duration(minutes: 5));
    final dataSaved = DateTime.now().subtract(const Duration(minutes: 2));
    SharedPreferences.setMockInitialValues({
      'sync_attempt_at': attempted.toUtc().toIso8601String(),
      'sync_data_at': dataSaved.toUtc().toIso8601String(),
      'sync_report_v1': jsonEncode({
        'phase': 'running',
        'attemptedAt': attempted.toUtc().toIso8601String(),
        'lastDataSuccessAt': null,
        'lastFullSuccessAt': null,
        'succeededCourses': 1,
        'failedCourses': 0,
        'issues': [],
      }),
    });
    final store = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(store.syncReport.attemptedAt, attempted);
    expect(store.syncReport.lastDataSuccessAt, dataSaved);
    expect(
        store.syncReport.issues,
        contains(predicate<SyncIssue>((issue) =>
            issue.kind == SyncIssueKind.storage &&
            issue.stage == 'persistence')));
  });

  test('corrupt sync report is recovered as partial when journal has data',
      () async {
    SharedPreferences.setMockInitialValues({'sync_report_v1': '{broken-json'});
    final repository = LocalAssignmentRepository();
    final savedAt = DateTime.now().subtract(const Duration(minutes: 3));
    await repository.mergeAndSave(
        [_assignment(deadlineAt: DateTime.now().add(const Duration(days: 2)))]);
    final durable = await repository.lastSyncAt();
    expect(durable, isNotNull);
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: 'student'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      repository: repository,
    );
    addTearDown(store.dispose);

    await store.restoreSession();

    expect(store.syncReport.phase, SyncPhase.partial);
    expect(store.syncReport.lastDataSuccessAt, durable);
    expect(store.syncReport.lastFullSuccessAt, durable);
    expect(
        store.syncReport.issues,
        contains(predicate<SyncIssue>((issue) =>
            issue.kind == SyncIssueKind.storage &&
            issue.stage == 'persistence')));
    expect(store.error, contains('同步记录恢复未完成'));
    expect(savedAt.isBefore(durable!), isTrue);
  });

  test(
      'corrupt report recovers partial-sync data timestamp and persists repaired report',
      () async {
    final attempted = DateTime.now().subtract(const Duration(minutes: 4));
    final dataSaved = DateTime.now().subtract(const Duration(minutes: 2));
    SharedPreferences.setMockInitialValues({
      'sync_attempt_at': attempted.toUtc().toIso8601String(),
      'sync_data_at': dataSaved.toUtc().toIso8601String(),
      'sync_report_v1': '{broken-json',
    });
    final repository = LocalAssignmentRepository();
    await repository.mergeAndSave(
        [_assignment(deadlineAt: DateTime.now().add(const Duration(days: 2)))],
        completeSync: false);
    expect(await repository.lastSyncAt(), isNull,
        reason:
            'a partial course sync must not advance the full-sync timestamp');
    final store = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      repository: repository,
    );
    addTearDown(store.dispose);

    await store.restoreSession();

    expect(store.syncReport.phase, SyncPhase.partial);
    expect(store.syncReport.attemptedAt, attempted);
    expect(store.syncReport.lastDataSuccessAt, dataSaved);
    expect(store.syncReport.lastFullSuccessAt, isNull,
        reason: 'the data mirror must not be promoted to a full sync');
    expect(store.error, contains('同步记录恢复未完成'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final repaired = SyncReport.fromJson(
        jsonDecode(prefs.getString('sync_report_v1')!) as Map<String, dynamic>);
    expect(repaired.phase, SyncPhase.partial);
    expect(repaired.lastDataSuccessAt, dataSaved);
    expect(repaired.lastFullSuccessAt, isNull);
  });

  test(
      'newer durable full-sync timestamp downgrades stale success report and persists repair',
      () async {
    final previous = DateTime.now().subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'sync_attempt_at': previous.toUtc().toIso8601String(),
      'sync_data_at': previous.toUtc().toIso8601String(),
      'sync_report_v1': jsonEncode(SyncReport(
        phase: SyncPhase.success,
        attemptedAt: previous,
        lastDataSuccessAt: previous,
        lastFullSuccessAt: previous,
        succeededCourses: 1,
      ).toJson()),
    });
    final repository = LocalAssignmentRepository();
    await repository.mergeAndSave(
        [_assignment(deadlineAt: DateTime.now().add(const Duration(days: 2)))]);
    final durable = await repository.lastSyncAt();
    expect(durable, isNotNull);
    final store = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      repository: repository,
    );
    addTearDown(store.dispose);

    await store.restoreSession();

    expect(store.syncReport.phase, SyncPhase.partial,
        reason:
            'the repository advanced after the last durable success report');
    expect(store.syncReport.lastFullSuccessAt, durable);
    expect(
        store.syncReport.issues,
        contains(predicate<SyncIssue>((issue) =>
            issue.kind == SyncIssueKind.storage &&
            issue.stage == 'persistence')));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final repaired = SyncReport.fromJson(
        jsonDecode(prefs.getString('sync_report_v1')!) as Map<String, dynamic>);
    expect(repaired.phase, SyncPhase.partial);
    expect(repaired.lastFullSuccessAt, durable);
  });

  test('failed running-report write retains the new attempt timestamp',
      () async {
    final previousAttempt = DateTime.now().subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'sync_attempt_at': previousAttempt.toUtc().toIso8601String(),
      'sync_report_v1': jsonEncode(SyncReport(
        phase: SyncPhase.success,
        attemptedAt: previousAttempt,
        lastDataSuccessAt: previousAttempt,
        lastFullSuccessAt: previousAttempt,
      ).toJson()),
    });
    final client = _QueuedChaoxingClient([[]]);
    final store = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    _installRunningReportFailure(prefs);

    await store.syncAssignments();

    expect(client.fetchCount, 0,
        reason:
            'the initial running report must be durable before network work');
    expect(store.syncReport.phase, SyncPhase.failed);
    expect(store.syncReport.attemptedAt, isNotNull);
    expect(store.syncReport.attemptedAt!.isAfter(previousAttempt), isTrue,
        reason: 'a failed report write must not restore the previous attempt');
    expect(store.error, contains('同步结果未能保存'));
    await prefs.reload();
    final persisted = SyncReport.fromJson(
        jsonDecode(prefs.getString('sync_report_v1')!) as Map<String, dynamic>);
    expect(persisted.phase, SyncPhase.failed);
    expect(persisted.attemptedAt, store.syncReport.attemptedAt);
  });
  test('failed final report write recovers saved data as partial after restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final client = _QueuedChaoxingClient([
      [_assignment(deadlineAt: DateTime.now().add(const Duration(days: 2)))],
    ]);
    final store = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    _installFinalReportFailure(prefs);

    await store.syncAssignments();

    expect(client.fetchCount, 1);
    expect(store.findAssignment('cx:work:1:2:work-1'), isNotNull,
        reason: 'the successfully persisted journal remains available');
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(store.error, contains('同步结果记录未能保存'));
    await prefs.reload();
    final durableReport =
        jsonDecode(prefs.getString('sync_report_v1')!) as Map<String, dynamic>;
    expect(durableReport['phase'], 'running',
        reason: 'the failed final write must not be represented as committed');

    final restored = AssignmentStore(
      sessionStore:
          _MemorySessionStore(account: 'student', password: 'password'),
      notificationService: _RecordingNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(restored.dispose);
    await restored.restoreSession();

    expect(restored.findAssignment('cx:work:1:2:work-1'), isNotNull);
    expect(restored.syncReport.phase, SyncPhase.partial);
    expect(restored.syncReport.lastDataSuccessAt, isNotNull);
    expect(restored.syncReport.lastFullSuccessAt, isNotNull,
        reason: 'the repository timestamp proves the full data commit');
    expect(
        restored.syncReport.issues,
        contains(predicate<SyncIssue>((issue) =>
            issue.kind == SyncIssueKind.storage &&
            issue.stage == 'persistence')));
  });
}

Assignment _assignment({required DateTime deadlineAt}) {
  return Assignment(
    id: 'cx:work:1:2:work-1',
    courseName: '大学英语',
    title: '章节作业',
    deadlineAt: deadlineAt,
    requirementsText: '完成后提交',
    status: 'pending',
    lastSyncedAt: DateTime(2026, 5, 6, 8),
  );
}

class _QueuedChaoxingClient extends ChaoxingLocalClient {
  _QueuedChaoxingClient(this.responses);

  final List<List<Assignment>> responses;
  int fetchCount = 0;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    return const ChaoxingLoginResult(success: true);
  }

  @override
  Future<List<Assignment>> fetchAssignments() async {
    final index = fetchCount++;
    return responses[index];
  }
}

class _RecordingNotificationService extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {}

  List<Assignment> lastAssignments = [];
  int rescheduleCalls = 0;

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    rescheduleCalls++;
    lastAssignments = List.of(assignments);
  }
}

class _ManualScheduleWarningService extends _RecordingNotificationService {
  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {
    lastWarning = '精确提醒不可用，个人日程已改为系统允许的近似时间提醒';
  }
}

class _MemorySessionStore extends SecureSessionStore {
  _MemorySessionStore({this.account, this.password});

  final String? account;
  final String? password;

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;

  @override
  Future<String?> readChaoxingPassword() async => password;
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _PartialClient extends ChaoxingLocalClient {
  int calls = 0;
  @override
  Future<List<Assignment>> fetchAssignments() async {
    calls++;
    lastSyncWarning = '部分课程未读取';
    return [];
  }
}

class _OfflineClient extends ChaoxingLocalClient {
  @override
  bool get needsSessionInitialization => false;
  int logins = 0;
  @override
  Future<List<Assignment>> fetchAssignments() async =>
      throw StateError('Connection timeout');
  @override
  Future<ChaoxingLoginResult> login(
      {required String account, required String password}) async {
    logins++;
    return const ChaoxingLoginResult(success: true);
  }
}

void _installFailingStore(
  SharedPreferences prefs,
  Set<String> failingKeys,
) {
  final values = {
    for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!
  };
  SharedPreferencesStorePlatform.instance =
      _FailSelectedWrites(values, failingKeys);
}

void _installRunningReportFailure(SharedPreferences prefs) {
  final values = {
    for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!
  };
  SharedPreferencesStorePlatform.instance = _FailRunningReportStore(values);
}

void _installFinalReportFailure(SharedPreferences prefs) {
  final values = {
    for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!
  };
  SharedPreferencesStorePlatform.instance = _FailFinalReportStore(values);
}

class _FailRunningReportStore extends InMemorySharedPreferencesStore {
  _FailRunningReportStore(super.data) : super.withData();

  bool _failedRunningWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (!_failedRunningWrite &&
        key == 'flutter.sync_report_v1' &&
        value is String &&
        jsonDecode(value)['phase'] == 'running') {
      _failedRunningWrite = true;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

class _FailFinalReportStore extends InMemorySharedPreferencesStore {
  _FailFinalReportStore(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.sync_report_v1' &&
        value is String &&
        jsonDecode(value)['phase'] != 'running') {
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

class _FailSelectedWrites extends InMemorySharedPreferencesStore {
  _FailSelectedWrites(super.data, this.failingKeys) : super.withData();

  final Set<String> failingKeys;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failingKeys.contains(key)) return false;
    return super.setValue(valueType, key, value);
  }
}

class _ColdClient extends ChaoxingLocalClient {
  final events = <String>[];
  bool ready = false;
  @override
  bool get needsSessionInitialization => !ready;
  @override
  Future<ChaoxingLoginResult> login(
      {required String account, required String password}) async {
    events.add('login');
    ready = true;
    return const ChaoxingLoginResult(success: true);
  }

  @override
  Future<List<Assignment>> fetchAssignments() async {
    events.add('fetch');
    if (!ready) throw StateError('result=false');
    return [];
  }
}
