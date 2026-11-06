import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_assignment_parser.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

void main() {
  final root = Directory('test/fixtures/chaoxing');
  final catalog =
      jsonDecode(File('${root.path}/catalog.json').readAsStringSync()) as Map;
  test(
      'fixture payloads contain no authentication keys or signed query parameters',
      () {
    final forbidden = RegExp(
        r'([?&](enc|workEnc|stuenc|token|cookie|password)=|"(cookie|authorization|password|access_token)"\s*:)',
        caseSensitive: false);
    for (final file in root.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json') && !file.path.endsWith('.html')) {
        continue;
      }
      expect(forbidden.hasMatch(file.readAsStringSync()), false,
          reason: file.path);
    }
  });
  for (final raw in catalog['network'] as List) {
    final entry = raw as Map;
    test('offline fixture: ${entry['name']}', () async {
      final overrides =
          jsonDecode(File('${root.path}/${entry['file']}').readAsStringSync())
              as Map;
      final common =
          jsonDecode(File('${root.path}/common.json').readAsStringSync())
              as Map;
      final routes = {...common, ...overrides};
      final requested = <Uri>[];
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          requested.add(o.uri);
          final route = routes[o.uri.path] as Map?;
          if (route == null) {
            h.reject(DioException(
                requestOptions: o, error: 'Offline fixture has no route'));
            return;
          }
          if (route['status'] == 0) {
            h.reject(DioException(
                requestOptions: o, type: DioExceptionType.connectionTimeout));
            return;
          }
          h.resolve(Response(
              requestOptions: o,
              statusCode: route['status'] as int,
              data: route['body']));
        }));
      final client = ChaoxingLocalClient(dio: dio);
      if (entry['exception'] == 'auth') {
        await expectLater(client.fetchAssignments(),
            throwsA(isA<ChaoxingAuthenticationException>()));
      } else if (entry['exception'] == 'read') {
        await expectLater(
            client.fetchAssignments(),
            throwsA(isA<SyncReadException>().having(
                (e) => e.issue.kind.name, 'issue kind', entry['issueKind'])));
      } else {
        final rows = await client.fetchAssignments();
        expect(rows.map((a) => a.status).toList(), entry['statuses']);
        expect(rows.every((a) => a.isFormal), true);
      }
      expect(client.requestTimings.values.fold<int>(0, (v, m) => v + m.count),
          entry['requests']);
      expect(
          client.requestTimings.values
              .fold<int>(0, (v, m) => v + m.httpFailures),
          entry['httpFailures']);
      expect(
          client.requestTimings.keys.every((k) =>
              {'课程列表', '课程入口', '课程导航', '作业列表', '作业详情', '其他'}.contains(k)),
          true);
      for (final uri in requested) {
        final host = switch (uri.path) {
          '/mycourse/backclazzdata' => 'mooc1-api.chaoxing.com',
          '/mooc2-ans/coursemanagev3/stu-base-info' => 'mooc2-ans.chaoxing.com',
          _ => 'mooc1.chaoxing.com',
        };
        expect(uri.scheme, 'https');
        expect(uri.host, host);
        expect(uri.port, 443);
        expect(uri.userInfo, isEmpty);
      }
      client.clearSession();
      expect(client.requestTimings, isEmpty);
    });
  }
  for (final raw in catalog['deadlines'] as List) {
    final e = raw as Map;
    test('deadline fixture: ${e['file']}', () {
      final result = ChaoxingAssignmentParser.readDetailDeadline(
          File('${root.path}/${e['file']}').readAsStringSync());
      expect(result.noLimit, e['noLimit']);
      expect(result.missingYear, e['missingYear']);
      expect(result.notOpen, e['notOpen']);
      expect(result.deadlineAt?.toUtc().toIso8601String(), e['utc']);
    });
  }
}
