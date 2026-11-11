import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/home_sync_presentation.dart';

Map<String, dynamic> row(int id, {int status = 0, int end = 0}) => {
      'title': '题$id',
      'stuStatus': status,
      'startTime': DateTime.utc(2024, 10, 27).millisecondsSinceEpoch,
      'endTime': end,
      'taskUrl': 'https://mooc1.chaoxing.com/work/task?workId=$id&classId=2'
    };

ChaoxingLocalClient client(List<Map<String, dynamic>> rows,
    void Function(RequestOptions, RequestInterceptorHandler) detail,
    {int courseCount = 1}) {
  final dio = Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.uri.path == '/work/task') return detail(o, h);
      final data = switch (o.uri.path) {
        '/mycourse/backclazzdata' => {
            'courses': [
              for (var i = 1; i <= courseCount; i++)
                {'courseId': '$i', 'clazzId': '2', 'courseName': '课$i'}
            ]
          },
        '/visit/stucoursemiddle' =>
          '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>',
        '/mooc2-ans/coursemanagev3/stu-base-info' => {'status': true},
        '/mooc-ans/work/api/task' => {
            'status': true,
            'total': rows.length,
            'data': rows
          },
        _ => throw StateError('unexpected route ${o.uri.path}')
      };
      h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
    }));
  return ChaoxingLocalClient(dio: dio, wait: (_) async {});
}

Assignment oldWork() => Assignment(
    id: 'cx:work:1:2:1',
    courseName: '课',
    title: '题',
    deadlineAt: DateTime.utc(2024, 11, 5, 15, 59),
    requirementsText: '',
    status: 'pending',
    deadlineRawText: '2024-11-05 23:59',
    lastSyncedAt: DateTime.utc(2024));

void main() {
  test('detail authentication expiry retains fresh rows and stops later reads',
      () async {
    var calls = 0;
    final progress = <AssignmentSyncProgress>[];
    final c = client([row(1), row(2)], (o, h) {
      calls++;
      h.resolve(
          Response(requestOptions: o, statusCode: 401, data: 'login required'));
    }, courseCount: 2);
    c.onProgress = progress.add;
    final work = await c.fetchAssignments();
    expect(work, hasLength(2));
    expect(calls, 1);
    expect(
        c.issues.any(
            (i) => i.stage == 'detail' && i.kind == SyncIssueKind.authExpired),
        isTrue);
    expect(
        c.issues.any((i) =>
            i.stage == 'workList' && i.kind == SyncIssueKind.authExpired),
        isTrue);
    expect(progress.last.pendingDetailIds, isEmpty);
    expect(progress.last.resolvedCount, 2);
    final summary = HomeSyncPresentation.from(
        SyncReport(phase: SyncPhase.partial, issues: c.issues),
        loading: false,
        hasCache: true,
        now: DateTime.now());
    expect(summary.action, HomeSyncAction.login);
  });
  test('detail challenge with unread courses cannot claim detail-only failure',
      () async {
    final c = client(
        [row(1)],
        (o, h) => h.resolve(
            Response(requestOptions: o, statusCode: 200, data: '请完成安全验证')),
        courseCount: 2);
    final work = await c.fetchAssignments();
    expect(work, hasLength(1));
    final summary = HomeSyncPresentation.from(
        SyncReport(phase: SyncPhase.partial, issues: c.issues),
        loading: false,
        hasCache: true,
        now: DateTime.now());
    expect(summary.summary, '部分课程未更新');
    expect(summary.action, HomeSyncAction.verify);
    expect(c.issues.any((i) => i.stage == 'workList'), isTrue);
  });
  test('HTTP200 permission page is forbidden rather than unknown schema',
      () async {
    final c = client(
        [row(1)],
        (o, h) => h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: '<html>没有此页面访问权限</html>')));
    final work = await c.fetchAssignments();
    expect(work, hasLength(1));
    expect(
        c.issues.any(
            (i) => i.stage == 'detail' && i.kind == SyncIssueKind.forbidden),
        isTrue);
  });
  test('not-open detail reports its actual boundary without inventing cutoff',
      () async {
    final c = client(
        [row(1)],
        (o, h) => h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: '<p>该作业未开始，开始时间：2026-11-05 08:00</p>')));
    final work = await c.fetchAssignments();
    expect(work.single.deadlineAt, isNull);
    expect(work.single.deadlineLabel, '尚未开放，截止时间待确认');
    expect(c.issues.first.message, contains('尚未开放'));
    final summary = HomeSyncPresentation.from(
        SyncReport(phase: SyncPhase.partial, issues: c.issues),
        loading: false,
        hasCache: true,
        now: DateTime.now());
    expect(summary.summary, '部分截止时间待确认');
    expect(summary.showCached, isFalse);
  });
  test('same-work start restores historical cutoff and calendar day', () async {
    final c = client(
        [row(1)],
        (o, h) => h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: '作答时间：10-27 08:00 至 11-05 23:59')));
    final work = await c.fetchAssignments();
    expect(work.single.deadlineAt!.toUtc(), DateTime.utc(2024, 11, 5, 15, 59));
    expect(c.issues, isEmpty);
    expect(
        AssignmentQuery.forDay(work, DateTime(2024, 11, 5), {}), hasLength(1));
    expect(AssignmentQuery.forDay(work, DateTime(2026, 11, 5), {}), isEmpty);
  });

  for (final kind in [SyncIssueKind.network, SyncIssueKind.forbidden]) {
    test('$kind retains new work and the previously verified deadline',
        () async {
      final c = client([row(1)], (o, h) {
        if (kind == SyncIssueKind.network) {
          h.reject(DioException(
              requestOptions: o, type: DioExceptionType.connectionTimeout));
        } else {
          h.resolve(Response(requestOptions: o, statusCode: 403, data: '拒绝访问'));
        }
      });
      final work = await c.fetchAssignments();
      expect(work, hasLength(1));
      expect(work.single.deadlineReadFailed, isTrue);
      expect(
          c.issues.any((i) => i.kind == kind && i.stage == 'detail'), isTrue);
      final merged =
          LocalAssignmentRepository.mergeAssignments([oldWork()], work);
      expect(merged.single.deadlineAt, oldWork().deadlineAt);
      expect(merged.single.deadlineTrusted, isTrue);
      expect(merged.single.deadlineReadFailed, isTrue);
    });
  }

  test('only explicit unlimited detail clears a previous date', () async {
    final c = client(
        [row(1)],
        (o, h) => h.resolve(
            Response(requestOptions: o, statusCode: 200, data: '截止时间：不限')));
    final work = await c.fetchAssignments();
    final merged =
        LocalAssignmentRepository.mergeAssignments([oldWork()], work);
    expect(merged.single.deadlineAt, isNull);
    expect(merged.single.deadlineTrusted, isTrue);
    expect(merged.single.deadlineReadFailed, isFalse);
  });

  test('challenge stops remaining details without discarding list rows',
      () async {
    var calls = 0;
    final c = client([row(1), row(2)], (o, h) {
      calls++;
      h.resolve(Response(
          requestOptions: o, statusCode: 200, data: '<html>请完成安全验证</html>'));
    });
    final work = await c.fetchAssignments();
    expect(calls, 1);
    expect(work, hasLength(2));
    expect(work.every((a) => a.deadlineReadFailed), isTrue);
    expect(
        c.issues.any((i) =>
            i.kind == SyncIssueKind.verificationRequired &&
            i.stage == 'detail'),
        isTrue);
  });

  test('known list timestamps and completed work avoid detail requests',
      () async {
    final c = client([
      row(1, end: DateTime.utc(2026, 11, 5).millisecondsSinceEpoch),
      row(2, status: 4)
    ], (o, h) => fail('must not request a detail'));
    final work = await c.fetchAssignments();
    expect(work.first.deadlineAt!.toUtc(), DateTime.utc(2026, 11, 5));
    expect(work.last.isCompleted, isTrue);
  });

  test('first trusted deadline is visible while the second detail is pending',
      () async {
    final secondStarted = Completer<void>();
    final secondGate = Completer<void>();
    final events = <AssignmentSyncProgress>[];
    final c = client([row(1), row(2)], (options, handler) async {
      final id = options.uri.queryParameters['workId'];
      if (id == '2') {
        secondStarted.complete();
        await secondGate.future;
      }
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: '作答时间：10-27 08:00 至 11-05 23:59',
      ));
    });
    c.onProgress = events.add;

    final fetching = c.fetchAssignments();
    await secondStarted.future;

    final interim = events.last;
    final first =
        interim.assignments.singleWhere((item) => item.id == 'cx:work:1:2:1');
    final second =
        interim.assignments.singleWhere((item) => item.id == 'cx:work:1:2:2');
    expect(interim.stage, AssignmentSyncStage.details);
    expect(first.deadlineAt, isNotNull);
    expect(first.deadlineTrusted, isTrue);
    expect(second.deadlineAt, isNull);
    expect(interim.pendingDetailIds, {'cx:work:1:2:2'});
    expect(interim.attemptedCount, 2);
    expect(interim.resolvedCount, 1);

    secondGate.complete();
    final complete = await fetching;
    await pumpEventQueue();
    expect(complete, hasLength(2));
    expect(events.last.pendingDetailIds, isEmpty);
    expect(events.last.resolvedCount, 2);
  });

  test('mismatched year remains visible and excluded from calendar', () async {
    final c = client(
        [row(1)],
        (o, h) => h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: '作答时间：10-28 08:00 至 11-05 23:59')));
    final work = await c.fetchAssignments();
    expect(work.single.deadlineLabel, '截止 11-05 23:59（年份待确认）');
    expect(work.single.deadlineTrusted, isFalse);
    expect(AssignmentQuery.forDay(work, DateTime(2024, 11, 5), {}), isEmpty);
    expect(
        AssignmentQuery.home(work, DateTime(2024), {}).uncertain, hasLength(1));
  });
}
