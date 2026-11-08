import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Session extends SecureSessionStore {
  String? account = 'A';
  String? password = 'dummy';
  String? displayName;
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
  Future<void> clear() async {
    account = null;
    password = null;
    displayName = null;
    avatarUrl = null;
  }

  @override
  Future<void> clearWebSession() async {}
}

class _LoginClient extends ChaoxingLocalClient {
  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true);

  @override
  Future<List<Assignment>> fetchAssignments() async => const [];
}

class _Widget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _RecordingNotifications extends LocalNotificationService {
  int privateCleanupCalls = 0;
  bool failCleanup = false;

  @override
  Future<void> cancelPrivateSchedules() async {
    privateCleanupCalls++;
    if (failCleanup) throw StateError('synthetic cleanup failure');
  }

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> assignments,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const permissions = MethodChannel('study_assistant/permissions');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (call) async {
      if (call.method == 'getAndroidSdkInt') return 35;
      return true;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null);
  });

  test('account switch cancels delivered legacy private notifications',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_details_v1': true,
    });
    final active = <Map<String, Object?>>[
      {
        'id': 730001,
        'title': '作业即将截止',
        'body': '旧账号课程与作业标题',
        'payload': 'a:studyassistant:///assignments/old-private',
      },
    ];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'pendingNotificationRequests':
          return <Map<String, Object?>>[];
        case 'getActiveNotifications':
          return active;
        case 'cancel':
          final id = (call.arguments as Map)['id'] as int;
          cancelled.add(id);
          active.removeWhere((item) => item['id'] == id);
          return null;
        case 'getNotificationChannels':
          return <Map<String, Object?>>[];
        case 'createNotificationChannel':
          return null;
        case 'zonedSchedule':
          return null;
        default:
          return true;
      }
    });

    final store = AssignmentStore(
      sessionStore: _Session(),
      notificationService: LocalNotificationService(),
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.loginChaoxing(
      account: 'B',
      password: 'dummy',
      agreementAccepted: true,
    );

    expect(store.account, 'B');
    expect(cancelled, contains(730001));
    expect(active, isEmpty);
  });

  test('active notification read failure keeps the old account selected',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_details_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'pendingNotificationRequests':
          return <Map<String, Object?>>[];
        case 'getActiveNotifications':
          throw PlatformException(code: 'active-read-failed');
        default:
          return true;
      }
    });
    final session = _Session();
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: LocalNotificationService(),
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.loginChaoxing(
      account: 'B',
      password: 'dummy',
      agreementAccepted: true,
    );

    expect(store.account, 'A');
    expect(session.account, 'A');
    expect(store.notificationPrivacyPending, isTrue);
    expect(store.error, contains('系统通知状态读取失败'));
  });

  test('first login also clears private notifications left from an old session',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_details_v1': true,
    });
    final active = <Map<String, Object?>>[
      {
        'id': 730002,
        'title': '个人考试提醒',
        'body': '升级前遗留的私人通知',
        'payload': 'p:old-manual',
      },
    ];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'pendingNotificationRequests':
          return <Map<String, Object?>>[];
        case 'getActiveNotifications':
          return active;
        case 'cancel':
          final id = (call.arguments as Map)['id'] as int;
          cancelled.add(id);
          active.removeWhere((item) => item['id'] == id);
          return null;
        default:
          return true;
      }
    });
    final session = _Session()..account = null;
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: LocalNotificationService(),
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.loginChaoxing(
      account: 'B',
      password: 'dummy',
      agreementAccepted: true,
    );

    expect(store.account, 'B');
    expect(session.account, 'B');
    expect(cancelled, contains(730002));
    expect(active, isEmpty);
  });

  test('logout performs full privacy cleanup when details are enabled',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_details_v1': true,
    });
    final active = <Map<String, Object?>>[
      {
        'id': 730003,
        'title': '作业即将截止',
        'body': '退出前的私人通知',
        'payload': 'a:studyassistant:///assignments/logout-private',
      },
      {
        'id': 1900000008,
        'title': '课业手记测试通知',
        'body': '如果看到了这条通知，当前显示链路可用',
        'payload': 't:notification-test',
      },
    ];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'pendingNotificationRequests':
          return <Map<String, Object?>>[];
        case 'getActiveNotifications':
          return active;
        case 'cancel':
          final id = (call.arguments as Map)['id'] as int;
          cancelled.add(id);
          active.removeWhere((item) => item['id'] == id);
          return null;
        default:
          return true;
      }
    });
    final service = LocalNotificationService()..showDetails = true;
    final store = AssignmentStore(
      sessionStore: _Session(),
      notificationService: service,
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.logout();

    expect(store.isAuthenticated, isFalse);
    expect(service.showDetails, isTrue);
    expect(cancelled, containsAll([730003, 1900000008]));
    expect(active, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notification_details_v1'), isTrue);
  });

  test('logout performs full privacy cleanup when details are hidden',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_details_v1': false,
    });
    final notifications = _RecordingNotifications();
    final store = AssignmentStore(
      sessionStore: _Session(),
      notificationService: notifications,
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    notifications.privateCleanupCalls = 0;
    await store.logout();

    expect(store.isAuthenticated, isFalse);
    expect(notifications.showDetails, isFalse);
    expect(notifications.privateCleanupCalls, 1);
  });

  test('same-account reauthentication preserves existing reminders', () async {
    SharedPreferences.setMockInitialValues({
      'notification_details_v1': true,
    });
    final notifications = _RecordingNotifications()..showDetails = true;
    final session = _Session();
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: notifications,
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.loginChaoxing(
      account: 'A',
      password: 'dummy',
      agreementAccepted: true,
    );

    expect(store.account, 'A');
    expect(session.account, 'A');
    expect(notifications.privateCleanupCalls, 0);
  });

  test('cleanup failure blocks account replacement and remains retryable',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_details_v1': true,
    });
    final notifications = _RecordingNotifications()
      ..showDetails = true
      ..failCleanup = true;
    final session = _Session();
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: notifications,
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.loginChaoxing(
      account: 'B',
      password: 'dummy',
      agreementAccepted: true,
    );

    expect(store.account, 'A');
    expect(session.account, 'A');
    expect(store.error, contains('synthetic cleanup failure'));
    expect(store.notificationPrivacyPending, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notification_privacy_cleanup_pending_v1'), isTrue);
  });

  test('logout completes after cleanup failure and retries after restart',
      () async {
    SharedPreferences.setMockInitialValues({
      'notification_details_v1': true,
    });
    final session = _Session();
    final failing = _RecordingNotifications()
      ..showDetails = true
      ..failCleanup = true;
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: failing,
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.logout();

    expect(store.isAuthenticated, isFalse);
    expect(session.account, isNull);
    expect(store.notificationPrivacyPending, isTrue);
    expect(store.error, contains('账号已退出'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notification_privacy_cleanup_pending_v1'), isTrue);

    final retry = _RecordingNotifications()..showDetails = true;
    final restarted = AssignmentStore(
      sessionStore: session,
      notificationService: retry,
      widgetSnapshotService: _Widget(),
      chaoxingClient: _LoginClient(),
    );
    addTearDown(restarted.dispose);
    await restarted.restoreSession();

    expect(restarted.notificationPrivacyPending, isFalse);
    expect(retry.privateCleanupCalls, 1);
    expect(prefs.getBool('notification_privacy_cleanup_pending_v1'), isNull);
  });
}
