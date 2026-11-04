import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';

void main() {
  test('legacy HTTP course redirect is upgraded before session is sent',
      () async {
    final visited = <Uri>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        visited.add(o.uri);
        final data = switch (o.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '数学'}
              ]
            },
          '/visit/stucoursemiddle' => '',
          '/mycourse/studentcourse' => '<input id="workEnc" value="fixture">',
          '/mooc2/work/list' => '<span>0/0</span>',
          _ => ''
        };
        h.resolve(Response(
            requestOptions: o,
            statusCode: o.uri.path == '/visit/stucoursemiddle' ? 302 : 200,
            data: data,
            headers: Headers.fromMap(o.uri.path == '/visit/stucoursemiddle'
                ? {
                    'location': [
                      'http://mooc1-1.chaoxing.com/mycourse/studentcourse?enc=fixture'
                    ]
                  }
                : {})));
      }));
    expect(await ChaoxingLocalClient(dio: dio).fetchAssignments(), isEmpty);
    expect(
        visited.any(
            (u) => u.path == '/mycourse/studentcourse' && u.scheme == 'https'),
        isTrue);
    expect(visited.every((u) => u.scheme == 'https'), isTrue);
  });
}
