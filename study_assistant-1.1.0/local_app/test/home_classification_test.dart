import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';

void main() {
  test('home separates confirmed no deadline from unknown and failed dates',
      () {
    final now = DateTime.utc(2026, 11, 4);
    Assignment a(int id,
            {String status = 'pending',
            DateTime? due,
            bool trusted = true,
            bool failed = false}) =>
        Assignment(
            id: 'cx:work:1:2:$id',
            courseName: '高等数学2',
            title: '题$id',
            deadlineAt: due,
            deadlineTrusted: trusted,
            deadlineReadFailed: failed,
            requirementsText: '',
            status: status,
            lastSyncedAt: now);
    final records = [
      a(1),
      a(2, status: 'unknown'),
      a(3, failed: true),
      a(4, trusted: false),
      a(5, due: now),
      a(6, due: now.add(const Duration(days: 30))),
      a(7, due: now.add(const Duration(days: 31))),
      a(8, due: now.subtract(const Duration(seconds: 1)))
    ];
    final g = AssignmentQuery.home(records, now, {});
    expect(g.noDeadline.map((a) => a.workId), ['1']);
    expect(g.uncertain.length, 3);
    expect(g.near.length, 1);
    expect(g.far.length, 1);
    expect(g.overdue.length, 2);
    expect(
        [...g.near, ...g.far, ...g.overdue, ...g.uncertain, ...g.noDeadline]
            .map((a) => a.id)
            .toSet()
            .length,
        8);
  });
}
