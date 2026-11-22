// Formal-source fixtures intentionally isolate the existing formal request flow.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';

void main() {
  for (final (classQuery, expectedPath) in [
    ('jclassId=2', '/mooc2/work/list'),
    ('classId=2&jclassId=3', '/mooc-ans/work/api/task'),
  ]) {
    test('fanyav3 chooses the signed link only with a consistent $classQuery',
        () async {
      final workRequests = <String>[];
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
          final path = request.uri.path;
          if (path.contains('/work/')) workRequests.add(path);
          final data = switch (path) {
            '/mycourse/backclazzdata' => {
                'courses': [
                  {'courseId': '1', 'clazzId': '2', 'courseName': '合成课程'},
                ],
              },
            '/visit/stucoursemiddle' =>
              '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>',
            '/mooc2-ans/coursemanagev3/stu-base-info' => {
                'status': true,
                'navigationList': [
                  {
                    'linkUrl':
                        '/mooc2/work/list?courseId=1&$classQuery&enc=synthetic'
                  },
                ],
              },
            '/mooc2/work/list' => '<span>0/0</span>',
            '/mooc-ans/work/api/task' => {
                'status': true,
                'total': 0,
                'data': [],
              },
            _ => throw StateError('unexpected endpoint $path'),
          };
          handler.resolve(
              Response(requestOptions: request, statusCode: 200, data: data));
        }));
      final client = ChaoxingLocalClient(
          enableExams: false, enableClassroomTasks: false, dio: dio);
      expect(await client.fetchAssignments(), isEmpty);
      expect(client.succeededCourses, 1);
      expect(workRequests, [expectedPath]);
    });
  }

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
    final c = ChaoxingLocalClient(
        enableExams: false, enableClassroomTasks: false, dio: dio);
    expect(await c.fetchAssignments(), isEmpty);
    expect(c.succeededCourses, 1);
    expect(seen, contains('/mooc2-ans/coursemanagev3/stu-base-info'));
  });
}
