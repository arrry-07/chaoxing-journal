import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

void main() {
  for (final value in [0, null]) {
    test(
        'V3 $value is not no-limit: fetch original detail URL for exact cutoff',
        () async {
      var details = 0;
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
                'total': 1,
                'data': [
                  {
                    'title': '题',
                    'stuStatus': 0,
                    'endTime': value,
                    'taskUrl':
                        'https://mooc1.chaoxing.com/work/task?workId=1&classId=2&enc=fixture-only'
                  }
                ]
              },
            '/work/task' => '作答时间：2026-11-04 08:00 至 2026-11-09 23:59',
            _ => throw StateError('unexpected')
          };
          if (o.uri.path == '/work/task') {
            details++;
            expect(o.uri.queryParameters['enc'], 'fixture-only');
          }
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        }));
      final c = ChaoxingLocalClient(dio: dio);
      final work = await c.fetchAssignments();
      expect(details, 1);
      expect(
          work.single.deadlineAt!.toUtc(), DateTime.utc(2026, 11, 9, 15, 59));
      expect(work.single.deadlineTrusted, isTrue);
      expect(work.single.deadlineReadFailed, isFalse);
    });
  }
  test('old zero-valued cache is demoted without deleting work', () {
    final a = Assignment(
        id: 'cx:work:1:2:3',
        courseName: '课',
        title: '题',
        deadlineAt: null,
        deadlineRawText: '0',
        deadlineTrusted: true,
        status: 'pending',
        requirementsText: '',
        lastSyncedAt: DateTime.now());
    final restored = Assignment.fromJson(a.toJson());
    expect(restored.id, a.id);
    expect(restored.deadlineTrusted, isFalse);
    expect(restored.deadlineLabel, isNot('未设置截止时间'));
  });
}
