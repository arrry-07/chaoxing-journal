import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';

void main() {
  test('formal scope and horizon keep unknown discoverable and history folded',
      () {
    final now = DateTime.utc(2026, 11, 4, 2);
    Assignment a(String id, int days, String status) => Assignment(
        id: id,
        courseName: '同名课',
        title: id,
        deadlineAt: now.add(Duration(days: days)),
        requirementsText: '',
        status: status,
        lastSyncedAt: now);
    final records = [
      a('cx:work:1:2:1', 1, 'pending'),
      a('cx:work:1:3:1', 45, 'returned'),
      a('cx:work:1:2:2', -200, 'pending'),
      a('cx:work:1:2:3', 2, 'unknown'),
      a('cx:activity:1:2:4', 1, 'pending'),
      a('cx:work:1:2:5', 1, 'submitted')
    ];
    final g = AssignmentQuery.home(records, now, {});
    expect(g.near.map((a) => a.id), ['cx:work:1:2:1']);
    expect(g.far.length, 1);
    expect(g.overdue.length, 1);
    expect(g.uncertain.length, 1);
    expect(AssignmentQuery.scope(records, {'1:3'}).length, 1);
    expect(Assignment.fromJson(records[4].toJson()).source,
        AssignmentSource.classroomActivity);
  });
  test('calendar business day is Beijing even with UTC input', () {
    final a = Assignment(
        id: 'cx:work:1:2:3',
        courseName: '课',
        title: '题',
        deadlineAt: DateTime.utc(2026, 11, 4, 17),
        requirementsText: '',
        status: 'unknown',
        lastSyncedAt: DateTime.utc(2026));
    expect(AssignmentQuery.forDay([a], DateTime(2026, 11, 5), {}).length, 1);
  });
  test('calendar excludes retained historical deadline after read failure', () {
    final now = DateTime.utc(2026, 11, 4, 2);
    final failedRead = Assignment(
        id: 'cx:work:1:2:3',
        courseName: '课',
        title: '题',
        deadlineAt: DateTime.utc(2026, 11, 5, 2),
        requirementsText: '',
        status: 'pending',
        deadlineTrusted: true,
        deadlineReadFailed: true,
        lastSyncedAt: now);

    expect(AssignmentQuery.forDay([failedRead], DateTime(2026, 11, 5), {}),
        isEmpty);
    expect(AssignmentQuery.home([failedRead], now, {}).uncertain, [failedRead]);
    expect(AssignmentQuery.home([failedRead], now, {}).near, isEmpty);
  });

  test('search matches title and course without changing source scope', () {
    final now = DateTime.utc(2026, 11, 4, 2);
    Assignment work(String id,
            {required String title,
            required String course,
            String status = 'pending',
            DateTime? due}) =>
        Assignment(
            id: id,
            courseName: course,
            title: title,
            deadlineAt: due ?? now.add(const Duration(days: 1)),
            requirementsText: '',
            status: status,
            lastSyncedAt: now);
    final rows = [
      work('cx:work:1:2:a', title: '高数练习', course: '高等数学'),
      work('cx:work:1:2:b', title: 'English Essay', course: '大学英语'),
      work('cx:activity:1:2:c', title: '高数课堂活动', course: '高等数学'),
      work('cx:work:1:2:d',
          title: '高数已提交', course: '高等数学', status: 'submitted'),
    ];

    expect(
        AssignmentQuery.filterHome(rows,
                query: '英语', deadline: AssignmentDeadlineFilter.all, now: now)
            .map((a) => a.id),
        ['cx:work:1:2:b']);
    expect(
        AssignmentQuery.filterHome(rows,
                query: '高数', deadline: AssignmentDeadlineFilter.all, now: now)
            .map((a) => a.id),
        ['cx:work:1:2:a']);
  });

  test('deadline filters distinguish horizons overdue unknown and undated', () {
    final now = DateTime.utc(2026, 11, 4, 2);
    Assignment work(String id,
            {DateTime? due,
            String status = 'pending',
            bool trusted = true,
            bool failed = false}) =>
        Assignment(
            id: 'cx:work:1:2:$id',
            courseName: '课程',
            title: id,
            deadlineAt: due,
            requirementsText: '',
            status: status,
            deadlineTrusted: trusted,
            deadlineReadFailed: failed,
            lastSyncedAt: now);
    final rows = [
      work('today', due: now.add(const Duration(hours: 1))),
      work('week', due: now.add(const Duration(days: 7))),
      work('month', due: now.add(const Duration(days: 30))),
      work('late', due: now.subtract(const Duration(minutes: 1))),
      work('unknown', status: 'unknown', due: now.add(const Duration(days: 1))),
      work('failed',
          due: now.add(const Duration(days: 1)), trusted: false, failed: true),
      work('none'),
    ];
    List<String> ids(AssignmentDeadlineFilter filter) =>
        AssignmentQuery.filterHome(rows, deadline: filter, now: now)
            .map((a) => a.id.split(':').last)
            .toList();

    expect(ids(AssignmentDeadlineFilter.next7Days), ['today', 'week']);
    expect(
        ids(AssignmentDeadlineFilter.next30Days), ['today', 'week', 'month']);
    expect(ids(AssignmentDeadlineFilter.overdue), ['late']);
    expect(ids(AssignmentDeadlineFilter.uncertain), ['unknown', 'failed']);
    expect(ids(AssignmentDeadlineFilter.noDeadline), ['none']);
  });
}
