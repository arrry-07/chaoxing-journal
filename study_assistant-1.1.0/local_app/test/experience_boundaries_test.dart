import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_assignment_parser.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('late profile response cannot replace the next account cookie',
      () async {
    final started = Completer<void>(), release = Completer<void>();
    var logins = 0;
    String cookie = '';
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        if (o.uri.path == '/base') {
          started.complete();
          await release.future;
          h.resolve(Response(
              requestOptions: o,
              statusCode: 200,
              data: '',
              headers: Headers.fromMap({
                'set-cookie': ['UID=old; Domain=chaoxing.com; Path=/']
              })));
          return;
        }
        if (o.uri.path == '/mycourse/backclazzdata') {
          cookie = o.headers['Cookie']?.toString() ?? '';
          h.resolve(Response(
              requestOptions: o, statusCode: 200, data: {'courses': []}));
          return;
        }
        if (o.uri.path == '/v11/loginregister') {
          logins++;
          h.resolve(Response(
              requestOptions: o,
              statusCode: 200,
              data: {'status': true},
              headers: Headers.fromMap({
                'set-cookie': ['UID=$logins; Domain=chaoxing.com; Path=/']
              })));
          return;
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: ''));
      }));
    final c = ChaoxingLocalClient(dio: dio)..deferProfile = true;
    await c.login(account: 'A', password: 'dummy');
    final old = c.loadProfile();
    await started.future;
    c.clearSession();
    await c.login(account: 'B', password: 'dummy');
    release.complete();
    await old;
    await c.fetchAssignments();
    expect(cookie, contains('UID=2'));
    expect(cookie, isNot(contains('UID=old')));
  });
  test('unrecognized course entries count as failed and have an issue',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final body = switch (o.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '课'},
                {'unexpected': true}
              ]
            },
          '/visit/stucoursemiddle' => '<input id="workEnc" value="s">',
          '/mooc2/work/list' => '暂无作业',
          _ => ''
        };
        h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
      }));
    final c = ChaoxingLocalClient(dio: dio);
    expect(await c.fetchAssignments(), isEmpty);
    expect(c.failedCourses, 1);
    expect(c.issues.single.kind, SyncIssueKind.schemaChanged);
  });
  test(
      'source migration survives restart without deleting history or merging classes',
      () async {
    Assignment a(String id) => Assignment(
        id: id,
        courseName: '同名课',
        title: id,
        deadlineAt: null,
        requirementsText: '',
        status: 'unknown',
        lastSyncedAt: DateTime(2026, 11, 4));
    final old = [
      a('cx:work:1:2:3'),
      a('cx:work:1:4:3'),
      a('cx:activity:1:2:3'),
      a('cx:exam:1:2:3'),
      a('cx:manual:3'),
      a('old')
    ];
    SharedPreferences.setMockInitialValues({
      'local_assignments':
          jsonEncode(old.map((a) => a.toJson()..remove('source')).toList())
    });
    final first = await LocalAssignmentRepository().loadJournal();
    expect(first.length, 6);
    expect(first.where((a) => a.isFormal).length, 2);
    await LocalAssignmentRepository().mergeAndSave([]);
    final second = await LocalAssignmentRepository().loadJournal();
    expect(second.map((a) => a.source), first.map((a) => a.source));
    expect(second.map((a) => a.id).toSet().length, 6);
  });
  for (final sample in [
    (403, 'denied', SyncIssueKind.forbidden),
    (200, '<html>安全验证 captcha</html>', SyncIssueKind.verificationRequired),
    (200, '{"unexpected":{}}', SyncIssueKind.schemaChanged)
  ]) {
    test('course response classified as ${sample.$3.name}', () async {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (o, h) => h.resolve(Response(
                requestOptions: o, statusCode: sample.$1, data: sample.$2))));
      await expectLater(
          ChaoxingLocalClient(dio: dio).fetchAssignments(),
          throwsA(isA<SyncReadException>()
              .having((e) => e.issue.kind, 'kind', sample.$3)));
    });
  }
  test('confirmed empty course list is a successful empty result', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(
              requestOptions: o, statusCode: 200, data: {'courses': []}))));
    expect(await ChaoxingLocalClient(dio: dio).fetchAssignments(), isEmpty);
  });
  test('explicit start year disambiguates yearless cross-year end', () {
    expect(
        ChaoxingAssignmentParser.parseDetailDeadline(
                '作答时间：2026-12-30 09:00 至 01-02 12:00')!
            .toUtc(),
        DateTime.utc(2027, 1, 2, 4));
    expect(
        ChaoxingAssignmentParser.parseDetailDeadline('截止时间：2026-03-09 15:49',
                now: DateTime(2026, 11, 4))!
            .toUtc(),
        DateTime.utc(2026, 3, 9, 7, 49));
  });
}
