// Formal-source fixtures intentionally isolate the existing formal request flow.
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/home_sync_presentation.dart';
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
        chaoxingClient: ChaoxingLocalClient(
            enableExams: false, enableClassroomTasks: false, dio: dio));
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

  test('course notice read failure is partial without losing homework',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        chaoxingClient: _NoticeSourceClient(SyncSourcePhase.partial));
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();

    expect(store.assignments.single.id, 'cx:work:1:2:3');
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(store.syncReport.summary, '部分课程通知未更新');
    expect(store.syncReport.issues.single.stage, 'courseNotice');
    final presentation = HomeSyncPresentation.from(
      store.syncReport,
      loading: false,
      hasCache: true,
      hasPreviousData: true,
      now: DateTime.now(),
      successAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(presentation.summary, '部分课程通知未更新');
    expect(presentation.showCached, isFalse);
  });

  test('partial course notice keeps old cache and local read state', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    await repository.activateAccount('student');
    final oldNotice = CourseNotice(
      id: 'cx:notice:${'a' * 64}',
      courseName: '高等数学',
      title: '旧通知',
      platformUnread: true,
      localRead: true,
      lastSyncedAt: DateTime.utc(2030, 5, 19),
    );
    final newNotice = CourseNotice(
      id: 'cx:notice:${'b' * 64}',
      courseName: '高等数学',
      title: '新通知',
      platformUnread: true,
      lastSyncedAt: DateTime.utc(2030, 5, 20),
    );
    await repository.saveCourseNotices(
        CourseNoticeCollection(items: [oldNotice]), 'student');
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        repository: repository,
        chaoxingClient: _NoticeSourceClient(
          SyncSourcePhase.partial,
          notices: [newNotice],
        ));
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();

    expect(store.assignments.single.id, 'cx:work:1:2:3');
    expect(store.syncReport.summary, '部分课程通知未更新');
    expect(store.courseNotices.items.map((notice) => notice.id),
        containsAll([oldNotice.id, newNotice.id]));
    expect(
        store.courseNotices.items
            .singleWhere((notice) => notice.id == oldNotice.id)
            .localRead,
        isTrue);
    expect(
        (await repository.loadCourseNotices()).items.map((notice) => notice.id),
        containsAll([oldNotice.id, newNotice.id]));
  });

  test('course notice cache save failure is partial after homework save',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _FailingNoticeSaveRepository();
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
        repository: repository,
        chaoxingClient: _NoticeSourceClient(SyncSourcePhase.success));
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();

    expect(store.assignments.single.id, 'cx:work:1:2:3');
    expect(repository.noticeSaveAttempts, 1);
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(
        store.syncReport.issues.any((issue) =>
            issue.stage == 'persistence' && issue.message.contains('课程通知缓存')),
        isTrue);
    expect(store.syncReport.summary, '作业数据已保存，但同步状态记录需要处理');
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
    // Wait until the coalesced fetch is actually in flight before logging out;
    // a sync cancelled before starting now aborts cleanly without fetching.
    await client.started.future;
    final logout = store.logout();
    client.response.complete([_assignment(id: 'cx:one', title: '第一课')]);
    await Future.wait([first, second, logout]);
    expect(client.fetchCount, 1);
    expect(store.error, isNull);
    expect(store.isAuthenticated, isFalse);
    expect(store.assignments, isEmpty);
    expect(await store.repository.loadJournal(), isEmpty);
    expect(store.lastSyncAt, isNull);
  });

  test(
      'syncAssignments cancelled immediately by logout before fetch starts aborts with zero fetches',
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

    final sync = store.syncAssignments();
    final logout = store.logout();
    await Future.wait([sync, logout]);
    expect(client.fetchCount, 0);
    expect(store.isAuthenticated, isFalse);
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

  test('sync context includes hidden assignments for deadline reconciliation',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalAssignmentRepository();
    final hidden = _assignment(
      id: 'cx:activity:7:11:88',
      title: '隐藏课堂题',
    ).copyWith(status: 'submitted');
    await repository.mergeAndSave([hidden]);
    await repository.updateCompletion(hidden.id, true);
    final client = _InspectingClient();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: 'student'),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      repository: repository,
      chaoxingClient: client,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await store.syncAssignments();

    expect(client.previousIds, contains(hidden.id));
    expect(client.trackedIds, contains(hidden.id));
    expect(store.hiddenAssignments.single.deadlineAt, hidden.deadlineAt);
  });

  test('hidden exam group stays hidden when a new notice is discovered',
      () async {
    SharedPreferences.setMockInitialValues({});
    final formal = _exam(
      id: 'cx:exam:1:2:3',
      examId: '3',
      title: '高等数学期末考试',
    );
    final noticeA = _exam(
      id: 'cx:examNotice:inbox:701',
      examId: '701',
      related: '3',
      notice: true,
      title: '考试通知 A',
    );
    final noticeB = _exam(
      id: 'cx:examNotice:inbox:702',
      examId: '702',
      related: '3',
      notice: true,
      title: '考试通知 B',
    );
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: 'student'),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _FakeChaoxingClient(const []),
    );
    addTearDown(store.dispose);
    await store.repository.mergeAndSave([formal, noticeA, noticeB]);
    await store.restoreSession();

    expect(store.courseworkGroups, hasLength(1));
    expect(store.courseworkGroups.single.sourceCount, 3);
    expect(store.statsAssignments.single.id, formal.id);
    await store.setAssignmentsHidden(
      [formal.id, noticeA.id, noticeB.id],
      true,
    );
    expect(store.hiddenCourseworkGroups.single.sourceCount, 3);
    expect(store.courseAssignments, isEmpty);
    expect(store.statsAssignments, isEmpty);

    final newNotice = _exam(
      id: 'cx:examNotice:inbox:703',
      examId: '703',
      related: '3',
      notice: true,
      title: '考试通知 C',
    );
    await store.repository.mergeAndSave([newNotice]);
    await store.refreshAssignments();

    expect(store.assignments.map((item) => item.id), contains(newNotice.id));
    expect(store.hiddenCourseworkGroups.single.sourceCount, 4);
    expect(store.courseAssignments, isEmpty);
    expect(store.statsAssignments, isEmpty);

    await store.setCourseworkGroupHidden(
      store.hiddenCourseworkGroups.single,
      false,
    );
    expect(store.hiddenCourseworkGroups, isEmpty);
    expect(store.courseworkGroups.single.sourceCount, 4);
    expect(store.statsAssignments.single.id, formal.id);
  });

  test(
      'deadline alert tracks official advance/unknown->72h per account, ignores manual/extension/backup/fail, and preserves unacknowledged on write error',
      () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime.utc(2026, 11, 20, 4);
    final client = _MutableSyncClient([
      Assignment(
        id: 'cx:work:1:2:10',
        courseName: '操作系统',
        title: '实验报告一',
        deadlineAt: now.add(const Duration(days: 5)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
      Assignment(
        id: 'cx:work:1:2:11',
        courseName: '计算机网络',
        title: '抓包实验',
        deadlineAt: null,
        deadlineTrusted: false,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ]);
    final repo = _FailingAckRepository();
    AssignmentStore makeBoundStore(String account) => AssignmentStore(
          sessionStore: _MemorySessionStore(account: account, password: 'pw'),
          notificationService: _NoopNotificationService(),
          widgetSnapshotService: _NoopWidgetSnapshotService(),
          repository: repo,
          chaoxingClient: client,
          clock: () => now,
        );

    var store = makeBoundStore('student-a');
    await store.restoreSession();
    // Baseline sync creates no alerts.
    await store.syncAssignments();
    expect(
        store.activeDeadlineAlertFor(store.findAssignment('cx:work:1:2:10')!),
        isNull);

    // Manual deadline change does not trigger teacher advance alert.
    expect(
      await store.setManualDeadline(
        store.findAssignment('cx:work:1:2:11')!,
        now.add(const Duration(hours: 12)),
      ),
      isTrue,
    );
    expect(
        store.activeDeadlineAlertFor(store.findAssignment('cx:work:1:2:11')!),
        isNull);

    // Failed sync & backup restore do not trigger alerts.
    client.shouldFail = true;
    await store.syncAssignments();
    client.shouldFail = false;
    final backup = BackupSnapshot.create(
      owner: BackupSnapshot.ownerFor('student-a'),
      createdAt: now,
      records: [
        Assignment(
          id: 'cx:work:1:2:99',
          courseName: '备份课',
          title: '旧备份作业',
          deadlineAt: now.add(const Duration(hours: 10)),
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
        ),
      ],
      hidden: const {},
      courses: const [],
      unfollowed: const {},
      reminderOffsets: const [120],
      autoSyncIntervalMinutes: 60,
      personal: PersonalWorkspace(),
      notebook: StudyNotebook(),
    );
    expect(await store.restoreLocalBackup(backup), isTrue);
    expect(store.changes, isEmpty);

    // Next sync: 10 is moved earlier (+5d -> +2d); 11 gets unknown->within 72h.
    now = now.add(const Duration(hours: 1));
    client.nextAssignments = [
      Assignment(
        id: 'cx:work:1:2:10',
        courseName: '操作系统',
        title: '实验报告一',
        deadlineAt: now.add(const Duration(days: 2)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
      Assignment(
        id: 'cx:work:1:2:11',
        courseName: '计算机网络',
        title: '抓包实验',
        deadlineAt: now.add(const Duration(hours: 36)),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ];
    await store.syncAssignments();
    final hw10 = store.findAssignment('cx:work:1:2:10')!;
    final hw11 = store.findAssignment('cx:work:1:2:11')!;
    final alert10 = store.activeDeadlineAlertFor(hw10);
    final alert11 = store.activeDeadlineAlertFor(hw11);
    expect(alert10, isNotNull);
    expect(alert11, isNotNull);

    // Persistence failure leaves badge unacknowledged.
    repo.failAckWrites = true;
    expect(await store.acknowledgeDeadlineAlert(alert10!.effectiveChangeId),
        isFalse);
    expect(store.activeDeadlineAlertFor(hw10)?.effectiveChangeId,
        alert10.effectiveChangeId);
    repo.failAckWrites = false;

    // Succeeding persist hides alert across cold restart of same account.
    expect(await store.acknowledgeDeadlineAlert(alert10.effectiveChangeId),
        isTrue);
    expect(store.activeDeadlineAlertFor(hw10), isNull);
    store.dispose();

    store = makeBoundStore('student-a');
    await store.restoreSession();
    expect(
        store.activeDeadlineAlertFor(store.findAssignment('cx:work:1:2:10')!),
        isNull);
    expect(
        store.activeDeadlineAlertFor(store.findAssignment('cx:work:1:2:11')!),
        isNotNull);

    // Later official advance event on 10 requires fresh confirmation; extension clears it.
    now = now.add(const Duration(hours: 2));
    client.nextAssignments = [
      Assignment(
        id: 'cx:work:1:2:10',
        courseName: '操作系统',
        title: '实验报告一',
        deadlineAt: now.add(const Duration(hours: 18)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ];
    await store.syncAssignments();
    final alert10Second =
        store.activeDeadlineAlertFor(store.findAssignment('cx:work:1:2:10')!);
    expect(alert10Second, isNotNull);
    expect(alert10Second!.effectiveChangeId, isNot(alert10.effectiveChangeId));

    // Teacher extending 10 cancels urgent advance alert.
    now = now.add(const Duration(hours: 1));
    client.nextAssignments = [
      Assignment(
        id: 'cx:work:1:2:10',
        courseName: '操作系统',
        title: '实验报告一',
        deadlineAt: now.add(const Duration(days: 6)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
      ),
    ];
    await store.syncAssignments();
    expect(
        store.activeDeadlineAlertFor(store.findAssignment('cx:work:1:2:10')!),
        isNull);

    // Account switch isolates change acks & logs.
    client.nextAssignments = const [];
    await store.loginChaoxing(
        account: 'student-b', password: 'pw', agreementAccepted: true);
    expect(store.account, 'student-b');
    expect(store.changes, isEmpty);
    await store.loginChaoxing(
        account: 'student-a', password: 'pw', agreementAccepted: true);
    expect(store.account, 'student-a');
    expect(
        store.activeDeadlineAlertFor(store.findAssignment('cx:work:1:2:10')!),
        isNull);
    expect(
        store.activeDeadlineAlertFor(store.findAssignment('cx:work:1:2:11')!),
        isNotNull);
    store.dispose();
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

Assignment _exam({
  required String id,
  required String examId,
  String? related,
  bool notice = false,
  required String title,
}) =>
    Assignment(
      id: id,
      source: AssignmentSource.exam,
      exam: ExamInfo(
        examId: examId,
        relatedExamId: related,
        courseId: '1',
        clazzId: '2',
        startAt: DateTime.utc(2026, 11, 20, 1),
        endAt: DateTime.utc(2026, 11, 20, 2),
        startTrusted: !notice,
        endTrusted: !notice,
        lifecycle: notice ? 'unknown' : 'scheduled',
        noticeOnly: notice,
      ),
      courseName: '高等数学',
      title: title,
      deadlineAt: null,
      requirementsText: '',
      status: 'unknown',
      lastSyncedAt: DateTime.utc(2026, 11, 16, 8),
    );

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

class _NoticeSourceClient extends ChaoxingLocalClient {
  _NoticeSourceClient(this.courseNoticePhase,
      {this.notices = const <CourseNotice>[]});

  final SyncSourcePhase courseNoticePhase;
  final List<CourseNotice> notices;

  @override
  List<CourseNotice> get lastFetchedNotices => notices;

  @override
  Future<List<Assignment>> fetchAssignmentsWithOptions({
    bool collectCourseNotices = false,
    bool enableTaskEngineProbe = false,
  }) async {
    sourceResults = [
      const SyncSourceResult(
        source: 'courseWork',
        phase: SyncSourcePhase.success,
        succeededCourses: 1,
      ),
      const SyncSourceResult(
        source: 'exam',
        phase: SyncSourcePhase.success,
        succeededCourses: 1,
      ),
      SyncSourceResult(
        source: 'courseNotice',
        phase: courseNoticePhase,
        succeededCourses: courseNoticePhase == SyncSourcePhase.success ? 1 : 0,
        failedCourses: courseNoticePhase == SyncSourcePhase.success ? 0 : 1,
      ),
    ];
    issues = const [];
    lastSyncWarning = null;
    return [
      _assignment(
        id: 'cx:work:1:2:3',
        title: '新作业',
      )
    ];
  }
}

class _FailingNoticeSaveRepository extends LocalAssignmentRepository {
  int noticeSaveAttempts = 0;

  @override
  Future<void> saveCourseNotices(
      CourseNoticeCollection value, String account) async {
    noticeSaveAttempts++;
    throw StateError('通知缓存写入失败');
  }
}

class _InspectingClient extends ChaoxingLocalClient {
  Set<String> previousIds = {};
  Set<String> trackedIds = {};

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true);

  @override
  Future<List<Assignment>> fetchAssignments() async {
    previousIds = previousAssignments.keys.toSet();
    trackedIds = Set.of(trackedActivityIds);
    return [];
  }
}

class _MemorySessionStore extends SecureSessionStore {
  _MemorySessionStore({
    this.account,
    this.password,
  });

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
  }

  @override
  Future<void> clear() async {
    account = null;
    password = null;
  }

  @override
  Future<void> clearWebSession() async {}

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

class _MutableSyncClient extends ChaoxingLocalClient {
  _MutableSyncClient(this.nextAssignments);

  List<Assignment> nextAssignments;
  bool shouldFail = false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true);

  @override
  Future<List<Assignment>> fetchAssignments() async {
    if (shouldFail) throw StateError('模拟读取失败');
    return nextAssignments;
  }
}

class _FailingAckRepository extends LocalAssignmentRepository {
  bool failAckWrites = false;

  @override
  Future<void> writeAcknowledgedDeadlineChangeIdsInPrefs(
    SharedPreferences prefs,
    Iterable<String> orderedIds,
  ) async {
    if (failAckWrites) throw StateError('模拟确认状态写入失败');
    await super.writeAcknowledgedDeadlineChangeIdsInPrefs(prefs, orderedIds);
  }
}
