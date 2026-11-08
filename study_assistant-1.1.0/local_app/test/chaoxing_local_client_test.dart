import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

void main() {
  Future<void> verifyStaleDetailFetchIsDiscarded(
      {required bool singleCourse}) async {
    final detailStarted = Completer<void>();
    final detailResponse = Completer<Response<dynamic>>();
    RequestOptions? detailRequest;
    final dio = Dio()
      ..interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) async {
        dynamic body;
        switch (options.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                {
                  'courseId': '7',
                  'clazzId': '11',
                  'courseName': '样例课程',
                  'cpi': '8',
                }
              ]
            };
          case '/visit/stucoursemiddle':
            body = '<input id="workEnc" value="signature">';
          case '/mooc2/work/list':
            final url = Uri.encodeComponent(
                'https://mooc1.chaoxing.com/work/task?courseId=7&classId=11&workId=9&enc=synthetic');
            body =
                '<li onclick="goTask(this);" data="$url"><p class="overHidden2 fl">样例作业</p><p class="status fl">未提交</p></li>';
          case '/work/task':
            detailRequest = options;
            detailStarted.complete();
            handler.resolve(await detailResponse.future);
            return;
          default:
            fail('unexpected endpoint ${options.uri}');
        }
        handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: body));
      }));
    final client = ChaoxingLocalClient(dio: dio);
    final fetch = singleCourse
        ? client.fetchAssignmentsForCourse(courseId: '7', clazzId: '11')
        : client.fetchAssignments();

    await detailStarted.future;
    client.clearSession();
    detailResponse.complete(Response(
        requestOptions: detailRequest!,
        statusCode: 200,
        data: '作答时间：2026-12-30 09:00 至 2027-01-02 12:00'));

    expect(await fetch, isEmpty);
    expect(client.courses, isEmpty);
    expect(client.hasCourseResponse, isFalse);
    expect(client.issues, isEmpty);
    expect(client.requestTimings, isEmpty);
    expect(client.diagnostics.requests, isEmpty);
    expect(client.diagnostics.fullSyncElapsedMs, isNull);
  }

  test(
      'full sync discards old rows when the session changes during detail read',
      () => verifyStaleDetailFetchIsDiscarded(singleCourse: false));
  test(
      'single-course refresh discards old rows when the session changes during detail read',
      () => verifyStaleDetailFetchIsDiscarded(singleCourse: true));

  test('return reconciliation reads only the selected class homework list',
      () async {
    final queried = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final q = o.uri.queryParameters;
        dynamic body;
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                for (final id in ['11', '22'])
                  {
                    'courseId': '7',
                    'clazzId': id,
                    'courseName': '样例',
                    'cpi': '8'
                  }
              ]
            };
          case '/visit/stucoursemiddle':
            expect(q['clazzid'], '22');
            body =
                '<input id="workEnc" value="signature"><input id="enc" value="student">';
          case '/mooc2/work/list':
            queried.add(q['classId']!);
            final url = Uri.encodeComponent(
                'https://mooc1.chaoxing.com/work/task?courseId=7&classId=22&workId=9&enc=synthetic');
            body =
                '<li onclick="goTask(this);" data="$url"><p class="overHidden2 fl">样例作业</p><p class="status fl">已提交</p></li>';
          case '/work/task':
            body = '作答时间：2026-12-30 09:00 至 2027-01-02 12:00';
          default:
            fail('unexpected endpoint ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
      }));
    final rows = await ChaoxingLocalClient(dio: dio)
        .fetchAssignmentsForCourse(courseId: '7', clazzId: '22');
    expect(queried, ['22']);
    expect(rows.single.clazzId, '22');
    expect(rows.single.isCompleted, isTrue);
  });
  test('explicit logged-out JSON is an authentication error even with cookies',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: o.uri.path == '/v11/loginregister'
                ? {'status': true}
                : o.uri.path == '/mycourse/backclazzdata'
                    ? {'result': false, 'msg': '请先登录'}
                    : '',
            headers: Headers.fromMap({
              'set-cookie': ['UID=dummy; Domain=chaoxing.com; Path=/']
            })));
      }));
    final client = ChaoxingLocalClient(dio: dio);
    await client.login(account: 'dummy', password: 'dummy');
    await expectLater(client.fetchAssignments(),
        throwsA(isA<ChaoxingAuthenticationException>()));
  });
  test('login preserves tracked activities for the authenticated retry',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: o.uri.path == '/v11/loginregister' ? {'status': true} : ''));
      }));
    final client = ChaoxingLocalClient(dio: dio)
      ..trackedActivityIds = {'cx:activity:1'};
    await client.login(account: 'dummy', password: 'dummy');
    expect(client.trackedActivityIds, {'cx:activity:1'});
  });
  test('login cannot restore a session after clearSession during SSO redirect',
      () async {
    final ssoStarted = Completer<void>();
    final ssoResponse = Completer<Response<dynamic>>();
    final dio = Dio()
      ..interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) async {
        if (options.uri.path == '/v11/loginregister') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'status': true,
              'url': 'https://sso.chaoxing.com/login',
            },
          ));
          return;
        }
        if (options.uri.host == 'sso.chaoxing.com') {
          ssoStarted.complete();
          handler.resolve(await ssoResponse.future);
          return;
        }
        fail('unexpected endpoint ${options.uri}');
      }));
    final client = ChaoxingLocalClient(dio: dio);

    final login = client.login(account: 'student', password: 'password');
    await ssoStarted.future;
    client.clearSession();
    ssoResponse.complete(Response(
      requestOptions:
          RequestOptions(path: 'https://sso.chaoxing.com/login', method: 'GET'),
      statusCode: 200,
      data: 'ok',
    ));

    final result = await login;

    expect(result.success, isFalse);
    expect(result.message, contains('会话已切换'));
    expect(client.canHydrateProfile, isFalse,
        reason: 'a stale login must not repopulate _loginPayload');
  });
  test('host-only cookies stay scoped and expired cookies are removed',
      () async {
    final sent = <String, String>{};
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent[o.uri.host] = o.headers['Cookie']?.toString() ?? '';
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: o.uri.path == '/v11/loginregister'
                ? {'status': true, 'url': 'https://sso.chaoxing.com/login'}
                : '',
            headers: Headers.fromMap({
              'set-cookie': o.uri.host == 'passport2-api.chaoxing.com'
                  ? [
                      'private=secret; Path=/',
                      'shared=ok; Domain=chaoxing.com; Path=/',
                      'gone=no; Domain=chaoxing.com; Max-Age=0; Path=/'
                    ]
                  : []
            })));
      }));
    await ChaoxingLocalClient(dio: dio)
        .login(account: 'dummy', password: 'dummy');
    expect(sent['sso.chaoxing.com'], contains('shared=ok'));
    expect(sent['sso.chaoxing.com'], isNot(contains('private=')));
    expect(sent['sso.chaoxing.com'], isNot(contains('gone=')));
  });
  test('login does not send session to an unrelated redirect host', () async {
    final hosts = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        hosts.add(o.uri.host);
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: o.uri.path == '/v11/loginregister'
                ? {
                    'status': true,
                    'url': 'https://chaoxing.com.example.org/collect'
                  }
                : '',
            headers: Headers.fromMap({
              'set-cookie': ['UID=dummy; Path=/']
            })));
      }));
    final result = await ChaoxingLocalClient(dio: dio)
        .login(account: 'dummy', password: 'dummy');
    expect(result.success, isTrue);
    expect(hosts, isNot(contains('chaoxing.com.example.org')));
  });
  test(
      'reads same-name classes separately with course signatures and a per-work detail link',
      () async {
    final queried = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final q = o.uri.queryParameters;
        dynamic body;
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            body = {
              'courses': [
                for (final id in ['11', '22'])
                  {
                    'courseId': '7',
                    'clazzId': id,
                    'courseName': '数学',
                    'cpi': '8'
                  }
              ]
            };
          case '/visit/stucoursemiddle':
            body =
                '<input value="work${q['clazzid']}" id="workEnc"><input id="enc" value="student"><input id="openc" value="open">';
          case '/mooc2/work/list':
            final id = q['classId']!;
            expect(q['enc'], 'work$id');
            expect(q['stuenc'], 'student');
            expect(q['openc'], 'open');
            queried.add(id);
            final url = Uri.encodeComponent(
                'https://mooc1.chaoxing.com/work/task?workId=9&classId=$id&enc=detail');
            body =
                '<li onclick="goTask(this);" data="$url"><p class="overHidden2 fl">已提交格式示例</p><p class="status fl">${id == '11' ? '未提交' : '待批阅'}</p></li>';
          case '/work/task':
            expect(q['enc'], 'detail');
            body = q['classId'] == '11'
                ? '作答时间：2026-12-30 09:00 至 2027-01-02 12:00'
                : '<html>请登录</html>';
          case '/v2/apis/active/student/activelist':
            body = {
              'data': {'activeList': []}
            };
          default:
            fail('unexpected request ${o.uri}');
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
      }));
    final client = ChaoxingLocalClient(dio: dio);
    final work = await client.fetchAssignments();
    expect(queried, ['11', '22']);
    expect(work.map((a) => a.id), ['cx:work:7:11:9', 'cx:work:7:22:9']);
    expect(work.first.status, 'pending');
    expect(work.first.deadlineAt!.toUtc(), DateTime.utc(2027, 1, 2, 4));
    expect(work.last.status, 'reviewing');
    expect(work.last.deadlineAt, isNull);
    expect(work.last.deadlineReadFailed, isFalse);
    expect(client.lastSyncWarning, isNull);
  });

  test('confirmed empty work list succeeds but permission and login pages fail',
      () async {
    var workPage = '<span>0/0</span>';
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final data = switch (o.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '数学'}
              ]
            },
          '/visit/stucoursemiddle' => '<input id="workEnc" value="signature">',
          '/mooc2/work/list' => workPage,
          _ => {
              'data': {'activeList': []}
            },
        };
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final client = ChaoxingLocalClient(dio: dio);
    expect(await client.fetchAssignments(), isEmpty);
    expect(client.lastSyncWarning, isNull);
    for (final bad in ['没有此页面访问权限', '请登录', '<html></html>']) {
      workPage = bad;
      await expectLater(
          client.fetchAssignments(), throwsA(isA<SyncReadException>()));
    }
  });

  test(
      'login follows Chaoxing redirect before resolving profile name and avatar',
      () async {
    final requests = <_RecordedRequest>[];
    final dio = Dio(
      BaseOptions(
        validateStatus: (status) => status != null && status < 500,
      ),
    )..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(
              _RecordedRequest(
                method: options.method,
                host: options.uri.host,
                path: options.uri.path,
                headers: Map<String, dynamic>.from(options.headers),
              ),
            );

            if (options.uri.host == 'passport2-api.chaoxing.com' &&
                options.uri.path == '/v11/loginregister') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'status': true,
                    'url': 'https://sso.chaoxing.com/login?token=ok',
                  },
                ),
              );
              return;
            }

            if (options.uri.host == 'sso.chaoxing.com') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: 'ok',
                  headers: Headers.fromMap({
                    'set-cookie': [
                      'UID=998877; Domain=.chaoxing.com; Path=/; HttpOnly'
                    ],
                  }),
                ),
              );
              return;
            }

            if (options.uri.host == 'i.chaoxing.com' &&
                options.uri.path == '/base') {
              final cookie = options.headers['Cookie']?.toString() ?? '';
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: cookie.contains('UID=998877')
                      ? '<html><span class="user-name">李雷</span></html>'
                      : '<html>未登录</html>',
                ),
              );
              return;
            }

            if (options.uri.host == 'photo.chaoxing.com') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': [
                      'https://p.cldisk.com/star3/160_160c/998877.png',
                    ],
                  }),
                ),
              );
              return;
            }

            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 404,
                data: 'not found',
              ),
            );
          },
        ),
      );
    final client = ChaoxingLocalClient(dio: dio);

    final result = await client.login(account: 'student', password: 'password');

    expect(result.success, isTrue);
    expect(result.displayName, '李雷');
    expect(result.avatarUrl, 'https://p.cldisk.com/star3/160_160c/998877.png');
    expect(requests.map((request) => '${request.host}${request.path}'), [
      'passport2-api.chaoxing.com/v11/loginregister',
      'sso.chaoxing.com/login',
      'i.chaoxing.com/base',
      'photo.chaoxing.com/p/998877_160',
    ]);
    expect(requests.last.headers['Cookie'], contains('UID=998877'));
  });

  test('extracts Chaoxing profile from nested SSO msg payload', () async {
    final dio = Dio(
      BaseOptions(
        validateStatus: (status) => status != null && status < 500,
      ),
    )..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.host == 'passport2-api.chaoxing.com') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'status': true,
                    'url':
                        'https://sso.chaoxing.com/apis/login/userLogin4Uname.do',
                  },
                ),
              );
              return;
            }
            if (options.uri.host == 'sso.chaoxing.com') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'msg': {
                      'name': '样例同学',
                      'nick': '样例同学',
                      'uid': 100001,
                      'puid': 200002,
                      'pic': 'http://photo.chaoxing.com/p/200002_120?flag=1',
                    },
                    'status': true,
                  },
                  headers: Headers.fromMap({
                    'set-cookie': ['UID=100001; Path=/; HttpOnly'],
                  }),
                ),
              );
              return;
            }
            if (options.uri.host == 'i.chaoxing.com' &&
                options.uri.path == '/base') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data:
                      '<html><head><meta name="viewport" content="width=device-width"></head></html>',
                ),
              );
              return;
            }
            if (options.uri.host == 'photo.chaoxing.com') {
              expect(options.uri.path, '/p/200002_120');
              expect(options.uri.queryParameters['flag'], '1');
              expect(options.uri.queryParameters['psize'], '160_160c');
              expect(options.uri.queryParameters['ext'], 'png');
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': [
                      'https://p.cldisk.com/star3/160_160c/sample-avatar.png',
                    ],
                  }),
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 404,
                data: 'not found',
              ),
            );
          },
        ),
      );
    final client = ChaoxingLocalClient(dio: dio);

    final result = await client.login(account: 'student', password: 'password');

    expect(result.success, isTrue);
    expect(result.displayName, '样例同学');
    expect(
      result.avatarUrl,
      'https://p.cldisk.com/star3/160_160c/sample-avatar.png',
    );
  });
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.host,
    required this.path,
    required this.headers,
  });

  final String method;
  final String host;
  final String path;
  final Map<String, dynamic> headers;
}
