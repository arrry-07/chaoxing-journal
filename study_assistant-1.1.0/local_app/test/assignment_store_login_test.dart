import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('login keeps a specific platform refusal and leaves credentials unsaved',
      () async {
    final session = _MemorySessionStore();
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _RefusedLoginClient(),
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.loginChaoxing(
        account: 'synthetic', password: 'synthetic', agreementAccepted: true);
    expect(store.isAuthenticated, isFalse);
    expect(store.error, '登录失败，请完成安全验证');
    expect(session.account, isNull);
    expect(session.password, isNull);
  });

  test('authentication returns while homework remains blocked', () async {
    final client = _BlockedClient();
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: client);
    addTearDown(store.dispose);
    await store
        .loginChaoxing(
            account: 'student', password: 'p', agreementAccepted: true)
        .timeout(const Duration(milliseconds: 500));
    expect(store.isAuthenticated, isTrue, reason: store.error);
    client.gate.complete([]);
    await store.syncAssignments();
  });
  test('foreground sync publishes an in-memory preview until persistence ends',
      () async {
    final client = _PreviewSyncClient();
    final session = _MemorySessionStore()
      ..account = 'student'
      ..password = 'p';
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final syncing = store.syncAssignments();
    await client.rowsPublished.future;
    expect(store.assignments, isEmpty);
    expect(store.homeDisplayAssignments, hasLength(2));
    expect(store.isHomeAssignmentPreviewOnly('cx:work:1:2:1'), isTrue);
    expect(store.isHomeDeadlinePending('cx:work:1:2:1'), isFalse);

    client.firstDetailPublished.complete();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(store.isHomeDeadlinePending('cx:work:1:2:2'), isTrue);
    expect(
      store.homeDisplayAssignments
          .singleWhere((item) => item.id == 'cx:work:1:2:1')
          .deadlineAt,
      isNotNull,
    );

    client.finishFetch.complete();
    await syncing;
    expect(store.homeSyncProgress, isNull);
    expect(store.isHomeAssignmentPreviewOnly('cx:work:1:2:1'), isFalse);
    expect(store.isHomeDeadlinePending('cx:work:1:2:2'), isFalse);
    expect(store.assignments, hasLength(2));
  });
  test('failed journal save removes the preview and keeps old persisted data',
      () async {
    final client = _PreviewSyncClient();
    final session = _MemorySessionStore()
      ..account = 'student'
      ..password = 'p';
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      repository: _FailingMergeRepository(),
      chaoxingClient: client,
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final syncing = store.syncAssignments();
    await client.rowsPublished.future;
    expect(store.homeDisplayAssignments, hasLength(2));
    client.firstDetailPublished.complete();
    client.finishFetch.complete();
    await syncing;

    expect(store.homeSyncProgress, isNull);
    expect(store.homeDisplayAssignments, isEmpty);
    expect(store.assignments, isEmpty);
    expect(store.error, contains('disk full'));
    expect(store.syncReport.phase, SyncPhase.failed);
  });
  test('foreground preview respects the account course-follow filter',
      () async {
    SharedPreferences.setMockInitialValues({
      'unfollowed_courses': ['1:2'],
    });
    final client = _PreviewSyncClient();
    final session = _MemorySessionStore()
      ..account = 'student'
      ..password = 'p';
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final syncing = store.syncAssignments();
    await client.rowsPublished.future;
    expect(store.homeDisplayAssignments, isEmpty);
    client.firstDetailPublished.complete();
    client.finishFetch.complete();
    await syncing;
  });
  test('foreground preview never revives a locally hidden assignment',
      () async {
    final session = _MemorySessionStore()
      ..account = 'student'
      ..password = 'p';
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.repository.mergeAndSave([
      Assignment(
        id: 'cx:work:1:2:1',
        courseName: '高等数学',
        title: '已隐藏作业',
        deadlineAt: DateTime.now(),
        requirementsText: '',
        status: 'completed',
        completedAt: DateTime.now(),
        lastSyncedAt: DateTime.now(),
      ),
    ], completeSync: false);
    await store.refreshAssignments();
    expect(await store.hideAssignment('cx:work:1:2:1'), isTrue);
    expect(store.homeDisplayAssignments, isEmpty);

    final client = _PreviewSyncClient(firstStatus: 'returned');
    final previewStore = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: client,
      manageBackgroundSchedule: false,
    );
    addTearDown(previewStore.dispose);
    await previewStore.restoreSession();
    final syncing = previewStore.syncAssignments();
    await client.rowsPublished.future;
    expect(
      previewStore.homeDisplayAssignments
          .any((item) => item.id == 'cx:work:1:2:1'),
      isFalse,
    );
    client.firstDetailPublished.complete();
    client.finishFetch.complete();
    await syncing;
    expect(
      previewStore.homeDisplayAssignments
          .any((item) => item.id == 'cx:work:1:2:1'),
      isFalse,
    );
  });
  test(
    'login marks session authenticated even when first assignment sync fails',
    () async {
      final store = AssignmentStore(
        sessionStore: _MemorySessionStore(),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: _LoginOnlyChaoxingClient(),
      );
      addTearDown(store.dispose);

      await store.loginChaoxing(
        account: 'student',
        password: 'password',
        agreementAccepted: true,
      );

      expect(store.isAuthenticated, isTrue, reason: store.error);
      expect(store.account, 'student');
      expect(store.profileDisplayName, '李雷');
      expect(store.profileAvatarUrl, 'https://photo.chaoxing.com/p/998877_160');
      expect(await store.sessionStore.readChaoxingDisplayName(), '李雷');
      expect(
        await store.sessionStore.readChaoxingAvatarUrl(),
        'https://photo.chaoxing.com/p/998877_160',
      );
      await store.syncAssignments();
      expect(store.error, contains('同步'));
    },
  );

  for (final credentials in [
    {
      'shuniZuilingSchoolUserLocalId': 'old',
      'shuniZuilingPassword': 'old',
      'shuniZuilingSchoolCode': 's'
    },
    {
      'chaoxingAccount': 'student',
      'chaoxingPassword': 'p',
      'shuniZuilingSchoolUserLocalId': 'old'
    },
    {'chaoxingAccount': 'student', 'chaoxingPassword': 'p'},
  ]) {
    test('restores account after upgrade from ${credentials.keys.join(",")}',
        () async {
      FlutterSecureStorage.setMockInitialValues({...credentials});
      final store = AssignmentStore(
          sessionStore: SecureSessionStore(),
          notificationService: _NoopNotificationService(),
          widgetSnapshotService: _NoopWidgetSnapshotService());
      addTearDown(store.dispose);
      await store.restoreSession();
      expect(store.isAuthenticated, credentials.containsKey('chaoxingAccount'));
      expect(store.account, credentials['chaoxingAccount']);
      expect(await const FlutterSecureStorage().readAll(), {
        if (store.isAuthenticated) 'chaoxingAccount': 'student',
        if (store.isAuthenticated) 'chaoxingPassword': 'p',
      });
    });
  }

  test('refreshing Chaoxing session saves recovered profile data', () async {
    final sessionStore = _MemorySessionStore()
      ..account = 'student'
      ..password = 'password';
    final store = AssignmentStore(
      sessionStore: sessionStore,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _RefreshingChaoxingClient(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();

    expect(store.profileDisplayName, '郜小展');
    expect(await sessionStore.readChaoxingDisplayName(), '郜小展');
    expect(
      await sessionStore.readChaoxingAvatarUrl(),
      'https://photo.chaoxing.com/p/402733611_160',
    );
  });
}

class _LoginOnlyChaoxingClient extends ChaoxingLocalClient {
  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    return const ChaoxingLoginResult(
      success: true,
      displayName: '李雷',
      avatarUrl: 'https://photo.chaoxing.com/p/998877_160',
    );
  }

  @override
  Future<List<Assignment>> fetchAssignments() async {
    throw StateError('同步失败');
  }
}

class _RefreshingChaoxingClient extends ChaoxingLocalClient {
  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    return const ChaoxingLoginResult(
      success: true,
      displayName: '郜小展',
      avatarUrl: 'https://photo.chaoxing.com/p/402733611_160',
    );
  }

  @override
  Future<List<Assignment>> fetchAssignments() async {
    return [
      Assignment(
        id: 'cx:1',
        courseName: '高等数学',
        title: '习题作业',
        deadlineAt: DateTime.now().add(const Duration(days: 1)),
        requirementsText: '完成后提交',
        status: 'pending',
        lastSyncedAt: DateTime.now(),
      ),
    ];
  }
}

class _RefusedLoginClient extends ChaoxingLocalClient {
  @override
  Future<ChaoxingLoginResult> login(
          {required String account, required String password}) async =>
      const ChaoxingLoginResult(success: false, message: '登录失败，请完成安全验证');
}

class _MemorySessionStore extends SecureSessionStore {
  String? account;
  String? password;
  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    this.account = account;
    this.password = password;
    chaoxingDisplayName = displayName;
    chaoxingAvatarUrl = avatarUrl;
  }

  @override
  Future<String?> readChaoxingAccount() async => account;

  String? chaoxingDisplayName;
  String? chaoxingAvatarUrl;

  @override
  Future<String?> readChaoxingDisplayName() async => chaoxingDisplayName;

  @override
  Future<String?> readChaoxingAvatarUrl() async => chaoxingAvatarUrl;

  @override
  Future<String?> readChaoxingPassword() async => password;
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {}

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

class _BlockedClient extends _LoginOnlyChaoxingClient {
  final gate = Completer<List<Assignment>>();
  @override
  bool get needsSessionInitialization => false;
  @override
  Future<List<Assignment>> fetchAssignments() => gate.future;
}

class _PreviewSyncClient extends ChaoxingLocalClient {
  _PreviewSyncClient({this.firstStatus = 'pending'});

  final rowsPublished = Completer<void>();
  final firstDetailPublished = Completer<void>();
  final finishFetch = Completer<void>();
  final String firstStatus;

  @override
  bool get needsSessionInitialization => false;

  Assignment _row(
    String id, {
    DateTime? deadline,
    String status = 'pending',
  }) =>
      Assignment(
        id: 'cx:work:1:2:$id',
        courseName: '高等数学',
        title: '作业 $id',
        deadlineAt: deadline,
        deadlineTrusted: deadline != null,
        requirementsText: '',
        status: status,
        submitUrl:
            'https://mooc1.chaoxing.com/work/task?workId=$id&courseId=1&classId=2',
        lastSyncedAt: DateTime.now(),
      );

  @override
  Future<List<Assignment>> fetchAssignments() async {
    final first = _row('1', status: firstStatus);
    final second = _row('2');
    onProgress?.call(AssignmentSyncProgress(
      stage: AssignmentSyncStage.courses,
      assignments: const [],
      pendingDetailIds: const {},
      resolvedCount: 0,
      attemptedCount: 0,
    ));
    onProgress?.call(AssignmentSyncProgress(
      stage: AssignmentSyncStage.workLists,
      assignments: [first, second],
      pendingDetailIds: const {},
      resolvedCount: 0,
      attemptedCount: 0,
    ));
    rowsPublished.complete();
    await firstDetailPublished.future;
    final trustedFirst = first.copyWith(
      deadlineAt: DateTime.now().add(const Duration(days: 2)),
      deadlineTrusted: true,
    );
    onProgress?.call(AssignmentSyncProgress(
      stage: AssignmentSyncStage.details,
      assignments: [trustedFirst, second],
      pendingDetailIds: {second.id},
      resolvedCount: 1,
      attemptedCount: 1,
    ));
    await finishFetch.future;
    final trustedSecond = second.copyWith(
      deadlineAt: DateTime.now().add(const Duration(days: 3)),
      deadlineTrusted: true,
    );
    onProgress?.call(AssignmentSyncProgress(
      stage: AssignmentSyncStage.details,
      assignments: [trustedFirst, trustedSecond],
      pendingDetailIds: const {},
      resolvedCount: 2,
      attemptedCount: 2,
    ));
    succeededCourses = 1;
    return [trustedFirst, trustedSecond];
  }
}

class _FailingMergeRepository extends LocalAssignmentRepository {
  @override
  Future<List<Assignment>> mergeAndSave(
    List<Assignment> incoming, {
    bool completeSync = true,
    Future<bool> Function()? canCommit,
  }) {
    throw StateError('disk full');
  }
}
