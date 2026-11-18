import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_notice_parser.dart';
import 'package:study_assistant_mobile/src/models/course_notice.dart';

void main() {
  test(
      'parses platformUnread strictly from string 0/1, sanitizes URLs, and respects 4-digit year times',
      () {
    final courses = const [
      ChaoxingCourseRef(courseId: '100', clazzId: '200', courseName: '高等数学'),
      ChaoxingCourseRef(courseId: '101', clazzId: '201', courseName: '大学物理'),
      ChaoxingCourseRef(courseId: '101', clazzId: '202', courseName: '大学物理'),
    ];

    final payload = {
      'status': true,
      'notices': {
        'lastGetId': 'cursor-1',
        'lastPage': false,
        'list': [
          {
            'uuid': 'notice-unique-1',
            'title': '《高等数学》第五次作业提醒',
            'content':
                '<p>请前往 https://mooc1.chaoxing.com/work?enc=secretToken123 完成</p><p>截止时间：2030-05-10 23:59</p>',
            'rtf_content': '',
            'createrName': '张老师',
            'completeTime': '2030-05-01 09:30',
            'isread': '0',
          },
          {
            'uuid': 'notice-ambiguous-course',
            'title': '大学物理实验分组公告',
            'content': '截止时间：05-10 23:59 点击 https://i.chaoxing.com/x?token=abc',
            'createrName': '物理教研室',
            'completeTime': '2030-05-01',
            'isread': '1',
          },
          {
            'uuid': 'notice-attached',
            'title': '实验报告说明',
            'content': '提交方式见通知',
            'createrName': '李老师',
            'completeTime': '2030-05-02 14:00',
            'isread': 0,
            'attachment': [
              {
                'att_web': {
                  'courseId': '101',
                  'clazzId': '202',
                  'title': '大学物理',
                }
              }
            ],
          },
        ],
      },
    };

    final parsed = ChaoxingNoticeParser.parsePage(payload, courses: courses);
    expect(parsed, isNotNull);
    expect(parsed!.cursor, 'cursor-1');
    expect(parsed.rows, hasLength(3));

    final first = parsed.rows[0];
    expect(first.platformUnread, isTrue);
    expect(first.localRead, isFalse);
    expect(first.courseKey, '100:200');
    expect(first.courseName, '高等数学');
    expect(first.summary, isNot(contains('secretToken123')));
    expect(first.summary, contains('（链接请在官方页面查看）'));
    expect(first.publishedTrusted, isTrue);
    expect(first.extractedEventTrusted, isTrue);
    expect(
      first.extractedEventAt!.toUtc(),
      DateTime.utc(2030, 5, 10, 15, 59),
    );

    final second = parsed.rows[1];
    expect(second.platformUnread, isFalse);
    expect(second.courseKey, isNull);
    expect(second.summary, isNot(contains('token=abc')));
    // Missing 4-digit year must not be guessed.
    expect(second.extractedEventAt, isNull);
    expect(second.extractedEventTrusted, isFalse);
    // Day-only date is parsed without claiming minute precision.
    expect(second.publishedAt, isNotNull);
    expect(second.publishedTrusted, isFalse);

    final third = parsed.rows[2];
    expect(third.platformUnread, isTrue);
    expect(third.courseKey, '101:202');
    expect(third.courseName, '大学物理');
  });

  test('mergeIncoming preserves existing localRead and linkedManualEntryId',
      () {
    final t1 = DateTime.utc(2030, 5, 1, 1);
    final t2 = DateTime.utc(2030, 5, 2, 1);
    final noticeId = 'cx:notice:${'a' * 64}';
    final initial = CourseNoticeCollection(items: [
      CourseNotice(
        id: noticeId,
        courseName: '高等数学',
        title: '旧标题',
        platformUnread: true,
        localRead: true,
        linkedManualEntryId: 'notice-1234',
        lastSyncedAt: t1,
      ),
    ]);

    final updated = initial.mergeIncoming([
      CourseNotice(
        id: noticeId,
        courseName: '高等数学',
        title: '新标题',
        platformUnread: true,
        localRead: false,
        lastSyncedAt: t2,
      ),
    ]);

    expect(updated.items.single.title, '新标题');
    expect(updated.items.single.localRead, isTrue);
    expect(updated.items.single.linkedManualEntryId, 'notice-1234');
    expect(updated.unreadCount, 0);
  });
}
