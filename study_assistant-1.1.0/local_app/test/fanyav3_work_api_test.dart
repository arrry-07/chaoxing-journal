// Formal-source fixtures intentionally isolate the existing formal request flow.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';

void main() {
  test('fanyav3 formal work status and evaluation matrix', () async {
    final rows = <({
      Object? status,
      int? evaluation,
      String expected,
      bool completed
    })>[];
    for (final status in [0, 1, 2, 3, 4, 5, null, 'invalid']) {
      for (final evaluation in [0, 1]) {
        final expected = switch (status) {
          4 => 'completed',
          5 => 'returned',
          3 when evaluation == 0 => 'reviewing',
          0 || 1 || 2 when evaluation == 0 => 'pending',
          _ => 'unknown',
        };
        rows.add((
          status: status,
          evaluation: evaluation,
          expected: expected,
          completed: expected == 'completed' || expected == 'reviewing'
        ));
      }
    }
    for (final status in [1, 2, 5]) {
      rows.add((
        status: status,
        evaluation: null,
        expected: status == 5 ? 'returned' : 'pending',
        completed: false
      ));
    }
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final Object data;
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
            data = {
              'status': true,
              'total': rows.length,
              'data': [
                for (var i = 0; i < rows.length; i++)
                  {
                    'title': '合成作业 $i',
                    if (rows[i].status != null) 'stuStatus': rows[i].status,
                    if (rows[i].evaluation != null)
                      'evaluation': rows[i].evaluation,
                    'endTime': 1794052800000,
                    'taskUrl':
                        'https://mooc1.chaoxing.com/work/task?workId=${i + 1}&courseId=1&classId=2'
                  }
              ]
            };
          default:
            fail('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final works = await ChaoxingLocalClient(
            enableExams: false, enableClassroomTasks: false, dio: dio)
        .fetchAssignments();
    final byId = {for (final work in works) work.id: work};
    expect(works.length, rows.length);
    expect(byId.length, rows.length);
    for (var i = 0; i < rows.length; i++) {
      final work = byId['cx:work:1:2:${i + 1}'];
      expect(work, isNotNull, reason: 'row $i');
      expect(work!.status, rows[i].expected, reason: 'row $i');
      expect(work.isCompleted, rows[i].completed, reason: 'row $i');
    }
  });

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
    final works = await ChaoxingLocalClient(
            enableExams: false, enableClassroomTasks: false, dio: dio)
        .fetchAssignments();
    expect(pages, ['1', '2']);
    expect(works.map((a) => a.status), ['reviewing', 'unknown']);
    expect(works.every((a) => a.isFormal && a.deadlineTrusted), isTrue);
  });

  test('evaluated returned work stays returned instead of becoming unknown',
      () async {
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
            data = {
              'status': true,
              'total': 1,
              'data': [
                {
                  'title': '退回后待重做',
                  'stuStatus': 5,
                  'evaluation': 1,
                  'endTime': 1794052800000,
                  'taskUrl':
                      'https://mooc1.chaoxing.com/work/task?workId=1&classId=2'
                }
              ]
            };
          default:
            fail('unexpected ${o.uri.path}');
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
      }));
    final works = await ChaoxingLocalClient(
            enableExams: false, enableClassroomTasks: false, dio: dio)
        .fetchAssignments();
    expect(works.single.status, 'returned');
    expect(works.single.isCompleted, isFalse);
  });
}
