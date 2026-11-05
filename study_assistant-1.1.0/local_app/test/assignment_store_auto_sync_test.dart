import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
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
  List<Assignment> lastAssignments = [];

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    lastAssignments = List.of(assignments);
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
