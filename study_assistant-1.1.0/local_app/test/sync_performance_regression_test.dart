import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'exam_sync_test.dart' show ExamFixture;

void omitFirstExamCredential(ExamFixture f) {
  var first = true;
  f.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
    if (first && o.uri.path == '/visit/stucoursemiddle') {
      first = false;
      f.middleReads++;
      f.requests.add(o);
      h.resolve(Response(
          requestOptions: o,
          statusCode: 200,
          data: '<input id="workEnc" value="synthetic">'));
    } else {
      h.next(o);
    }
  }));
}

void main() {
  for (final singleCourse in [false, true]) {
    test('one refresh shares credential page, not exam lists ($singleCourse)',
        () async {
      final f = ExamFixture();
      final c = f.client();
      Future<void> refresh() async {
        final rows = singleCourse
            ? await c.fetchAssignmentsForCourse(courseId: '7', clazzId: '11')
            : await c.fetchAssignments();
        expect(
            rows.where((a) => a.isExam && !a.exam!.noticeOnly), hasLength(1));
        expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
            SyncSourcePhase.success);
      }

      await refresh();
      expect(f.middleReads, 1); // Previously two GETs per course per refresh.
      expect(c.requestTimings['课程入口']?.count, 1);
      if (!singleCourse) expect(c.requestTimings['账号考试']?.count, 1);
      expect(f.requests.where((r) => r.uri.path == '/exam/test'), hasLength(1));
      await refresh(); // Manual refresh still contacts all list sources.
      expect(f.middleReads, 2);
      expect(f.requests.where((r) => r.uri.path == '/exam/test'), hasLength(2));
      expect(f.requests.where((r) => r.uri.path.endsWith('/examList')),
          hasLength(2));
      c.clearSession();
      await refresh();
      expect(f.middleReads, 3);
    });
  }

  test('missing exam credential is reread rather than reused', () async {
    final f = ExamFixture();
    omitFirstExamCredential(f);
    final c = f.client();
    await c.fetchAssignments();
    expect(f.middleReads, 2);
    expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.success);
  });

  test('redirects are revalidated while terminal course page is shared',
      () async {
    final f = ExamFixture();
    f.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      if (o.uri.path != '/visit/stucoursemiddle') {
        h.next(o);
        return;
      }
      f.middleReads++;
      f.requests.add(o);
      h.resolve(Response(
          requestOptions: o,
          statusCode: 302,
          headers: Headers.fromMap({
            'location': [
              'https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu?courseid=7&clazzid=11'
            ]
          })));
    }));
    final c = f.client();
    await c.fetchAssignments();
    expect(f.middleReads, 2); // Redirects never cached or bypassed.
    expect(f.requests.where((r) => r.uri.path == '/mooc2-ans/mycourse/stu'),
        hasLength(1)); // Previously two terminal GETs.
    expect(c.requestTimings['课程入口']?.count, 3);
    expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.success);
  });

  test('failed formal collection invalidates shared credentials', () async {
    final f = ExamFixture()..formalHttp = 403;
    await f.client().fetchAssignments();
    expect(f.middleReads, 2);
  });

  test('uncached redirect still rejects changed class identity', () async {
    final f = ExamFixture()
      ..redirectedMiddle = true
      ..redirectedClass = '12';
    omitFirstExamCredential(f);
    final c = f.client();
    await c.fetchAssignments();
    expect(f.middleReads, 2);
    expect(f.requests.any((r) => r.uri.path == '/mooc2-ans/mycourse/stu'),
        isFalse);
    expect(c.sourceResults.firstWhere((s) => s.source == 'exam').phase,
        SyncSourcePhase.partial);
  });

  test('session replacement discards a cancelled refresh cache', () async {
    final f = ExamFixture()..gate = Completer<void>();
    final c = f.client();
    final old = c.fetchAssignments();
    await f.started.future;
    c.clearSession();
    f.gate!.complete();
    expect(await old, isEmpty);
    f.gate = null;
    await c.fetchAssignments();
    expect(f.middleReads, 2);
  });
}
