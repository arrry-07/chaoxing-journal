import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment sample(String id, {String status = 'pending'}) => Assignment(
    id: 'cx:work:1:2:$id',
    courseName: '样例课',
    title: id,
    deadlineAt: DateTime(2030, 11, 6, 23, 59),
    requirementsText: '',
    status: status,
    lastSyncedAt: DateTime.now());

class Session extends SecureSessionStore {
  String? account = 'A';
  bool failNextSave = false;
  @override
  Future<String?> readChaoxingAccount() async => account;
  @override
  Future<String?> readChaoxingPassword() async => 'dummy';
  @override
  Future<String?> readChaoxingDisplayName() async => null;
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
  @override
  Future<void> saveChaoxingAccount(
      {required String account,
      required String password,
      String? displayName,
      String? avatarUrl}) async {
    this.account = account;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('凭据写入失败');
    }
  }

  @override
  Future<void> clear() async {
    account = null;
  }
}

class Client extends ChaoxingLocalClient {
  bool failLogin = false, partial = false;
  String? cookieOwner = 'A';
  @override
  bool get needsSessionInitialization => cookieOwner == null;
  @override
  void clearSession() {
    super.clearSession();
    cookieOwner = null;
  }

  @override
  Future<ChaoxingLoginResult> login(
      {required String account, required String password}) async {
    cookieOwner = account;
    return ChaoxingLoginResult(
        success: !failLogin, message: failLogin ? '登录失败' : null);
  }

  @override
  Future<List<Assignment>> fetchAssignments() async {
    lastSyncWarning = partial ? '部分课程未更新' : null;
    issues = partial
        ? [const SyncIssue(SyncIssueKind.verificationRequired, '请完成验证')]
        : [];
    return [
      sample('shared'),
      sample(cookieOwner == 'B' ? 'B-only' : 'A-server')
    ];
  }
}

class Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {}
  final starts = <List<String>>[];
  Completer<void>? gate, started;
  @override
  Future<void> rescheduleAssignments(List<Assignment> items,
      {List<int>? offsetsMinutes}) async {
    starts.add([for (final item in items) item.id, 'offsets:$offsetsMinutes']);
    if (gate case final g?) {
      gate = null;
      started?.complete();
      await g.future;
    }
  }
}

class WidgetService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> items) async {}
}

class BoundaryNotifications extends Notifications {
  final pending = <String>{};
  @override
  Future<void> rescheduleAssignments(List<Assignment> items,
      {List<int>? offsetsMinutes}) async {
    if (items.any((a) => a.title == 'B-only')) throw StateError('B提醒安排失败');
    pending
      ..clear()
      ..addAll(items.map((a) => a.title));
  }
}

class LogoutNotifications extends Notifications {
  bool fail = false;
  @override
  Future<void> rescheduleAssignments(List<Assignment> items,
      {List<int>? offsetsMinutes}) async {
    lastWarning = fail ? '旧提醒可能仍有效' : null;
  }
}

AssignmentStore makeStore(Session session,
        {Client? client, Notifications? notifications}) =>
    AssignmentStore(
        sessionStore: session,
        notificationService: notifications ?? Notifications(),
        widgetSnapshotService: WidgetService(),
        chaoxingClient: client ?? Client());
void main() {
  test('restored synchronization timestamps preserve local display semantics',
      () {
    final local = DateTime(2030, 11, 6, 12, 30);
    final restored = SyncReport.fromJson(SyncReport(
            phase: SyncPhase.success,
            attemptedAt: local,
            lastDataSuccessAt: local)
        .toJson());
    expect(restored.attemptedAt, local);
    expect(restored.lastDataSuccessAt!.isUtc, isFalse);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('switching account isolates completed, hidden and followed state',
      () async {
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave(
        [sample('shared', status: 'submitted'), sample('A-only')]);
    await repo.updateCompletion('cx:work:1:2:A-only', true);
    final session = Session();
    final store = makeStore(session);
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.followCourse('1:2', false);
    await store.loginChaoxing(
        account: 'B', password: 'dummy', agreementAccepted: true);
    await store.syncAssignments();
    expect(store.account, 'B');
    expect(store.visibleAssignments.map((a) => a.title),
        containsAll(['shared', 'B-only']));
    expect(store.assignments.map((a) => a.title), isNot(contains('A-only')));
    expect(store.hiddenAssignments, isEmpty);
    expect(store.follows('1:2'), isTrue);
    await store.loginChaoxing(
        account: 'A', password: 'dummy', agreementAccepted: true);
    await store.syncAssignments();
    expect(store.hiddenAssignments.map((a) => a.title), contains('A-only'));
    expect(store.follows('1:2'), isFalse);
  });
  test('failed switch preserves the previous identity and records', () async {
    final session = Session(), client = Client()..failLogin = true;
    final store = makeStore(session, client: client);
    addTearDown(store.dispose);
    await LocalAssignmentRepository().mergeAndSave([sample('A-only')]);
    await store.restoreSession();
    await store.loginChaoxing(
        account: 'B', password: 'bad', agreementAccepted: true);
    expect(store.account, 'A');
    expect(session.account, 'A');
    expect(store.assignments.map((a) => a.title), ['A-only']);
    expect(store.error, contains('登录失败'));
  });
  test('credential write failure rolls the active scope back', () async {
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([sample('A-only')]);
    final session = Session();
    final store = makeStore(session);
    addTearDown(store.dispose);
    await store.restoreSession();
    session.failNextSave = true;
    await store.loginChaoxing(
        account: 'B', password: 'dummy', agreementAccepted: true);
    expect(store.account, 'A');
    expect(session.account, 'A');
    expect((await repo.loadJournal()).single.title, 'A-only');
    expect(store.error, contains('凭据写入失败'));
    expect(store.chaoxingClient.needsSessionInitialization, isTrue);
    await store.syncAssignments();
    expect((store.chaoxingClient as Client).cookieOwner, 'A');
    expect(store.assignments.map((a) => a.title), isNot(contains('B-only')));
  });
  test('a restored cache without credentials cannot publish private reminders',
      () async {
    await LocalAssignmentRepository().mergeAndSave([sample('private')]);
    final notifications = Notifications();
    final store =
        makeStore(Session()..account = null, notifications: notifications);
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.isAuthenticated, isFalse);
    expect(
        notifications.starts.single.where((s) => s.startsWith('cx:')), isEmpty);
  });
  test('persisted instants include UTC designator', () {
    final json = sample('time').toJson();
    expect(json['deadlineAt'], endsWith('Z'));
    expect(json['lastSyncedAt'], endsWith('Z'));
  });
  test('logout cleanup warning remains visible with actionable system guidance',
      () async {
    final notifications = LogoutNotifications();
    final session = Session();
    final store = makeStore(session, notifications: notifications);
    addTearDown(store.dispose);
    await store.restoreSession();
    notifications.fail = true;
    await store.logout();
    expect(store.isAuthenticated, isFalse);
    expect(session.account, isNull);
    expect(store.error, contains('账号已退出'));
    expect(store.error, contains('系统'));
  });
  test('account switch removes old reminders even if new scheduling fails',
      () async {
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('B', previousAccount: 'B');
    await repo.mergeAndSave([sample('B-only')]);
    await repo.activateAccount('A');
    await repo.mergeAndSave([sample('A-only')]);
    final notifications = BoundaryNotifications();
    final store = makeStore(Session(), notifications: notifications);
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(notifications.pending, contains('A-only'));
    await store.loginChaoxing(
        account: 'B', password: 'dummy', agreementAccepted: true);
    await store.syncAssignments();
    expect(notifications.pending, isNot(contains('A-only')));
  });
  test('legacy ambiguous deadline is retained but cannot schedule as trusted',
      () {
    final json = sample('time').toJson()
      ..['deadlineAt'] = '2030-11-06T23:59:00.000'
      ..['deadlineTrusted'] = true;
    final a = Assignment.fromJson(json);
    expect(a.deadlineAt, isNotNull);
    expect(a.deadlineTrusted, isFalse);
  });
  test('damaged course references do not hide an intact journal', () async {
    await LocalAssignmentRepository().mergeAndSave([sample('intact')]);
    await (await SharedPreferences.getInstance())
        .setString('course_refs', '{broken');
    final store = makeStore(Session());
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.assignments.single.title, 'intact');
    expect(store.error, contains('课程'));
  });
  test('partial synchronization and its action survive restart', () async {
    final session = Session();
    final store = makeStore(session, client: Client()..partial = true);
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.partial);
    final restored = makeStore(session);
    addTearDown(restored.dispose);
    await restored.restoreSession();
    expect(restored.syncReport.phase, SyncPhase.partial);
    expect(restored.syncReport.issues.single.kind,
        SyncIssueKind.verificationRequired);
  });
  test('rule save waits for an older notification reschedule', () async {
    final notifications = Notifications();
    final store = makeStore(Session(), notifications: notifications);
    addTearDown(store.dispose);
    await store.restoreSession();
    final gate = Completer<void>();
    notifications.gate = gate;
    notifications.started = Completer<void>();
    final refreshing = store.refreshAssignments();
    await notifications.started!.future;
    var finished = false;
    final saving = store.saveReminderRule([7]).then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    gate.complete();
    await refreshing;
    await saving;
    expect(notifications.starts.last.last, 'offsets:[7]');
  });
}
