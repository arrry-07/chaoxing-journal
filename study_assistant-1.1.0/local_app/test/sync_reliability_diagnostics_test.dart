import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

const _deadlineBody = '作答时间：2026-12-30 09:00 至 2027-01-02 12:00';
const _allowedCategories = {
  '课程列表',
  '课程入口',
  '课程导航',
  '作业列表',
  '作业详情',
  '其他',
};

class _Reply {
  const _Reply(this.status, this.data, {this.headers = const {}});

  final int status;
  final dynamic data;
  final Map<String, List<String>> headers;
}

Response<dynamic> _response(RequestOptions request, _Reply reply) =>
    Response<dynamic>(
      requestOptions: request,
      statusCode: reply.status,
      data: reply.data,
      headers: Headers.fromMap(reply.headers),
    );

Dio _dioFor(
  FutureOr<_Reply> Function(RequestOptions request) handler,
  List<RequestOptions> log,
) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, h) async {
    log.add(request);
    try {
      h.resolve(_response(request, await handler(request)));
    } on DioException catch (error) {
      h.reject(error);
    }
  }));
  return dio;
}

Map<String, dynamic> _course(String id,
        {String clazzId = '2', String name = '课'}) =>
    {'courseId': id, 'clazzId': clazzId, 'courseName': name};

_Reply _courseList(List<Map<String, dynamic>> courses) =>
    _Reply(200, {'courses': courses});

_Reply _v3Middle() =>
    const _Reply(200, '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>');

_Reply _v3Navigation() =>
    const _Reply(200, {'status': true, 'navigationList': []});

_Reply _workPage(int total, List<Map<String, dynamic>> rows) =>
    _Reply(200, {'status': true, 'total': total, 'data': rows});

Map<String, dynamic> _workRow(
  int id, {
  String courseId = '1',
  String clazzId = '2',
  int? endTime,
}) =>
    {
      'title': '题$id',
      'stuStatus': 0,
      'endTime': endTime ?? 0,
      'taskUrl':
          'https://mooc1.chaoxing.com/work/task?workId=$id&courseId=$courseId&classId=$clazzId',
    };

Dio _v3Dio(
  List<List<Map<String, dynamic>>> pages,
  int total,
  List<RequestOptions> log,
) =>
    _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          final page = int.parse(request.uri.queryParameters['pageNum']!);
          final rows = page <= pages.length
              ? pages[page - 1]
              : const <Map<String, dynamic>>[];
          return _workPage(total, rows);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, log);

DioException _timeout(RequestOptions request) => DioException(
      requestOptions: request,
      type: DioExceptionType.connectionTimeout,
    );

void main() {
  test(
      'detail timeouts retry once, open the detail circuit, and reset next sync',
      () async {
    final requests = <RequestOptions>[];
    var failDetails = true;
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(3, [
            for (var id = 1; id <= 3; id++) _workRow(id),
          ]);
        case '/work/task':
          if (failDetails) throw _timeout(request);
          return const _Reply(200, _deadlineBody);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final waits = <Duration>[];
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(requests.where((r) => r.uri.path == '/work/task'), hasLength(2));
    expect(waits, [const Duration(milliseconds: 500)]);
    expect(rows, hasLength(3));
    expect(rows.every((a) => a.deadlineReadFailed), isTrue);
    final details = client.diagnostics.requests['作业详情']!;
    expect(details.count, 2);
    expect(details.failures, 2);
    expect(details.parseCount, 0);
    expect(details.averageHttpMs, greaterThanOrEqualTo(0));
    expect(details.p50HttpMs, greaterThanOrEqualTo(0));
    expect(details.p95HttpMs, greaterThanOrEqualTo(0));
    expect(details.maxHttpMs, greaterThanOrEqualTo(0));
    expect(client.issues.where((issue) => issue.circuitOpen), hasLength(2));
    expect(client.diagnostics.fullSyncElapsedMs, isNotNull);

    failDetails = false;
    final recovered = await client.fetchAssignments();

    expect(requests.where((r) => r.uri.path == '/work/task'), hasLength(5));
    expect(waits, hasLength(1));
    expect(recovered.every((a) => a.deadlineTrusted), isTrue);
    expect(recovered.every((a) => !a.deadlineReadFailed), isTrue);
    expect(client.diagnostics.requests['作业详情']!.count, 3);
    expect(client.diagnostics.requests['作业详情']!.failures, 0);
    expect(client.issues, isEmpty);
  });

  test('detail 403 is classified once and never retried', () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(1, [_workRow(1)]);
        case '/work/task':
          return const _Reply(403, '拒绝访问');
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(requests.where((r) => r.uri.path == '/work/task'), hasLength(1));
    expect(waits, isEmpty);
    expect(rows.single.deadlineReadFailed, isTrue);
    final issue = client.issues
        .firstWhere((issue) => issue.kind == SyncIssueKind.forbidden);
    expect(issue.httpStatus, 403);
    expect(issue.stage, 'detail');
    expect(client.diagnostics.requests['作业详情']!.count, 1);
    expect(client.diagnostics.requests['作业详情']!.failures, 1);
  });

  test('detail 404 preserves the status and is never retried', () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(1, [_workRow(1)]);
        case '/work/task':
          return const _Reply(404, 'not found');
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(requests.where((r) => r.uri.path == '/work/task'), hasLength(1));
    expect(waits, isEmpty);
    expect(rows.single.deadlineReadFailed, isTrue);
    final issue = client.issues
        .firstWhere((issue) => issue.kind == SyncIssueKind.notFound);
    expect(issue.httpStatus, 404);
    expect(client.diagnostics.requests['作业详情']!.count, 1);
    expect(client.diagnostics.requests['作业详情']!.failures, 1);
  });

  test('429 follows a bounded Retry-After exactly and then succeeds', () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    var details = 0;
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(1, [_workRow(1)]);
        case '/work/task':
          details++;
          if (details == 1) {
            return const _Reply(429, 'too many requests', headers: {
              'retry-after': ['1']
            });
          }
          return const _Reply(200, _deadlineBody);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(details, 2);
    expect(waits, [const Duration(seconds: 1)]);
    expect(rows.single.deadlineReadFailed, isFalse);
    expect(client.issues, isEmpty);
    final diagnostics = client.diagnostics.requests['作业详情']!;
    expect(diagnostics.count, 2);
    expect(diagnostics.failures, 1);
  });

  for (final retryAfter in [null, 'invalid-date']) {
    test('429 without a valid Retry-After ($retryAfter) is not retried',
        () async {
      final requests = <RequestOptions>[];
      final waits = <Duration>[];
      final dio = _dioFor((request) async {
        switch (request.uri.path) {
          case '/mycourse/backclazzdata':
            return _courseList([_course('1')]);
          case '/visit/stucoursemiddle':
            return _v3Middle();
          case '/mooc2-ans/coursemanagev3/stu-base-info':
            return _v3Navigation();
          case '/mooc-ans/work/api/task':
            return _workPage(1, [_workRow(1)]);
          case '/work/task':
            return _Reply(
              429,
              'too many requests',
              headers: {
                if (retryAfter != null) 'retry-after': [retryAfter],
              },
            );
          default:
            throw StateError('unexpected endpoint ${request.uri.path}');
        }
      }, requests);
      final client = ChaoxingLocalClient(
        dio: dio,
        wait: (delay) async => waits.add(delay),
      );

      final rows = await client.fetchAssignments();

      expect(requests.where((r) => r.uri.path == '/work/task'), hasLength(1));
      expect(waits, isEmpty);
      expect(rows.single.deadlineReadFailed, isTrue);
      final issue = client.issues
          .firstWhere((issue) => issue.kind == SyncIssueKind.rateLimited);
      expect(issue.httpStatus, 429);
      expect(issue.retryAfter, retryAfter);
      expect(issue.retryAfterSeconds, isNull);
      expect(client.diagnostics.requests['作业详情']!.count, 1);
      expect(client.diagnostics.requests['作业详情']!.failures, 1);
    });
  }

  test('429 Retry-After beyond two seconds is preserved but not awaited',
      () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(1, [_workRow(1)]);
        case '/work/task':
          return const _Reply(429, 'too many requests', headers: {
            'retry-after': ['3']
          });
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(requests.where((r) => r.uri.path == '/work/task'), hasLength(1));
    expect(waits, isEmpty);
    expect(rows.single.deadlineReadFailed, isTrue);
    final issue = client.issues
        .firstWhere((issue) => issue.kind == SyncIssueKind.rateLimited);
    expect(issue.retryAfter, '3');
    expect(issue.retryAfterSeconds, 3);
    expect(issue.httpStatus, 429);
  });

  test('429 accepts an HTTP-date Retry-After when it is within the cap',
      () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    var details = 0;
    final target =
        HttpDate.format(DateTime.now().toUtc().add(const Duration(seconds: 1)));
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(1, [_workRow(1)]);
        case '/work/task':
          details++;
          if (details == 1) {
            return _Reply(429, 'too many requests', headers: {
              'retry-after': [target]
            });
          }
          return const _Reply(200, _deadlineBody);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(details, 2);
    expect(waits, hasLength(1));
    // HttpDate has one-second resolution, so the remaining delay can be shorter
    // than a full second by the time the header is parsed.
    expect(waits.single, lessThanOrEqualTo(const Duration(seconds: 2)));
    expect(rows.single.deadlineReadFailed, isFalse);
  });

  test('5xx retries once and then opens the detail circuit with its status',
      () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(2, [_workRow(1), _workRow(2)]);
        case '/work/task':
          return const _Reply(503, 'unavailable');
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(requests.where((r) => r.uri.path == '/work/task'), hasLength(2));
    expect(waits, [const Duration(milliseconds: 500)]);
    expect(rows.every((a) => a.deadlineReadFailed), isTrue);
    final failed = client.issues.firstWhere((issue) =>
        issue.kind == SyncIssueKind.serverError && !issue.circuitOpen);
    expect(failed.httpStatus, 503);
    expect(client.issues.any((issue) => issue.circuitOpen), isTrue);
    final diagnostics = client.diagnostics.requests['作业详情']!;
    expect(diagnostics.count, 2);
    expect(diagnostics.failures, 2);
  });

  test('the per-sync retry budget stops the third automatic retry', () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    final attempts = <String, int>{};
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(3, [_workRow(1), _workRow(2), _workRow(3)]);
        case '/work/task':
          final id = request.uri.queryParameters['workId']!;
          final attempt = attempts[id] = (attempts[id] ?? 0) + 1;
          if (id != '3') {
            if (attempt == 1) throw _timeout(request);
            return const _Reply(200, _deadlineBody);
          }
          if (attempt == 1) {
            return const _Reply(429, 'too many requests', headers: {
              'retry-after': ['1']
            });
          }
          return const _Reply(200, _deadlineBody);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(attempts, {'1': 2, '2': 2, '3': 1});
    expect(waits, [
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 500),
    ]);
    expect(rows, hasLength(3));
    final third = rows.firstWhere((a) => a.id.endsWith(':3'));
    expect(third.deadlineReadFailed, isTrue);
    final issue = client.issues
        .firstWhere((issue) => issue.kind == SyncIssueKind.rateLimited);
    expect(issue.retryAfter, '1');
    expect(issue.retryAfterSeconds, 1);
    final diagnostics = client.diagnostics.requests['作业详情']!;
    expect(diagnostics.count, 5);
    expect(diagnostics.failures, 3);
  });

  test('5xx honors a short Retry-After before its single retry', () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    var detailAttempts = 0;
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(1, [_workRow(1)]);
        case '/work/task':
          detailAttempts++;
          if (detailAttempts == 1) {
            return const _Reply(503, 'temporarily unavailable', headers: {
              'retry-after': ['1']
            });
          }
          return const _Reply(200, _deadlineBody);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(detailAttempts, 2);
    expect(waits, [const Duration(seconds: 1)]);
    expect(rows.single.deadlineTrusted, isTrue);
    expect(client.issues, isEmpty);
  });

  test('multi-course sync keeps successful work and classifies each failure',
      () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([
            _course('1', name: '课程一'),
            _course('2', name: '课程二'),
            _course('3', name: '课程三'),
          ]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          final courseId = request.uri.queryParameters['courseId'];
          if (courseId == '1') {
            return _workPage(2, [
              _workRow(1, courseId: '1'),
              _workRow(2, courseId: '1'),
            ]);
          }
          if (courseId == '2') return const _Reply(403, '拒绝访问');
          return _workPage(0, const []);
        case '/work/task':
          final workId = request.uri.queryParameters['workId'];
          if (workId == '2') return const _Reply(403, '拒绝访问');
          return const _Reply(200, _deadlineBody);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    final rows = await client.fetchAssignments();

    expect(waits, isEmpty);
    expect(rows, hasLength(2));
    expect(rows.first.deadlineReadFailed, isFalse);
    expect(rows.last.deadlineReadFailed, isTrue);
    expect(client.succeededCourses, 2);
    expect(client.failedCourses, 2);
    expect(client.lastSyncWarning, contains('2 门待重试'));
    expect(
        requests.where((r) => r.uri.path == '/mooc-ans/work/api/task').length,
        3);
    expect(requests.where((r) => r.uri.path == '/work/task'), hasLength(2));
    final workList = client.diagnostics.requests['作业列表']!;
    expect(workList.count, 3);
    expect(workList.failures, 1);
    final details = client.diagnostics.requests['作业详情']!;
    expect(details.count, 2);
    expect(details.failures, 1);
    expect(
        client.issues
            .where((issue) => issue.kind == SyncIssueKind.forbidden)
            .length,
        2);
    expect(
        client.issues.any((issue) =>
            issue.kind == SyncIssueKind.partial && issue.stage == 'detail'),
        isTrue);
  });

  test('V3 multi-page success requests each page exactly once', () async {
    final requests = <RequestOptions>[];
    final deadline = DateTime.utc(2027, 1, 2).millisecondsSinceEpoch;
    final dio = _v3Dio([
      [
        _workRow(1, endTime: deadline),
      ],
      [
        _workRow(2, endTime: deadline),
      ],
    ], 2, requests);

    final rows = await ChaoxingLocalClient(dio: dio).fetchAssignments();

    expect(rows, hasLength(2));
    final workPages = requests
        .where((r) => r.uri.path == '/mooc-ans/work/api/task')
        .map((r) => r.uri.queryParameters['pageNum'])
        .toList();
    expect(workPages, ['1', '2']);
  });

  test('V3 empty page is a schema failure after the exact page count',
      () async {
    final requests = <RequestOptions>[];
    final dio = _v3Dio([
      [
        _workRow(1),
      ],
      [],
    ], 2, requests);
    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});

    await expectLater(
      client.fetchAssignments(),
      throwsA(isA<SyncReadException>()
          .having((e) => e.issue.kind, 'kind', SyncIssueKind.schemaChanged)),
    );

    expect(
        requests.where((r) => r.uri.path == '/mooc-ans/work/api/task').length,
        2);
    expect(client.diagnostics.requests['作业列表']!.count, 2);
    expect(client.diagnostics.requests['作业列表']!.parseFailures, 1);
  });

  test('V3 duplicate page is rejected after the exact page count', () async {
    final requests = <RequestOptions>[];
    final dio = _v3Dio([
      [
        _workRow(1),
      ],
      [
        _workRow(1),
      ],
    ], 2, requests);
    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});

    await expectLater(
      client.fetchAssignments(),
      throwsA(isA<SyncReadException>()
          .having((e) => e.issue.kind, 'kind', SyncIssueKind.schemaChanged)),
    );

    expect(
        requests.where((r) => r.uri.path == '/mooc-ans/work/api/task').length,
        2);
    expect(client.diagnostics.requests['作业列表']!.count, 2);
    expect(client.diagnostics.requests['作业列表']!.parseFailures, greaterThan(0));
  });

  test('V3 total mismatch is rejected after the exact page count', () async {
    final requests = <RequestOptions>[];
    final dio = _v3Dio([
      [
        _workRow(1),
      ],
      [
        _workRow(2),
      ],
      [],
    ], 3, requests);
    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});

    await expectLater(
      client.fetchAssignments(),
      throwsA(isA<SyncReadException>()
          .having((e) => e.issue.kind, 'kind', SyncIssueKind.schemaChanged)),
    );

    expect(
        requests.where((r) => r.uri.path == '/mooc-ans/work/api/task').length,
        3);
    expect(client.diagnostics.requests['作业列表']!.count, 3);
  });

  test('network time and local parsing time are measured separately', () async {
    final requests = <RequestOptions>[];
    final deadline = DateTime.utc(2027, 1, 2).millisecondsSinceEpoch;
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _Reply(
              200,
              jsonEncode({
                'courses': [_course('1')]
              }));
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _Reply(
              200, jsonEncode({'status': true, 'navigationList': []}));
        case '/mooc-ans/work/api/task':
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return _Reply(
            200,
            jsonEncode({
              'status': true,
              'total': 1,
              'data': [
                _workRow(1, endTime: deadline),
              ],
            }),
          );
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});

    final rows = await client.fetchAssignments();

    expect(rows, hasLength(1));
    expect(requests.every((r) => r.responseType == ResponseType.plain), isTrue);
    final workList = client.diagnostics.requests['作业列表']!;
    expect(workList.count, 1);
    expect(workList.averageHttpMs, greaterThanOrEqualTo(20));
    expect(workList.parseCount, greaterThan(0));
    expect(workList.averageParseMs, lessThan(workList.averageHttpMs));
    expect(workList.p50HttpMs, greaterThanOrEqualTo(20));
    expect(workList.maxHttpMs, greaterThanOrEqualTo(20));
    expect(client.diagnostics.fullSyncElapsedMs, greaterThanOrEqualTo(25));
    expect(client.requestTimings['作业列表']!.elapsedMs,
        greaterThanOrEqualTo(workList.averageHttpMs));
  });

  test('diagnostics retain no account, course, work or query identifiers',
      () async {
    final requests = <RequestOptions>[];
    const courseId = '987654321';
    const clazzId = '112233';
    const workId = '445566';
    const courseName = '课程机密';
    const title = '作业机密';
    final deadline = DateTime.utc(2027, 1, 2).millisecondsSinceEpoch;
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([
            _course(courseId, clazzId: clazzId, name: courseName),
          ]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(1, [
            {
              'title': title,
              'stuStatus': 0,
              'endTime': deadline,
              'taskUrl':
                  'https://mooc1.chaoxing.com/work/task?workId=$workId&courseId=$courseId&classId=$clazzId&token=SECRET_TOKEN',
            },
          ]);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});

    final rows = await client.fetchAssignments();
    expect(rows.single.title, title);
    final encoded = jsonEncode(client.diagnostics.toJson());
    for (final secret in [
      courseId,
      clazzId,
      workId,
      courseName,
      title,
      'SECRET_TOKEN',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
    expect(_allowedCategories.containsAll(client.diagnostics.requests.keys),
        isTrue);
    expect(_allowedCategories.containsAll(client.requestTimings.keys), isTrue);
  });

  test('session reset clears diagnostics, request samples and retry state',
      () async {
    final requests = <RequestOptions>[];
    final deadline = DateTime.utc(2027, 1, 2).millisecondsSinceEpoch;
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return _workPage(1, [
            _workRow(1, endTime: deadline),
          ]);
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});

    await client.fetchAssignments();
    expect(client.diagnostics.requests, isNotEmpty);
    expect(client.diagnostics.fullSyncElapsedMs, isNotNull);
    expect(client.requestTimings, isNotEmpty);

    client.clearSession();

    expect(client.diagnostics.requests, isEmpty);
    expect(client.diagnostics.fullSyncElapsedMs, isNull);
    expect(client.requestTimings, isEmpty);
  });

  test('all courses failing keeps a typed issue instead of StateError',
      () async {
    final requests = <RequestOptions>[];
    final waits = <Duration>[];
    final dio = _dioFor((request) async {
      switch (request.uri.path) {
        case '/mycourse/backclazzdata':
          return _courseList([_course('1')]);
        case '/visit/stucoursemiddle':
          return _v3Middle();
        case '/mooc2-ans/coursemanagev3/stu-base-info':
          return _v3Navigation();
        case '/mooc-ans/work/api/task':
          return const _Reply(403, '拒绝访问');
        default:
          throw StateError('unexpected endpoint ${request.uri.path}');
      }
    }, requests);
    final client = ChaoxingLocalClient(
      dio: dio,
      wait: (delay) async => waits.add(delay),
    );

    await expectLater(
      client.fetchAssignments(),
      throwsA(isA<SyncReadException>()
          .having((e) => e.issue.kind, 'kind', SyncIssueKind.forbidden)
          .having((e) => e.issue.httpStatus, 'status', 403)),
    );

    expect(
        requests.where((r) => r.uri.path == '/mooc-ans/work/api/task').length,
        1);
    expect(waits, isEmpty);
    expect(client.issues.single.kind, SyncIssueKind.forbidden);
    expect(client.diagnostics.requests['作业列表']!.count, 1);
    expect(client.diagnostics.requests['作业列表']!.failures, 1);
    expect(client.succeededCourses, 0);
  });
}
