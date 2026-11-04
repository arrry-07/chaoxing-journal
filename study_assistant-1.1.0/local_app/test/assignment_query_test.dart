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
}
