import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AssignmentQuery.debugResetDisplayCaches();
  });

  test(
      'evaluated returned V3 work reopens the completed record and returns to the current display',
      () async {
    const id = 'cx:work:1:2:1';
    final repository = LocalAssignmentRepository();
    await repository.mergeAndSave([
      Assignment(
        id: id,
        courseName: '课',
        title: '退回后重做',
        deadlineAt: DateTime.utc(2026, 12, 1, 10),
        deadlineTrusted: true,
        requirementsText: '',
        status: 'submitted',
        completedAt: DateTime.utc(2026, 11, 18),
        lastSyncedAt: DateTime.utc(2026, 11, 18),
      ),
    ]);

    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        final dynamic data = switch (options.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '课'}
              ]
            },
          '/visit/stucoursemiddle' =>
            '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>',
          '/mooc2-ans/coursemanagev3/stu-base-info' => {
              'status': true,
              'navigationList': []
            },
          '/mooc-ans/work/api/task' => {
              'status': true,
              'total': 1,
              'data': [
                {
                  'title': '退回后重做',
                  'stuStatus': 5,
                  'evaluation': 1,
                  'endTime': 1796119200000,
                  'taskUrl':
                      'https://mooc1.chaoxing.com/work/task?workId=1&courseId=1&classId=2'
                }
              ]
            },
          _ => throw StateError('unexpected ${options.uri.path}'),
        };
        handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data));
      }));
    final client = ChaoxingLocalClient(
        enableExams: false, enableClassroomTasks: false, dio: dio);

    final observed = await client.fetchAssignments();
    expect(observed.single.status, 'returned');
    expect(observed.single.isCompleted, isFalse);

    await repository.mergeAndSave(observed);
    final saved = (await repository.loadJournal()).single;
    expect(saved.status, 'returned');
    expect(saved.completedAt, isNull);
    expect(saved.isCompleted, isFalse);

    final current = AssignmentQuery.currentDisplay(
        await repository.loadJournal(), DateTime.utc(2026, 11, 19));
    expect(current.map((assignment) => assignment.id), contains(id));

    // Single-target return check also surfaces the reopened returned state cleanly.
    final returnedWork = await client.fetchReturnedWork(observed.single);
    expect(returnedWork, isNotNull);
    expect(returnedWork!.id, id);
    expect(returnedWork.status, 'returned');
    expect(returnedWork.isCompleted, isFalse);
  });
}
