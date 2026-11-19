// Formal-source fixtures intentionally isolate the existing formal request flow.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

void main() {
  test(
      'signed homework uses the same work API start to resolve a yearless period',
      () async {
    var metadataReads = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        final data = switch (options.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '7', 'clazzId': '11', 'courseName': '样例课程'}
              ]
            },
          '/visit/stucoursemiddle' => '<input id="workEnc" value="synthetic">',
          '/mooc2/work/list' => '''
<li onclick="goTask(this);"
 data="https://mooc1.chaoxing.com/work/task?courseId=7&amp;classId=11&amp;workId=9">
 <p class="overHidden2 fl">合成作业</p><p class="status fl">未提交</p>
</li>''',
          '/work/task' => '作答时间：10-27 08:00 至 11-05 23:59',
          '/mooc-ans/work/api/task' => {
              'status': true,
              'total': 1,
              'data': [
                {
                  'title': '合成作业',
                  'stuStatus': 0,
                  'startTime': DateTime.utc(2024, 10, 27, 0, 0, 47)
                      .millisecondsSinceEpoch,
                  'endTime': 0,
                  'taskUrl':
                      'https://mooc1.chaoxing.com/work/task?courseId=7&classId=11&workId=9'
                }
              ]
            },
          _ => throw StateError('unexpected route ${options.uri.path}')
        };
        if (options.uri.path == '/mooc-ans/work/api/task') {
          metadataReads++;
          expect(options.uri.queryParameters['courseId'], '7');
          expect(options.uri.queryParameters['classId'], '11');
        }
        handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data));
      }));
    final client = ChaoxingLocalClient(
        enableExams: false,
        enableClassroomTasks: false,
        dio: dio,
        wait: (_) async {});
    final works = await client.fetchAssignments();
    expect(works, hasLength(1));
    expect(works.single.deadlineAt?.toUtc(), DateTime.utc(2024, 11, 5, 15, 59));
    expect(works.single.deadlineTrusted, isTrue);
    expect(works.single.deadlineReadFailed, isFalse);
    expect(works.single.status, 'pending');
    expect(client.failedCourses, 0);
    expect(client.issues, isEmpty);
    expect(metadataReads, 1);
  });

  test('signed yearless period rolls over from a matched historical start',
      () async {
    final h = _Harness(
      details: {9: '作答时间：12-31 08:00 至 01-01 23:59'},
      rows: [_row(9, start: DateTime.utc(2024, 12, 31, 0, 0, 59))],
    );
    final work = (await h.client.fetchAssignments()).single;
    expect(work.deadlineAt?.toUtc(), DateTime.utc(2025, 1, 1, 15, 59));
    expect(work.deadlineTrusted, isTrue);
    expect(work.deadlineReadFailed, isFalse);
    expect(h.metadataReads, 1);
  });

  test('mismatched start, absent start and another work cannot supply a year',
      () async {
    final scenarios = <String, Map<String, dynamic>>{
      'different minute': _row(9, start: DateTime.utc(2024, 10, 27, 0, 1)),
      'absent start': _row(9),
      'another work with identical title': _row(99, start: _start)
        ..['title'] = 'HTML作业9',
    };
    for (final scenario in scenarios.entries) {
      final h = _Harness(rows: [scenario.value]);
      final work = (await h.client.fetchAssignments()).single;
      _expectUnconfirmed(work, reason: scenario.key);
      expect(work.id, 'cx:work:7:11:9', reason: scenario.key);
      expect(h.metadataReads, 1, reason: scenario.key);
      expect(h.client.succeededCourses, 1, reason: scenario.key);
      expect(
          h.client.issues.any((i) =>
              i.kind == SyncIssueKind.schemaChanged && i.stage == 'detail'),
          isTrue,
          reason: scenario.key);
    }
  });

  for (final wrongIdentity in ['course', 'class']) {
    test('signed anchor rejects metadata with the wrong $wrongIdentity',
        () async {
      final h = _Harness(rows: [
        _row(9, start: _start),
        _row(99,
            start: _start,
            courseId: wrongIdentity == 'course' ? '99' : '7',
            clazzId: wrongIdentity == 'class' ? '99' : '11'),
      ]);
      final work = (await h.client.fetchAssignments()).single;
      // Even the valid row preceding the identity failure must not leak.
      _expectUnconfirmed(work);
      expect(work.id, 'cx:work:7:11:9');
      expect(h.client.succeededCourses, 1);
      expect(h.client.failedCourses, greaterThan(0));
      expect(
          h.client.issues.any((i) =>
              i.kind == SyncIssueKind.schemaChanged && i.stage == 'detail'),
          isTrue);
      expect(h.metadataReads, 1);
    });
  }

  for (final status in [503, 401]) {
    test('supplementary API $status retains HTML rows and classifies failure',
        () async {
      final h = _Harness(
          ids: [9, 10],
          onMetadata: (request, handler) {
            handler.resolve(Response(
                requestOptions: request,
                statusCode: status,
                data: status == 401
                    ? 'login required'
                    : 'temporarily unavailable'));
          });
      final works = await h.client.fetchAssignments();
      expect(works.map((w) => w.id),
          unorderedEquals(['cx:work:7:11:9', 'cx:work:7:11:10']));
      for (final work in works) {
        _expectUnconfirmed(work, hasYearText: false);
      }
      final kind =
          status == 401 ? SyncIssueKind.authExpired : SyncIssueKind.serverError;
      expect(h.client.issues.any((i) => i.kind == kind && i.stage == 'detail'),
          isTrue);
      expect(h.client.succeededCourses, 1);
      expect(h.client.failedCourses, greaterThan(0));
      expect(h.client.lastSyncWarning, isNotNull);
      if (status == 401) {
        expect(h.metadataReads, 1);
        expect(h.detailReads, [9]);
      } else {
        // Retries are permitted; a second row must not restart the lookup.
        expect(h.metadataReads, 1 + h.retryWaits);
        expect(h.detailReads, [9, 10]);
        expect(
            h.client.issues.any((i) =>
                i.kind == SyncIssueKind.serverError && i.httpStatus == 503),
            isTrue);
      }
    });
  }

  test('exact, unlimited and submitted HTML work resolve deadlines safely',
      () async {
    final h = _Harness(ids: [
      9,
      10,
      11
    ], statuses: {
      11: '已提交'
    }, details: {
      9: '作答时间：2024-10-27 08:00 至 2024-11-05 23:59',
      10: '作答时间：不限',
      11: '作答时间：2024-10-27 08:00 至 2024-11-06 23:59',
    });
    final works = await h.client.fetchAssignments();
    final byId = {for (final work in works) work.id: work};
    expect(works, hasLength(3));
    expect(byId['cx:work:7:11:9']!.deadlineAt?.toUtc(),
        DateTime.utc(2024, 11, 5, 15, 59));
    expect(byId['cx:work:7:11:9']!.deadlineTrusted, isTrue);
    expect(byId['cx:work:7:11:10']!.deadlineAt, isNull);
    expect(byId['cx:work:7:11:10']!.deadlineTrusted, isTrue);
    expect(byId['cx:work:7:11:10']!.deadlineReadFailed, isFalse);
    expect(byId['cx:work:7:11:11']!.status, 'submitted');
    expect(byId['cx:work:7:11:11']!.deadlineAt!.toUtc(),
        DateTime.utc(2024, 11, 6, 15, 59));
    expect(byId['cx:work:7:11:11']!.deadlineReadFailed, isFalse);
    expect(h.metadataReads, 0);
    expect(h.detailReads, [9, 10, 11]);
    expect(h.client.issues, isEmpty);
  });

  test('one lookup anchors HTML rows without importing API rows or states',
      () async {
    final h = _Harness(ids: [
      9,
      10
    ], statuses: {
      10: '已退回'
    }, rows: [
      _row(9, start: _start, status: 4),
      _row(10, start: _start, status: 3),
      _row(99, start: _start),
    ]);
    final events = <AssignmentSyncProgress>[];
    h.client.onProgress = events.add;
    final works = await h.client.fetchAssignments();
    final byId = {for (final work in works) work.id: work};
    expect(byId.keys, unorderedEquals(['cx:work:7:11:9', 'cx:work:7:11:10']));
    expect(byId['cx:work:7:11:9']!.status, 'pending');
    expect(byId['cx:work:7:11:10']!.status, 'returned');
    for (final work in works) {
      expect(work.title, startsWith('HTML作业'));
      expect(work.deadlineAt?.toUtc(), DateTime.utc(2024, 11, 5, 15, 59));
      expect(work.deadlineTrusted, isTrue);
      expect(work.deadlineReadFailed, isFalse);
    }
    expect(h.metadataReads, 1);
    expect(h.detailReads, [9, 10]);
    expect(events, isNotEmpty);
    for (final event in events) {
      expect(event.assignments.map((w) => w.id),
          isNot(contains('cx:work:7:11:99')));
      expect(
          event.assignments.every((w) => w.title.startsWith('HTML作业')), isTrue);
      expect(
          event.assignments.every((w) =>
              w.status == (w.id.endsWith(':9') ? 'pending' : 'returned')),
          isTrue);
    }
    expect(h.client.issues, isEmpty);
  });

  test('signed anchor can come from the second metadata page', () async {
    final pages = <String>[];
    final h = _Harness(onMetadata: (request, handler) {
      final page = request.uri.queryParameters['pageNum']!;
      pages.add(page);
      expect(['1', '2'], contains(page));
      handler.resolve(_ok(
          request,
          _page([
            _row(page == '1' ? 99 : 9, start: _start),
          ], total: 2)));
    });
    final work = (await h.client.fetchAssignments()).single;
    expect(pages, ['1', '2']);
    expect(work.id, 'cx:work:7:11:9');
    expect(work.deadlineAt?.toUtc(), DateTime.utc(2024, 11, 5, 15, 59));
    expect(work.deadlineTrusted, isTrue);
    expect(h.detailReads, [9]);
    expect(h.client.issues, isEmpty);
  });

  test('invalid later metadata page cannot expose an earlier page anchor',
      () async {
    final pages = <String>[];
    final h = _Harness(onMetadata: (request, handler) {
      final page = request.uri.queryParameters['pageNum']!;
      pages.add(page);
      expect(['1', '2'], contains(page));
      handler.resolve(_ok(
          request,
          _page([
            page == '1'
                ? _row(9, start: _start)
                : _row(99, start: _start, clazzId: '99'),
          ], total: 2)));
    });
    final work = (await h.client.fetchAssignments()).single;
    expect(pages, ['1', '2']);
    _expectUnconfirmed(work);
    expect(work.id, 'cx:work:7:11:9');
    expect(
        h.client.issues.any((i) =>
            i.kind == SyncIssueKind.schemaChanged && i.stage == 'detail'),
        isTrue);
  });

  test(
      'supplementary V3 500 circuit does not block the next healthy HTML course',
      () async {
    final h = _Harness(
      courses: [
        {'courseId': '7', 'clazzId': '11', 'courseName': '合成课程A'},
        {'courseId': '8', 'clazzId': '12', 'courseName': '合成课程B'},
      ],
      courseWorkIds: {
        '7': [9],
        '8': [20]
      },
      details: {20: '作答时间：2024-10-27 08:00 至 2024-11-06 23:59'},
      onMetadata: (request, handler) {
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 500,
          data: 'synthetic supplementary service failure',
        ));
      },
    );
    final works = await h.client.fetchAssignments();

    expect(h.metadataReads, 2,
        reason: 'the supplementary failure must exercise consecutive failures');
    expect(
      h.requests
          .where((uri) => uri.path == '/mooc2/work/list')
          .map((uri) => uri.queryParameters['courseId']),
      ['7', '8'],
      reason:
          'the failed optional lookup must not prevent a real B HTML request',
    );
    expect(works.map((work) => work.id),
        unorderedEquals(['cx:work:7:11:9', 'cx:work:8:12:20']));
    final a = works.singleWhere((work) => work.courseId == '7');
    final b = works.singleWhere((work) => work.courseId == '8');
    _expectUnconfirmed(a);
    expect(b.title, 'HTML作业20');
    expect(b.status, 'pending');
    expect(b.deadlineAt?.toUtc(), DateTime.utc(2024, 11, 6, 15, 59));
    expect(b.deadlineTrusted, isTrue);
    expect(b.deadlineReadFailed, isFalse);
    expect(h.detailReads, [9, 20]);
    expect(h.client.succeededCourses, 2);
    expect(
        h.client.issues.any((issue) =>
            issue.kind == SyncIssueKind.serverError &&
            issue.httpStatus == 500 &&
            issue.courseKey == '7:11'),
        isTrue);
    expect(
        h.client.issues.where((issue) => issue.courseKey == '8:12'), isEmpty);
  });

  test(
      'active cancellation during supplementary lookup stops details and preview',
      () async {
    final started = Completer<void>();
    final cancellationObserved = Completer<DioException>();
    final h = _Harness(
        ids: [9, 10],
        onMetadata: (request, handler) async {
          final token = request.cancelToken;
          expect(token, isNotNull);
          started.complete();
          // Unlike clearSession/late-response mocks, this transport cannot finish
          // until the actual request token is cancelled. Return that cancel error.
          final cancellation = await token!.whenCancel;
          cancellationObserved.complete(cancellation);
          handler.reject(cancellation);
        });
    addTearDown(() => h.client.cancelActiveRequests());
    final events = <AssignmentSyncProgress>[];
    h.client.onProgress = events.add;
    Object? failure;
    final settled = h.client.fetchAssignments().then<void>((_) {},
        onError: (Object error, StackTrace stack) {
      failure = error;
    });
    await started.future.timeout(const Duration(seconds: 5));
    expect(h.detailReads, [9]);
    expect(events.any((event) => event.assignments.length == 2), isTrue);
    final eventsAtCancellation = events.length;

    h.client.cancelActiveRequests();
    final cancellation =
        await cancellationObserved.future.timeout(const Duration(seconds: 5));
    expect(cancellation.type, DioExceptionType.cancel);
    await settled.timeout(const Duration(seconds: 5));
    await pumpEventQueue();

    expect(h.detailReads, [9],
        reason: 'an explicit stop must not start the second HTML detail');
    expect(events.length, eventsAtCancellation,
        reason: 'no preview event may be emitted after the explicit stop');
    expect(h.metadataReads, 1);
    expect(
        failure,
        isA<SyncReadException>().having(
            (error) => error.issue.kind, 'kind', SyncIssueKind.cancelled));
  });

  test('clearSession during supplementary metadata discards a late response',
      () async {
    final started = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final h = _Harness(onMetadata: (request, handler) async {
      started.complete();
      await release.future;
      handler.resolve(_ok(request, _page([_row(9, start: _start)])));
    });
    final events = <AssignmentSyncProgress>[];
    h.client.onProgress = events.add;
    final fetching = h.client.fetchAssignments();
    await started.future.timeout(const Duration(seconds: 5));
    expect(events.any((e) => e.assignments.isNotEmpty), isTrue);
    h.client.clearSession();
    release.complete();
    final works = await fetching;
    await pumpEventQueue();
    expect(works, isEmpty);
    expect(h.client.courses, isEmpty);
    expect(h.client.succeededCourses, 0);
    expect(h.client.failedCourses, 0);
    expect(h.client.issues, isEmpty);
    expect(h.client.requestTimings, isEmpty);
    expect(events.expand((e) => e.assignments).any((w) => w.deadlineAt != null),
        isFalse,
        reason: 'a stale anchor cannot resolve the previous session preview');
    expect(h.metadataReads, 1);
  });
}

final _start = DateTime.utc(2024, 10, 27, 0, 0, 47);

void _expectUnconfirmed(Assignment work,
    {String? reason, bool hasYearText = true}) {
  expect(work.deadlineAt, isNull, reason: reason);
  expect(work.deadlineTrusted, isFalse, reason: reason);
  expect(work.deadlineReadFailed, isTrue, reason: reason);
  if (hasYearText) {
    expect(work.deadlineRawText, contains('年份待确认'), reason: reason);
  }
}

Map<String, dynamic> _row(int id,
        {DateTime? start,
        String courseId = '7',
        String clazzId = '11',
        int status = 0}) =>
    {
      'title': 'API作业$id',
      'stuStatus': status,
      if (start != null) 'startTime': start.millisecondsSinceEpoch,
      // A different absolute end must not replace the HTML detail evidence.
      'endTime': DateTime.utc(2030, 1, 1).millisecondsSinceEpoch,
      'taskUrl':
          'https://mooc1.chaoxing.com/work/task?courseId=$courseId&classId=$clazzId&workId=$id',
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> rows, {int? total}) =>
    {'status': true, 'total': total ?? rows.length, 'data': rows};

Response<dynamic> _ok(RequestOptions request, dynamic data) =>
    Response(requestOptions: request, statusCode: 200, data: data);

class _Harness {
  _Harness({
    List<int> ids = const [9],
    List<Map<String, dynamic>>? courses,
    Map<String, List<int>>? courseWorkIds,
    Map<int, String> details = const {},
    Map<int, String> statuses = const {},
    List<Map<String, dynamic>>? rows,
    FutureOr<void> Function(RequestOptions, RequestInterceptorHandler)?
        onMetadata,
  }) {
    final dio = Dio()
      ..interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) async {
        requests.add(request.uri);
        dynamic data;
        switch (request.uri.path) {
          case '/mycourse/backclazzdata':
            data = {
              'courses': courses ??
                  [
                    {'courseId': '7', 'clazzId': '11', 'courseName': '样例课程'}
                  ]
            };
          case '/visit/stucoursemiddle':
            data = '<input id="workEnc" value="synthetic">';
          case '/mooc2/work/list':
            final courseId = request.uri.queryParameters['courseId']!;
            final clazzId = request.uri.queryParameters['classId']!;
            final workIds = courseWorkIds?[courseId] ?? ids;
            data = workIds.map((id) => '''
<li onclick="goTask(this);"
 data="https://mooc1.chaoxing.com/work/task?courseId=$courseId&amp;classId=$clazzId&amp;workId=$id">
 <p class="overHidden2 fl">HTML作业$id</p>
 <p class="status fl">${statuses[id] ?? '未提交'}</p>
</li>''').join();
          case '/work/task':
            final id = int.parse(request.uri.queryParameters['workId']!);
            data = details[id] ?? '作答时间：10-27 08:00 至 11-05 23:59';
          case '/mooc-ans/work/api/task':
            expect(request.uri.queryParameters['courseId'], '7');
            expect(request.uri.queryParameters['classId'], '11');
            if (onMetadata != null) {
              await onMetadata(request, handler);
              return;
            }
            expect(request.uri.queryParameters['pageNum'], '1');
            data = _page(rows ?? [_row(9, start: _start)]);
          default:
            fail('unexpected route ${request.uri.path}');
        }
        handler.resolve(_ok(request, data));
      }));
    client = ChaoxingLocalClient(
        enableExams: false,
        enableClassroomTasks: false,
        dio: dio,
        wait: (_) async {
          retryWaits++;
        });
  }

  final requests = <Uri>[];
  int retryWaits = 0;
  late final ChaoxingLocalClient client;

  int get metadataReads =>
      requests.where((uri) => uri.path == '/mooc-ans/work/api/task').length;

  List<int> get detailReads => requests
      .where((uri) => uri.path == '/work/task')
      .map((uri) => int.parse(uri.queryParameters['workId']!))
      .toList();
}
