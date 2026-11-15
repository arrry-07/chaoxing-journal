import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';

class ClassroomFixture {
  bool formalFails = false,
      listFails = false,
      taskFails = false,
      wrongUser = false;
  bool answered = false, deleted = false;
  bool invalidExtraCourse = false, hasFormal = false, duplicateActivity = false;
  int totalCourses = 1, taskHttpStatus = 200;
  String activeClass = '11';
  final paths = <String>[];
  Completer<void>? gate;
  final started = Completer<void>();
  late final dio = Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      paths.add(o.uri.path);
      dynamic data;
      var code = 200;
      switch (o.uri.path) {
        case '/mycourse/backclazzdata':
          data = {
            'courses': [
              for (var i = 0; i < totalCourses; i++)
                {
                  'courseId': '${7 + i}',
                  'clazzId': '${11 + i}',
                  'courseName': '合成课程',
                  'cpi': '8'
                },
              if (invalidExtraCourse)
                {'courseId': 'invalid-course', 'clazzId': 'invalid-class'},
            ]
          };
        case '/visit/stucoursemiddle':
          if (formalFails) {
            code = 403;
            data = 'forbidden';
          } else {
            data = '<input id="workEnc" value="synthetic">';
          }
        case '/mooc2/work/list':
          final q = o.uri.queryParameters;
          final url = Uri.encodeComponent(
              'https://mooc1.chaoxing.com/work/task?courseId=${q['courseId']}&classId=${q['classId']}&workId=9&enc=synthetic');
          data = hasFormal
              ? '<li onclick="goTask(this);" data="$url"><p class="overHidden2 fl">合成正式作业</p><p class="status fl">已提交</p></li>'
              : '<div class="no_data">暂无作业</div>';
        case '/v2/apis/active/student/activelist':
          activeClass = o.queryParameters['classId'].toString();
          expect(o.queryParameters['showNotStartedActive'], 0);
          data = listFails
              ? {'result': 0}
              : {
                  'result': 1,
                  'data': {
                    'activeList': [
                      {'id': '35', 'activeType': 35, 'nameOne': '个人任务'},
                      {
                        'id': duplicateActivity ? '35' : '42',
                        'activeType': 42,
                        'nameOne': '随堂练习'
                      },
                      {'id': '47', 'activeType': 47, 'nameOne': '计时器'}
                    ]
                  }
                };
        case '/v2/apis/taskStu/getActiveInfoForMe':
          if (gate != null) {
            if (!started.isCompleted) started.complete();
            await gate!.future;
          }
          data = {
            'result': 1,
            'data': {
              'isNorm': 1,
              'toAnswerPage': 1,
              'useNoteEditor': 1,
              'isDelete': deleted ? 1 : 0
            }
          };
        case '/v2/apis/task/getTaskActiveInfo':
          data = {'result': 1, 'data': active('35')};
        case '/v2/apis/taskStu/getMyGroupInfo':
          if (taskFails || taskHttpStatus != 200) {
            code = taskFails ? 403 : taskHttpStatus;
            data = 'forbidden';
          } else {
            data = {
              'result': 1,
              'data': {
                'pptUserAttend': attend('35'),
                'groupId': 9,
                'taskGroupInfo': {
                  'activeId': '35',
                  'id': 9,
                  'submitStatus': 0,
                  'submitTime': null
                }
              }
            };
          }
        case '/v2/apis/quiz/quizDetail2':
          expect(o.queryParameters['moreClassAttendEnc'], '');
          expect(o.queryParameters['DB_STRATEGY'], 'PRIMARY_KEY');
          expect(o.queryParameters['STRATEGY_PARA'], 'activeId');
          data = {
            'result': 1,
            'data': {
              'pptActive': active('42'),
              'hasAnswerPermission': 1,
              'pptUserAttend': attend('42')
            }
          };
        case '/v2/apis/studentQuestion/getAnswerResult':
          data = {
            'result': 1,
            'data': {
              'uid': wrongUser ? 'other' : '123',
              'isAnswered': answered,
              'active': active('42')
            }
          };
        default:
          throw StateError('unexpected synthetic request');
      }
      h.resolve(Response(
          requestOptions: o,
          statusCode: code,
          data: data,
          headers: Headers.fromMap({
            'set-cookie': ['UID=123; Domain=.chaoxing.com; Path=/; Secure']
          })));
    }));
  Map<String, dynamic> active(String id) => {
        'id': id,
        'clazzid': activeClass,
        'courseId': null,
        'activeType': int.parse(id),
        'endtime': 1796140800000,
        'status': 2
      };
  Map<String, dynamic> attend(String id) =>
      {'uid': '123', 'activeId': id, 'groupId': 9, 'status': 0};
}

void main() {
  test('an unparsed course keeps both classroom baselines incomplete',
      () async {
    final f = ClassroomFixture()..invalidExtraCourse = true;
    final c = ChaoxingLocalClient(dio: f.dio);
    expect((await c.fetchAssignments()).length, 2);
    expect(c.failedCourses, 1);
    for (final s in c.sourceResults
        .where((s) => s.source.startsWith('classroomActivity:'))) {
      expect(s.phase, SyncSourcePhase.partial);
      expect(s.failedCourses, 1);
      expect(s.reasonCodes, contains('courseIdentityFailed'));
    }
  });
  test('activity authentication expiry retains successfully read formal work',
      () async {
    final f = ClassroomFixture()
      ..hasFormal = true
      ..taskHttpStatus = 401;
    final c = ChaoxingLocalClient(dio: f.dio);
    final rows = await c.fetchAssignments();
    expect(rows.where((a) => a.isFormal).length, 1);
    expect(c.sourceResults.first.phase, SyncSourcePhase.success);
    expect(c.sourceResults[1].phase, SyncSourcePhase.partial);
    expect(c.issues.any((i) => i.kind == SyncIssueKind.authExpired), isTrue);
  });
  test('type35 rate limit does not stop type42 in subsequent courses',
      () async {
    final f = ClassroomFixture()
      ..totalCourses = 2
      ..taskHttpStatus = 429;
    final c = ChaoxingLocalClient(dio: f.dio);
    final rows = await c.fetchAssignments();
    expect(
        rows.where((a) => a.activityType == 42 && a.status == 'pending').length,
        2);
    expect(c.sourceResults[2].phase, SyncSourcePhase.success);
    expect(c.sourceResults[1].failedCourses, 2);
    expect(
        f.paths.where((p) => p == '/v2/apis/taskStu/getMyGroupInfo').length, 1);
  });
  for (final cancel in [false, true]) {
    test(
        'last progress callback ${cancel ? 'cancels' : 'switches session'} without restoring old source results',
        () async {
      final f = ClassroomFixture();
      final c = ChaoxingLocalClient(dio: f.dio);
      var changed = false;
      c.onProgress = (p) {
        if (!changed && p.resolvedCount == 2 && p.pendingDetailIds.isEmpty) {
          changed = true;
          if (cancel) {
            c.cancelActiveRequests();
          } else {
            c.clearSession();
          }
        }
      };
      final future = c.fetchAssignments();
      if (cancel) {
        await expectLater(
            future,
            throwsA(isA<SyncReadException>()
                .having((e) => e.issue.kind, 'kind', SyncIssueKind.cancelled)));
      } else {
        expect(await future, isEmpty);
        expect(c.sourceResults, isEmpty);
      }
      expect(changed, isTrue);
    });
  }
  test('conflicting types for the same activity never overwrite each other',
      () async {
    final f = ClassroomFixture()..duplicateActivity = true;
    final c = ChaoxingLocalClient(dio: f.dio);
    expect(await c.fetchAssignments(), isEmpty);
    expect(
        c.sourceResults
            .where((s) => s.source.startsWith('classroomActivity:'))
            .every((s) => s.phase == SyncSourcePhase.failed),
        isTrue);
  });
  for (final single in [false, true]) {
    test(
        'normal ${single ? 'single-course' : 'full'} entry reads 35/42 without inbox and excludes 47',
        () async {
      final f = ClassroomFixture();
      final c = ChaoxingLocalClient(dio: f.dio);
      final rows = single
          ? await c.fetchAssignmentsForCourse(courseId: '7', clazzId: '11')
          : await c.fetchAssignments();
      expect(rows.map((a) => a.activityType).toSet(), {35, 42});
      expect(
          rows.every((a) =>
              a.status == 'pending' &&
              a.isInAssignmentScope &&
              a.deadlineTrusted),
          isTrue);
      expect(c.issues, isEmpty);
      expect(
          c.sourceResults
              .where((s) => s.phase == SyncSourcePhase.success)
              .length,
          4);
      expect(c.sourceResults.last.phase, SyncSourcePhase.notEnabled);
    });
  }
  test('formal access refusal does not discard valid classroom tasks',
      () async {
    final f = ClassroomFixture()..formalFails = true;
    final c = ChaoxingLocalClient(dio: f.dio);
    expect((await c.fetchAssignments()).length, 2);
    expect(c.sourceResults.first.phase, SyncSourcePhase.failed);
    expect(c.sourceResults[1].phase, SyncSourcePhase.success);
  });
  test('personal failure stays unknown and cannot contaminate another source',
      () async {
    final f = ClassroomFixture()
      ..taskFails = true
      ..answered = true;
    final c = ChaoxingLocalClient(dio: f.dio);
    final rows = await c.fetchAssignments();
    expect(rows.firstWhere((a) => a.activityType == 35).isPendingConfirmed,
        isFalse);
    expect(rows.firstWhere((a) => a.activityType == 42).status, 'submitted');
    expect(c.sourceResults[1].phase, SyncSourcePhase.partial);
    expect(c.sourceResults[2].phase, SyncSourcePhase.success);
  });
  test('another users answer cannot establish submission', () async {
    final f = ClassroomFixture()
      ..wrongUser = true
      ..answered = true;
    final c = ChaoxingLocalClient(dio: f.dio);
    final rows = await c.fetchAssignments();
    expect(rows.firstWhere((a) => a.activityType == 42).status, 'unknown');
    expect(rows.firstWhere((a) => a.activityType == 35).status, 'pending');
  });
  test(
      'deleted task stays outside the assignment scope without personal requests',
      () async {
    final f = ClassroomFixture()..deleted = true;
    final c = ChaoxingLocalClient(dio: f.dio);
    final rows = await c.fetchAssignments();
    expect(rows.firstWhere((a) => a.activityType == 35).availability,
        AssignmentAvailability.unavailable);
    expect(f.paths, isNot(contains('/v2/apis/taskStu/getMyGroupInfo')));
  });
  test('session replacement retracts classroom preview and discards late data',
      () async {
    final f = ClassroomFixture()..gate = Completer<void>();
    final c = ChaoxingLocalClient(dio: f.dio);
    final future = c.fetchAssignments();
    await f.started.future;
    c.clearSession();
    f.gate!.complete();
    expect(await future, isEmpty);
    expect(c.sourceResults, isEmpty);
    expect(c.issues, isEmpty);
  });
  test('explicit cancellation is never a valid empty source', () async {
    final f = ClassroomFixture()..gate = Completer<void>();
    final c = ChaoxingLocalClient(dio: f.dio);
    final future = c.fetchAssignments();
    await f.started.future;
    c.cancelActiveRequests();
    f.gate!.complete();
    await expectLater(
        future,
        throwsA(isA<SyncReadException>()
            .having((e) => e.issue.kind, 'kind', SyncIssueKind.cancelled)));
  });
}
