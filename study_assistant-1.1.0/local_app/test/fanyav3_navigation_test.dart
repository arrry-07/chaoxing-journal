import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';

void main() {
  test('fanyav3 uses server-provided signed formal homework navigation',
      () async {
    final seen = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seen.add(o.uri.path);
        final data = switch (o.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '课', 'cpi': '3'}
              ]
            },
          '/visit/stucoursemiddle' =>
            '<html><script src="/mooc2-ans-vue/js/fanyav3.js"></script></html>',
          '/mooc2-ans/coursemanagev3/stu-base-info' => {
              'status': true,
              'navigationList': [
                {
                  'linkUrl':
                      'https://mooc1.chaoxing.com/mooc2/work/list?courseId=1&classId=2&enc=server-signature'
                }
              ]
            },
          '/mooc2/work/list' => '<span>0/0</span>',
          _ => throw StateError('unexpected endpoint')
        };
        if (o.uri.path == '/mooc2/work/list') {
          expect(o.uri.queryParameters['enc'], 'server-signature');
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final c = ChaoxingLocalClient(dio: dio);
    expect(await c.fetchAssignments(), isEmpty);
    expect(c.succeededCourses, 1);
    expect(seen, contains('/mooc2-ans/coursemanagev3/stu-base-info'));
  });
}
