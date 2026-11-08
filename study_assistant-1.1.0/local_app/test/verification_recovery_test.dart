import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

void main() {
  test(
      'real antispider redirect stops course batch; only a valid signed probe confirms verification',
      () async {
    var released = false, probes = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        dynamic data = '';
        var status = 200;
        final headers = <String, List<String>>{};
        switch (o.uri.path) {
          case '/mycourse/backclazzdata':
            data = {
              'courses': [
                for (final id in ['1', '2'])
                  {'courseId': id, 'clazzId': '3', 'courseName': '课程'}
              ]
            };
          case '/visit/stucoursemiddle':
            probes++;
            if (released) {
              data = '<input id="workEnc" value="test">';
            } else {
              status = 302;
              headers['location'] = ['/antispiderShowVerify.ac'];
            }
          case '/processVerifyPng.ac':
            data = [137, 80, 78, 71];
            headers['set-cookie'] = [
              'verify=fixture; Domain=chaoxing.com; Path=/'
            ];
          case '/html/processVerify.ac':
            expect(o.headers['Cookie'], contains('verify=fixture'));
            expect(o.data['ucode'], 'a123');
          case '/mooc2/work/list':
            data = '<span>0/0</span>';
          default:
            fail('unexpected endpoint');
        }
        h.resolve(Response(
            requestOptions: o,
            statusCode: status,
            data: data,
            headers: Headers.fromMap(headers)));
      }));
    final c = ChaoxingLocalClient(dio: dio);
    await expectLater(
        c.fetchAssignments(),
        throwsA(isA<SyncReadException>().having(
            (e) => e.issue.kind, 'kind', SyncIssueKind.verificationRequired)));
    expect(probes, 1);
    expect(c.failedCourses, 2);
    expect(c.issues.single.kind, SyncIssueKind.verificationRequired);
    released = true;
    expect(await c.fetchAssignments(), isEmpty);
    expect(c.succeededCourses, 2);
  });
}
