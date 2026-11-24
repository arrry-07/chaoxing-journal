import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_exam_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/exam_schedule_presentation.dart';
import 'package:study_assistant_mobile/src/services/home_manual_timeline.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

final _now = DateTime.utc(2026, 11, 24, 2); // Beijing 10:00
const _channel = MethodChannel('study_assistant/external_links');

ManualEntry _manual(
  String id, {
  String title = '手动待办',
  String kind = 'todo',
  String course = '个人',
  DateTime? at,
  bool done = false,
}) =>
    ManualEntry(
      id: id,
      title: title,
      kind: kind,
      course: course,
      at: at,
      done: done,
    );

Assignment _work(
  String id, {
  required DateTime deadline,
  String title = '学习通作业',
  String status = 'pending',
  String courseName = '合成课程',
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: courseName,
      title: title,
      deadlineAt: deadline,
      deadlineTrusted: true,
      requirementsText: '',
      status: status,
      lastSyncedAt: _now,
    );

Assignment _formalExam({
  required String id,
  String title = '合成期末考试',
  DateTime? start,
  DateTime? end,
  String location = '',
  DateTime? syncAt,
}) =>
    ChaoxingExamParser.make(
      id: id,
      title: title,
      courseId: '7',
      clazzId: '11',
      status: 'pending',
      start: start,
      end: end,
      location: location,
      now: syncAt ?? _now,
    );

Map<String, dynamic> _noticePayload(
  String body, {
  String uuid = 'opaque:notice',
  String title = '合成期末考试',
  String examId = '99',
  String sendTime = '',
  String completeTime = '2040-01-02',
}) =>
    {
      'status': true,
      'notices': {
        'list': [
          {
            'uuid': uuid,
            'title': title,
            'content': body,
            'attachment': jsonEncode([
              {
                'attachmentType': 15,
                'att_web': {
                  'examOrWork': 'exam',
                  'examOrWorkId': int.parse(examId),
                  'courseId': 7,
                  'clazzId': 11,
                  'title': title,
                  'url':
                      'https://mooc1-api.chaoxing.com/examApi/intoexamorwork?taskrefId=$examId&courseId=7&classId=11&workOrExam=exam&enc=synthetic',
                }
              }
            ]),
            'sendTime': sendTime,
            'completeTime': completeTime,
          }
        ]
      }
    };

Assignment _notice(
  String body, {
  String uuid = 'opaque:notice',
  String title = '合成期末考试',
  String examId = '99',
  String sendTime = '',
}) =>
    ChaoxingExamParser.notices(
      _noticePayload(
        body,
        uuid: uuid,
        title: title,
        examId: examId,
        sendTime: sendTime,
      ),
      now: _now,
    )!
        .rows
        .single;

class _Session extends SecureSessionStore {
  String? account = 'A';

  @override
  Future<String?> readChaoxingAccount() async => account;
  @override
  Future<String?> readChaoxingPassword() async => 'pw';
  @override
  Future<String?> readChaoxingDisplayName() async => '合成账号';
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    this.account = account;
  }

  @override
  Future<void> clear() async {
    account = null;
  }
}

class _Notifications extends LocalNotificationService {
  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}
  @override
  Future<void> rescheduleSummary(
    List<Assignment> items,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> items, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _Widgets extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> items) async {}
}

class _OfflineClient extends ChaoxingLocalClient {
  _OfflineClient(Dio dio)
      : super(
          dio: dio,
          wait: (_) async {},
          enableExams: true,
          enableClassroomTasks: false,
        );

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    clearSession();
    return const ChaoxingLoginResult(success: true, displayName: '合成账号');
  }
}

class _FixtureServer {
  _FixtureServer() {
    dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options.uri.path);
        requestCookies[options.uri.path] =
            options.headers['Cookie']?.toString() ?? '';
        dynamic body;
        var status = 200;
        switch (options.uri.path) {
          case '/mycourse/backclazzdata':
            if (failCourseList) {
              handler.reject(DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ));
              return;
            }
            body = {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '合成课程'}
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="synthetic-work">';
          case '/mooc2/work/list':
            body =
                '<ul><li onclick="goTask()" data="/mooc2/work/doHomeWorkNew?courseId=1&amp;classId=2&amp;workId=10"><p class="overHidden2">在线作业</p><span class="status">未提交</span></li></ul>';
          case '/mooc2/work/doHomeWorkNew':
            if (detailTimeout) {
              handler.reject(DioException(
                requestOptions: options,
                type: DioExceptionType.receiveTimeout,
              ));
              return;
            }
            if (detail9010 && !verified) {
              status = 202;
              body = {'status': false, 'code': 9010, 'msg': '【9010】操作异常'};
            } else {
              body = '<div>截止时间：$detailDeadline</div>';
            }
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          case '/phone/moocAnalysis/examList':
            body = '<p class="blankTips">您好，本课程下暂未收到考试</p>';
          case '/exam/test':
            body =
                '<input id="courseId" value="1"><input id="classId" value="2"><div>暂无内容</div>';
          case '/exam-ans/exam/test/examcode/examlist':
            body = '<table class="dataTable"><tr><th>作答状态</th></tr></table>';
          default:
            throw StateError('unexpected ${options.uri.path}');
        }
        handler.resolve(
          Response(requestOptions: options, statusCode: status, data: body),
        );
      }));
  }

  late final Dio dio;
  final requests = <String>[];
  final requestCookies = <String, String>{};
  bool failCourseList = false;
  bool detail9010 = false;
  bool detailTimeout = false;
  bool verified = false;
  String detailDeadline = '2030-05-01 12:00';
}

Future<AssignmentStore> _store({
  required _Session session,
  required LocalAssignmentRepository repository,
  required ChaoxingLocalClient client,
}) async {
  final store = AssignmentStore(
    sessionStore: session,
    notificationService: _Notifications(),
    widgetSnapshotService: _Widgets(),
    repository: repository,
    chaoxingClient: client,
    clock: () => _now,
  );
  addTearDown(store.dispose);
  await store.restoreSession();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'unique missing-year exam mixes with manual entries while overdue stays '
      'bottom in both sort orders', () {
    final uniqueFormal = _formalExam(id: '99', title: '缺年考试');
    final uniqueNotice = _notice(
      '考试时间：11-25 09:00 至 11-25 11:00',
      uuid: 'unique-yearless',
      examId: '99',
      sendTime: '',
    );
    final uniqueRecords = [uniqueFormal, uniqueNotice];
    final uniqueDisplay = AssignmentQuery.projectDisplay(uniqueRecords).single;
    expect(uniqueDisplay.timelineTrusted, isFalse);
    expect(
      AssignmentQuery.displayTimelineAt(
        uniqueDisplay,
        records: uniqueRecords,
        now: _now,
      ),
      isNotNull,
    );

    final conflictFormal = _formalExam(id: '100', title: '冲突考试');
    final conflictRecords = [
      conflictFormal,
      _notice(
        '考试时间：11-25 09:00 至 11-25 11:00',
        uuid: 'conflict-a',
        title: '冲突考试',
        examId: '100',
        sendTime: '',
      ),
      _notice(
        '考试时间：11-26 09:00 至 11-26 11:00',
        uuid: 'conflict-b',
        title: '冲突考试',
        examId: '100',
        sendTime: '',
      ),
    ];
    final conflictDisplay =
        AssignmentQuery.projectDisplay(conflictRecords).single;
    expect(conflictDisplay.timelineTrusted, isFalse);
    expect(
      AssignmentQuery.displayTimelineAt(
        conflictDisplay,
        records: conflictRecords,
        now: _now,
      ),
      isNull,
    );

    final overdueWork = _work(
      'overdue',
      deadline: DateTime.utc(2026, 11, 23, 1),
      title: '学习通逾期',
      courseName: '合成课程',
    );
    final sameDayManual = _manual(
      'manual-today',
      title: '同日手动',
      at: DateTime.utc(2026, 11, 25, 6),
    );
    final overdueManual = _manual(
      'manual-overdue',
      title: '手动逾期',
      at: DateTime.utc(2026, 11, 23, 6),
    );
    final assignments = [
      uniqueDisplay,
      conflictDisplay,
      overdueWork,
    ];
    final sources = [
      ...uniqueRecords,
      ...conflictRecords,
      overdueWork,
    ];

    List<String> titles(HomeSortOrder order) => [
          for (final item in HomeManualTimeline.mergeAndSort(
            assignments: assignments,
            manualEntries: [sameDayManual, overdueManual],
            sourceRecords: sources,
            order: order,
            now: _now,
          ))
            item.title,
        ];

    for (final order in [
      HomeSortOrder.deadlineAsc,
      HomeSortOrder.deadlineDesc,
    ]) {
      final result = titles(order);
      expect(result.sublist(result.length - 2).toSet(), {'学习通逾期', '手动逾期'});
      expect(result.indexOf('冲突考试'), lessThan(result.length - 2));
      expect(result.indexOf('冲突考试'), greaterThanOrEqualTo(2));
    }

    final asc = titles(HomeSortOrder.deadlineAsc);
    expect(asc.take(2), ['缺年考试', '同日手动']);
    final desc = titles(HomeSortOrder.deadlineDesc);
    expect(desc.take(2), ['同日手动', '缺年考试']);

    final byCourse = titles(HomeSortOrder.courseName);
    expect(byCourse, hasLength(5));
    expect(byCourse, contains('冲突考试'));
  });

  test(
      'missing-year exam retains unconfirmed trust across repository '
      'persistence round-trip', () async {
    final notice = _notice(
      '考试时间：11-25 09:00 至 11-25 11:00',
      uuid: 'untrusted-roundtrip',
      sendTime: '',
    );
    expect(notice.timelineTrusted, isFalse);
    expect(notice.reminderAnchorAt, isNull);
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([notice], completeSync: false);
    final restored = (await repo.loadJournal()).single;
    expect(restored.timelineTrusted, isFalse);
    expect(restored.reminderAnchorAt, isNull);
    expect(AssignmentQuery.calendarDisplay([restored], _now), isEmpty);
  });

  test(
      'completeTime-only reschedule notice never overrides trusted formal exam '
      'or reminder anchor', () async {
    timezone_data.initializeTimeZones();
    final shanghai = tz.getLocation('Asia/Shanghai');
    final formal = _formalExam(
      id: '99',
      title: '正式期末考试',
      start: DateTime.utc(2026, 12, 20, 1),
      end: DateTime.utc(2026, 12, 20, 3),
      location: '原地点',
    );
    final notice = _notice(
      '考试时间：2026-12-21 09:00 至 2026-12-21 11:00\r考试地点：新地点',
      uuid: 'complete-time-only',
      examId: '99',
      sendTime: '',
    );
    expect(notice.publishedAt, isNull);
    final enriched = ChaoxingExamParser.enrichNotices([formal, notice]);
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave(enriched, completeSync: true);
    final loaded = await repo.loadJournal();
    final display = AssignmentQuery.projectDisplay(loaded).single;
    expect(display.exam!.startAt!.toUtc(), formal.exam!.startAt!.toUtc());
    expect(display.reminderAnchorAt!.toUtc(), formal.reminderAnchorAt!.toUtc());
    expect(display.exam!.location, '原地点');
    expect(display.isCompleted, isFalse);

    final plan = AssignmentReminderPlanner.planAfterSync(
      accountHash: 'hash',
      sessionEpoch: 1,
      assignments: loaded,
      hiddenAssignmentIds: const {},
      unfollowedCourseKeys: const {},
      knownAssignmentIds: const {},
      sentNewAssignmentIds: const {},
      baselineCompleted: true,
      completeSync: true,
      detectNewAssignments: false,
      newAssignmentReminderEnabled: false,
      reminderOffsetsMinutes: const [30],
      now: _now,
      location: shanghai,
    );
    expect(plan.deadlineEvents, isNotEmpty);
    expect(
      plan.deadlineEvents.every(
        (event) =>
            event.deadlineAt?.toUtc() == formal.reminderAnchorAt!.toUtc(),
      ),
      isTrue,
    );
  });

  test(
      'newer sendTime reschedule notice surfaces verification note without '
      'inventing completion', () async {
    final formal = _formalExam(
      id: '99',
      title: '缓存正式考试',
      start: DateTime.utc(2026, 11, 18, 1),
      end: DateTime.utc(2026, 11, 18, 3),
      syncAt: DateTime.utc(2026, 11, 17),
    );
    final notice = _notice(
      '考试时间：2026-11-26 09:00 至 2026-11-26 11:00\r考试地点：新地点',
      uuid: 'newer-notice',
      examId: '99',
      sendTime: '2026-11-19 12:00',
    );
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave(
      ChaoxingExamParser.enrichNotices([formal, notice]),
      completeSync: false,
    );
    final records = await repo.loadJournal();
    final projected = AssignmentQuery.projectDisplay(records).single;
    expect(projected.exam!.startAt?.toUtc(), formal.exam!.startAt?.toUtc());
    expect(projected.isCompleted, isFalse);
    expect(projected.exam!.location, '新通知地点：新地点（请核对）');
    final display = ExamSchedulePresentation.build(projected, records: records);
    expect(display.verificationNote, '有较新的通知与本机考试时间不一致，请核对官方最新安排');
    expect(display.detailTimeLines,
        contains('考试时间：2026-11-26 09:00 至 2026-11-26 11:00'));
  });

  test(
      'store 9010 pauses downstream sources, preserves prior journal, and '
      'recovers cleanly after verifyInBrowser', () async {
    final server = _FixtureServer()..detail9010 = true;
    final client = _OfflineClient(server.dio);
    final repo = LocalAssignmentRepository();
    final session = _Session();
    final store = await _store(
      session: session,
      repository: repo,
      client: client,
    );
    final old = _work(
      '10',
      deadline: DateTime.utc(2030, 5, 1, 4),
      title: '旧作业',
    );
    await repo.mergeAndSave([old], completeSync: false);
    await store.restoreSession();
    expect(await store.togglePin(old), isTrue);
    final oldKey = AssignmentStore.pinKeyOf(old);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'verifySession');
      server.verified = true;
      return [
        {'url': 'https://mooc1.chaoxing.com/', 'cookies': 'challenge=solved'},
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(
      store.syncReport.issues
          .any((issue) => issue.kind == SyncIssueKind.verificationRequired),
      isTrue,
    );
    expect(store.assignments.single.deadlineTrusted, isTrue);
    expect(store.pinnedKeys, contains(oldKey));
    expect(store.lastSyncAt, isNull);
    expect(server.requests, isNot(contains('/pc/notice/getNoticeList')));

    expect(await store.chaoxingClient.verifyInBrowser(), isTrue);
    server.verified = true;
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.success);
    expect(store.syncReport.issues, isEmpty);
    expect(store.assignments.single.deadlineTrusted, isTrue);
    expect(store.pinnedKeys, contains(oldKey));
    expect(store.lastSyncAt, isNotNull);
    expect(server.requests, contains('/pc/notice/getNoticeList'));
  });

  test(
      'logout or account switch during pending verifyInBrowser drops stale '
      'cookies and isolates target account', () async {
    final server = _FixtureServer()..detail9010 = true;
    final client = _OfflineClient(server.dio);
    final repo = LocalAssignmentRepository();
    final session = _Session();
    final store = await _store(
      session: session,
      repository: repo,
      client: client,
    );
    final old = _work(
      '10',
      deadline: DateTime.utc(2030, 5, 1, 4),
      title: '账号 A 作业',
    );
    await repo.mergeAndSave([old], completeSync: false);
    await store.restoreSession();
    expect(await store.togglePin(old), isTrue);
    final pending = <Completer<List<Map<String, dynamic>>?>>[];
    var hold = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
      expect(call.method, 'verifySession');
      if (!hold) return Future.value(null);
      final completer = Completer<List<Map<String, dynamic>>?>();
      pending.add(completer);
      return completer.future;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    await store.syncAssignments();
    hold = true;
    final staleVerify = store.chaoxingClient.verifyInBrowser();
    await Future<void>.delayed(Duration.zero);
    await store.logout();
    pending.single.complete([
      {'url': 'https://mooc1.chaoxing.com/', 'cookies': 'stale=leak'},
    ]);
    expect(await staleVerify, isFalse);
    expect(store.isAuthenticated, isFalse);
    expect(store.assignments, isEmpty);
    expect(store.pinnedKeys, isEmpty);

    // Re-seed account A, then switch to B while verification is still pending.
    session.account = 'A';
    await store.restoreSession();
    await repo.mergeAndSave([old], completeSync: false);
    await store.restoreSession();
    expect(await store.togglePin(old), isTrue);
    await store.syncAssignments();
    final switchVerify = store.chaoxingClient.verifyInBrowser();
    await Future<void>.delayed(Duration.zero);
    final switchFuture = store.loginChaoxing(
      account: 'B',
      password: 'pw',
      agreementAccepted: true,
    );
    pending.last.complete([
      {'url': 'https://mooc1.chaoxing.com/', 'cookies': 'stale=leak'},
    ]);
    expect(await switchVerify, isFalse);
    await switchFuture;
    expect(store.account, 'B');
    expect(store.assignments, isEmpty);
    expect(store.pinnedKeys, isEmpty);

    server.detail9010 = false;
    await store.syncAssignments();
    expect(server.requestCookies['/mycourse/backclazzdata'],
        isNot(contains('stale=leak')));
    expect(store.assignments.single.title, isNot('账号 A 作业'));
    expect(store.pinnedKeys, isEmpty);
  });

  test(
      'cold start 9010 without cached cookies keeps verification target '
      'across user cancel', () async {
    final server = _FixtureServer()..detail9010 = true;
    final client = _OfflineClient(server.dio);
    final repo = LocalAssignmentRepository();
    final session = _Session();
    final store = await _store(
      session: session,
      repository: repo,
      client: client,
    );
    var round = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'verifySession');
      round++;
      if (round == 1) return null;
      server.verified = true;
      return [
        {'url': 'https://mooc1.chaoxing.com/', 'cookies': 'challenge=solved'},
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(await store.chaoxingClient.verifyInBrowser(), isFalse);
    expect(await store.chaoxingClient.verifyInBrowser(), isTrue);
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.success);
    expect(store.syncReport.issues, isEmpty);
  });

  test(
      'network connectionError during sync keeps existing assignments, pins and '
      'lastSyncAt, then recovers', () async {
    final server = _FixtureServer();
    final client = _OfflineClient(server.dio);
    final repo = LocalAssignmentRepository();
    final session = _Session();
    final store = await _store(
      session: session,
      repository: repo,
      client: client,
    );

    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.success);
    expect(store.assignments, hasLength(1));
    final pinned = store.assignments.single;
    expect(await store.togglePin(pinned), isTrue);
    final beforeSyncAt = store.lastSyncAt;
    expect(beforeSyncAt, isNotNull);

    server.failCourseList = true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.failed);
    expect(
      store.syncReport.issues
          .any((issue) => issue.kind == SyncIssueKind.network),
      isTrue,
    );
    expect(store.assignments.single.id, pinned.id);
    expect(store.pinnedKeys, contains(AssignmentStore.pinKeyOf(pinned)));
    expect(store.lastSyncAt, beforeSyncAt);

    server.failCourseList = false;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.success);
    expect(store.syncReport.issues, isEmpty);
    expect(store.lastSyncAt, isNotNull);
    expect(store.lastSyncAt!.isAfter(beforeSyncAt!), isTrue);
  });

  test(
      'detail receiveTimeout produces partial sync without losing trusted '
      'prior deadline and clears after recovery', () async {
    final server = _FixtureServer();
    final client = _OfflineClient(server.dio);
    final repo = LocalAssignmentRepository();
    final session = _Session();
    final store = await _store(
      session: session,
      repository: repo,
      client: client,
    );

    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.success);
    final pinned = store.assignments.single;
    expect(pinned.deadlineTrusted, isTrue);
    final priorDeadline = pinned.deadlineAt!.toUtc();
    expect(await store.togglePin(pinned), isTrue);

    server.detailTimeout = true;
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(
      store.syncReport.issues.any(
        (issue) =>
            issue.kind == SyncIssueKind.network && issue.stage == 'detail',
      ),
      isTrue,
    );
    expect(store.assignments.single.deadlineTrusted, isTrue);
    expect(store.assignments.single.deadlineAt!.toUtc(), priorDeadline);
    expect(store.pinnedKeys, contains(AssignmentStore.pinKeyOf(pinned)));

    server.detailTimeout = false;
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.success);
    expect(store.syncReport.issues, isEmpty);
    expect(store.assignments.single.deadlineAt!.toUtc(), priorDeadline);
    expect(store.pinnedKeys, contains(AssignmentStore.pinKeyOf(pinned)));
  });
}
