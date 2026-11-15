import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_web_link.dart';

import 'classroom_client_integration_test.dart' show ClassroomFixture;

const publication = '11111111-1111-4111-8111-111111111111';
const relation = '22222222-2222-4222-8222-222222222222';
const studentPath = '/ai-evaluate/v2/redirect/active/stu';
const answerPath = '/mooc2-ans/ai-evaluate/v2/answer';
const studentUrl =
    'https://mooc2-ans.chaoxing.com$studentPath?courseid=7&clazzid=11&publishUuid=$publication';

class AiFixture {
  bool mixed = false;
  int personalHttp = 200;
  final legacy = ClassroomFixture();
  bool completed = false, wrongUser = false, failPersonal = false;
  bool wrongPerson = false, wrongRelation = false, missingEntry = false;
  final paths = <String>[];
  Completer<void>? gate;
  final started = Completer<void>();
  late final dio = Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      paths.add(o.uri.path);
      dynamic body;
      var status = 200;
      final headers = <String, List<String>>{
        'set-cookie': ['UID=123; Domain=.chaoxing.com; Path=/; Secure']
      };
      switch (o.uri.path) {
        case '/mycourse/backclazzdata':
          body = {
            'courses': [
              {
                'courseId': '7',
                'clazzId': '11',
                'courseName': '合成课程',
                'cpi': '8'
              }
            ]
          };
        case '/visit/stucoursemiddle':
          body = '<input id="workEnc" value="synthetic">';
        case '/mooc2/work/list':
          body = mixed
              ? '<li onclick="goTask(this);" data="https%3A%2F%2Fmooc1.chaoxing.com%2Fwork%2Ftask%3FcourseId%3D7%26classId%3D11%26workId%3D9"><p class="overHidden2 fl">合成正式作业</p><p class="status fl">已提交</p></li>'
              : '<div class="no_data">暂无作业</div>';
        case '/v2/apis/active/student/activelist':
          body = {
            'result': 1,
            'data': {
              'activeList': [
                if (mixed) ...[
                  {'id': '35', 'activeType': 35, 'nameOne': '个人任务'},
                  {'id': '42', 'activeType': 42, 'nameOne': '随堂练习'}
                ],
                {
                  'id': '77',
                  'activeType': 77,
                  'nameOne': 'AI 实践',
                  'status': 2,
                  'userStatus': 1,
                  'isLook': 1,
                  if (!missingEntry)
                    'content': jsonEncode({'stuUrl': studentUrl})
                }
              ]
            }
          };
        case studentPath:
          status = 302;
          body = '';
          headers['location'] = [
            'https://mooc2-ans.chaoxing.com$answerPath?courseid=7&clazzid=11&cpi=8&publishRelationUuid=$relation'
          ];
        case answerPath:
          body = [
            '<input id="courseId" value="7">',
            '<input id="clazzId" value="11">',
            '<input id="cpi" value="8">',
            '<input id="currentUserId" value="${wrongUser ? 'other' : '123'}">',
            '<input id="publishRelationUuid" value="$relation">',
          ].join();
        case '$answerPath/load-data':
          if (gate != null) {
            if (!started.isCompleted) started.complete();
            await gate!.future;
          }
          status = personalHttp;
          expect(o.queryParameters['publishRelationUuid'], relation);
          expect(o.queryParameters['cpi'], '8');
          expect(o.queryParameters['recordUuid'], '');
          body = {
            'status': !failPersonal,
            'data': {
              'personId': wrongPerson ? '999' : '8',
              'publishRelationUuid': wrongRelation ? publication : relation,
              'answerCount': completed ? 2 : 0,
              'scoreCount': completed ? 2 : 0,
              if (completed) 'answerScore': 88,
              'publishSetting': {'scoreType': 2, 'reachStandard': 60},
              'endTime': '2030-01-02 00:00:00',
              'answerRecords': <dynamic>[],
            }
          };
        default:
          if (mixed) {
            h.resolve(await legacy.dio.fetch(o));
            return;
          }
          throw StateError('unexpected synthetic AI request ${o.uri.path}');
      }
      h.resolve(Response(
          requestOptions: o,
          statusCode: status,
          data: body,
          headers: Headers.fromMap(headers)));
    }));
}

void main() {
  for (final code in [200, 429]) {
    test('AI personal failure $code preserves formal, task and quiz sources',
        () async {
      final f = AiFixture()
        ..mixed = true
        ..failPersonal = true
        ..personalHttp = code;
      final c = ChaoxingLocalClient(dio: f.dio);
      final rows = await c.fetchAssignments();
      expect(rows.where((a) => a.isFormal).length, 1);
      expect(rows.where((a) => a.activityType == 35).single.status, 'pending');
      expect(rows.where((a) => a.activityType == 42).single.status, 'pending');
      expect(rows.where((a) => a.activityType == 77).single.status, 'unknown');
      for (final key in [
        'courseWork',
        'classroomActivity:35',
        'classroomActivity:42'
      ]) {
        expect(c.sourceResults.singleWhere((s) => s.source == key).phase,
            SyncSourcePhase.success);
      }
      expect(
          c.sourceResults
              .singleWhere((s) => s.source == 'classroomActivity:77')
              .phase,
          SyncSourcePhase.partial);
    });
  }

  for (final cancel in [false, true]) {
    test(
        'AI late response after ${cancel ? 'cancellation' : 'session replacement'} is discarded',
        () async {
      final f = AiFixture()..gate = Completer<void>();
      final c = ChaoxingLocalClient(dio: f.dio);
      final future = c.fetchAssignments();
      await f.started.future;
      if (cancel) {
        c.cancelActiveRequests();
      } else {
        c.clearSession();
      }
      f.gate!.complete();
      if (cancel) {
        await expectLater(
            future,
            throwsA(isA<SyncReadException>()
                .having((e) => e.issue.kind, 'kind', SyncIssueKind.cancelled)));
      } else {
        expect(await future, isEmpty);
        expect(c.sourceResults, isEmpty);
      }
    });
  }

  for (final completed in [false, true]) {
    test(
        'AI practice uses its own personal API and enters assignment scope: $completed',
        () async {
      final f = AiFixture()..completed = completed;
      final c = ChaoxingLocalClient(dio: f.dio);
      final rows = await c.fetchAssignments();
      expect(rows, hasLength(1));
      final a = rows.single;
      expect(a.activityType, 77);
      expect(a.activityId, '77');
      expect(a.courseTaskKey, 'cx:activity:7:11:77');
      expect(a.status, completed ? 'submitted' : 'pending');
      expect(a.deadlineAt!.toUtc(), DateTime.utc(2030, 1, 1, 16));
      expect(a.deadlineTrusted, isTrue);
      expect(AssignmentQuery.scope(rows, {}), rows);
      expect(AssignmentWebLink.validatedUrl(a), studentUrl);
      expect(f.paths, contains('$answerPath/load-data'));
      expect(f.paths.any((p) => p.contains('/quiz/')), isFalse);
      final source = c.sourceResults
          .singleWhere((s) => s.source == 'classroomActivity:77');
      expect(source.phase, SyncSourcePhase.success);
      expect(source.unconfirmedCount, 0);
    });
  }
  for (final failure in ['user', 'person', 'relation', 'personal', 'entry']) {
    test(
        'AI $failure failure retains a scoped unknown record and partial source',
        () async {
      final f = AiFixture()
        ..completed = true
        ..wrongUser = failure == 'user'
        ..wrongPerson = failure == 'person'
        ..wrongRelation = failure == 'relation'
        ..failPersonal = failure == 'personal'
        ..missingEntry = failure == 'entry';
      final c = ChaoxingLocalClient(dio: f.dio);
      final a = (await c.fetchAssignments()).single;
      expect(a.isInAssignmentScope, isTrue);
      expect(a.status, 'unknown');
      expect(a.isPendingConfirmed, isFalse);
      expect(
          c.sourceResults
              .singleWhere((s) => s.source == 'classroomActivity:77')
              .phase,
          SyncSourcePhase.partial);
    });
  }
}
