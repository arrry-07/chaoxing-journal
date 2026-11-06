import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  test(
      'failed formal work never requests activities; legacy remains in records',
      () async {
    SharedPreferences.setMockInitialValues({});
    var recovered = false;
    var activityRequests = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.uri.path.contains('activelist')) activityRequests++;
        final dynamic body = switch (o.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '数学'}
              ]
            },
          '/visit/stucoursemiddle' => '<input id="workEnc" value="signed">',
          '/mooc2/work/list' => recovered
              ? '<li onclick="goTask(this);" data="https://mooc1.chaoxing.com/work/task?workId=9"><p class="overHidden2 fl">作业</p><p class="status fl">已提交</p></li>'
              : '没有此页面访问权限',
          '/work/task' => '截止时间：2026-12-01 18:00',
          _ => {
              'data': {
                'activeList': [
                  {
                    'id': '88',
                    'name': '作业',
                    'activeType': '6',
                    'submitStatusName': recovered ? '已提交' : '未提交',
                    'endTime': '2026-12-01 18:00:00'
                  },
                  if (recovered)
                    {'id': '99', 'name': '另一份作业', 'activeType': '6'}
                ]
              }
            }
        };
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
      }));
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: ChaoxingLocalClient(dio: dio));
    addTearDown(store.dispose);
    await store.repository
        .mergeAndSave([_assignment(id: 'cx:activity:7:11:88', title: '旧课堂题')]);
    await store.restoreSession();
    await store.syncAssignments();
    expect(store.visibleAssignments, isEmpty);
    expect(store.error, isNotNull);
    expect(activityRequests, 0);
    recovered = true;
    await store.syncAssignments();
    expect(store.error, isNull);
    expect(activityRequests, 0);
    expect(store.visibleAssignments, isEmpty);
    expect(store.assignments.map((a) => a.id),
        unorderedEquals(['cx:activity:7:11:88', 'cx:work:7:11:9']));
  });
  test('partial course sync retains old work and last successful sync time',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    await repository.mergeAndSave([_assignment(id: 'cx:one', title: '第一课')]);
    final previous = await repository.lastSyncAt();
    final client =
        _FakeChaoxingClient([_assignment(id: 'cx:two', title: '第二课')])
          ..lastSyncWarning = '部分课程读取失败';
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        repository: repository,
        chaoxingClient: client);
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(store.error, '部分课程读取失败');
    expect(store.assignments.map((a) => a.id),
        unorderedEquals(['cx:one', 'cx:two']));
    expect(store.lastSyncAt, previous);
  });

  test('overlapping refreshes share one fetch and logout clears its result',
      () async {
    SharedPreferences.setMockInitialValues({});
    final client = _DelayedClient();
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: client);
    addTearDown(store.dispose);
    await store.restoreSession();
    final first = store.syncAssignments();
    final second = store.syncAssignments();
    final logout = store.logout();
    await client.started.future;
    client.response.complete([_assignment(id: 'cx:one', title: '第一课')]);
    await Future.wait([first, second, logout]);
    expect(client.fetchCount, 1);
    expect(store.error, isNull);
    expect(store.isAuthenticated, isFalse);
    expect(store.assignments, isEmpty);
    expect(await store.repository.loadJournal(), isEmpty);
    expect(store.lastSyncAt, isNull);
  });

  test('syncAssignments stores Chaoxing homework', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(
        account: 'student',
        password: 'password',
      ),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _FakeChaoxingClient([
        _assignment(id: 'cx:activity:1', title: '学习通作业'),
      ]),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();

    expect(store.error, isNull);
    expect(store.assignments.map((item) => item.id), [
      'cx:activity:1',
    ]);
  });

  test('failed sync preserves cached Chaoxing homework', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final oldChaoxing = _assignment(id: 'cx:activity:old', title: '旧学习通作业');
    await repository.mergeAndSave([oldChaoxing]);
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(
        account: 'student',
        password: 'password',
      ),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      repository: repository,
      chaoxingClient: _FailingFetchChaoxingClient(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();

    expect(store.error, contains('学习通临时失败'));
    expect(
        store.assignments.map((item) => item.id),
        unorderedEquals([
          'cx:activity:old',
        ]));
  });
}

Assignment _assignment({required String id, required String title}) {
  return Assignment(
    id: id,
    courseName: '高等数学',
    title: title,
    deadlineAt: DateTime(2026, 5, 28, 22),
    requirementsText: '完成后提交',
    status: 'pending',
    lastSyncedAt: DateTime(2026, 5, 25, 12),
  );
}

class _DelayedClient extends ChaoxingLocalClient {
  final started = Completer<void>();
  final response = Completer<List<Assignment>>();
  int fetchCount = 0;

  @override
  Future<List<Assignment>> fetchAssignments() {
    fetchCount++;
    started.complete();
    return response.future;
  }
}

class _FakeChaoxingClient extends ChaoxingLocalClient {
  _FakeChaoxingClient(this.assignments);

  final List<Assignment> assignments;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    return const ChaoxingLoginResult(success: true);
  }

  @override
  Future<List<Assignment>> fetchAssignments() async => assignments;
}

class _FailingFetchChaoxingClient extends ChaoxingLocalClient {
  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    return const ChaoxingLoginResult(success: true);
  }

  @override
  Future<List<Assignment>> fetchAssignments() async {
    throw StateError('学习通临时失败');
  }
}

class _MemorySessionStore extends SecureSessionStore {
  _MemorySessionStore({
    this.account,
    this.password,
  });

  @override
  Future<void> clear() async {}

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

class _NoopNotificationService extends LocalNotificationService {
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
