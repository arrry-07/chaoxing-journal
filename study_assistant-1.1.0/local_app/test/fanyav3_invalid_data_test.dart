import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

void main() {
  for (final bad in ['negativeTotal', 'wrongClass', 'tooManyRows']) {
    test('formal work rejects $bad instead of complete success', () async {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          final data = switch (o.uri.path) {
            '/mycourse/backclazzdata' => {
                'courses': [
                  {'courseId': '1', 'clazzId': '2', 'courseName': '课'}
                ]
              },
            '/visit/stucoursemiddle' =>
              '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>',
            '/mooc2-ans/coursemanagev3/stu-base-info' => {
                'status': true,
                'navigationList': []
              },
            '/mooc-ans/work/api/task' => {
                'status': true,
                'total': bad == 'negativeTotal'
                    ? -1
                    : bad == 'tooManyRows'
                        ? 0
                        : 1,
                'data': bad == 'negativeTotal'
                    ? []
                    : [
                        {
                          'title': '题',
                          'endTime': 0,
                          'taskUrl':
                              'https://mooc1.chaoxing.com/work/task?workId=1&classId=${bad == 'wrongClass' ? '99' : '2'}'
                        }
                      ]
              },
            _ => throw StateError('unexpected')
          };
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        }));
      final c = ChaoxingLocalClient(dio: dio);
      await expectLater(
          c.fetchAssignments(),
          throwsA(isA<SyncReadException>().having(
              (e) => e.issue.kind, 'kind', SyncIssueKind.schemaChanged)));
      expect(c.succeededCourses, 0);
    });
  }
}
