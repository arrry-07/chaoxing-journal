import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/sync_scope.dart';

void main() {
  test('sync stage labels describe the actual source boundary', () {
    AssignmentSyncProgress progress(AssignmentSyncStage stage,
            {int unconfirmed = 0}) =>
        AssignmentSyncProgress(
          stage: stage,
          assignments: const [],
          pendingDetailIds: const {},
          resolvedCount: 0,
          attemptedCount: 0,
          unconfirmedCount: unconfirmed,
        );
    expect(progress(AssignmentSyncStage.courses).stageLabel, '正在读取课程');
    expect(progress(AssignmentSyncStage.workLists).stageLabel, '正在读取作业');
    expect(progress(AssignmentSyncStage.classroomTasks).stageLabel, '正在读取课堂任务');
    expect(progress(AssignmentSyncStage.exams).stageLabel, '作业已读取 · 正在读取考试');
    expect(progress(AssignmentSyncStage.exams, unconfirmed: 2).stageLabel,
        '作业已读取，部分截止待确认 · 正在读取考试');
  });

  test('scoped client reports planned, completed, skipped, and failed counts',
      () async {
    final events = <AssignmentSyncProgress>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final path = o.uri.path;
        if (path == '/mycourse/backclazzdata') {
          h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: jsonEncode({
              'courses': [
                {
                  'courseId': '1',
                  'clazzId': '10',
                  'courseName': '本学期成功课',
                },
                {
                  'courseId': '2',
                  'clazzId': '20',
                  'courseName': '本学期失败课',
                },
                {
                  'courseId': '3',
                  'clazzId': '30',
                  'courseName': '往期归档课',
                },
              ],
            }),
          ));
          return;
        }
        if (path == '/visit/stucoursemiddle') {
          final courseId = o.uri.queryParameters['courseid'];
          h.resolve(Response(
            requestOptions: o,
            statusCode: courseId == '2' ? 500 : 200,
            data: courseId == '2' ? 'error' : '<input id="workEnc" value="w">',
          ));
          return;
        }
        if (path == '/mooc2/work/list') {
          h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: '<div>暂无作业</div>',
          ));
          return;
        }
        if (path == '/phone/moocAnalysis/examList') {
          h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data:
                '<div class="ybox"><p class="blankTips">您好，本课程下暂未收到考试</p></div>',
          ));
          return;
        }
        if (path == '/exam-ans/exam/test/examcode/examlist') {
          h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data:
                '<table class="dataTable"><tr><th>考试名称</th><th>作答状态</th></tr></table><script>page.showPage(0/12+1,Math.ceil(0/12));</script>',
          ));
          return;
        }
        if (path == '/pc/notice/getNoticeList') {
          h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: {'status': true},
          ));
          return;
        }
        throw StateError('unexpected path $path');
      }));

    final client = ChaoxingLocalClient(
      dio: dio,
      enableClassroomTasks: false,
      wait: (_) async {},
    )..onProgress = events.add;
    client.nextSyncCourseSelector = (catalog) => SyncScopeSelection(
          scope: AssignmentSyncScope.current,
          targetCourses: catalog.take(2).toList(),
          skippedCourseKeys: const {'3:30'},
          includeAccountExams: true,
        );

    await client.fetchAssignments();
    final last = events.last;
    expect(last.plannedCourses, 2);
    expect(last.skippedCourses, 1);
    expect(last.completedCourses, 1);
    expect(last.failedCourses, 1);
  });
}
