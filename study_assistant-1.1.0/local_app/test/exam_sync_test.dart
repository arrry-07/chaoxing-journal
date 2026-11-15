import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_exam_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_web_link.dart';
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
        int total = 1}) =>
    '''<input id="courseId" value="$courseId"><input id="classId" value="11"><ul><li class="lookLi"><div class="titTxt"><p><a title="合成考试" onclick="show(0)">合成考试</a></p><span>$start 至 $end</span><span><strong>已完成<strong onclick="goTest('7','99','2','2030','3','0','secret')">不得保留成绩</strong></strong></span></div></li></ul><script>page.showPage(0/9+1,Math.ceil($total/9),"changePage");</script>''';
const accountEmpty =
    '<table class="dataTable"><tr><th>考试名称</th><th>作答状态</th></tr></table><script>page.showPage(0/12+1,Math.ceil(0/12));</script>';

class ExamFixture {
  Dio? legacy;
  bool emptyPhone = false;
  int examHttp = 200;
  int formalHttp = 200;
  bool partialPc = false;
  bool badPc = false, repeatPhone = false, unsafeRedirect = false;
  Completer<void>? gate;
  final started = Completer<void>();
  final requests = <RequestOptions>[];
  late final Dio dio = Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      requests.add(o);
      dynamic body = '';
      var status = 200;
      final headers = <String, List<String>>{};
      switch (o.uri.path) {
        case '/mycourse/backclazzdata':
          if (legacy != null) {
            h.resolve(await legacy!.fetch<dynamic>(o));
            return;
          }
          body = {
            'courses': [
              {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程'}
            ]
          };
        case '/visit/stucoursemiddle':
          body =
              '<input id="workEnc" value="synthetic"><input id="examEnc" value="synthetic">';
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
          status = examHttp;
          body = emptyPhone ? phoneEmpty : phoneRow('完成', more: repeatPhone);
          if (unsafeRedirect) {
            status = 302;
            headers['location'] = [
              'https://mooc1.chaoxing.com/exam/test/testStart'
            ];
          }
        case '/exam/test':
          body = badPc ? '<unknown>' : pcRow();
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
          body = accountEmpty;
        case '/pc/notice/getNoticeList':
          expect(o.method, 'POST');
          body = (o.data as Map)['lastValue'] == ''
              ? {
                  'status': true,
                  'notices': {
                    'lastGetId': 'cursor',
                    'list': [
                      {
                        'uuid': 'notice-1',
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
  test('empty phone list still reads independent PC course exams', () async {
    final f = ExamFixture()..emptyPhone = true;
    final rows = await f.client().fetchAssignments();
    expect(rows.where((a) => a.isExam && !a.exam!.noticeOnly).length, 1);
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
}
