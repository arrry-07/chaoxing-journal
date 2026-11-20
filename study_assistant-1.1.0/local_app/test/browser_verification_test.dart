// Formal-source fixtures intentionally isolate the existing formal request flow.
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'browser verification imports only trusted session cookies and does not claim data success',
      () async {
    const channel = MethodChannel('study_assistant/external_links');
    var importDone = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'verifySession');
      expect(call.arguments['url'],
          startsWith('https://mooc1.chaoxing.com/visit/'));
      return [
        {'url': 'https://mooc1.chaoxing.com/', 'cookies': 'challenge=manual'},
        {'url': 'https://attacker.example/', 'cookies': 'evil=leak'}
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (importDone && o.uri.host == 'mooc1.chaoxing.com') {
          expect(o.headers['Cookie'], contains('challenge=manual'));
          expect(o.headers['Cookie'], isNot(contains('evil=')));
        }
        final data = o.uri.path == '/mycourse/backclazzdata'
            ? {
                'courses': [
                  {'courseId': '1', 'clazzId': '2', 'courseName': '课'}
                ]
              }
            : '<html>unrecognized</html>';
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final c = ChaoxingLocalClient(
        enableExams: false, enableClassroomTasks: false, dio: dio);
    await expectLater(c.fetchAssignments(), throwsA(isA<SyncReadException>()));
    expect(await c.verifyInBrowser(courseInspection: true), isTrue);
    expect(c.succeededCourses, 0);
    importDone = true;
    await expectLater(c.fetchAssignments(), throwsA(isA<SyncReadException>()));
  });

  test(
      'challenge target follows the current exam course, not the last work page',
      () async {
    const channel = MethodChannel('study_assistant/external_links');
    String? opened;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'verifySession');
      opened = call.arguments['url'] as String?;
      return <Map<String, dynamic>>[];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic body = '';
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '课程 A'},
                {'courseId': '3', 'clazzId': '4', 'courseName': '课程 B'},
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="synthetic-work">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/phone/moocAnalysis/examList':
            body = o.uri.queryParameters['courseId'] == '1'
                ? '<html><body>请完成安全验证</body></html>'
                : '<p class="blankTips">您好，本课程下暂未收到考试</p>';
          case '/exam-ans/exam/test/examcode/examlist':
            body = '<table class="dataTable"><tr><th>作答状态</th></tr></table>';
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));
    final c = ChaoxingLocalClient(
      dio: dio,
      enableClassroomTasks: false,
      wait: (_) async {},
    );
    await c.fetchAssignments();
    expect(await c.verifyInBrowser(), isTrue);
    final target = Uri.parse(opened!);
    expect(target.path, '/visit/stucoursemiddle');
    expect(target.queryParameters['courseid'], '1');
    expect(target.queryParameters['clazzid'], '2');
    expect(target.queryParameters['courseid'], isNot('3'));
  });

  test('course access inspection requires an explicit opt-in', () async {
    const channel = MethodChannel('study_assistant/external_links');
    String? opened;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      opened = call.arguments['url'] as String?;
      return <Map<String, dynamic>>[];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final body = switch (o.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '课程'}
              ]
            },
          '/visit/stucoursemiddle' =>
            '<input id="workEnc" value="synthetic-work">',
          '/mooc2/work/list' => '<div>暂无作业</div>',
          _ => throw StateError('unexpected ${o.uri.path}')
        };
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));
    final c = ChaoxingLocalClient(
      dio: dio,
      enableExams: false,
      enableClassroomTasks: false,
      wait: (_) async {},
    );
    await c.fetchAssignments();
    await expectLater(
        c.verifyInBrowser(), throwsA(isA<VerificationTargetUnavailable>()));
    expect(await c.verifyInBrowser(courseInspection: true), isTrue);
    final target = Uri.parse(opened!);
    expect(target.path, '/visit/stucoursemiddle');
    expect(target.queryParameters['courseid'], '1');
  });
}
