import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';

DateTime _beijing(int year, int month, int day,
        [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour - 8, minute);

Assignment _work(
  String id, {
  DateTime? deadlineAt,
  DateTime? publishedAt,
  DateTime? availableFromAt,
  bool deadlineTrusted = true,
  bool deadlineReadFailed = false,
  String status = 'pending',
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: '合成课程',
      title: id,
      deadlineAt: deadlineAt,
      publishedAt: publishedAt,
      availableFromAt: availableFromAt,
      deadlineTrusted: deadlineTrusted,
      deadlineReadFailed: deadlineReadFailed,
      requirementsText: '',
      status: status,
      lastSyncedAt: deadlineAt ?? DateTime.utc(2026),
    );

Assignment _exam(
  String id, {
  DateTime? startAt,
  DateTime? endAt,
  bool startTrusted = true,
  bool endTrusted = true,
  String lifecycle = 'scheduled',
  String status = 'pending',
}) =>
    Assignment(
      id: 'cx:exam:1:2:$id',
      source: AssignmentSource.exam,
      courseName: '合成课程',
      title: id,
      deadlineAt: endAt,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.utc(2026),
      exam: ExamInfo(
        examId: id,
        courseId: '1',
        clazzId: '2',
        startAt: startAt,
        endAt: endAt,
        startTrusted: startTrusted,
        endTrusted: endTrusted,
        lifecycle: lifecycle,
      ),
    );

void main() {
  test('Beijing semester switches exactly at March and September first', () {
    expect(
        AssignmentQuery.semesterStartAt(_beijing(2026, 2, 28, 23, 59)).toUtc(),
        _beijing(2025, 9, 1));
    expect(AssignmentQuery.semesterStartAt(_beijing(2026, 3, 1)).toUtc(),
        _beijing(2026, 3, 1));
    expect(
        AssignmentQuery.semesterStartAt(_beijing(2026, 8, 31, 23, 59)).toUtc(),
        _beijing(2026, 3, 1));
    expect(AssignmentQuery.semesterStartAt(_beijing(2026, 9, 1)).toUtc(),
        _beijing(2026, 9, 1));
  });

  test('newly published work stays current within the inclusive 30 days', () {
    final now = _beijing(2026, 9, 5, 12);
    final edge = _work(
      'edge',
      deadlineAt: _beijing(2026, 7, 1),
      publishedAt: now.subtract(const Duration(days: 30)),
    );
    final tooOld = _work(
      'too-old',
      deadlineAt: _beijing(2026, 7, 1),
      publishedAt: now.subtract(const Duration(days: 30, minutes: 1)),
    );
    expect(AssignmentQuery.isArchivedPastTerm(edge, now), isFalse);
    expect(AssignmentQuery.isArchivedPastTerm(tooOld, now), isTrue);
  });

  test('confirmed no-deadline work follows a trusted current-term start', () {
    final now = _beijing(2026, 10, 5, 12);
    final current = _work(
      'current',
      availableFromAt: _beijing(2026, 9, 2),
    );
    final previous = _work(
      'previous',
      availableFromAt: _beijing(2026, 8, 31),
    );
    expect(AssignmentQuery.isArchivedPastTerm(current, now), isFalse);
    expect(AssignmentQuery.isArchivedPastTerm(previous, now), isTrue);
  });

  test('past-term deadlines archive while extensions return to the home term',
      () {
    final now = _beijing(2026, 10, 5, 12);
    final overdue = _work('old', deadlineAt: _beijing(2026, 1, 15));
    final extended = _work('extended', deadlineAt: _beijing(2026, 12, 20));
    expect(AssignmentQuery.isArchivedPastTerm(overdue, now), isTrue);
    expect(AssignmentQuery.isArchivedPastTerm(extended, now), isFalse);
    expect(
      AssignmentQuery.isArchivedPastTerm(
        _work(
          'recent-extension',
          deadlineAt: _beijing(2026, 1, 15),
          publishedAt: _beijing(2026, 9, 15),
        ),
        now,
      ),
      isFalse,
    );
  });

  test('insufficient or failed time evidence stays pending', () {
    final now = _beijing(2026, 10, 5, 12);
    expect(
      AssignmentQuery.isArchivedPastTerm(
        _work(
          'untrusted',
          deadlineAt: _beijing(2026, 1, 15),
          deadlineTrusted: false,
        ),
        now,
      ),
      isFalse,
    );
    expect(
      AssignmentQuery.isArchivedPastTerm(
        _work(
          'failed',
          deadlineAt: _beijing(2026, 1, 15),
          deadlineReadFailed: true,
        ),
        now,
      ),
      isFalse,
    );
  });

  test('old exams archive by trusted end or unambiguous start only', () {
    final now = _beijing(2026, 11, 19, 12);
    final ended = _exam(
      'ended',
      startAt: _beijing(2026, 6, 9, 8),
      endAt: _beijing(2026, 6, 9, 10),
      lifecycle: 'ended',
    );
    final startOnly = _exam(
      'start-only',
      startAt: _beijing(2026, 7, 4, 8),
      endAt: null,
      endTrusted: false,
    );
    final futureEnd = _exam(
      'future-end',
      startAt: _beijing(2026, 8, 31, 8),
      endAt: _beijing(2026, 9, 2, 10),
    );
    final yearless = _exam(
      'yearless',
      startAt: null,
      endAt: null,
      startTrusted: false,
      endTrusted: false,
      lifecycle: 'unknown',
    );
    expect(AssignmentQuery.isArchivedPastTerm(ended, now), isTrue);
    expect(AssignmentQuery.isArchivedPastTerm(startOnly, now), isTrue);
    expect(AssignmentQuery.isArchivedPastTerm(futureEnd, now), isFalse);
    expect(AssignmentQuery.isArchivedPastTerm(yearless, now), isFalse);
  });

  test('home calendar recovery and reminders share the archive decision', () {
    final now = _beijing(2026, 11, 19, 12);
    final old = _work('old', deadlineAt: _beijing(2026, 1, 15));
    final current = _work('current', deadlineAt: _beijing(2026, 12, 15));
    final records = [old, current];

    expect(AssignmentQuery.currentDisplay(records, now), [current]);
    expect(AssignmentQuery.filterHome(records, now: now), [current]);
    expect(AssignmentQuery.home(records, now, {}).overdue, isEmpty);
    expect(AssignmentQuery.isCalendarDated(old, now), isFalse);
    expect(
      AssignmentQuery.forDay(records, DateTime(2026, 1, 15), {}, now: now),
      isEmpty,
    );
    expect(AssignmentRecoveryScope.deadlinePending.matches(old, now), isFalse);
    expect(
      AssignmentReminderSnapshot(
        assignment: old,
        hidden: false,
        followed: true,
      ).eligibleAt(now),
      isFalse,
    );
  });
}
