import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/features/course_study_hub_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_floating_nav_bar.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_sync_diagnostics_exporter.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_chapter_progress.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _TestSessionStore extends SecureSessionStore {
  String? _account = '13800000001';
  String? _password = 'secret-pass';
  String? _displayName = '测试同学';
  String? _avatarUrl = 'https://photo.chaoxing.com/p/1_160';

  @override
  Future<String?> readChaoxingAccount() async => _account;

  @override
  Future<String?> readChaoxingPassword() async => _password;

  @override
  Future<String?> readChaoxingDisplayName() async => _displayName;

  @override
  Future<String?> readChaoxingAvatarUrl() async => _avatarUrl;

  @override
  Future<void> saveChaoxingAccount({
    required String account,
    required String password,
    String? displayName,
    String? avatarUrl,
  }) async {
    _account = account;
    _password = password;
    _displayName = displayName;
    _avatarUrl = avatarUrl;
  }

  @override
  Future<void> clearWebSession() async {}

  @override
  Future<void> clear() async {
    _account = null;
    _password = null;
    _displayName = null;
    _avatarUrl = null;
  }
}

class _TestNotificationService extends LocalNotificationService {
  final List<ManualEntry> scheduledManualEntries = [];

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
  Future<void> rescheduleManual(List<ManualEntry> entries) async {
    scheduledManualEntries
      ..clear()
      ..addAll(entries.where((e) => !e.done && e.remind && e.at != null));
  }
}

class _TestWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _WidgetHubClient extends ChaoxingLocalClient {
  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true, displayName: '测试同学');

  @override
  List<CourseNotice> get lastFetchedNotices => [
        CourseNotice(
          id: 'cx:notice:${'a' * 64}',
          courseId: '10',
          clazzId: '20',
          courseName: '人工智能导论',
          senderName: '王教授',
          title: '《人工智能导论》实验提交说明',
          summary: '请完成实验报告。',
          publishedAt: DateTime.utc(2030, 5, 20, 2, 0),
          publishedTrusted: true,
          extractedEventAt: DateTime.utc(2030, 6, 1, 12, 0),
          extractedEventTrusted: true,
          platformUnread: true,
          localRead: false,
          lastSyncedAt: DateTime.utc(2030, 5, 20, 2, 0),
        ),
      ];

  @override
  Future<List<Assignment>> fetchAssignments() async {
    hasCourseResponse = true;
    courses = const [
      ChaoxingCourseRef(courseId: '10', clazzId: '20', courseName: '人工智能导论'),
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

  @override
  Future<CourseChapterSnapshot> fetchCourseChapters(
    ChaoxingCourseRef course,
  ) async =>
      CourseChapterSnapshot(
        courseId: course.courseId,
        clazzId: course.clazzId,
        courseName: course.courseName,
        completedPoints: 2,
        totalPoints: 4,
        progressTrusted: true,
        nodes: const [
          ChapterNode(
            sectionId: 'cx:chapter:10:20:0:1',
            level: 0,
            code: '1',
            title: '深度学习基础',
            state: ChapterTaskState.noTaskPoints,
          ),
          ChapterNode(
            sectionId: 'cx:chapter:10:20:1:1.1',
            level: 1,
            code: '1.1',
            title: '感知机',
            state: ChapterTaskState.completed,
          ),
          ChapterNode(
            sectionId: 'cx:chapter:10:20:1:1.2',
            level: 1,
            code: '1.2',
            title: '反向传播',
            state: ChapterTaskState.pendingPoints,
            pendingPoints: 2,
          ),
        ],
        lastSyncedAt: DateTime.utc(2030, 5, 20, 2, 0),
      );
}

class _LargeHubClient extends _WidgetHubClient {
  @override
  List<CourseNotice> get lastFetchedNotices => [
        for (var i = 1; i <= 80; i++)
          CourseNotice(
            id: 'cx:notice:${i.toRadixString(16).padLeft(64, '0')}',
            courseId: '10',
            clazzId: '20',
            courseName: '人工智能导论',
            senderName: '王教授',
            title: '批次通知 $i',
            summary: '请查看课程通知正文。',
            publishedAt: DateTime.utc(2030, 5, 20, 12, 80 - i),
            publishedTrusted: true,
            lastSyncedAt: DateTime.utc(2030, 5, 21),
          ),
      ];

  @override
  Future<List<Assignment>> fetchAssignments() async {
    final assignments = await super.fetchAssignments();
    courses = [
      ...courses,
      for (var i = 2; i <= 40; i++)
        ChaoxingCourseRef(
          courseId: '${100 + i}',
          clazzId: '20',
          courseName: '章节课程 $i',
        ),
    ];
    succeededCourses = courses.length;
    sourceResults = [
      SyncSourceResult(
        source: 'courseWork',
        phase: SyncSourcePhase.success,
        succeededCourses: courses.length,
      ),
      SyncSourceResult(
        source: 'courseNotice',
        phase: SyncSourcePhase.success,
        succeededCourses: courses.length,
        recordCount: 80,
      ),
    ];
    return assignments;
  }
}

class _NoticeScopeHubClient extends ChaoxingLocalClient {
  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true, displayName: '测试同学');

  @override
  List<CourseNotice> get lastFetchedNotices => [
        CourseNotice(
          id: 'cx:notice:${'a' * 64}',
          courseId: '10',
          clazzId: '20',
          courseName: '人工智能导论',
          senderName: '王教授',
          title: '已关联通知一',
          summary: '课程作业说明。',
          publishedAt: DateTime.utc(2030, 5, 20, 2, 0),
          publishedTrusted: true,
          platformUnread: true,
          lastSyncedAt: DateTime.utc(2030, 5, 20, 2, 0),
        ),
        CourseNotice(
          id: 'cx:notice:${'b' * 64}',
          courseId: '10',
          clazzId: '20',
          courseName: '人工智能导论',
          senderName: '王教授',
          title: '已关联通知二',
          summary: '课程实验安排。',
          publishedAt: DateTime.utc(2030, 5, 21, 2, 0),
          publishedTrusted: true,
          platformUnread: true,
          lastSyncedAt: DateTime.utc(2030, 5, 21, 2, 0),
        ),
        CourseNotice(
          id: 'cx:notice:${'c' * 64}',
          courseName: '通知中心',
          senderName: '小通活动助手',
          title: '平台竞赛邀请',
          summary: '平台活动邀请，不属于已关注课程。',
          publishedAt: DateTime.utc(2030, 5, 22, 2, 0),
          publishedTrusted: true,
          platformUnread: true,
          lastSyncedAt: DateTime.utc(2030, 5, 22, 2, 0),
        ),
      ];

  @override
  Future<List<Assignment>> fetchAssignments() async {
    hasCourseResponse = true;
    courses = const [
      ChaoxingCourseRef(courseId: '10', clazzId: '20', courseName: '人工智能导论'),
    ];
    succeededCourses = 1;
    failedCourses = 0;
    issues = const [];
    sourceResults = const [
      SyncSourceResult(
        source: 'courseNotice',
        phase: SyncSourcePhase.success,
        succeededCourses: 1,
        recordCount: 3,
      ),
    ];
    return const [];
  }
}

class _InboxOnlyHubClient extends _NoticeScopeHubClient {
  @override
  List<CourseNotice> get lastFetchedNotices => [
        CourseNotice(
          id: 'cx:notice:${'d' * 64}',
          courseName: '通知中心',
          senderName: '小通活动助手',
          title: '空目录平台邀请',
          summary: '没有课程目录时仍可切到收件箱。',
          publishedAt: DateTime.utc(2030, 5, 22, 2, 0),
          publishedTrusted: true,
          platformUnread: true,
          lastSyncedAt: DateTime.utc(2030, 5, 22, 2, 0),
        ),
      ];

  @override
  Future<List<Assignment>> fetchAssignments() async {
    hasCourseResponse = true;
    courses = const [];
    succeededCourses = 0;
    failedCourses = 0;
    issues = const [];
    sourceResults = const [
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

class _HubNetworkFixture {
  int noticeCalls = 0;
  int probeCalls = 0;
  int chapterCalls = 0;

  late final Dio dio = Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      dynamic body = '';
      final headers = <String, List<String>>{};
      switch (o.uri.path) {
        case '/v11/loginregister':
          body = {'status': true};
          headers['set-cookie'] = ['UID=12345; Path=/; Domain=chaoxing.com'];
        case '/mycourse/backclazzdata':
          body = {
            'courses': [
              {'courseId': '10', 'clazzId': '20', 'courseName': '人工智能导论'}
            ]
          };
        case '/visit/stucoursemiddle':
          body =
              '<input id="workEnc" value="w1"><input id="examEnc" value="e1"><input id="enc" value="c1"><input id="openc" value="op1">';
        case '/mooc2/work/list':
          body = '<div>暂无作业</div>';
        case '/v2/apis/active/student/activelist':
          body = {
            'result': 1,
            'data': {'activeList': []}
          };
        case '/phone/moocAnalysis/examList':
          body =
              '<div class="ybox"><p class="blankTips">您好，本课程下暂未收到考试</p></div>';
        case '/exam/test':
          body =
              '<input id="courseId" value="10"><input id="classId" value="20"><div>暂无考试</div>';
        case '/exam-ans/exam/test/examcode/examlist':
          body =
              '<table class="dataTable"><tr><th>考试名称</th><th>作答状态</th></tr></table>';
        case '/pc/notice/getNoticeList':
          noticeCalls++;
          final firstPage = o.data is Map && (o.data as Map)['lastValue'] == '';
          body = firstPage
              ? {
                  'status': true,
                  'notices': {
                    'lastGetId': 'c1',
                    'lastPage': true,
                    'list': [
                      {
                        'uuid': 'course-notice-1',
                        'title': '《人工智能导论》实验提交说明',
                        'content':
                            '请完成实验报告，截止时间：2030-06-01 20:00。链接 https://mooc1.chaoxing.com/x?enc=tokenABC',
                        'createrName': '王教授',
                        'completeTime': '2030-05-20 10:00',
                        'isread': '0',
                      }
                    ],
                  },
                }
              : {'status': true};
        case '/v2/apis/active/getData':
          probeCalls++;
          body = {'result': 1, 'data': []};
        case '/mooc2-ans/mycourse/studentcourse':
          chapterCalls++;
          body = '''
<div>已完成任务点: <span>2</span>/4</div>
<div class="catalog_num fl"><span><i><em>1</em></i></span></div>
<div class="catalog_name newCatalog_name"><a class="clicktitle"><span title="深度学习基础">深度学习基础</span></a></div>
<li><div class="chapter_item" title="1.1 感知机"><span class="catalog_sbar">1.1</span><span class="icon_yiwanc"></span></div></li>
<li><div class="chapter_item" title="1.2 反向传播"><span class="catalog_sbar">1.2</span><span class="catalog_points_yi">2</span></div></li>
''';
        default:
          throw StateError('unexpected ${o.uri.path}');
      }
      h.resolve(Response(
        requestOptions: o,
        data: body,
        statusCode: 200,
        headers: Headers.fromMap(headers),
      ));
    }));
}

Future<AssignmentStore> _syncHub(ChaoxingLocalClient client) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = AssignmentStore(
    sessionStore: _TestSessionStore(),
    notificationService: _TestNotificationService(),
    widgetSnapshotService: _TestWidgetSnapshotService(),
    chaoxingClient: client,
  );
  addTearDown(store.dispose);
  await store.restoreSession();
  await store.syncAssignments();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'notices default to linked courses and inbox exposes platform invitations',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _TestSessionStore(),
      notificationService: _TestNotificationService(),
      widgetSnapshotService: _TestWidgetSnapshotService(),
      chaoxingClient: _NoticeScopeHubClient(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(store.courseNotices.items, hasLength(3));

    await tester.pumpWidget(
      MaterialApp(home: CourseStudyHubScreen(store: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('已关联课程'), findsOneWidget);
    expect(find.text('全部 (2)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('已关联通知一'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('已关联通知一'), findsOneWidget);
    expect(find.text('已关联通知二'), findsOneWidget);
    expect(find.text('平台竞赛邀请'), findsNothing);

    await tester.tap(find.byTooltip('全部标为已读'));
    await tester.pumpAndSettle();
    expect(
      store.courseNotices.items
          .where((n) => n.courseKey != null)
          .every((n) => n.localRead),
      isTrue,
    );
    expect(
      store.courseNotices.items
          .singleWhere((n) => n.courseKey == null)
          .localRead,
      isFalse,
    );

    await tester.ensureVisible(find.text('已关联课程'));
    await tester.tap(find.text('已关联课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收件箱（全部）').last);
    await tester.pumpAndSettle();
    expect(find.text('全部 (3)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('平台竞赛邀请'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('平台竞赛邀请'), findsOneWidget);

    await tester.tap(find.byTooltip('全部标为已读'));
    await tester.pumpAndSettle();
    expect(store.courseNotices.items.every((n) => n.localRead), isTrue);
  }, timeout: const Timeout(Duration(seconds: 15)));

  testWidgets('notice search waits for the latest input before filtering',
      (tester) async {
    final store = await _syncHub(_NoticeScopeHubClient());
    await tester.pumpWidget(
      MaterialApp(home: CourseStudyHubScreen(store: store)),
    );
    await tester.pumpAndSettle();

    final search = find.byType(TextField);
    final first = find.text('已关联通知一');
    final second = find.text('已关联通知二');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);

    await tester.enterText(search, '通知一');
    await tester.pump(const Duration(milliseconds: 50));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget, reason: '首个输入后的 50ms 仍显示原结果');

    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(search, '通知二');
    await tester.pump(const Duration(milliseconds: 50));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget, reason: '旧输入到期时仍应等待新输入');

    await tester.pump(const Duration(milliseconds: 200));
    expect(first, findsNothing);
    expect(second, findsOneWidget);
  });

  testWidgets('clearing notice search restores results immediately',
      (tester) async {
    final store = await _syncHub(_NoticeScopeHubClient());
    await tester.pumpWidget(
      MaterialApp(home: CourseStudyHubScreen(store: store)),
    );
    await tester.pumpAndSettle();

    final search = find.byType(TextField);
    final clear = find.byTooltip('清除搜索');
    final first = find.text('已关联通知一');
    final second = find.text('已关联通知二');
    await tester.enterText(search, '无匹配通知');
    await tester.pump(const Duration(milliseconds: 250));
    expect(first, findsNothing);
    expect(second, findsNothing);

    await tester.enterText(search, '通知一');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(clear);
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(clear, findsNothing);
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
  });

  testWidgets('unmounting the hub cancels a pending notice search',
      (tester) async {
    final store = await _syncHub(_NoticeScopeHubClient());
    await tester.pumpWidget(
      MaterialApp(home: CourseStudyHubScreen(store: store)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '通知一');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(CourseStudyHubScreen), findsNothing);
    expect(tester.takeException(), isNull);
    // End before the debounce expires so the binding detects an orphaned timer.
  });

  testWidgets('80 notices build the last row only when scrolled into range',
      (tester) async {
    final store = await _syncHub(_LargeHubClient());
    expect(store.courseNotices.items, hasLength(80));
    await tester.pumpWidget(
      MaterialApp(home: CourseStudyHubScreen(store: store)),
    );
    await tester.pumpAndSettle();

    final first = find.text('批次通知 1');
    final last = find.text('批次通知 80');
    expect(first.hitTestable(), findsOneWidget);
    final lastInitiallyBuilt = last.evaluate().isNotEmpty;

    await tester.scrollUntilVisible(
      last,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
    expect(first.hitTestable(), findsNothing);
    expect(lastInitiallyBuilt, isFalse, reason: '首屏不应构建第 80 条通知');
  });

  testWidgets('chapter courses load lazily and keep an expanded course usable',
      (tester) async {
    final store = await _syncHub(_LargeHubClient());
    expect(store.courses, hasLength(40));
    expect(await store.syncCourseChapters(courseKey: '10:20'), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: CourseStudyHubScreen(store: store, initialTab: 'chapters'),
      ),
    );
    await tester.pumpAndSettle();

    final first = find.text('人工智能导论');
    final courseKey = find.byKey(const ValueKey('chapter-course-10:20'));
    final last = find.text('章节课程 40');
    final section = find.text('1.2 反向传播');
    final scrollable = find.byType(Scrollable).first;
    expect(first.hitTestable(), findsOneWidget);
    expect(courseKey, findsOneWidget);
    expect(section, findsNothing);
    final lastInitiallyBuilt = last.evaluate().isNotEmpty;

    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(section.hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(last, 350, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
    expect(first.hitTestable(), findsNothing);

    await tester.scrollUntilVisible(first, -350, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(courseKey, findsOneWidget);
    expect(section, findsOneWidget, reason: '滚出缓存区后再返回仍应展开');
    final addTodo = find.text('设待办');
    await tester.ensureVisible(addTodo);
    await tester.pumpAndSettle();
    expect(addTodo.hitTestable(), findsOneWidget);
    await tester.tap(addTodo);
    await tester.pumpAndSettle();
    final picker = find.byType(DatePickerDialog);
    expect(picker, findsOneWidget);
    await tester.tap(find.descendant(
      of: picker,
      matching: find.textContaining(RegExp(r'^cancel$', caseSensitive: false)),
    ));
    await tester.pumpAndSettle();
    expect(store.notebook.entries.single.title, '[章节任务点] 1.2 反向传播');
    expect(find.text('已加待办'), findsOneWidget);
    expect(lastInitiallyBuilt, isFalse, reason: '首屏不应构建第 40 门课程');
  });

  testWidgets('empty course directory still offers the inbox scope',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _TestSessionStore(),
      notificationService: _TestNotificationService(),
      widgetSnapshotService: _TestWidgetSnapshotService(),
      chaoxingClient: _InboxOnlyHubClient(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(store.courseNotices.items, hasLength(1));

    await tester.pumpWidget(
      MaterialApp(home: CourseStudyHubScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('全部 (0)'), findsOneWidget);
    expect(find.text('当前通知范围内没有记录，可切换到「收件箱」查看平台消息。'), findsOneWidget);
    await tester.tap(find.text('已关联课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收件箱（全部）').last);
    await tester.pumpAndSettle();
    expect(find.text('全部 (1)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('空目录平台邀请'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('空目录平台邀请'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 15)));

  test(
      'manual sync collects course notices and task probe while background check skips them',
      () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final fixture = _HubNetworkFixture();
    final notifications = _TestNotificationService();
    final store = AssignmentStore(
      sessionStore: _TestSessionStore(),
      notificationService: notifications,
      widgetSnapshotService: _TestWidgetSnapshotService(),
      chaoxingClient: ChaoxingLocalClient(dio: fixture.dio, wait: (_) async {}),
      clock: () => DateTime(2030, 5, 20, 12, 0),
    );
    addTearDown(store.dispose);

    await store.restoreSession();
    await store.saveBackgroundCheckEnabled(true);

    // Background automatic check must skip courseNotice and taskEnginePlan.
    await store.runBackgroundAutomaticCheck(BackgroundSyncTrigger.daytime);
    expect(fixture.probeCalls, 0);
    expect(store.courseNotices.items, isEmpty);
    expect(
      store.syncReport.sourceResults.any((s) => s.source == 'courseNotice'),
      isFalse,
    );

    // Manual sync collects courseNotice and taskEnginePlan.
    await store.syncAssignments();
    expect(fixture.probeCalls, 1);
    expect(store.courseNotices.items, hasLength(1));
    expect(store.unreadCourseNoticeCount, 1);
    expect(
      store.syncReport.sourceResults.any((s) => s.source == 'courseNotice'),
      isTrue,
    );

    // Creating reminder from notice is idempotent and schedules local alarm.
    final notice = store.courseNotices.items.single;
    final firstEntry = await store.createReminderFromNotice(
      notice,
      remindAt: DateTime(2030, 6, 1, 19, 0),
    );
    expect(firstEntry, isNotNull);
    expect(firstEntry!.title, startsWith('[课程通知]'));
    expect(notifications.scheduledManualEntries, hasLength(1));

    final updatedNotice = store.courseNotices.items.single;
    expect(updatedNotice.localRead, isTrue);
    final duplicate = await store.createReminderFromNotice(
      updatedNotice,
      remindAt: DateTime(2030, 6, 1, 19, 0),
    );
    expect(duplicate!.id, firstEntry.id);
    expect(store.notebook.entries, hasLength(1));

    // Chapter sync & todo creation.
    final ok = await store.syncCourseChapters();
    expect(ok, isTrue);
    expect(fixture.chapterCalls, 1);
    final snapshot = store.courseChapters.byCourse['10:20']!;
    final pendingNode = snapshot.nodes
        .singleWhere((n) => n.state == ChapterTaskState.pendingPoints);
    final chapEntry = await store.createTodoFromChapterNode(
      snapshot,
      pendingNode,
      remindAt: DateTime(2030, 5, 21, 18, 0),
      minutes: 45,
    );
    expect(chapEntry, isNotNull);
    expect(chapEntry!.title, startsWith('[章节任务点] 1.2'));
    expect(notifications.scheduledManualEntries, hasLength(2));
  });

  test('diagnostics exporter excludes personal identifiers and course names',
      () {
    final jsonText = ChaoxingSyncDiagnosticsExporter.exportJson(
      appVersion: '1.8.11+78',
      report: const SyncReport(
        phase: SyncPhase.partial,
        succeededCourses: 6,
        failedCourses: 1,
        sourceResults: [
          SyncSourceResult(
            source: 'exam',
            phase: SyncSourcePhase.partial,
            succeededCourses: 6,
            failedCourses: 1,
            recordCount: 2,
            reasonCodes: ['examPcSupplementUnavailable'],
          ),
        ],
        issues: [
          SyncIssue(
            SyncIssueKind.schemaChanged,
            '课程《高密课程》出错',
            stage: 'exam',
            courseKey: '10:20',
            httpStatus: 200,
          ),
        ],
      ),
      phaseElapsedMs: const {'exams': 123},
      requestTimings: const {},
    );
    final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
    expect(parsed['schemaVersion'], 1);
    expect(jsonText, isNot(contains('高密课程')));
    expect(jsonText, isNot(contains('10:20')));
    expect((parsed['issueGroups'] as List).single['stage'], 'exam');
  });

  testWidgets(
      'ProfileScreen navigates to /course-hub while keeping bottom bar on 我的 and SyncStatusScreen copies diagnostics',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _TestSessionStore(),
      notificationService: _TestNotificationService(),
      widgetSnapshotService: _TestWidgetSnapshotService(),
      chaoxingClient: _WidgetHubClient(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();

    String? copiedClipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedClipboard = (call.arguments as Map)['text'] as String?;
          return null;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        ShellRoute(
          builder: (_, __, child) => AppShell(
            assignmentStore: store,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, __) => ProfileScreen(store: store),
            ),
            GoRoute(
              path: '/course-hub',
              builder: (_, state) => CourseStudyHubScreen(
                store: store,
                initialTab: state.uri.queryParameters['tab'],
              ),
            ),
            GoRoute(
              path: '/sync',
              builder: (_, __) => SyncStatusScreen(store: store),
            ),
            GoRoute(
              path: '/agenda',
              builder: (_, __) => const Scaffold(body: Text('agenda-stub')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('课程通知与章节'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('课程通知与章节'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程通知与章节'));
    await tester.pumpAndSettle();

    expect(find.text('《人工智能导论》实验提交说明'), findsOneWidget);
    expect(find.byType(JournalFloatingNavBar), findsNothing);

    // Filter chips, search, and tapping detail marks notice locally read.
    await tester.tap(find.text('含识别时间'));
    await tester.pumpAndSettle();
    expect(find.text('《人工智能导论》实验提交说明'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不存在关键词');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('当前筛选条件下没有匹配的通知。'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('《人工智能导论》实验提交说明'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('《人工智能导论》实验提交说明'));
    await tester.pumpAndSettle();
    expect(store.unreadCourseNoticeCount, 0);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Switch to chapters tab and trigger manual chapter refresh.
    await tester.ensureVisible(find.textContaining('章节任务点'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('章节任务点'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新课程章节'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已完成 2/4 任务点'), findsOneWidget);

    // Expand course card and filter pending sections only.
    await tester.ensureVisible(find.text('人工智能导论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('人工智能导论'));
    await tester.pumpAndSettle();
    expect(find.text('1.1 感知机'), findsOneWidget);
    expect(find.text('1.2 反向传播'), findsOneWidget);
    await tester.ensureVisible(find.text('仅看待完成任务点小节'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅看待完成任务点小节'));
    await tester.pumpAndSettle();
    expect(find.text('1.1 感知机'), findsNothing);
    expect(find.text('1.2 反向传播'), findsOneWidget);

    // Returning to /profile restores bottom floating nav on 我的 tab.
    router.pop();
    await tester.pumpAndSettle();
    final nav = tester
        .widget<JournalFloatingNavBar>(find.byType(JournalFloatingNavBar));
    expect(nav.selectedIndex, 3);

    // Verify SyncStatusScreen diagnostic copy button.
    router.go('/sync');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('复制脱敏同步诊断摘要'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('复制脱敏同步诊断摘要'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制脱敏同步诊断摘要'));
    await tester.pumpAndSettle();
    expect(copiedClipboard, isNotNull);
    expect(copiedClipboard, contains('"schemaVersion": 1'));
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('cancelling chapter sync preserves prior syncReport phase', () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final fixture = _HubNetworkFixture();
    final store = AssignmentStore(
      sessionStore: _TestSessionStore(),
      notificationService: _TestNotificationService(),
      widgetSnapshotService: _TestWidgetSnapshotService(),
      chaoxingClient: ChaoxingLocalClient(dio: fixture.dio, wait: (_) async {}),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.success);

    final ok = await store.syncCourseChapters();
    expect(ok, isTrue);
    store.cancelSynchronization();
    expect(store.syncReport.phase, SyncPhase.success);
  });

  test('cleanNoticeSummary strips duplicate leading course-name prefixes', () {
    expect(
      CourseStudyHubScreen.cleanNoticeSummary('课程名称：数据结构\n请周五前完成实验报告。'),
      '请周五前完成实验报告。',
    );
    expect(
      CourseStudyHubScreen.cleanNoticeSummary('课程名称: 数据结构'),
      '',
    );
    expect(
      CourseStudyHubScreen.cleanNoticeSummary('正文内容\n课程名称：保留中间引用'),
      '正文内容\n课程名称：保留中间引用',
    );
  });

  testWidgets(
      'CourseListScreen and CourseStudyHubScreen show teacher names, clip long teacher lists at 320w@2x, and search by teacher',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _TestSessionStore(),
      notificationService: _TestNotificationService(),
      widgetSnapshotService: _TestWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.repository.activateAccount('13800000001');
    await store.repository.saveCourses(
      const [
        CourseRef(
          courseId: '10',
          clazzId: '100',
          name: '大学英语',
          teacherNames: ['Alice教师', 'Bob教师', 'Carol教师', 'Dave教师'],
          folderName: '2026年秋',
        ),
        CourseRef(
          courseId: '11',
          clazzId: '101',
          name: '大学英语',
          teacherNames: ['Eve导师'],
        ),
      ],
      account: '13800000001',
    );
    await store.restoreSession();

    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget wrap(Widget child) => MaterialApp(
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: inner!,
          ),
          home: child,
        );

    // 1. CourseListScreen displays class + teacher names, clips long lists, and filters by teacher.
    await tester.pumpWidget(wrap(CourseListScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.textContaining('班级 100 · Alice教师'), findsOneWidget);
    expect(find.textContaining('班级 101 · Eve导师'), findsOneWidget);
    final listSub =
        tester.widget<Text>(find.textContaining('班级 100 · Alice教师'));
    expect(listSub.maxLines, 2);
    expect(listSub.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('course-list-search-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('course-list-search')),
      'Eve导师',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('班级 101 · Eve导师'), findsOneWidget);
    expect(find.textContaining('班级 100 · Alice教师'), findsNothing);
    expect(tester.takeException(), isNull);

    // 2. CourseStudyHubScreen chapters show teacher names and notice picker searches by teacher.
    await tester.pumpWidget(wrap(CourseStudyHubScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已关联课程'));
    await tester.pumpAndSettle();
    expect(find.textContaining('班级 100 · Alice教师'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Eve导师');
    await tester.pumpAndSettle();
    expect(find.textContaining('班级 101 · Eve导师'), findsOneWidget);
    expect(find.textContaining('班级 100 · Alice教师'), findsNothing);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('章节任务点'));
    await tester.pumpAndSettle();
    expect(find.textContaining('班级 100 · Alice教师'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Phase 3E collapses system reminders, keeps primary unread badge accurate, isolates single-course slice by verified courseKey, and resets on account change',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final now = DateTime.utc(2026, 11, 20, 4);
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('13800000001');
    await repo.saveCourses(
      const [
        CourseRef(
          courseId: '1',
          clazzId: '10',
          name: '线性代数',
          teacherNames: ['陈老师'],
          folderName: '2026年秋',
        ),
        CourseRef(
          courseId: '1',
          clazzId: '11',
          name: '线性代数',
          teacherNames: ['李教授'],
          folderName: '2025年秋',
        ),
      ],
      account: '13800000001',
    );

    final activeWork = Assignment(
      id: 'cx:work:1:10:w1',
      courseName: '线性代数',
      title: '10班进行中作业',
      deadlineAt: now.add(const Duration(days: 2)),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    final submittedWork = Assignment(
      id: 'cx:work:1:10:w2',
      courseName: '线性代数',
      title: '10班已完成旧作业',
      deadlineAt: now.subtract(const Duration(days: 300)),
      requirementsText: '',
      status: 'submitted',
      lastSyncedAt: now,
    );
    final wrongClassWork = Assignment(
      id: 'cx:work:1:11:w9',
      courseName: '线性代数',
      title: '11班不应混入作业',
      deadlineAt: now.subtract(const Duration(days: 300)),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    await repo.mergeAndSave([activeWork, submittedWork, wrongClassWork]);

    await repo.saveCourseNotices(
      CourseNoticeCollection(items: [
        CourseNotice(
          id: 'cx:notice:${'1'.padLeft(64, '0')}',
          courseId: '1',
          clazzId: '10',
          courseName: '线性代数',
          senderName: '陈老师',
          title: '陈老师调课通知',
          lastSyncedAt: now,
        ),
        CourseNotice(
          id: 'cx:notice:${'2'.padLeft(64, '0')}',
          courseId: '1',
          clazzId: '10',
          courseName: '线性代数',
          senderName: '陈老师',
          title: '作业结束提醒',
          lastSyncedAt: now.subtract(const Duration(minutes: 1)),
        ),
        CourseNotice(
          id: 'cx:notice:${'3'.padLeft(64, '0')}',
          courseId: '1',
          clazzId: '11',
          courseName: '线性代数',
          senderName: '学习通知',
          title: '作业结束提醒',
          lastSyncedAt: now,
        ),
        CourseNotice(
          id: 'cx:notice:${'4'.padLeft(64, '0')}',
          courseId: '1',
          clazzId: '10',
          courseName: '线性代数',
          senderName: '学习通知',
          title: '作业：《线性代数》第七章提交提醒',
          lastSyncedAt: now.subtract(const Duration(minutes: 2)),
        ),
      ]),
      '13800000001',
    );

    final store = AssignmentStore(
      repository: repo,
      sessionStore: _TestSessionStore(),
      notificationService: _TestNotificationService(),
      widgetSnapshotService: _TestWidgetSnapshotService(),
      chaoxingClient: _WidgetHubClient(),
      clock: () => now,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    // System reminder alone must not recall past course 1:11, and global badge excludes system reminders.
    expect(
        store.termCatalog.entryFor('1:11')!.state, CourseCatalogState.archived);
    expect(store.unreadCourseNoticeCount, 2);

    await tester.pumpWidget(MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/course-hub',
        routes: [
          GoRoute(
            path: '/course-hub',
            builder: (_, state) => CourseStudyHubScreen(
              store: store,
              initialTab: state.uri.queryParameters['tab'],
              initialCourseKey: state.uri.queryParameters['courseKey'],
            ),
          ),
          GoRoute(
            path: '/assignment/:id',
            builder: (_, state) => Scaffold(
              body: Text('detail:${state.pathParameters['id']}'),
            ),
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('课程通知 (2)'), findsOneWidget);
    expect(find.text('陈老师调课通知'), findsOneWidget);
    expect(find.text('作业结束提醒'),
        findsOneWidget); // Human teacher same-title stays visible.
    expect(find.text('作业：《线性代数》第七章提交提醒'), findsNothing);
    expect(find.byKey(const ValueKey('notice-system-reminders-card')),
        findsOneWidget);
    expect(find.text('系统提醒（2）'), findsOneWidget);

    // Expand collapsed system reminders section and mark them read independently.
    await tester.ensureVisible(
      find.byKey(const ValueKey('notice-system-reminders-toggle')),
    );
    await tester.tap(
      find.byKey(const ValueKey('notice-system-reminders-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.text('作业：《线性代数》第七章提交提醒'), findsOneWidget);
    expect(store.unreadCourseNoticeCount, 2);

    await tester.tap(
      find.byKey(const ValueKey('notice-system-reminders-mark-read')),
    );
    await tester.pumpAndSettle();
    expect(store.courseNotices.systemReminderUnreadCount, 0);
    expect(store.unreadCourseNoticeCount, 2);

    // Navigate to single-course slice for 1:10 and verify strict class isolation.
    final ctx = tester.element(find.byType(CourseStudyHubScreen));
    GoRouter.of(ctx).push('/course-hub?courseKey=1:10');
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('course-hub-course-slice')), findsOneWidget);
    expect(find.textContaining('教师：陈老师'), findsOneWidget);
    expect(find.text('10班进行中作业'), findsOneWidget);
    expect(find.text('10班已完成旧作业'), findsOneWidget);
    expect(find.text('11班不应混入作业'), findsNothing);

    // Logout removes private single-course slice immediately.
    await store.logout();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-hub-course-slice')), findsNothing);
    expect(store.courseNotices.items, isEmpty);
  });
}
