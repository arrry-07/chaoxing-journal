import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';

void main() {
  test(
      'confirmed V3 session reads each next formal list without repeating page and navigation requests',
      () async {
    var middle = 0, nav = 0, work = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic data;
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            data = {
              'courses': [
                for (final id in ['1', '2', '3'])
                  {'courseId': id, 'clazzId': '4', 'courseName': '课'}
              ]
            };
          case '/visit/stucoursemiddle':
            middle++;
            data = '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>';
          case '/mooc2-ans/coursemanagev3/stu-base-info':
            nav++;
            data = {'status': true, 'navigationList': []};
          case '/mooc-ans/work/api/task':
            work++;
            data = {'status': true, 'total': 0, 'data': []};
          default:
            fail('unexpected');
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final c = ChaoxingLocalClient(dio: dio);
    expect(await c.fetchAssignments(), isEmpty);
    expect(c.succeededCourses, 3);
    expect(middle, 1);
    expect(nav, 1);
    expect(work, 3);
  });
}
