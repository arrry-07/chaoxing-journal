import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    expect(store.isAuthenticated, isTrue);
    client.gate.complete([]);
    await store.syncAssignments();
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

      expect(store.isAuthenticated, isTrue);
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
