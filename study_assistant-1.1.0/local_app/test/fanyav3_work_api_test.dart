import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';

void main() {
  test(
      'fanyav3 formal homework API keeps submitted and unknown distinct, follows all pages',
      () async {
    final pages = <String>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic data;
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            data = {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '课'}
              ]
            };
          case '/visit/stucoursemiddle':
            data = '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>';
          case '/mooc2-ans/coursemanagev3/stu-base-info':
            data = {'status': true, 'navigationList': []};
          case '/mooc-ans/work/api/task':
            pages.add(o.uri.queryParameters['pageNum']!);
            data = {
              'status': true,
              'total': 2,
              'data': [
                {
                  'title': '正式题',
                  'stuStatus': pages.length == 1 ? 3 : null,
                  'endTime': 1794052800000,
                  'taskUrl':
                      'https://mooc1.chaoxing.com/work/task?workId=${pages.length}&classId=2'
                }
              ]
            };
          default:
            fail('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final works = await ChaoxingLocalClient(dio: dio).fetchAssignments();
    expect(pages, ['1', '2']);
    expect(works.map((a) => a.status), ['reviewing', 'unknown']);
    expect(works.every((a) => a.isFormal && a.deadlineTrusted), isTrue);
  });
}
