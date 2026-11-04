import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';

void main() {
  test(
      'normal signed course page can include captcha library without a challenge',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final data = switch (o.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '数学'}
              ]
            },
          '/visit/stucoursemiddle' =>
            '<html><script src="/js/captcha.js"></script><input id="workEnc" value="test"></html>',
          '/mooc2/work/list' => '<span>0/0</span>',
          _ => ''
        };
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final client = ChaoxingLocalClient(dio: dio);
    expect(await client.fetchAssignments(), isEmpty);
    expect(client.succeededCourses, 1);
  });
  test('login completes every trusted SSO redirect before returning', () async {
    final paths = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        paths.add(o.uri.path);
        h.resolve(Response(
            requestOptions: o,
            statusCode: o.uri.path == '/sso/start' ? 302 : 200,
            headers: Headers.fromMap(o.uri.path == '/sso/start'
                ? {
                    'location': ['https://i.chaoxing.com/sso/end']
                  }
                : {}),
            data: o.uri.path == '/v11/loginregister'
                ? {'status': true, 'url': 'https://i.chaoxing.com/sso/start'}
                : ''));
      }));
    await (ChaoxingLocalClient(dio: dio)..deferProfile = true)
        .login(account: 'fixture', password: 'fixture');
    expect(paths, contains('/sso/end'));
  });
}
