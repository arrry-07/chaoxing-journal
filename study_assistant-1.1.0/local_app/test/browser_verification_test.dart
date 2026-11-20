// Formal-source fixtures intentionally isolate the existing formal request flow.
import 'dart:async';

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

  test(
      'JSON 9010 challenge in detail stops downstream sources and resumes after verification',
      () async {
    const channel = MethodChannel('study_assistant/external_links');
    var verified = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'verifySession');
      verified = true;
      return [
        {'url': 'https://mooc1.chaoxing.com/', 'cookies': 'challenge=solved'},
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final requests = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(o.uri.path);
        dynamic body = '';
        var status = 200;
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '课程 A'}
              ]
            };
          case '/visit/stucoursemiddle':
            body =
                '<input id="workEnc" value="w"><input id="examEnc" value="e">';
          case '/mooc2/work/list':
            body =
                '<ul><li onclick="goTask()" data="/mooc2/work/doHomeWorkNew?courseId=1&amp;classId=2&amp;workId=10"><p class="overHidden2">作业1</p><span class="status">未提交</span></li></ul>';
          case '/mooc2/work/doHomeWorkNew':
            if (!verified) {
              status = 202;
              body = {'status': false, 'code': 9010, 'msg': '【9010】操作异常'};
            } else {
              body = '<div>截止时间：2030-05-01 12:00</div>';
            }
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = '<p class="blankTips">您好，本课程下暂未收到考试</p>';
          case '/exam/test':
            body =
                '<input id="courseId" value="1"><input id="classId" value="2"><div>暂无内容</div>';
          case '/exam-ans/exam/test/examcode/examlist':
            body = '<table class="dataTable"><tr><th>作答状态</th></tr></table>';
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          case '/v2/apis/active/getData':
            body = {'result': 1, 'data': []};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, data: body, statusCode: status));
      }));

    final c = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    final first = await c.fetchAssignmentsWithOptions(
        collectCourseNotices: true, enableTaskEngineProbe: true);
    expect(first.single.deadlineReadFailed, isTrue);
    expect(
        c.issues
            .singleWhere((i) => i.kind == SyncIssueKind.verificationRequired)
            .stage,
        'detail');
    expect(requests, isNot(contains('/v2/apis/active/student/activelist')));
    expect(requests, isNot(contains('/phone/moocAnalysis/examList')));
    expect(requests, isNot(contains('/v2/apis/active/getData')));
    final workSource =
        c.sourceResults.singleWhere((s) => s.source == 'courseWork');
    expect(workSource.phase, SyncSourcePhase.partial);
    expect(workSource.reasonCodes, contains('verificationPaused'));

    expect(await c.verifyInBrowser(), isTrue);
    requests.clear();
    final resumed = await c.fetchAssignmentsWithOptions(
        collectCourseNotices: true, enableTaskEngineProbe: true);
    expect(resumed.single.deadlineTrusted, isTrue);
    expect(c.issues, isEmpty);
    expect(c.lastSyncWarning, isNull);
    expect(
        c.sourceResults.every((s) =>
            s.phase == SyncSourcePhase.success ||
            s.phase == SyncSourcePhase.notEnabled),
        isTrue);
  });

  test(
      'cancelled verification keeps target and session switch drops stale cookies',
      () async {
    const channel = MethodChannel('study_assistant/external_links');
    var cancelMode = true;
    final pendingVerify = <Completer<List<Map<String, dynamic>>?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      if (cancelMode) return Future.value(null);
      final completer = Completer<List<Map<String, dynamic>>?>();
      pendingVerify.add(completer);
      return completer.future;
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
          '/visit/stucoursemiddle' => '<input id="workEnc" value="w">',
          '/mooc2/work/list' => '<html><body>请完成安全验证</body></html>',
          _ => '',
        };
        h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
      }));

    final c = ChaoxingLocalClient(
        dio: dio,
        enableExams: false,
        enableClassroomTasks: false,
        wait: (_) async {});
    await expectLater(c.fetchAssignments(), throwsA(isA<SyncReadException>()));
    expect(await c.verifyInBrowser(), isFalse);

    cancelMode = false;
    final verifyFuture = c.verifyInBrowser();
    c.clearSession();
    pendingVerify.single.complete([
      {'url': 'https://mooc1.chaoxing.com/', 'cookies': 'stale=leak'},
    ]);
    expect(await verifyFuture, isFalse);
    expect(c.needsSessionInitialization, isTrue);
  });

  test(
      'root chaoxing.com verification cookies apply across subdomains and subpath updates do not duplicate',
      () async {
    const channel = MethodChannel('study_assistant/external_links');
    var round = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'verifySession');
      round++;
      return [
        {
          'url': 'https://mooc1.chaoxing.com/visit/stucoursemiddle',
          'cookies':
              'antispider=cleared; route=mooc1; pathTok=${round == 1 ? 'old' : 'new'}',
        },
        {
          'url': 'https://mooc1.chaoxing.com/',
          'cookies': 'antispider=cleared; route=mooc1',
        },
        {
          'url': 'https://chaoxing.com/',
          'cookies': 'antispider=cleared',
        },
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final sentCookies = <String, String>{};
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final cookie = o.headers['Cookie']?.toString() ?? '';
        sentCookies['${o.uri.host}${o.uri.path}'] = cookie;
        dynamic body = '';
        var status = 200;
        final headers = <String, List<String>>{};
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '课程 A'}
              ]
            };
          case '/visit/stucoursemiddle':
            if (round == 0) {
              body = '<html><body>请完成安全验证</body></html>';
            } else {
              status = 302;
              headers['location'] = [
                'https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu?courseid=1&clazzid=2'
              ];
            }
          case '/mooc2-ans/mycourse/stu':
            body =
                '<input id="workEnc" value="w"><input id="examEnc" value="e">';
          case '/mooc2/work/list':
            body = '<div>暂无作业</div>';
          case '/v2/apis/active/student/activelist':
            body = {
              'result': 1,
              'data': {'activeList': []}
            };
          case '/phone/moocAnalysis/examList':
            body = '<p class="blankTips">您好，本课程下暂未收到考试</p>';
          case '/exam-ans/exam/test/examcode/examlist':
            body = '<table class="dataTable"><tr><th>作答状态</th></tr></table>';
          case '/pc/notice/getNoticeList':
            body = {'status': true};
          default:
            throw StateError('unexpected ${o.uri.path}');
        }
        h.resolve(Response(
            requestOptions: o,
            data: body,
            statusCode: status,
            headers: Headers.fromMap(headers)));
      }));

    final c = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    await expectLater(c.fetchAssignments(), throwsA(isA<SyncReadException>()));

    expect(await c.verifyInBrowser(), isTrue);
    sentCookies.clear();
    await c.fetchAssignments();

    expect(sentCookies['mooc1-api.chaoxing.com/mycourse/backclazzdata'],
        contains('antispider=cleared'));
    expect(sentCookies['mooc1-api.chaoxing.com/mycourse/backclazzdata'],
        isNot(contains('route=mooc1')));
    expect(sentCookies['mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu'],
        contains('antispider=cleared'));
    expect(sentCookies['mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu'],
        isNot(contains('route=mooc1')));
    expect(
        sentCookies[
            'mobilelearn.chaoxing.com/v2/apis/active/student/activelist'],
        contains('antispider=cleared'));
    expect(sentCookies['notice.chaoxing.com/pc/notice/getNoticeList'],
        contains('antispider=cleared'));
    final mooc1MiddleCookie =
        sentCookies['mooc1.chaoxing.com/visit/stucoursemiddle']!;
    expect(RegExp(r'\bantispider=cleared\b').allMatches(mooc1MiddleCookie),
        hasLength(1));
    expect(mooc1MiddleCookie, contains('route=mooc1'));
    expect(mooc1MiddleCookie, contains('pathTok=old'));

    expect(await c.verifyInBrowser(courseInspection: true), isTrue);
    sentCookies.clear();
    await c.fetchAssignments();
    final updatedMiddleCookie =
        sentCookies['mooc1.chaoxing.com/visit/stucoursemiddle']!;
    expect(updatedMiddleCookie, contains('pathTok=new'));
    expect(updatedMiddleCookie, isNot(contains('pathTok=old')));
    expect(RegExp(r'\bantispider=cleared\b').allMatches(updatedMiddleCookie),
        hasLength(1));
  });
}
