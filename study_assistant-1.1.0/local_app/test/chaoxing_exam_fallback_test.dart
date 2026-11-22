import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_exam_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

const _course =
    ChaoxingCourseRef(courseId: '7', clazzId: '11', courseName: '合成课程');

const _phoneEmpty =
    '<div class="ybox"><p class="blankTips">您好，本课程下暂未收到考试</p></div>';

String _phoneRow(String state, {String id = '99'}) =>
    '<table class="listTable"><tr data="/exam/phone/task-exam?courseId=7&amp;classId=11&amp;taskrefId=$id"><td>合成考试</td><td>不得保留成绩</td><td>$state</td><td></td></tr></table><script>var havemore=false;</script>';

const _accountEmptyNoScript =
    '<table class="dataTable"><tr><th>考试名称</th><th>作答状态</th></tr></table>';

String _accountRefer({
  required String courseId,
  required String classId,
  required String examId,
}) =>
    Uri.encodeComponent(
        '/exam-ans/exam/test/examcode/examnotes?courseId=$courseId&classId=$classId&examId=$examId');

String _accountGoRow({
  required String title,
  required String time,
  required String moocId,
  required String clazzId,
  required String examId,
  String state = '已过期',
  String personal = '未交',
}) =>
    '''
  <tr class="dataTr">
    <td>1</td><td>$title</td><td>$time</td><td>100</td><td>$state</td><td>$personal</td><td>--</td><td>线上</td>
    <td><a href="javascript:;" onclick="go('https://mooc1-api.chaoxing.com/exam-ans/mycourse/transfer?moocId=$moocId&amp;clazzid=$clazzId&amp;refer=${_accountRefer(courseId: moocId, classId: clazzId, examId: examId)}', stopExam)">查看</a></td>
  </tr>
''';

void main() {
  test(
      'empty phone exam list with valid workEnc and missing examEnc succeeds without false error',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = '';
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程'}
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="synthetic-work">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = _phoneEmpty;
          case '/exam-ans/exam/test/examcode/examlist':
            body = _accountEmptyNoScript;
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));

    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    final rows = await client.fetchAssignments();

    expect(rows, isEmpty);
    expect(
      client.issues.where((issue) => issue.stage == 'exam'),
      isEmpty,
    );
    expect(
      client.sourceResults.singleWhere((s) => s.source == 'exam').phase,
      SyncSourcePhase.success,
    );
    expect(
      client.sourceResults.singleWhere((s) => s.source == 'examAccount').phase,
      SyncSourcePhase.success,
    );
  });

  test(
      'missing examEnc when phone exam list has items retains phone exam and marks examPcSupplementUnavailable',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = '';
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程'}
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="synthetic-work">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = _phoneRow('未开始');
          case '/exam-ans/exam/test/examcode/examlist':
            body = _accountEmptyNoScript;
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));

    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    final rows = await client.fetchAssignments();

    expect(rows.where((a) => a.isExam && !a.exam!.noticeOnly), hasLength(1));
    final examSource =
        client.sourceResults.singleWhere((s) => s.source == 'exam');
    expect(examSource.phase, SyncSourcePhase.partial);
    expect(examSource.reasonCodes, contains('examPcSupplementUnavailable'));
  });

  test(
      'course notice later invalid row keeps earlier page and marks source partial',
      () async {
    var noticeCalls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = '';
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程'}
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="synthetic-work">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = _phoneEmpty;
          case '/exam-ans/exam/test/examcode/examlist':
            body = _accountEmptyNoScript;
          case '/pc/notice/getNoticeList':
            noticeCalls++;
            final firstPage =
                o.data is Map && (o.data as Map)['lastValue'] == '';
            body = firstPage
                ? {
                    'status': true,
                    'notices': {
                      'lastGetId': 'notice-cursor-1',
                      'lastPage': false,
                      'list': [
                        {
                          'uuid': 'course-notice-1',
                          'title': '普通课程公告',
                          'content': '这是一条普通课程公告',
                          'createrName': '任课教师',
                          'completeTime': '2030-05-20 10:00',
                          'isread': '0',
                        }
                      ],
                    },
                  }
                : {
                    'status': true,
                    'notices': {
                      'lastGetId': '',
                      'lastPage': true,
                      'list': [
                        {
                          'uuid': 'bad uuid',
                          'title': '后续普通公告',
                          'content': '没有考试信息',
                          'createrName': '任课教师',
                          'completeTime': '2030-05-20 11:00',
                          'isread': '0',
                        }
                      ],
                    },
                  };
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));

    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    final rows =
        await client.fetchAssignmentsWithOptions(collectCourseNotices: true);

    expect(rows, isEmpty);
    expect(noticeCalls, 2);
    expect(client.lastFetchedNotices.single.title, '普通课程公告');
    final courseNotice =
        client.sourceResults.singleWhere((s) => s.source == 'courseNotice');
    expect(courseNotice.phase, SyncSourcePhase.partial);
    expect(courseNotice.recordCount, 1);
    expect(courseNotice.reasonCodes, contains('listOrMetadataUnavailable'));
    expect(
      client.sourceResults.singleWhere((s) => s.source == 'examNotice').phase,
      SyncSourcePhase.success,
    );
  });

  test(
      'exam notice failure after the course notice window keeps notices success',
      () async {
    var noticeCalls = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = '';
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程'}
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="synthetic-work">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = _phoneEmpty;
          case '/exam-ans/exam/test/examcode/examlist':
            body = _accountEmptyNoScript;
          case '/pc/notice/getNoticeList':
            noticeCalls++;
            final cursor = (o.data as Map)['lastValue'] as String;
            final page = cursor.isEmpty
                ? 0
                : int.parse(cursor.substring('cursor-'.length));
            if (page < 5) {
              body = {
                'status': true,
                'notices': {
                  'lastGetId': 'cursor-${page + 1}',
                  'lastPage': false,
                  'list': [
                    {
                      'uuid': 'course-notice-$page',
                      'title': '第 $page 页课程公告',
                      'content': '普通课程公告',
                      'createrName': '任课教师',
                      'completeTime': '2030-05-20 10:00',
                      'isread': '0',
                      'attachment': jsonEncode([
                        {
                          'att_web': {
                            'courseId': '7',
                            'clazzId': '11',
                            'courseName': '合成课程',
                          }
                        }
                      ]),
                    }
                  ],
                },
              };
            } else {
              body = {'status': false, 'msg': 'later page unavailable'};
            }
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));

    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    await client.fetchAssignmentsWithOptions(collectCourseNotices: true);

    expect(noticeCalls, 6);
    final courseNotice =
        client.sourceResults.singleWhere((s) => s.source == 'courseNotice');
    expect(courseNotice.phase, SyncSourcePhase.success);
    expect(courseNotice.recordCount, 5);
    expect(courseNotice.reasonCodes, isEmpty);
    expect(client.lastFetchedNotices, hasLength(5));
    final examNotice =
        client.sourceResults.singleWhere((s) => s.source == 'examNotice');
    expect(examNotice.phase,
        anyOf(SyncSourcePhase.partial, SyncSourcePhase.failed));
  });

  test('first shared notice failure still fails both notice sources', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = '';
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程'}
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="synthetic-work">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = _phoneEmpty;
          case '/exam-ans/exam/test/examcode/examlist':
            body = _accountEmptyNoScript;
          case '/pc/notice/getNoticeList':
            body = {'status': false, 'msg': 'unavailable'};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));
    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    await client.fetchAssignmentsWithOptions(collectCourseNotices: true);
    expect(
        client.sourceResults
            .singleWhere((s) => s.source == 'courseNotice')
            .phase,
        SyncSourcePhase.failed);
    expect(
        client.sourceResults.singleWhere((s) => s.source == 'examNotice').phase,
        SyncSourcePhase.failed);
  });

  for (final classKey in ['classId', 'classid', 'cLaZzId']) {
    test('phone exam rows accept class alias $classKey', () {
      final html = _phoneRow('未开始').replaceFirst('classId=', '$classKey=');
      final page = ChaoxingExamParser.phone(html, _course);
      expect(page?.rows.map((row) => row.id), ['cx:exam:7:11:99']);
    });
  }

  for (final extra in ['clazzId=12', 'classId=11']) {
    test('phone exam rejects ambiguous class query $extra', () {
      final html =
          _phoneRow('未开始').replaceFirst('classId=11', 'classId=11&amp;$extra');
      expect(ChaoxingExamParser.phone(html, _course), isNull);
    });
  }

  test('phone exam ignores blank class occurrences', () {
    final html = _phoneRow('未开始')
        .replaceFirst('classId=11', 'classId=11&amp;classId=%20');
    expect(ChaoxingExamParser.phone(html, _course)?.rows.single.clazzId, '11');
  });

  test('PC exams accept class identity from case-insensitive hidden names', () {
    const html = '<input type="hidden" name="CoUrSeId" value="7">'
        '<input type="hidden" name="cLaZzId" value="11"><div>暂无考试</div>';
    final page = ChaoxingExamParser.coursePc(html, _course);
    expect(page?.total, 0);
  });

  test('PC exams reject conflicting hidden class aliases', () {
    const html = '<input id="courseId" value="7">'
        '<input id="classId" value="11"><input name="clazzId" value="12">'
        '<div>暂无考试</div>';
    expect(ChaoxingExamParser.coursePc(html, _course), isNull);
  });

  for (final outerKey in ['classId', 'classid', 'cLaSsId']) {
    test('account go link resolves outer class alias $outerKey', () {
      final row = _accountGoRow(
        title: '合成考试',
        time: '2026-06-09 21:30 至 2026-06-09 23:10',
        moocId: '101',
        clazzId: '202',
        examId: '9001',
      ).replaceFirst('clazzid=202', '$outerKey=202');
      final page = ChaoxingExamParser.account(
        '<table class="dataTable"><tr><th>作答状态</th></tr>$row</table>'
        '<script>page.showPage(0/12+1,Math.ceil(1/12));</script>',
      );
      expect(page?.rows.map((row) => row.id), ['cx:exam:101:202:9001']);
    });
  }

  test('account go link rejects conflicting outer class aliases', () {
    final row = _accountGoRow(
      title: '合成考试',
      time: '2026-06-09 21:30 至 2026-06-09 23:10',
      moocId: '101',
      clazzId: '202',
      examId: '9001',
    ).replaceFirst('clazzid=202', 'clazzid=202&amp;classId=203');
    final page = ChaoxingExamParser.account(
      '<table class="dataTable"><tr><th>作答状态</th></tr>$row</table>'
      '<script>page.showPage(0/12+1,Math.ceil(1/12));</script>',
    );
    expect(page!.rows, isEmpty);
    expect(page.skippedWithoutId, 1);
  });

  test('coursePc accepts valid empty page without Math.ceil pagination script',
      () {
    const html =
        '<input id="courseId" value="7"><input id="classId" value="11"><div>暂无考试</div>';
    final parsed = ChaoxingExamParser.coursePc(html, _course);
    expect(parsed, isNotNull);
    expect(parsed!.rows, isEmpty);
    expect(parsed.total, 0);
  });

  test(
      'account parser handles empty table, 8-column rows, inline examId, and skips rows missing IDs without fabricating',
      () {
    final empty = ChaoxingExamParser.account(_accountEmptyNoScript);
    expect(empty, isNotNull);
    expect(empty!.rows, isEmpty);
    expect(empty.total, 0);
    expect(empty.skippedWithoutId, 0);

    const mixedHtml = '''
<table class="dataTable">
  <tr><th>序号</th><th>考试名称</th><th>时间</th><th>时长</th><th>考试状态</th><th>作答状态</th><th>分数</th><th>方式</th></tr>
  <tr class="dataTr" data-examid="501">
    <td>1</td><td>线上期中</td><td>2030-05-01 09:00 至 2030-05-01 11:00</td><td>120</td><td>未开始</td><td>未开始</td><td>--</td><td>线上</td>
  </tr>
  <tr class="dataTr">
    <td>2</td><td>内联标识考试</td><td>2030-05-02 09:00 至 2030-05-02 10:00</td><td>60</td><td>未开始</td><td>未作答</td><td>--</td><td><a href="/exam/go?examId=8801">进入</a></td>
  </tr>
  <tr class="dataTr">
    <td>3</td><td>无标识历史行</td><td>2024-01-01 09:00 至 2024-01-01 11:00</td><td>120</td><td>已结束</td><td>已完成</td><td>90</td><td>归档</td>
  </tr>
</table>
<script>page.showPage(0/12+1,Math.ceil(3/12));</script>
''';

    final parsed = ChaoxingExamParser.account(mixedHtml);
    expect(parsed, isNotNull);
    expect(parsed!.total, 3);
    expect(parsed.skippedWithoutId, 1);
    expect(parsed.rows.map((e) => e.exam!.examId).toList(), ['501', '8801']);
    expect(parsed.rows.any((e) => e.exam!.examId == '3'), isFalse);
  });

  test('account parser resolves course identity and exact time from go refer',
      () {
    final html = '''
<table class="dataTable">
  <tr><th>序号</th><th>考试名称</th><th>时间</th><th>时长</th><th>考试状态</th><th>作答状态</th><th>分数</th><th>方式</th><th>操作</th></tr>
  ${_accountGoRow(title: '新建试卷20260609191916', time: '2026-06-09 21:30 至 2026-06-09 23:10', moocId: '101', clazzId: '202', examId: '9001')}
  ${_accountGoRow(title: '新建试卷20260624101003', time: '2026-06-24 10:12 至 2026-06-24 23:12', moocId: '101', clazzId: '202', examId: '9002')}
  ${_accountGoRow(title: '新建试卷20260703231948', time: '2026-07-04 08:00 至 2026-07-04 23:00', moocId: '101', clazzId: '202', examId: '9003')}
</table>
<script>page.showPage(0/12+1,Math.ceil(3/12));</script>
''';
    final parsed = ChaoxingExamParser.account(html);
    expect(parsed, isNotNull);
    expect(parsed!.total, 3);
    expect(parsed.rows, hasLength(3));
    expect(parsed.skippedWithoutId, 0);
    expect(parsed.rows.map((e) => e.id).toList(), [
      'cx:exam:101:202:9001',
      'cx:exam:101:202:9002',
      'cx:exam:101:202:9003',
    ]);
    final first = parsed.rows.first;
    expect(first.exam!.startAt!.toUtc(), DateTime.utc(2026, 6, 9, 13, 30));
    expect(first.exam!.endAt!.toUtc(), DateTime.utc(2026, 6, 9, 15, 10));
    expect(first.exam!.startTrusted, isTrue);
    expect(first.exam!.endTrusted, isTrue);
    expect(first.exam!.lifecycle, 'ended');
    expect(first.status, 'pending');
    expect(parsed.rows[1].exam!.startAt!.toUtc(),
        DateTime.utc(2026, 6, 24, 2, 12));
    expect(parsed.rows[2].exam!.startAt!.toUtc(), DateTime.utc(2026, 7, 4, 0));
  });

  test('account parser accepts the observed relative go target and quoted arg',
      () {
    final refer =
        _accountRefer(courseId: '101', classId: '202', examId: '9001');
    final html = '''
<table class="dataTable">
  <tr><th>序号</th><th>考试名称</th><th>时间</th><th>时长</th><th>考试状态</th><th>作答状态</th><th>分数</th><th>方式</th><th>操作</th></tr>
  <tr class="dataTr">
    <td>1</td><td>合成考试</td><td>2026-06-09 21:30 至 2026-06-09 23:10</td><td>100</td><td>已过期</td><td>未交</td><td>--</td><td>线上</td>
    <td><a onclick="go('/exam-ans/mycourse/transfer?moocId=101&amp;clazzid=202&amp;refer=$refer', '2')">查看</a></td>
  </tr>
</table>
<script>page.showPage(0/12+1,Math.ceil(1/12));</script>
''';
    final parsed = ChaoxingExamParser.account(html);
    expect(parsed, isNotNull);
    expect(parsed!.rows.single.id, 'cx:exam:101:202:9001');
    expect(parsed.rows.single.exam!.startAt!.toUtc(),
        DateTime.utc(2026, 6, 9, 13, 30));
    expect(parsed.skippedWithoutId, 0);
  });

  test('account identity rejects nested contradictions and duplicate targets',
      () {
    String table(String operation) => '''
<table class="dataTable">
  <tr><th>序号</th><th>考试名称</th><th>时间</th><th>时长</th><th>考试状态</th><th>作答状态</th><th>分数</th><th>方式</th><th>操作</th></tr>
  <tr class="dataTr"><td>1</td><td>合成考试</td><td>2026-06-09 21:30 至 2026-06-09 23:10</td><td>100</td><td>已过期</td><td>未交</td><td>--</td><td>线上</td><td>$operation</td></tr>
</table>
<script>page.showPage(0/12+1,Math.ceil(1/12));</script>
''';
    String go(String courseId, String examId) {
      final url =
          "https://mooc1-api.chaoxing.com/exam-ans/mycourse/transfer?moocId=101&amp;clazzid=202&amp;refer=${_accountRefer(courseId: courseId, classId: '202', examId: examId)}";
      return 'onclick="go(\'$url\', stopExam)"';
    }

    final mismatch =
        ChaoxingExamParser.account(table('<a ${go('999', '9001')}>查看</a>'));
    expect(mismatch!.rows, isEmpty);
    expect(mismatch.skippedWithoutId, 1);

    final duplicate = ChaoxingExamParser.account(
        table('<a ${go('101', '9001')}>查看</a><a ${go('101', '9002')}>重开</a>'));
    expect(duplicate!.rows, isEmpty);
    expect(duplicate.skippedWithoutId, 1);

    final repeatedSame = ChaoxingExamParser.account(table(
        '<a ${go('101', '9001')}>查看</a><a ${go('101', '9001')}>再次查看</a>'));
    expect(repeatedSame!.rows.single.exam!.examId, '9001');
    expect(repeatedSame.skippedWithoutId, 0);

    final startEntry =
        "https://mooc1-api.chaoxing.com/exam-ans/mycourse/transfer?moocId=101&amp;clazzid=202&amp;refer=${_accountRefer(courseId: '101', classId: '202', examId: '9002')}";
    final withStartOnly = ChaoxingExamParser.account(table(
        '<a onclick="go(\'$startEntry\', startExam)">开始</a><a ${go('101', '9001')}>查看</a>'));
    expect(withStartOnly!.rows.single.exam!.examId, '9001');

    final refer = Uri.encodeComponent(
        '/exam-ans/exam/test/examcode/examnotes?courseId=101&classId=202&examId=9001&examId=9002');
    final duplicateQuery = ChaoxingExamParser.account(table(
        '<a onclick="go(\'https://mooc1-api.chaoxing.com/exam-ans/mycourse/transfer?moocId=101&amp;clazzid=202&amp;refer=$refer\', stopExam)">查看</a>'));
    expect(duplicateQuery!.rows, isEmpty);
    expect(duplicateQuery.skippedWithoutId, 1);
  });

  test('account merge keeps trusted course times and fills unknown status', () {
    final now = DateTime.utc(2026, 1, 1);
    final official = ChaoxingExamParser.make(
      id: '99',
      title: '课程考试',
      courseId: '7',
      clazzId: '11',
      courseName: '合成课程',
      status: 'unknown',
      start: DateTime.utc(2030, 4, 2, 1),
      end: DateTime.utc(2030, 4, 2, 3),
      stateText: '未开始',
      now: now,
    );
    final account = ChaoxingExamParser.make(
      id: '99',
      title: '账号考试',
      courseId: '7',
      clazzId: '11',
      status: 'pending',
      start: DateTime.utc(2030, 4, 1, 1),
      end: DateTime.utc(2030, 4, 1, 3),
      stateText: '未开始',
      now: now,
    );
    final merged =
        ChaoxingExamParser.mergeAccountEvidence([official], [account]);
    expect(merged.rows, hasLength(1));
    expect(merged.timeConflicts, 1);
    final row = merged.rows.single;
    expect(row.courseName, '合成课程');
    expect(row.title, '课程考试');
    expect(row.exam!.startAt!.toUtc(), DateTime.utc(2030, 4, 2, 1));
    expect(row.exam!.endAt!.toUtc(), DateTime.utc(2030, 4, 2, 3));

    final unknown = ChaoxingExamParser.make(
      id: '100',
      title: '待确认课程考试',
      courseId: '7',
      clazzId: '11',
      courseName: '合成课程',
      status: 'unknown',
      now: now,
    );
    final evidence = ChaoxingExamParser.make(
      id: '100',
      title: '账号考试',
      courseId: '7',
      clazzId: '11',
      status: 'pending',
      start: DateTime.utc(2030, 5, 1, 1),
      end: DateTime.utc(2030, 5, 1, 2),
      stateText: '未开始',
      now: now,
    );
    final filled =
        ChaoxingExamParser.mergeAccountEvidence([unknown], [evidence]);
    expect(filled.rows.single.status, 'pending');
    expect(filled.rows.single.exam!.startTrusted, isTrue);
    expect(
        filled.rows.single.exam!.startAt!.toUtc(), DateTime.utc(2030, 5, 1, 1));
  });

  test(
      'client marks examAccount partial with accountExamRowSkippedNoId when rows lack IDs',
      () async {
    const accountHtml = '''
<table class="dataTable">
  <tr><th>序号</th><th>考试名称</th><th>时间</th><th>时长</th><th>考试状态</th><th>作答状态</th><th>分数</th><th>方式</th></tr>
  <tr class="dataTr">
    <td>1</td><td>无标识历史行</td><td>2024-01-01 09:00 至 2024-01-01 11:00</td><td>120</td><td>已结束</td><td>已完成</td><td>90</td><td>归档</td>
  </tr>
</table>
<script>page.showPage(0/12+1,Math.ceil(1/12));</script>
''';
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = '';
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {'courses': []};
          case '/exam-ans/exam/test/examcode/examlist':
            body = accountHtml;
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));

    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    await client.fetchAssignments();

    final source =
        client.sourceResults.singleWhere((s) => s.source == 'examAccount');
    expect(source.phase, SyncSourcePhase.success);
    expect(source.isNormalDegradation, isTrue);
    expect(source.reasonCodes, contains('accountExamRowSkippedNoId'));
    expect(client.issues, isEmpty);
    expect(client.lastSyncWarning, isNull);
  });

  test(
      'task engine probe is opt-in via fetchAssignmentsWithOptions and non-blocking on single-course error',
      () async {
    final paths = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        paths.add(o.uri.path);
        dynamic body = '';
        var status = 200;
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '课程A'},
                {'courseId': '8', 'clazzId': '12', 'courseName': '课程B'},
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="synthetic-work">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = _phoneEmpty;
          case '/exam-ans/exam/test/examcode/examlist':
            body = _accountEmptyNoScript;
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          case '/v2/apis/active/getData':
            if (o.queryParameters['courseId'] == '7') {
              body = {
                'result': 1,
                'data': [
                  {'planCount': 3, 'planFinishCount': 1}
                ]
              };
            } else {
              status = 500;
              body = 'error';
            }
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: status));
      }));

    final defaultClient = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    await defaultClient.fetchAssignments();
    expect(paths, isNot(contains('/v2/apis/active/getData')));

    paths.clear();
    final manualClient = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    await manualClient.fetchAssignmentsWithOptions(
      collectCourseNotices: true,
      enableTaskEngineProbe: true,
    );
    expect(paths, contains('/v2/apis/active/getData'));
    final probe = manualClient.sourceResults
        .singleWhere((s) => s.source == 'taskEnginePlan');
    expect(probe.phase, SyncSourcePhase.partial);
    expect(probe.recordCount, 3);
    expect(probe.unconfirmedCount, 2);
    expect(probe.reasonCodes, contains('unfinishedPlanDetected'));
  });
}
