import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_classroom_parser.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

void main() {
  final seed = Assignment(
      id: 'cx:activity:7:11:35',
      activityType: 35,
      courseName: '合成课程',
      title: '个人任务',
      deadlineAt: null,
      requirementsText: '',
      status: 'unknown',
      lastSyncedAt: DateTime.utc(2030));
  Assignment parse(int status, int? time) =>
      ChaoxingClassroomParser.parseTask(seed, currentUid: '123', metadata: {
        'isDelete': 0,
        'isNorm': 1,
        'useNoteEditor': 1,
        'toAnswerPage': 1
      }, detailPayload: {
        'result': 1,
        'data': {
          'id': '35',
          'courseId': '7',
          'clazzid': '11',
          'endtime': DateTime.utc(2030, 2).millisecondsSinceEpoch
        }
      }, personalPayload: {
        'result': 1,
        'data': {
          'pptUserAttend': {'uid': '123', 'activeId': '35', 'groupId': '9'},
          'taskGroupInfo': {
            'id': '9',
            'activeId': '35',
            'submitStatus': status,
            'submitTime': time
          }
        }
      });
  test('personal submit status needs its matching timestamp', () {
    expect(parse(0, null).status, 'pending');
    expect(parse(1, DateTime.utc(2030).millisecondsSinceEpoch).status,
        'submitted');
    expect(parse(1, null).status, 'unknown');
    expect(
        parse(0, DateTime.utc(2030).millisecondsSinceEpoch).status, 'unknown');
  });
  for (final state in [-1, 2, 9]) {
    test('unverified personal state $state cannot hide a task as submitted',
        () {
      final a = parse(state, DateTime.utc(2030).millisecondsSinceEpoch);
      expect(a.status, 'unknown');
      expect(a.isCompleted, isFalse);
    });
  }
}
