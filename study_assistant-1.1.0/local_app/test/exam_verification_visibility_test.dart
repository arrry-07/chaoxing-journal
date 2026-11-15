import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_exam_visibility.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

const _hiddenStartPopups = '''
<div id="tipWin" style="width:376px;height:auto;display:none;">
  <div><div id="identifyCodeInp" style="width:253px;display:none">
    <span>请输入验证码</span><input name="code">
  </div></div>
</div>
<div id="reTest-tipWin" style="width:376px;height:auto;display:none;">
  <div id="reTest-identifyCodeInp" style="width:253px;display:none">
    <span>请输入验证码</span>
  </div>
</div>
''';

String _pcList({bool empty = false}) => '''
<input id="courseId" value="7"><input id="classId" value="11">
${empty ? '<div>暂无内容</div>' : '''
<ul><li class="lookLi"><a title="合成考试" onclick="goTest('7','99')">合成考试</a>
<div>2030-04-01 09:00 至 2030-04-01 10:00</div>
<strong>未开始</strong></li></ul>'''}
<script>page.showPage(1,Math.ceil(${empty ? 0 : 1}/9));</script>
''';

class _Fixture {
  _Fixture(this.pcBody,
      {this.pcPath = '/exam/test',
      this.empty = false,
      this.location,
      this.formalBody = '<div>暂无作业</div>'});

  final String pcBody, pcPath, formalBody;
  final bool empty;
  final String? location;
  final requests = <RequestOptions>[];

  late final dio = Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      dynamic body;
      var status = 200;
      final headers = <String, List<String>>{};
      switch (options.uri.path) {
        case '/mycourse/backclazzdata':
          body = {
            'courses': [
              {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程'}
            ]
          };
        case '/visit/stucoursemiddle':
          body =
              '<input id="workEnc" value="synthetic"><input id="examEnc" value="synthetic">';
        case '/mooc2/work/list':
          body = formalBody;
        case '/phone/moocAnalysis/examList':
          body = empty
              ? '<p class="blankTips">您好，本课程下暂未收到考试</p>'
              : '<table><tr data="/exam/phone/task-exam?courseId=7&amp;classId=11&amp;taskrefId=99"><td>合成考试</td><td></td><td>未开始</td></tr></table>';
        case '/exam/test':
        case '/exam-ans/exam/test':
          body = pcBody;
          if (options.uri.path == '/exam/test' && pcPath != '/exam/test') {
            status = 302;
            headers['location'] = ['$pcPath?courseId=7&classId=11'];
            body = '';
          } else if (location != null) {
            status = 302;
            headers['location'] = [location!];
          }
        case '/exam-ans/exam/test/examcode/examlist':
          body =
              '<table class="dataTable"><th>作答状态</th></table><script>Math.ceil(0/12)</script>';
        case '/pc/notice/getNoticeList':
          body = {'status': true};
        default:
          fail('Unexpected synthetic route: ${options.uri.path}');
      }
      handler.resolve(Response(
          requestOptions: options,
          data: body,
          statusCode: status,
          headers: Headers.fromMap(headers)));
    }));

  ChaoxingLocalClient client({bool enableExams = true}) => ChaoxingLocalClient(
      dio: dio,
      enableExams: enableExams,
      enableClassroomTasks: false,
      wait: (_) async {});
}

void main() {
  for (final path in ['/exam/test', '/exam-ans/exam/test']) {
    for (final empty in [false, true]) {
      test('closed hidden start popups do not block PC list $path empty=$empty',
          () async {
        final fixture = _Fixture('${_pcList(empty: empty)}$_hiddenStartPopups',
            pcPath: path, empty: empty);
        final client = fixture.client();
        final records = await client.fetchAssignments();
        expect(records.length, empty ? 0 : 1);
        expect(client.sourceResults.firstWhere((s) => s.source == 'exam').phase,
            SyncSourcePhase.success);
        expect(
            client.issues
                .where((i) => i.kind == SyncIssueKind.verificationRequired),
            isEmpty);
        if (!empty) {
          expect(records.single.id, 'cx:exam:7:11:99');
          expect(records.single.timelineTrusted, isTrue);
          expect(records.single.status, 'pending');
        }
        expect(fixture.requests.any((r) => r.uri.path == path), isTrue);
        expect(fixture.requests.any((r) => r.uri.path.contains('testStart')),
            isFalse);
      });
    }
  }

  for (final id in [
    'tipWin',
    'identifyCodeInp',
    'reTest-tipWin',
    'reTest-identifyCodeInp'
  ]) {
    for (final hidden in [false, true]) {
      test('known popup $id is ignored only when explicitly hidden=$hidden',
          () async {
        final popup =
            '<div id="$id" style="width:253px;display:${hidden ? 'none' : 'block'}"><div><span>请输入验证码</span></div></div>';
        final client = _Fixture('${_pcList()}$popup').client();
        await client.fetchAssignments();
        expect(client.sourceResults.firstWhere((s) => s.source == 'exam').phase,
            hidden ? SyncSourcePhase.success : SyncSourcePhase.partial);
        expect(
            client.issues
                .any((i) => i.kind == SyncIssueKind.verificationRequired),
            !hidden);
      });
    }
  }

  test('single quoted hidden popup attributes match the confirmed markup',
      () async {
    final client =
        _Fixture('${_pcList()}${_hiddenStartPopups.replaceAll('"', "'")}')
            .client();
    final records = await client.fetchAssignments();
    expect(records.single.timelineTrusted, isTrue);
    expect(client.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.success);
  });

  final blockedBodies = {
    'visible original popups':
        _hiddenStartPopups.replaceAll('display:none', 'display:block'),
    'challenge outside hidden popups': '$_hiddenStartPopups<div>请完成人机验证</div>',
    'unclosed hidden parent':
        '<div id="tipWin" style="display:none"><div id="identifyCodeInp" style="display:none"><span>请输入验证码</span></div>',
    'unclosed hidden child':
        '<div id="identifyCodeInp" style="display:none"><span>请输入验证码</span>',
    'unrecognized hidden container':
        '<div id="anotherPopup" style="display:none">请输入验证码</div>',
    'conflicting display declarations':
        '<div id="tipWin" style="display:none;display:block">请输入验证码</div>',
    'known ID without explicit hiding': '<div id="tipWin">请输入验证码</div>',
    'fake popup attributes inside another attribute':
        '''<div data-note=" id='tipWin' style='display:none'">请输入验证码</div>''',
    'popup ID only in a data attribute':
        '<div data-id="tipWin" style="display:none">请输入验证码</div>',
  };
  for (final entry in blockedBodies.entries) {
    test('${entry.key} remains a verification challenge', () async {
      final client = _Fixture('${_pcList()}${entry.value}').client();
      final records = await client.fetchAssignments();
      expect(records.single.id, 'cx:exam:7:11:99');
      expect(records.single.timelineTrusted, isFalse);
      expect(client.sourceResults.firstWhere((s) => s.source == 'exam').phase,
          SyncSourcePhase.partial);
      expect(
          client.issues
              .any((i) => i.kind == SyncIssueKind.verificationRequired),
          isTrue);
    });
  }

  test('external antispider redirect still blocks a list with hidden popups',
      () async {
    final fixture = _Fixture('${_pcList()}$_hiddenStartPopups',
        location: 'https://mooc1.chaoxing.com/antispiderShowVerify.ac');
    final client = fixture.client();
    await client.fetchAssignments();
    expect(
        client.issues.any((i) => i.kind == SyncIssueKind.verificationRequired),
        isTrue);
    expect(fixture.requests.any((r) => r.uri.path.contains('antispider')),
        isFalse);
  });

  test('formal work challenge classification is unchanged', () async {
    final client =
        _Fixture(_pcList(), formalBody: '<div>暂无作业</div>$_hiddenStartPopups')
            .client(enableExams: false);
    await expectLater(
        client.fetchAssignments(),
        throwsA(isA<SyncReadException>().having(
            (e) => e.issue.kind, 'kind', SyncIssueKind.verificationRequired)));
  });

  for (final entry in [
    (kind: '课程考试', url: 'https://mooc1.chaoxing.com/visit/stucoursemiddle'),
    (
      kind: '课程考试',
      url: 'https://mooc1-api.chaoxing.com/phone/moocAnalysis/examList'
    ),
    (
      kind: '课程考试',
      url: 'https://mooc1-api.chaoxing.com/exam-ans/exam/test/examcode/examlist'
    ),
    (kind: '正式作业', url: 'https://mooc1.chaoxing.com/exam/test'),
    (kind: '课程考试', url: 'https://example.invalid/exam/test'),
    (kind: '课程考试', url: 'http://mooc1.chaoxing.com/exam/test'),
  ]) {
    test('visibility exception does not cover ${entry.kind} ${entry.url}', () {
      expect(
          examListChallengeBody(_hiddenStartPopups,
              uri: Uri.parse(entry.url), requestKind: entry.kind),
          _hiddenStartPopups);
    });
  }
}
