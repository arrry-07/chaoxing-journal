import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_classroom_parser.dart';

void main() {
  test('recurses into course folders and counts malformed leaves only', () {
    const course = {'courseId': '7', 'clazzId': '11', 'courseName': '文件夹内课程'};
    final result = ChaoxingApiParser.parseCourseRefsDetailed({
      'channelList': [
        {
          'content': {
            'folderName': '第一层',
            'children': [
              {
                'courseList': [
                  course,
                  {
                    'content': {
                      'id': '8',
                      'name': '空子列表课程',
                      'clazz': {'id': '12'},
                      'children': [],
                    },
                  },
                  {'unexpected': true}
                ],
              },
              {'folderName': '空文件夹', 'channelList': []},
            ],
          },
        },
        course,
      ],
    });
    expect(result.refs.map((course) => course.courseId), ['7', '8']);
    expect(result.refs.map((course) => course.clazzId), ['11', '12']);
    expect(
        result.refs.map((course) => course.courseName), ['文件夹内课程', '空子列表课程']);
    expect(result.duplicates, 1);
    expect(result.rejected, 1);
  });

  test('parses backclazzdata course list', () {
    final courses = ChaoxingApiParser.parseCourseRefs({
      'channelList': [
        {
          'key': 'fallback-class',
          'content': {
            'cpi': 789,
            'clazz': {
              'data': [
                {'id': 222},
              ],
            },
            'course': {
              'data': [
                {'id': 111, 'name': '大学英语'},
              ],
            },
          },
        },
      ],
    });

    expect(courses, hasLength(1));
    expect(courses.first.courseId, '111');
    expect(courses.first.clazzId, '222');
    expect(courses.first.courseName, '大学英语');
    expect(courses.first.cpi, '789');
  });

  test('parses active list homework items into assignments', () {
    final assignments = ChaoxingApiParser.parseActivityAssignments(
      {
        'data': {
          'activeList': [
            {
              'id': 333,
              'nameOne': '章节作业',
              'activeType': 42,
              'status': 1,
              'endTime': '2026-05-07 08:00:00',
            },
            {
              'id': 444,
              'nameOne': '课堂签到',
              'activeType': 2,
              'status': 1,
              'endTime': '2026-05-07 08:00:00',
            },
          ],
        },
      },
      ChaoxingCourseRef(
        courseId: '111',
        clazzId: '222',
        courseName: '大学英语',
        cpi: '789',
      ),
      now: DateTime(2026, 5, 5, 8),
    );

    expect(assignments, hasLength(1));
    expect(assignments.first.id, 'cx:activity:111:222:333');
    expect(assignments.first.title, '章节作业');
    expect(assignments.first.courseName, '大学英语');
    expect(assignments.first.deadlineAt, isNull);
    expect(assignments.first.deadlineTrusted, isFalse);
    expect(assignments.first.submitUrl, isNull);
  });

  test('deduplicates repeated course-class identities', () {
    final parsed = ChaoxingApiParser.parseCourseRefsDetailed({
      'courses': [
        {'courseId': '7', 'clazzId': '11', 'courseName': '课程'},
        {'courseId': '7', 'clazzId': '11', 'courseName': '课程'},
        {'unexpected': true},
      ],
    });
    expect(parsed.refs, hasLength(1));
    expect(parsed.duplicates, 1);
    expect(parsed.rejected, 1);
  });

  test('parses active list exams into assignment items', () {
    final assignments = ChaoxingApiParser.parseActivityExamAssignments(
      {
        'data': {
          'activeList': [
            {
              'id': 777,
              'nameOne': '期末考试',
              'activeType': 49,
              'endTime': '2026-06-20 09:30:00',
              'examPlace': '教学楼 A201',
              'examDuration': '120',
            },
            {
              'id': 778,
              'nameOne': '课堂签到',
              'activeType': 2,
              'endTime': '2026-06-20 09:30:00',
            },
          ],
        },
      },
      ChaoxingCourseRef(
        courseId: '111',
        clazzId: '222',
        courseName: '大学英语',
        cpi: '789',
      ),
      now: DateTime(2026, 5, 5, 8),
    );

    expect(assignments, hasLength(1));
    expect(assignments.first.id, 'cx:exam:111:222:777');
    expect(assignments.first.title, '期末考试');
    expect(assignments.first.courseName, '大学英语');
    expect(assignments.first.deadlineAt, DateTime(2026, 6, 20, 9, 30));
    expect(assignments.first.requirementsText, contains('教学楼 A201'));
    expect(assignments.first.requirementsText, contains('120 分钟'));
    expect(assignments.first.status, 'unknown');
    expect(assignments.first.submitUrl, contains('activeId=777'));
  });

  test(
    'list status labels cannot establish personal submission',
    () {
      final assignments = ChaoxingApiParser.parseActivityAssignments(
        {
          'data': {
            'activeList': [
              {
                'id': 555,
                'nameOne': '互评作业',
                'activeType': 42,
                'status': 2,
                'statusName': '已互评',
                'endTime': '2026-05-07 08:00:00',
              },
              {
                'id': 556,
                'nameOne': '互评作业',
                'activeType': 42,
                'status': 1,
                'statusName': '未完成',
                'endTime': '2026-05-08 08:00:00',
              },
            ],
          },
        },
        ChaoxingCourseRef(
          courseId: '111',
          clazzId: '222',
          courseName: '大学英语',
          cpi: '789',
        ),
        now: DateTime(2026, 5, 5, 8),
      );

      expect(assignments, hasLength(2));
      expect(assignments.first.id, 'cx:activity:111:222:555');
      expect(assignments.every((a) => a.status == 'unknown'), isTrue);
    },
  );

  test('keeps numeric activity lifecycle status unknown', () {
    final assignments = ChaoxingApiParser.parseActivityAssignments(
      {
        'data': {
          'activeList': [
            {
              'id': 888,
              'nameOne': '章节作业',
              'activeType': 42,
              'status': 2,
              'endTime': '2026-05-07 08:00:00',
            },
          ],
        },
      },
      const ChaoxingCourseRef(
        courseId: '111',
        clazzId: '222',
        courseName: '大学英语',
      ),
      now: DateTime(2026, 5, 5, 8),
    );

    expect(assignments.single.status, 'unknown');
    expect(assignments.single.isCompleted, isFalse);
  });

  test('keeps peer review homework when description asks to complete review',
      () {
    final assignments = ChaoxingApiParser.parseActivityAssignments(
      {
        'data': {
          'activeList': [
            {
              'id': 889,
              'nameOne': '互评作业',
              'activeType': 42,
              'status': 1,
              'description': '请在截止前完成互评',
              'endTime': '2026-05-07 08:00:00',
            },
          ],
        },
      },
      const ChaoxingCourseRef(
        courseId: '111',
        clazzId: '222',
        courseName: '大学英语',
      ),
      now: DateTime(2026, 5, 5, 8),
    );

    expect(assignments.single.id, 'cx:activity:111:222:889');
    expect(assignments.single.status, 'unknown');
  });

  test('parses ISO UTC homework deadline as local time', () {
    final assignments = ChaoxingApiParser.parseActivityAssignments(
      {
        'data': {
          'activeList': [
            {
              'id': 890,
              'nameOne': '章节作业',
              'activeType': 42,
              'status': 1,
              'endTime': '2026-06-01T15:59:10.900Z',
            },
          ],
        },
      },
      const ChaoxingCourseRef(
        courseId: '111',
        clazzId: '222',
        courseName: '大学英语',
      ),
      now: DateTime(2026, 5, 5, 8),
    );

    expect(assignments.single.deadlineAt, isNull);
    final deadline =
        ChaoxingClassroomParser.absoluteTime('2026-06-01T15:59:10.900Z')!;
    expect(deadline.isUtc, isFalse);
    expect(deadline.toUtc(), DateTime.utc(2026, 6, 1, 15, 59, 10, 900));
  });

  test(
      'preserves the instant of an offset deadline across the UTC date boundary',
      () {
    final assignments = ChaoxingApiParser.parseActivityAssignments(
      {
        'activeList': [
          {
            'id': 892,
            'nameOne': '凌晨截止作业',
            'activeType': 42,
            'endTime': '2026-06-02T00:15:10.900+08:00',
          },
        ],
      },
      const ChaoxingCourseRef(
          courseId: '111', clazzId: '222', courseName: '大学英语'),
      now: DateTime.utc(2026, 5, 5),
    );

    expect(assignments.single.deadlineAt, isNull);
    final deadline =
        ChaoxingClassroomParser.absoluteTime('2026-06-02T00:15:10.900+08:00')!;
    expect(deadline.isUtc, isFalse);
    expect(deadline.toUtc(), DateTime.utc(2026, 6, 1, 16, 15, 10, 900));
  });

  test('an exam start in the past does not establish personal submission', () {
    final result = ChaoxingApiParser.parseActivityExamAssignments({
      'activeList': [
        {
          'id': '1',
          'name': '考试',
          'startTime': '2026-05-04 09:00',
          'statusName': '已结束'
        },
        {
          'id': '2',
          'name': '考试',
          'startTime': '2026-05-04 09:00',
          'submitStatusName': '已提交'
        },
      ]
    }, const ChaoxingCourseRef(courseId: '1', clazzId: '2', courseName: '课程'),
        now: DateTime(2026, 5, 5));
    expect(result.map((a) => a.status), ['unknown', 'submitted']);
  });

  test('parses exams that only provide start time', () {
    final assignments = ChaoxingApiParser.parseActivityExamAssignments(
      {
        'data': {
          'activeList': [
            {
              'id': 891,
              'nameOne': '期末考试',
              'activeType': 49,
              'startTime': '2026-06-20 09:30:00',
              'examDuration': '120',
            },
          ],
        },
      },
      const ChaoxingCourseRef(
        courseId: '111',
        clazzId: '222',
        courseName: '大学英语',
      ),
      now: DateTime(2026, 5, 5, 8),
    );

    expect(assignments.single.id, 'cx:exam:111:222:891');
    expect(assignments.single.deadlineAt, DateTime(2026, 6, 20, 9, 30));
  });
}
