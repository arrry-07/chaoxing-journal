import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_assignment_parser.dart';

void main() {
  test('legacy dates without parser evidence remain untrusted', () {
    final old = {
      'id': 'cx:work:1:2:3',
      'courseName': '课',
      'title': '题',
      'deadlineAt': '2027-03-04T12:00:00',
      'requirementsText': '',
      'status': 'pending',
      'lastSyncedAt': '2026-11-04T12:00:00'
    };
    expect(Assignment.fromJson(old).deadlineTrusted, isFalse);
  });
  test('ambiguous year must not be guessed from current date', () {
    expect(
        ChaoxingAssignmentParser.parseDetailDeadline('截止时间：03-04 12:00',
            now: DateTime(2026, 11, 4)),
        isNull);
  });
  test('unknown submission cannot claim overdue', () {
    final a = Assignment(
        id: 'cx:work:1:2:3',
        courseName: '数学',
        title: '练习',
        deadlineAt: DateTime(2026, 3),
        requirementsText: '',
        status: 'unknown',
        lastSyncedAt: DateTime(2026, 11));
    expect(a.isOverdue, isFalse);
  });
}
