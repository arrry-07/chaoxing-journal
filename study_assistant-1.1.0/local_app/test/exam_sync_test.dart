import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_exam_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';
import 'package:study_assistant_mobile/src/models/course_term_preferences.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/models/sync_scope.dart';
import 'package:study_assistant_mobile/src/services/assignment_web_link.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
import 'ai_practice_client_test.dart' show AiFixture;

const course =
    ChaoxingCourseRef(courseId: '7', clazzId: '11', courseName: '合成课程');
const phoneEmpty =
    '<div class="ybox"><p class="blankTips">您好，本课程下暂未收到考试</p></div>';
String phoneRow(String state,
        {String id = '99', String courseId = '7', bool more = false}) =>
    '<table class="listTable"><tr data="/exam/phone/task-exam?courseId=$courseId&amp;classId=11&amp;taskrefId=$id"><td>合成考试</td><td>不得保留成绩</td><td>$state</td><td></td></tr></table><script>var havemore=$more;</script>';
String pcRow(
        {String end = '2030-04-02 10:00',
        String start = '2030-04-01 09:00',
        String courseId = '7',
        String examId = '99',
        int total = 1}) =>
    '''<input id="courseId" value="$courseId"><input id="classId" value="11"><ul><li class="lookLi"><div class="titTxt"><p><a title="合成考试" onclick="show(0)">合成考试</a></p><span>$start 至 $end</span><span><strong>已完成<strong onclick="goTest('$courseId','$examId','2','2030','3','0','secret')">不得保留成绩</strong></strong></span></div></li></ul><script>page.showPage(0/9+1,Math.ceil($total/9),"changePage");</script>''';
String notViewablePcRow() =>
    '''<input id="courseId" value="7"><input id="classId" value="11"><ul><li class="lookLi"><div class="titTxt"><p><a title="合成考试" onclick="WAY.box.show({'divid':'notAllowLookPaperWin'});">合成考试</a></p><span>2030-04-01 09:00 至 2030-04-02 10:00</span><span><strong>已完成</strong></span></div><div class="titOper"><span>查看</span></div></li></ul><script>page.showPage(0/9+1,Math.ceil(1/9),"changePage");</script>''';
const accountEmpty =
    '<table class="dataTable"><tr><th>考试名称</th><th>作答状态</th></tr></table><script>page.showPage(0/12+1,Math.ceil(0/12));</script>';

String accountGoRow({
  required String title,
  required String time,
  String courseId = '7',
  String clazzId = '11',
  String examId = '99',
  String personal = '未交',
}) {
  final refer = Uri.encodeComponent(
      '/exam-ans/exam/test/examcode/examnotes?courseId=$courseId&classId=$clazzId&examId=$examId');
  return '''
<table class="dataTable">
  <tr><th>序号</th><th>考试名称</th><th>时间</th><th>时长</th><th>考试状态</th><th>作答状态</th><th>分数</th><th>方式</th><th>操作</th></tr>
  <tr class="dataTr">
    <td>1</td><td>$title</td><td>$time</td><td>100</td><td>已过期</td><td>$personal</td><td>--</td><td>线上</td>
    <td><a href="javascript:;" onclick="go('https://mooc1-api.chaoxing.com/exam-ans/mycourse/transfer?moocId=$courseId&amp;clazzid=$clazzId&amp;refer=$refer', stopExam)">查看</a></td>
  </tr>
</table>
<script>page.showPage(0/12+1,Math.ceil(1/12));</script>
''';
}

class ExamFixture {
  Dio? legacy;
  bool emptyPhone = false;
  bool redirectedMiddle = false, compoundNotice = false;
  String? unsignedCoursePage;
  bool vueExamRedirect = false;
  int middleReads = 0;
  String redirectedClass = '11';
  String redirectedExtras = '';
  String pcMetadata = '';
  List<Map<String, dynamic>>? noticeRows;
  int examHttp = 200;
  int courseCount = 1;
  bool phoneTimeout = false, pcTimeout = false, phoneSecondPageFails = false;
  String? examRetryAfter, verificationPath;
  bool phoneSecondPageMalformed = false;
  int formalHttp = 200;
  bool partialPc = false;
  bool notViewablePc = false;
  int extraPhoneExams = 0;
  bool badPc = false, repeatPhone = false, unsafeRedirect = false;
  String phoneState = '完成';
  String accountHtml = accountEmpty;
  Completer<void>? gate;
  final started = Completer<void>();
  final requests = <RequestOptions>[];
  late final Dio dio = Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      requests.add(o);
      dynamic body = '';
      var status = 200;
      final headers = <String, List<String>>{};
      if (o.uri.path == verificationPath) {
        h.resolve(Response(
          requestOptions: o,
          statusCode: 200,
          data: '<html><p>请完成安全验证</p></html>',
        ));
        return;
      }
      switch (o.uri.path) {
        case '/mycourse/backclazzdata':
          if (legacy != null) {
            h.resolve(await legacy!.fetch<dynamic>(o));
            return;
          }
          body = {
            'courses': [
              for (var i = 7; i < 7 + courseCount; i++)
                {'courseId': '$i', 'clazzId': '11', 'courseName': '合成课程'}
            ]
          };
        case '/visit/stucoursemiddle':
          body =
              '<input id="workEnc" value="synthetic"><input id="examEnc" value="synthetic">';
          middleReads++;
          if (unsignedCoursePage != null) body = unsignedCoursePage;
          // Force the exam reader to revisit the entry in redirect scenarios;
          // a complete first credential page is legitimately shared in-sync.
          if (redirectedMiddle && middleReads == 1) {
            body = '<input id="workEnc" value="synthetic">';
          }
          if (redirectedMiddle && middleReads > 1) {
            status = 302;
            headers['location'] = [
              'https://mooc2-ans.chaoxing.com${vueExamRedirect ? '/mooc2-ans-vue/fanyav3/stu' : '/mooc2-ans/mycourse/stu'}?courseid=7&clazzid=$redirectedClass$redirectedExtras'
            ];
          }
        case '/mooc2-ans/mycourse/stu':
          body =
              '<input id="workEnc" value="synthetic"><input id="examEnc" value="synthetic">';
        case '/mooc2-ans-vue/fanyav3/stu':
          body = '<main>新版课程</main>';
        case '/mooc-ans/work/api/task':
          if (unsignedCoursePage != null) {
            body = {'status': true, 'total': 0, 'data': []};
          }
        case '/mooc2/work/list':
          if (legacy != null) {
            h.resolve(await legacy!.fetch<dynamic>(o));
            return;
          }
          body = '<div>暂无作业</div>';
          status = formalHttp;
        case '/phone/moocAnalysis/examList':
        case '/mooc-ans/phone/moocAnalysis/examList':
          if (gate != null) {
            if (!started.isCompleted) started.complete();
            await gate!.future;
          }
          if (phoneTimeout) {
            h.reject(DioException(
                requestOptions: o, type: DioExceptionType.connectionTimeout));
            return;
          }
          if (examRetryAfter != null) {
            headers['retry-after'] = [examRetryAfter!];
          }
          status = phoneSecondPageFails && o.method == 'POST' ? 500 : examHttp;
          final courseId = o.uri.queryParameters['courseId'] ?? '7';
          body = emptyPhone
              ? phoneEmpty
              : [
                  phoneRow(phoneState,
                      courseId: courseId,
                      more: repeatPhone ||
                          phoneSecondPageFails ||
                          phoneSecondPageMalformed),
                  for (var i = 0; i < extraPhoneExams; i++)
                    phoneRow('未开始', id: '${100 + i}'),
                ].join();
          if (phoneSecondPageMalformed && o.method == 'POST') {
            body = '<html>无法识别的列表</html>';
          }
          if (unsafeRedirect) {
            status = 302;
            headers['location'] = [
              'https://mooc1.chaoxing.com/exam/test/testStart'
            ];
          }
        case '/exam/test':
          if (pcTimeout) {
            h.reject(DioException(
                requestOptions: o, type: DioExceptionType.connectionTimeout));
            return;
          }
          body = badPc
              ? '<unknown>'
              : notViewablePc
                  ? notViewablePcRow()
                  : pcRow(courseId: o.uri.queryParameters['courseId']!) +
                      pcMetadata;
          if (partialPc) {
            if (o.uri.queryParameters['start'] == '0') {
              body = [
                for (var i = 0; i < 9; i++)
                  pcRow(total: 10).replaceAll("'99'", "'${100 + i}'")
              ].join();
            } else {
              status = 403;
              body = 'unavailable';
            }
          }
        case '/exam-ans/exam/test/examcode/examlist':
          body = accountHtml;
        case '/work/task':
          body = '作答时间：2026-01-01 00:00 至 2026-01-01 00:30';
        case '/pc/notice/getNoticeList':
          expect(o.method, 'POST');
          body = (o.data as Map)['lastValue'] == ''
              ? {
                  'status': true,
                  'notices': {
                    'lastGetId': 'cursor',
                    'list': noticeRows ??
                        [
                          {
                            'uuid': compoundNotice
                                ? 'synthetic-notice:opaque-resource'
                                : 'notice-1',
                            'title': '考试安排通知',
                            'content': '请核对考试地点',
                            'sendTime': '2030-04-01',
                            'completeTime': '2030-04-02'
                          },
                          {'uuid': 'notice-2', 'title': '普通通知', 'content': '欢迎'}
                        ]
                  }
                }
              : {'status': true};
        default:
          if (legacy != null) {
            h.resolve(await legacy!.fetch<dynamic>(o));
            return;
          }
          throw StateError('unexpected route ${o.uri.path}');
      }
      h.resolve(Response(
          requestOptions: o,
          data: body,
          statusCode: status,
          headers: Headers.fromMap(headers)));
    }));
  ChaoxingLocalClient client() => ChaoxingLocalClient(
      dio: dio, enableClassroomTasks: false, wait: (_) async {});
}

void main() {
  test(
      'account evidence fills same-identity exam times without replacing status',
      () async {
    final f = ExamFixture()
      ..phoneState = '已过期'
      ..badPc = true
      ..accountHtml = accountGoRow(
        title: '新建试卷20260609191916',
        time: '2026-06-09 21:30 至 2026-06-09 23:10',
      );
    final c = f.client();
    final rows = await c.fetchAssignments();
    final examRows =
        rows.where((a) => a.isExam && !a.exam!.noticeOnly).toList();
    expect(examRows, hasLength(1));
    final exam = examRows.single;
    expect(exam.id, 'cx:exam:7:11:99');
    expect(exam.courseName, '合成课程');
    expect(exam.title, '合成考试');
    expect(exam.status, 'pending');
    expect(exam.exam!.lifecycle, 'ended');
    expect(exam.exam!.startAt!.toUtc(), DateTime.utc(2026, 6, 9, 13, 30));
    expect(exam.exam!.endAt!.toUtc(), DateTime.utc(2026, 6, 9, 15, 10));
    expect(exam.exam!.startTrusted, isTrue);
    expect(exam.exam!.endTrusted, isTrue);
    expect(AssignmentQuery.currentDisplay([exam], DateTime.utc(2026, 11, 20)),
        isEmpty);
    final account =
        c.sourceResults.singleWhere((s) => s.source == 'examAccount');
    expect(account.phase, SyncSourcePhase.success);
    expect(account.recordCount, 1);
  });

  test('verified course middle redirect preserves exam time collection',
      () async {
    final f = ExamFixture()..redirectedMiddle = true;
    final c = f.client();
    final rows = await c.fetchAssignments();
    expect(
        rows.firstWhere((a) => a.isExam && !a.exam!.noticeOnly).timelineTrusted,
        isTrue);
    expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.success);
  });
  test('compound notice UUID remains a stable portable identity', () async {
    final f = ExamFixture()..compoundNotice = true;
    final c = f.client();
    final rows = await c.fetchAssignments();
    expect(rows.where((a) => a.exam!.noticeOnly).length, 1);
    final notice = rows.firstWhere((a) => a.exam!.noticeOnly);
    expect(notice.hasExamIdentity, isTrue);
    expect(notice.exam!.examId, isNot(contains(':')));
    expect(Assignment.fromJson(notice.toJson()).hasExamIdentity, isTrue);
    expect(c.sourceResults.firstWhere((s) => s.source == 'examNotice').phase,
        SyncSourcePhase.success);
  });
  test('course middle redirect cannot substitute another class identity',
      () async {
    final f = ExamFixture()
      ..redirectedMiddle = true
      ..redirectedClass = '12';
    final c = f.client();
    await c.fetchAssignments();
    expect(f.requests.any((r) => r.uri.path == '/mooc2-ans/mycourse/stu'),
        isFalse);
    expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.partial);
  });
  test('notice identity depends on the whole opaque resource UUID, never title',
      () {
    Map<String, dynamic> payload(String id, String title) => {
          'status': true,
          'notices': {
            'list': [
              {'uuid': id, 'title': title}
            ]
          }
        };
    final a = ChaoxingExamParser.notices(payload('synthetic:1', '考试原通知'))!
        .rows
        .single;
    final b = ChaoxingExamParser.notices(payload('synthetic:1', '考试改期通知'))!
        .rows
        .single;
    final c = ChaoxingExamParser.notices(payload('synthetic:2', '考试原通知'))!
        .rows
        .single;
    expect(a.id, b.id);
    expect(a.id, isNot(c.id));
    expect(
        ChaoxingExamParser.notices(payload('bad\nidentity', '考试通知')), isNull);
  });
  test('redirect checks every repeated and aliased identity parameter',
      () async {
    for (final extra in ['&classId=12', '&clazzid=12', '&courseId=8']) {
      final f = ExamFixture()
        ..redirectedMiddle = true
        ..redirectedExtras = extra;
      final c = f.client();
      await c.fetchAssignments();
      expect(f.requests.any((r) => r.uri.path == '/mooc2-ans/mycourse/stu'),
          isFalse);
      expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
          SyncSourcePhase.partial);
    }
  });
  test('unrelated notice with unavailable UUID does not erase exam candidates',
      () {
    final parsed = ChaoxingExamParser.notices({
      'status': true,
      'notices': {
        'list': [
          {'uuid': null, 'title': '普通通知'},
          {'uuid': 'opaque:exam', 'title': '考试通知'}
        ]
      }
    });
    expect(parsed!.rows.length, 1);
    expect(parsed.rows.single.hasExamIdentity, isTrue);
  });
  test(
      'formal failure cannot discard successful exam observations in full or course refresh',
      () async {
    for (final single in [false, true]) {
      final f = ExamFixture()..formalHttp = 403;
      final c = f.client();
      final rows = single
          ? await c.fetchAssignmentsForCourse(courseId: '7', clazzId: '11')
          : await c.fetchAssignments();
      expect(rows.any((a) => a.isExam && !a.exam!.noticeOnly), isTrue);
    }
  });
  test('failed formal lists are not described as already read at exam stage',
      () async {
    final f = ExamFixture()..formalHttp = 403;
    final c = f.client();
    AssignmentSyncProgress? examStage;
    c.onProgress = (progress) {
      if (progress.stage == AssignmentSyncStage.exams) examStage = progress;
    };
    await c.fetchAssignments();
    expect(examStage, isNotNull);
    expect(examStage!.workListFailureCount, greaterThan(0));
    expect(examStage!.stageLabel, contains('部分课程作业未更新'));
    expect(examStage!.stageLabel, isNot(contains('作业已读取')));
  });
  test('PC partial pagination preserves parsed first page when the next fails',
      () async {
    final f = ExamFixture()
      ..emptyPhone = true
      ..partialPc = true;
    final c = f.client();
    final rows = await c.fetchAssignments();
    expect(rows.where((a) => a.isExam && !a.exam!.noticeOnly).length, 9);
    expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.partial);
  });
  test('failed PC time evidence retains historical times with trust revoked',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    final old = ChaoxingExamParser.make(
        id: '99',
        title: '考试',
        courseId: '7',
        clazzId: '11',
        status: 'pending',
        start: DateTime.utc(2030, 1, 1, 1),
        end: DateTime.utc(2030, 1, 1, 3),
        now: DateTime.utc(2029));
    await repo.mergeAndSave([old]);
    final phone = ChaoxingExamParser.phone(phoneRow('未开始'), course,
            now: DateTime.utc(2029, 2))!
        .rows
        .single;
    await repo.mergeAndSave([phone]);
    final saved = (await repo.loadJournal()).single;
    expect(saved.exam!.startAt!.toUtc(), old.exam!.startAt!.toUtc());
    expect(saved.exam!.endAt!.toUtc(), old.exam!.endAt!.toUtc());
    expect(saved.exam!.startTrusted, isFalse);
    expect(saved.exam!.endTrusted, isFalse);
    expect(saved.status, 'pending');
    expect(saved.reminderAnchorAt, isNull);
  });
  test(
      'phone accepts stable identity and explicit completion without retaining grades',
      () {
    final a = ChaoxingExamParser.phone(phoneRow('完成'), course)!.rows.single;
    expect(a.id, 'cx:exam:7:11:99');
    expect(a.isCompleted, isTrue);
    expect(a.toJson().toString(), isNot(contains('不得保留成绩')));
    expect(ChaoxingExamParser.phone(phoneRow('完成', courseId: '8'), course),
        isNull);
    expect(ChaoxingExamParser.phone('<html>unknown</html>', course), isNull);
    expect(ChaoxingExamParser.phone(phoneEmpty, course)!.rows, isEmpty);
  });
  test(
      'ended does not imply personal completion; unknown states remain unknown',
      () {
    for (final state in ['已结束', '4', '任意状态']) {
      final a = ChaoxingExamParser.phone(phoneRow(state), course)!.rows.single;
      expect(a.isCompleted, isFalse);
      expect(a.status, 'unknown');
    }
    expect(ChaoxingExamParser.personalStatus('未开始'), 'pending');
  });
  test('PC absolute times use China timezone and require matching identities',
      () {
    final a = ChaoxingExamParser.coursePc(pcRow(), course)!.rows.single;
    expect(a.exam!.startAt!.toUtc(), DateTime.utc(2030, 4, 1, 1));
    expect(a.exam!.endAt!.toUtc(), DateTime.utc(2030, 4, 2, 2));
    expect(a.timelineAt, a.exam!.startAt);
    expect(
        ChaoxingExamParser.coursePc(pcRow().replaceAll("'", '&#x27;'), course)!
            .rows
            .single
            .hasExamIdentity,
        isTrue);
    expect(a.deadlineAt, a.exam!.endAt);
    final notViewable =
        ChaoxingExamParser.coursePc(notViewablePcRow(), course)!;
    expect(notViewable.rows, isEmpty);
    expect(notViewable.skipped, 1);
    expect(notViewable.observed, 1);
    expect(ChaoxingExamParser.coursePc(pcRow(courseId: '8'), course), isNull);
    expect(
        ChaoxingExamParser.coursePc(pcRow(end: '2029-04-01 01:00'), course)!
            .rows
            .single
            .exam!
            .startTrusted,
        isFalse);
    expect(ChaoxingExamParser.chinaTime('2030-02-31 12:00'), isNull);
  });
  test(
      'notifications remain separate uncertain notices and never use publication dates',
      () {
    final parsed = ChaoxingExamParser.notices({
      'status': true,
      'notices': {
        'lastGetId': 1,
        'list': [
          {
            'uuid': 'notice-1',
            'title': '考试安排',
            'content': '内容',
            'sendTime': '2030-01-01',
            'completeTime': '2030-02-01'
          }
        ]
      }
    })!;
    expect(parsed.rows.single.exam!.noticeOnly, isTrue);
    expect(parsed.rows.single.timelineAt, isNull);
    expect(parsed.rows.single.deadlineAt, isNull);
    expect(parsed.rows.single.reminderAnchorAt, isNull);
    expect(ChaoxingExamParser.notices({'status': true})!.rows, isEmpty);
    expect(ChaoxingExamParser.notices({'status': false}), isNull);
  });
  test('normal full sync includes exams, notices and source coverage',
      () async {
    final f = ExamFixture();
    final client = f.client();
    final rows = await client.fetchAssignments();
    expect(rows.length, 2);
    expect(
        rows.where((a) => !a.exam!.noticeOnly).single.timelineTrusted, isTrue);
    expect(
        client.sourceResults.where((s) => s.phase != SyncSourcePhase.success),
        isEmpty);
    expect(
        f.requests.any(
            (r) => RegExp('testStart|lookPaper|submit').hasMatch(r.uri.path)),
        isFalse);
  });
  test('phone circuit protects prior exams and resets on the next refresh',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    final f = ExamFixture()
      ..courseCount = 3
      ..phoneTimeout = true;
    final client = f.client();
    final old = [
      for (final (id, status) in [('7', 'submitted'), ('9', 'pending')])
        ChaoxingExamParser.make(
          id: '99',
          title: '旧考试',
          courseId: id,
          clazzId: '11',
          status: status,
          now: DateTime.utc(2026, 11, 1),
        ).copyWith(
            completedAt:
                status == 'submitted' ? DateTime.utc(2026, 11, 1) : null),
    ];
    await repo.mergeAndSave(old);
    client.previousAssignments = {for (final a in old) a.id: a};

    final first = await client.fetchAssignments();
    expect(first.where((a) => !a.exam!.noticeOnly), isEmpty);
    await repo.mergeAndSave(first, completeSync: false);
    final retained = {for (final a in await repo.loadJournal()) a.id: a};
    for (final previous in old) {
      final saved = retained[previous.id]!;
      expect(saved.status, previous.status);
      expect(saved.lastSyncedAt.toUtc(), previous.lastSyncedAt.toUtc());
      expect(saved.completedAt?.toUtc(), previous.completedAt?.toUtc());
    }
    expect(
        f.requests
            .where((r) => r.uri.path.endsWith('/examList'))
            .map((r) => r.uri.queryParameters['courseId']),
        ['7', '7']);
    final failures = client.issues.where((i) => i.stage == 'exam').toList();
    expect(failures, hasLength(1));
    expect(failures.single.circuitOpen, isTrue);
    final source = client.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(source.failedCourses, 3);
    expect(source.reasonCodes,
        containsAll(['examPhoneListFailed', 'examCircuitPaused']));

    f.phoneTimeout = false;
    f.requests.clear();
    final recovered = await client.fetchAssignments();
    expect(
        recovered.singleWhere((a) => a.id == old.last.id).status, 'submitted');
    expect(
        f.requests
            .where((r) => r.uri.path.endsWith('/examList'))
            .map((r) => r.uri.queryParameters['courseId']),
        ['7', '8', '9']);
    expect(client.issues.where((i) => i.circuitOpen), isEmpty);
  });

  test('PC supplement circuit does not block the next phone course', () async {
    final f = ExamFixture()
      ..courseCount = 2
      ..pcTimeout = true;
    final c = f.client();
    final rows = await c.fetchAssignments();
    expect(rows.where((a) => !a.exam!.noticeOnly).map((a) => a.courseId),
        unorderedEquals(['7', '8']));
    expect(f.requests.where((r) => r.uri.path == '/exam/test'), hasLength(2));
    expect(f.requests.where((r) => r.uri.path.endsWith('/examList')),
        hasLength(2));
    final exam = c.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(exam.recordCount, 2);
    expect(
        exam.reasonCodes,
        containsAll([
          'examPcSupplementUnavailable',
          'examPcListFailed',
          'examCircuitPaused'
        ]));
    expect(exam.reasonCodes, isNot(contains('examPhoneListFailed')));
  });

  test('phone pagination failure retains its first page and phase', () async {
    final f = ExamFixture()..phoneSecondPageFails = true;
    final c = f.client();
    final rows = await c.fetchAssignments();
    expect(rows.where((a) => !a.exam!.noticeOnly), hasLength(1));
    expect(f.requests.where((r) => r.uri.path == '/exam/test'), isEmpty);
    final exam = c.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(exam.reasonCodes, contains('examPhoneListFailed'));
    expect(exam.reasonCodes, isNot(contains('examPcSupplementUnavailable')));
  });

  for (final phase in ['phone-page', 'phone-schema', 'pc-supplement']) {
    test('an unread exam after $phase failure remains in the journal',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalAssignmentRepository();
      final f = ExamFixture()
        ..phoneSecondPageFails = phase == 'phone-page'
        ..phoneSecondPageMalformed = phase == 'phone-schema'
        ..pcTimeout = phase == 'pc-supplement';
      final client = f.client();
      final completedAt = DateTime.utc(2026, 11, 1);
      final old = ChaoxingExamParser.make(
        id: '101',
        title: '旧考试',
        courseId: '7',
        clazzId: '11',
        status: 'submitted',
        now: completedAt,
      ).copyWith(completedAt: completedAt);
      await repo.mergeAndSave([old]);
      client.previousAssignments = {old.id: old};
      final incoming = await client.fetchAssignments();
      expect(incoming.where((row) => row.id == old.id), isEmpty);
      expect(incoming.any((row) => row.exam!.examId == '99'), isTrue);
      await repo.mergeAndSave(incoming, completeSync: false);
      final retained =
          (await repo.loadJournal()).singleWhere((row) => row.id == old.id);
      expect(retained.status, 'submitted');
      expect(retained.completedAt?.toUtc(), completedAt);
      expect(retained.lastSyncedAt.toUtc(), completedAt);
    });
  }

  for (final (route, stage) in [
    ('/phone/moocAnalysis/examList', 'exam'),
    ('/exam-ans/exam/test/examcode/examlist', 'examAccount'),
  ]) {
    test('verification in $stage stops later exam and notice sources',
        () async {
      final f = ExamFixture()..verificationPath = route;
      final client = f.client();
      final rows =
          await client.fetchAssignmentsWithOptions(collectCourseNotices: true);
      expect(f.requests.last.uri.path, route);
      expect(rows.any((row) => row.exam!.noticeOnly), isFalse);
      expect(rows.isNotEmpty, stage == 'examAccount');
      final issue = client.issues
          .singleWhere((i) => i.kind == SyncIssueKind.verificationRequired);
      expect(issue.stage, stage);
      final paused = client.sourceResults
          .where((s) => s.reasonCodes.contains('verificationPaused'));
      expect(paused.map((s) => s.source),
          containsAll(['examNotice', 'courseNotice']));
      expect(paused.every((s) => s.phase == SyncSourcePhase.failed), isTrue);
    });
  }

  test('account verification preserves unread exams with course identity',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    final f = ExamFixture()
      ..verificationPath = '/exam-ans/exam/test/examcode/examlist';
    final client = f.client();
    final stored = ChaoxingExamParser.make(
      id: '105',
      title: '账号考试',
      courseId: '22',
      clazzId: '33',
      status: 'submitted',
      now: DateTime.utc(2026, 11, 1),
    );
    await repo.mergeAndSave([stored]);
    client.previousAssignments = {stored.id: stored};
    final rows = await client.fetchAssignments();
    expect(rows.map((row) => row.id), isNot(contains(stored.id)));
    await repo.mergeAndSave(rows, completeSync: false);
    final old =
        (await repo.loadJournal()).singleWhere((row) => row.id == stored.id);
    expect(old.status, 'submitted');
    expect(old.lastSyncedAt.toUtc(), stored.lastSyncedAt.toUtc());
    expect(old.courseKey, '22:33');
  });

  test('single course verification stops classroom and exam requests',
      () async {
    final f = ExamFixture()..verificationPath = '/mooc2/work/list';
    final client = ChaoxingLocalClient(dio: f.dio, wait: (_) async {});
    await expectLater(
        client.fetchAssignmentsForCourse(courseId: '7', clazzId: '11'),
        throwsA(isA<SyncReadException>().having(
            (e) => e.issue.kind, 'kind', SyncIssueKind.verificationRequired)));
    expect(f.requests.last.uri.path, f.verificationPath);
    expect(client.sourceResults.map((s) => s.source),
        containsAll(['courseWork', 'classroomActivity:35', 'exam']));
  });

  test('exam rate limit retains Retry-After and isolation metadata', () async {
    final f = ExamFixture()
      ..examHttp = 429
      ..examRetryAfter = '3';
    final c = f.client();
    await c.fetchAssignments();
    final issue = c.issues.singleWhere((i) => i.stage == 'exam');
    expect(issue.kind, SyncIssueKind.rateLimited);
    expect(issue.httpStatus, 429);
    expect(issue.retryAfter, '3');
    expect(issue.retryAfterSeconds, 3);
    expect(issue.circuitOpen, isFalse);
  });

  test('empty phone list still reads independent PC course exams', () async {
    final f = ExamFixture()..emptyPhone = true;
    final rows = await f.client().fetchAssignments();
    expect(rows.where((a) => a.isExam && !a.exam!.noticeOnly).length, 1);
    expect(f.middleReads, 1);
  });
  test('skipped PC supplement preserves the prior exam observation', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    final f = ExamFixture()
      ..unsignedCoursePage = '<main>课程入口</main>'
      ..emptyPhone = true;
    final client = f.client();
    final completion = DateTime.utc(2026, 10, 1, 5);
    final old = ChaoxingExamParser.make(
      id: '99',
      title: '往期考试',
      courseId: '7',
      clazzId: '11',
      status: 'submitted',
      now: DateTime.utc(2026, 10, 2),
    ).copyWith(completedAt: completion);
    await repo.mergeAndSave([old]);
    client.previousAssignments = {old.id: old};

    final rows = await client.fetchAssignments();
    expect(rows.where((row) => row.id == old.id), isEmpty);
    await repo.mergeAndSave(rows, completeSync: false);
    final retained =
        (await repo.loadJournal()).singleWhere((row) => row.id == old.id);
    expect(retained.status, old.status);
    expect(retained.completedAt!.toUtc(), completion);
    expect(retained.lastSyncedAt.toUtc(), old.lastSyncedAt.toUtc());
    expect(f.middleReads, 1);
    final source = client.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(source.phase, SyncSourcePhase.success);
    expect(source.isNormalDegradation, isTrue);
    expect(source.reasonCodes, contains('examPcSupplementUnavailable'));
    expect(client.issues, isEmpty);
    expect(client.lastSyncWarning, isNull);
  });
  test('empty phone list does not probe for a missing PC credential', () async {
    final f = ExamFixture()
      ..unsignedCoursePage = '<main>课程入口</main>'
      ..emptyPhone = true;
    final client = f.client();
    final rows = await client.fetchAssignments();
    expect(rows.where((a) => a.isExam && !a.exam!.noticeOnly), isEmpty);
    expect(f.middleReads, 1);
    expect(f.requests.where((r) => r.uri.path == '/exam/test'), isEmpty);
    final source = client.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(source.phase, SyncSourcePhase.success);
    expect(source.succeededCourses, 1);
    expect(source.failedCourses, 0);
    expect(
        client.sourceResults.singleWhere((s) => s.source == 'courseWork').phase,
        SyncSourcePhase.success);
  });
  test('an explicit course access denial stops the homework fallback',
      () async {
    final f = ExamFixture()
      ..unsignedCoursePage = '<main>没有此页面访问权限</main>'
      ..emptyPhone = true;
    final client = f.client();
    await client.fetchAssignments();
    expect(f.requests.where((r) => r.uri.path == '/mooc-ans/work/api/task'),
        isEmpty);
    final issue = client.issues.singleWhere((i) => i.stage == 'coursePage');
    expect(issue.kind, SyncIssueKind.forbidden);
    expect(issue.courseKey, '7:11');
  });
  test('validated Vue redirect retains phone exam without a PC credential',
      () async {
    final f = ExamFixture()
      ..redirectedMiddle = true
      ..vueExamRedirect = true;
    final client = f.client();
    final rows = await client.fetchAssignments();
    final exam = rows.singleWhere((a) => a.isExam && !a.exam!.noticeOnly);
    expect(exam.exam!.examId, '99');
    expect(exam.isCompleted, isTrue);
    expect(exam.timelineTrusted, isFalse);
    expect(f.requests.where((r) => r.uri.path == '/mooc2-ans-vue/fanyav3/stu'),
        hasLength(1));
    expect(client.issues.where((i) => i.stage == 'exam'), isEmpty);
    expect(client.lastSyncWarning, isNull);
    final source = client.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(source.phase, SyncSourcePhase.success);
    expect(source.isNormalDegradation, isTrue);
    expect(source.succeededCourses, 1);
    expect(source.failedCourses, 0);
    expect(source.reasonCodes, ['examPcSupplementUnavailable']);
  });
  test('Vue redirects still require the exact class identity', () async {
    final f = ExamFixture()
      ..redirectedMiddle = true
      ..vueExamRedirect = true
      ..redirectedClass = '12';
    final client = f.client();
    await client.fetchAssignments();
    expect(f.requests.where((r) => r.uri.path == '/mooc2-ans-vue/fanyav3/stu'),
        isEmpty);
    expect(client.issues.where((i) => i.stage == 'exam'), isNotEmpty);
  });
  test('non-viewable completed PC row never fails a successful phone list',
      () async {
    final f = ExamFixture()..notViewablePc = true;
    final client = f.client();
    final rows = await client.fetchAssignments();

    expect(rows.where((a) => a.isExam && !a.exam!.noticeOnly), hasLength(1));
    expect(client.issues.where((issue) => issue.stage == 'exam'), isEmpty);
    expect(
        client.sourceResults
            .singleWhere((source) => source.source == 'exam')
            .phase,
        SyncSourcePhase.success);
  });
  test('non-viewable PC row without a phone identity stays a visible failure',
      () async {
    final f = ExamFixture()
      ..emptyPhone = true
      ..notViewablePc = true;
    final client = f.client();
    await client.fetchAssignments();

    expect(
        client.sourceResults
            .singleWhere((source) => source.source == 'exam')
            .phase,
        SyncSourcePhase.failed);
    expect(
        client.issues.any((issue) =>
            issue.stage == 'exam' &&
            issue.message.contains('examPcUnreadable')),
        isTrue);
  });
  test('non-viewable PC row only explains one missing phone identity',
      () async {
    final f = ExamFixture()
      ..notViewablePc = true
      ..extraPhoneExams = 1;
    final client = f.client();
    await client.fetchAssignments();

    expect(
        client.sourceResults
            .singleWhere((source) => source.source == 'exam')
            .phase,
        SyncSourcePhase.partial);
    expect(
        client.issues.any((issue) =>
            issue.stage == 'exam' &&
            issue.message.contains('examListDisagreement')),
        isTrue);
  });
  test('background window ending before exam reads preserves formal work',
      () async {
    final ai = AiFixture()..mixed = true;
    final f = ExamFixture()..legacy = ai.dio;
    final c = f.client();
    c.shouldStop =
        () => f.requests.any((r) => r.uri.path == '/mooc2/work/list');
    final rows = await c.fetchAssignments();
    expect(rows.where((a) => a.isFormal).length, 1);
    expect(f.requests.any((r) => r.uri.path.contains('examList')), isFalse);
    expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.failed);
    expect(c.lastSyncWarning, isNotNull);
  });
  test('default full sync preserves formal, 35, 42 and 77 alongside exams',
      () async {
    final ai = AiFixture()..mixed = true;
    final f = ExamFixture()..legacy = ai.dio;
    final c = ChaoxingLocalClient(dio: f.dio);
    final rows = await c.fetchAssignments();
    expect(rows.length, 6);
    expect(rows.where((a) => a.isFormal).length, 1);
    expect(
        rows
            .where((a) => a.isSupportedClassroomTask)
            .map((a) => a.activityType)
            .toSet(),
        {35, 42, 77});
    expect(rows.where((a) => a.isExam).length, 2);
    expect(
        c.sourceResults
            .where((s) => s.source != 'groupHistory')
            .every((s) => s.phase == SyncSourcePhase.success),
        isTrue);
  });
  test(
      'supplemental time failure preserves phone personal evidence and marks partial',
      () async {
    final f = ExamFixture()..badPc = true;
    final c = f.client();
    final rows = await c.fetchAssignments();
    expect(rows.first.isCompleted, isTrue);
    expect(rows.first.timelineTrusted, isFalse);
    expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.partial);
  });
  test(
      'failed exam source retains prior identity as unknown and other notices survive',
      () async {
    final f = ExamFixture()..examHttp = 403;
    final c = f.client();
    final old = ChaoxingExamParser.make(
        id: '99',
        title: '旧考试',
        courseId: '7',
        clazzId: '11',
        status: 'pending',
        start: DateTime(2030));
    c.previousAssignments = {old.id: old};
    final rows = await c.fetchAssignments();
    expect(rows.firstWhere((a) => a.id == old.id).status, 'unknown');
    expect(rows.any((a) => a.exam!.noticeOnly), isTrue);
  });
  test(
      'repeating pages and redirects to exam start fail without unsafe request',
      () async {
    for (final redirect in [false, true]) {
      final f = ExamFixture()
        ..repeatPhone = !redirect
        ..unsafeRedirect = redirect;
      final c = f.client();
      await c.fetchAssignments();
      expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
          isNot(SyncSourcePhase.success));
      expect(f.requests.any((r) => r.uri.path.endsWith('testStart')), isFalse);
    }
  });
  test('cancel and changed session reject late exam observations', () async {
    for (final cancel in [false, true]) {
      final f = ExamFixture()..gate = Completer<void>();
      final c = f.client();
      final future = c.fetchAssignments();
      await f.started.future;
      if (cancel) {
        c.cancelActiveRequests();
      } else {
        c.clearSession();
      }
      f.gate!.complete();
      if (cancel) {
        await expectLater(future, throwsA(isA<SyncReadException>()));
      } else {
        expect(await future, isEmpty);
      }
    }
  });
  test(
      'journal reopens exams only with current personal evidence and preserves hidden IDs',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    final a = ChaoxingExamParser.make(
        id: '99',
        title: '考试',
        courseId: '7',
        clazzId: '11',
        status: 'submitted',
        now: DateTime(2030));
    await repo.mergeAndSave([a]);
    await repo.mergeAndSave(
        [a.copyWith(status: 'unknown', lastSyncedAt: DateTime(2030, 1, 2))]);
    final all = await repo.loadJournal();
    expect(all.single.status, 'unknown');
  });
  test('cached exam links only allow exact list entry', () {
    final a = ChaoxingExamParser.make(
        id: '99', title: '考试', courseId: '7', clazzId: '11', status: 'pending');
    expect(AssignmentWebLink.validatedUrl(a), a.submitUrl);
    expect(
        AssignmentWebLink.validatedUrl(a.copyWith(
            submitUrl: 'https://mooc1.chaoxing.com/exam/test/testStart')),
        isNull);
    final restored = Assignment.fromJson(a.toJson());
    expect(restored.hasExamIdentity, isTrue);
  });

  test(
      'empty phone list reads PC-only exam when redirected course entry provides examEnc',
      () async {
    final requests = <Uri>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(o.uri);
        dynamic body = '';
        var status = 200;
        final headers = <String, List<String>>{};
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '8', 'clazzId': '11', 'courseName': '仅PC考试课程'},
              ]
            };
          case '/visit/stucoursemiddle':
            status = 302;
            headers['location'] = [
              'https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu?courseid=8&clazzid=11'
            ];
          case '/mooc2-ans/mycourse/stu':
            body =
                '<input id="workEnc" value="synthetic-work"><input id="examEnc" value="pc-only-enc">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = '<p class="blankTips">您好，本课程下暂未收到考试</p>';
          case '/exam/test':
            body = pcRow(courseId: '8', examId: '801');
          case '/exam-ans/exam/test/examcode/examlist':
            body = '<table class="dataTable"><tr><th>作答状态</th></tr></table>';
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(
            requestOptions: o,
            statusCode: status,
            data: body,
            headers: Headers.fromMap(headers)));
      }));

    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    final rows = await client.fetchAssignments();
    final pcOnly = rows.singleWhere((a) => !a.exam!.noticeOnly);
    expect(pcOnly.courseId, '8');
    expect(pcOnly.exam!.examId, '801');
    expect(pcOnly.timelineTrusted, isTrue);
    expect(requests.where((u) => u.path == '/exam/test'), hasLength(1));
    expect(requests.where((u) => u.path == '/visit/stucoursemiddle'),
        hasLength(2));
    expect(requests.where((u) => u.path == '/mooc2-ans/mycourse/stu'),
        hasLength(1));
    final examSource =
        client.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(examSource.phase, SyncSourcePhase.success);
    expect(client.issues, isEmpty);
  });

  test(
      'multi-course Vue deployment caps course entry probes and avoids request storm across refreshes',
      () async {
    final requests = <Uri>[];
    final examCourseIds = {'2', '3', '4', '5'};
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(o.uri);
        dynamic body = '';
        var status = 200;
        final headers = <String, List<String>>{};
        final courseId = o.uri.queryParameters['courseId'] ??
            o.uri.queryParameters['courseid'];
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                for (var i = 1; i <= 10; i++)
                  {'courseId': '$i', 'clazzId': '11', 'courseName': 'Vue课程$i'},
              ]
            };
          case '/visit/stucoursemiddle':
            status = 302;
            headers['location'] = [
              'https://mooc2-ans.chaoxing.com/mooc2-ans-vue/fanyav3/stu?courseid=$courseId&clazzid=11'
            ];
          case '/mooc2-ans-vue/fanyav3/stu':
            body = '<main>新版课程</main>';
          case '/mooc-ans/work/api/task':
            body = {'status': true, 'total': 0, 'data': []};
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = examCourseIds.contains(courseId)
                ? phoneRow('未开始', id: '90$courseId', courseId: courseId!)
                : phoneEmpty;
          case '/exam-ans/exam/test/examcode/examlist':
            body = accountEmpty;
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(
            requestOptions: o,
            statusCode: status,
            data: body,
            headers: Headers.fromMap(headers)));
      }));

    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    final first = await client.fetchAssignments();
    expect(first.where((a) => a.isExam && !a.exam!.noticeOnly), hasLength(4));
    final firstMiddle =
        requests.where((u) => u.path == '/visit/stucoursemiddle').toList();
    expect(firstMiddle, hasLength(3));
    expect(
        firstMiddle.map((u) => u.queryParameters['courseid']), ['1', '2', '3']);
    final firstSource =
        client.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(firstSource.phase, SyncSourcePhase.success);
    expect(firstSource.isNormalDegradation, isTrue);
    expect(firstSource.reasonCodes, contains('examPcSupplementUnavailable'));
    expect(client.issues, isEmpty);
    expect(client.lastSyncWarning, isNull);

    requests.clear();
    final second = await client.fetchAssignments();
    expect(second.where((a) => a.isExam && !a.exam!.noticeOnly), hasLength(4));
    expect(requests.where((u) => u.path == '/visit/stucoursemiddle'), isEmpty);
    final secondSource =
        client.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(secondSource.phase, SyncSourcePhase.success);
    expect(secondSource.isNormalDegradation, isTrue);
    expect(secondSource.reasonCodes, contains('examPcSupplementUnavailable'));
    expect(client.issues, isEmpty);
    expect(client.lastSyncWarning, isNull);
  });

  test(
      'PC supplement circuit preserves trusted exam schedule and recovers to success',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    final f = ExamFixture()
      ..courseCount = 2
      ..pcTimeout = true;
    final client = f.client();
    final trustedStart = DateTime.utc(2030, 6, 1, 1);
    final trustedEnd = DateTime.utc(2030, 6, 1, 3);
    final prior = ChaoxingExamParser.make(
      id: '99',
      title: '合成考试',
      courseId: '7',
      clazzId: '11',
      status: 'pending',
      start: trustedStart,
      end: trustedEnd,
      location: '原考场A101',
      now: DateTime.utc(2026, 11, 1),
    );
    await repo.mergeAndSave([prior]);
    client.previousAssignments = {prior.id: prior};

    final failedRows = await client.fetchAssignments();
    await repo.mergeAndSave(failedRows, completeSync: false);
    final retained =
        (await repo.loadJournal()).singleWhere((row) => row.id == prior.id);
    expect(retained.exam!.startAt?.toUtc(), trustedStart);
    expect(retained.exam!.endAt?.toUtc(), trustedEnd);
    expect(retained.exam!.startTrusted, isFalse);
    expect(retained.exam!.location, '原考场A101');
    expect(
        client.issues.any((i) => i.stage == 'exam' && i.circuitOpen), isTrue);
    expect(
        client.sourceResults.singleWhere((s) => s.source == 'exam').reasonCodes,
        containsAll(['examPcSupplementUnavailable', 'examCircuitPaused']));

    f.pcTimeout = false;
    final recovered = await client.fetchAssignments();
    await repo.mergeAndSave(recovered,
        completeSync: client.lastSyncWarning == null);
    expect(client.issues.where((i) => i.circuitOpen), isEmpty);
    expect(client.lastSyncWarning, isNull);
    expect(client.sourceResults.singleWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.success);
  });

  test(
      'PC-only exam is discovered when course entry redirect uses camelCase clazzId',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = '';
        var status = 200;
        final headers = <String, List<String>>{};
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程'}
              ]
            };
          case '/visit/stucoursemiddle':
            status = 302;
            headers['location'] = [
              'https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu?courseId=7&clazzId=11'
            ];
          case '/mooc2-ans/mycourse/stu':
            body =
                '<input id="workEnc" value="w"><input id="examEnc" value="synthetic">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/phone/moocAnalysis/examList':
            body = phoneEmpty;
          case '/exam/test':
            body = pcRow();
          case '/exam-ans/exam/test/examcode/examlist':
            body = accountEmpty;
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(
            requestOptions: o,
            statusCode: status,
            data: body,
            headers: Headers.fromMap(headers)));
      }));

    final client = ChaoxingLocalClient(
      dio: dio,
      enableClassroomTasks: false,
      wait: (_) async {},
    );
    final rows = await client.fetchAssignments();
    final exam = rows.singleWhere((a) => a.isExam && !a.exam!.noticeOnly);
    expect(exam.id, 'cx:exam:7:11:99');
    expect(exam.exam!.startTrusted, isTrue);
  });

  test('account exam inner refer link accepts camelCase clazzId', () {
    final refer = Uri.encodeComponent(
        '/exam-ans/exam/test/examcode/examnotes?courseId=7&clazzId=11&examId=99');
    final html = '''
<table class="dataTable">
  <tr><th>序号</th><th>考试名称</th><th>时间</th><th>时长</th><th>考试状态</th><th>作答状态</th><th>分数</th><th>方式</th><th>操作</th></tr>
  <tr class="dataTr">
    <td>1</td><td>合成账号考试</td><td>2030-04-01 09:00 至 2030-04-01 11:00</td><td>100</td><td>未开始</td><td>未交</td><td>--</td><td>线上</td>
    <td><a href="javascript:;" onclick="go('https://mooc1-api.chaoxing.com/exam-ans/mycourse/transfer?moocId=7&amp;clazzId=11&amp;refer=$refer', stopExam)">查看</a></td>
  </tr>
</table>
<script>page.showPage(0/12+1,Math.ceil(1/12));</script>
''';
    final parsed = ChaoxingExamParser.account(html)!;
    expect(parsed.rows.single.id, 'cx:exam:7:11:99');
    expect(parsed.rows.single.clazzId, '11');
  });

  test(
      'current scope preserves examAccount when all course exams are skipped, avoids downgrading cached course exams to unknown, and matches notices against full catalog',
      () async {
    final f = ExamFixture()
      ..accountHtml = accountGoRow(
        title: '全账期统考',
        time: '2030-06-09 09:00 至 2030-06-09 11:00',
        courseId: '7',
        clazzId: '11',
        examId: '701',
      )
      ..noticeRows = [
        {
          'uuid': 'n-archived-course',
          'title': '《合成课程》往期补考提醒',
          'content': '课程名称：合成课程\n请同学按时查看补考安排',
          'senderName': '张老师',
          'sendTime': '2030-04-01 09:00',
        },
      ];

    final termCatalog = CourseTermCatalog.build(
      courses: const [
        CourseRef(
            courseId: '7', clazzId: '11', name: '合成课程', folderName: '2025年秋'),
      ],
      assignments: const [],
      notices: const <CourseNotice>[],
      preferences: const CourseTermPreferences.empty(),
      now: DateTime.utc(2026, 11, 20, 4),
    );

    final cachedCourseExam = Assignment(
      id: 'cx:exam:7:11:old1',
      source: AssignmentSource.exam,
      courseName: '合成课程',
      title: '往期课程考试',
      deadlineAt: DateTime.utc(2025, 11, 10, 3),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.utc(2025, 11, 1),
      exam: ExamInfo(
        examId: 'old1',
        courseId: '7',
        clazzId: '11',
        startAt: DateTime.utc(2025, 11, 10, 1),
        endAt: DateTime.utc(2025, 11, 10, 3),
        startTrusted: true,
        endTrusted: true,
        lifecycle: 'ended',
      ),
    );

    final client = f.client()
      ..previousAssignments = {cachedCourseExam.id: cachedCourseExam}
      ..nextSyncCourseSelector = (catalog) => SyncScopeSelection.select(
            catalog: catalog,
            scope: AssignmentSyncScope.current,
            termCatalog: termCatalog,
          );

    final rows = await client.fetchAssignmentsWithOptions(
      collectCourseNotices: true,
    );
    expect(client.plannedCourses, 0);
    expect(client.skippedCourses, 1);
    expect(rows.any((a) => a.id == 'cx:exam:7:11:701'), isTrue);
    expect(rows.any((a) => a.id == cachedCourseExam.id), isFalse);
    expect(
        f.requests.where((r) => r.uri.path == '/phone/moocAnalysis/examList'),
        isEmpty);
    expect(
      client.lastFetchedNotices
          .any((n) => n.title == '《合成课程》往期补考提醒' && n.courseKey == '7:11'),
      isTrue,
    );
  });
}
