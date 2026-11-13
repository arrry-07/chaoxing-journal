import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

Assignment _assignment({
  String id = 'cx:work:1:2:1',
  String status = 'pending',
  DateTime? deadlineAt,
  bool deadlineTrusted = true,
  bool deadlineReadFailed = false,
  String? deadlineRawText,
}) =>
    Assignment(
      id: id,
      courseName: '课程',
      title: '作业',
      deadlineAt: deadlineAt,
      deadlineTrusted: deadlineTrusted,
      deadlineReadFailed: deadlineReadFailed,
      deadlineRawText: deadlineRawText,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.utc(2026, 11, 13),
    );

void main() {
  test('deadline bucket treats an exact deadline as overdue', () {
    final now = DateTime.utc(2026, 11, 13, 4);

    expect(
      _assignment(deadlineAt: now.add(const Duration(microseconds: 1)))
          .deadlineBucketAt(now),
      AssignmentDeadlineBucket.notExpiredWithDeadline,
    );
    expect(
      _assignment(deadlineAt: now).deadlineBucketAt(now),
      AssignmentDeadlineBucket.overdue,
    );
    expect(
      _assignment(deadlineAt: now.subtract(const Duration(microseconds: 1)))
          .deadlineBucketAt(now),
      AssignmentDeadlineBucket.overdue,
    );
    expect(
      _assignment().deadlineBucketAt(now),
      AssignmentDeadlineBucket.confirmedNoDeadline,
    );
    expect(
      _assignment(status: 'submitted', deadlineAt: now).deadlineBucketAt(now),
      AssignmentDeadlineBucket.completed,
    );
  });

  test('deadline bucket keeps conflicting or unreadable evidence pending', () {
    final now = DateTime.utc(2026, 11, 13, 4);

    expect(
      _assignment(
        status: 'unknown',
        deadlineAt: now.subtract(const Duration(days: 1)),
      ).deadlineBucketAt(now),
      AssignmentDeadlineBucket.unconfirmed,
    );
    expect(
      _assignment(
        status: 'overdue',
        deadlineAt: now.add(const Duration(days: 1)),
      ).deadlineBucketAt(now),
      AssignmentDeadlineBucket.unconfirmed,
    );
    expect(
      _assignment(
        deadlineAt: now.add(const Duration(days: 1)),
        deadlineReadFailed: true,
      ).deadlineBucketAt(now),
      AssignmentDeadlineBucket.unconfirmed,
    );
    expect(
      _assignment(
        deadlineTrusted: false,
        deadlineRawText: '11月20日（年份待确认）',
      ).deadlineBucketAt(now),
      AssignmentDeadlineBucket.unconfirmed,
    );
  });
}
