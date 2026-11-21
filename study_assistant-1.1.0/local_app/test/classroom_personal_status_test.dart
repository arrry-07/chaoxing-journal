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

  final quizSeed = Assignment(
      id: 'cx:activity:7:11:42',
      activityType: 42,
      courseName: '合成课程',
      title: '第3章随堂练习1',
      deadlineAt: null,
      requirementsText: '',
      status: 'unknown',
      lastSyncedAt: DateTime.utc(2030));

  Map<String, dynamic> quizActive() => {
        'id': '42',
        'clazzid': '11',
        'courseId': null,
        'activeType': 42,
        'endtime': DateTime.utc(2030, 2).millisecondsSinceEpoch,
        'status': 2,
      };

  test('unsubmitted quiz without pptUserAttend confirms pending via answer uid',
      () {
    final parsed = ChaoxingClassroomParser.parseQuiz(
      quizSeed,
      currentUid: '123',
      detailPayload: {
        'result': 1,
        'data': {
          'puid': '123',
          'pptActive': quizActive(),
          'pptUserAttend': null,
          'hasAnswerPermission': 1,
        }
      },
      answerPayload: {
        'result': 1,
        'data': {
          'uid': '123',
          'isAnswered': false,
          'active': quizActive(),
        }
      },
    );
    expect(parsed.status, 'pending');
    expect(parsed.isPendingConfirmed, isTrue);
    expect(parsed.deadlineTrusted, isTrue);
  });

  test('quiz accepts personal identity from answer pptUserAttend', () {
    final parsed = ChaoxingClassroomParser.parseQuiz(
      quizSeed,
      currentUid: '123',
      detailPayload: {
        'result': 1,
        'data': {
          'pptActive': quizActive(),
          'pptUserAttend': null,
          'hasAnswerPermission': 1,
        }
      },
      answerPayload: {
        'result': 1,
        'data': {
          'isAnswered': true,
          'pptUserAttend': {'uid': '123', 'activeId': '42'},
          'submitTime': DateTime.utc(2030, 1, 2).millisecondsSinceEpoch,
        }
      },
    );
    expect(parsed.status, 'submitted');
    expect(parsed.completedAt, isNotNull);
  });

  test('quiz without pptUserAttend stays unknown if answer lacks identity', () {
    final missingActivity = ChaoxingClassroomParser.parseQuiz(
      quizSeed,
      currentUid: '123',
      detailPayload: {
        'result': 1,
        'data': {
          'pptActive': quizActive(),
          'pptUserAttend': null,
          'hasAnswerPermission': 1,
        }
      },
      answerPayload: {
        'result': 1,
        'data': {'uid': '123', 'isAnswered': false}
      },
    );
    expect(missingActivity.status, 'unknown');

    final missingUid = ChaoxingClassroomParser.parseQuiz(
      quizSeed,
      currentUid: '123',
      detailPayload: {
        'result': 1,
        'data': {
          'pptActive': quizActive(),
          'pptUserAttend': null,
          'hasAnswerPermission': 1,
        }
      },
      answerPayload: {
        'result': 1,
        'data': {'isAnswered': false, 'active': quizActive()}
      },
    );
    expect(missingUid.status, 'unknown');

    final noCurrentUid = ChaoxingClassroomParser.parseQuiz(
      quizSeed,
      currentUid: null,
      detailPayload: {
        'result': 1,
        'data': {
          'pptActive': quizActive(),
          'pptUserAttend': null,
          'hasAnswerPermission': 1,
        }
      },
      answerPayload: {
        'result': 1,
        'data': {'uid': '123', 'isAnswered': false, 'active': quizActive()}
      },
    );
    expect(noCurrentUid.status, 'unknown');
  });

  test('quiz rejects mismatched answer uid even without pptUserAttend', () {
    expect(
      () => ChaoxingClassroomParser.parseQuiz(
        quizSeed,
        currentUid: '123',
        detailPayload: {
          'result': 1,
          'data': {
            'pptActive': quizActive(),
            'pptUserAttend': null,
            'hasAnswerPermission': 1,
          }
        },
        answerPayload: {
          'result': 1,
          'data': {'uid': 'other', 'isAnswered': false, 'active': quizActive()}
        },
      ),
      throwsFormatException,
    );
  });
}
