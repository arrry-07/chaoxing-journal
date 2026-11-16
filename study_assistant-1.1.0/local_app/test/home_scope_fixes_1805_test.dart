import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';

final _now = DateTime.utc(2026, 11, 16, 8);

Assignment _work(
  String id, {
  String status = 'pending',
  DateTime? deadline,
  bool trusted = true,
}) =>
    Assignment(
      id: 'cx:work:c:k:$id',
      courseName: '正式课程',
      title: '正式作业$id',
      deadlineAt: deadline,
      deadlineTrusted: trusted,
      requirementsText: '',
      status: status,
      lastSyncedAt: _now,
    );

Assignment _classroom(
  String id, {
  int activityType = 42,
  String status = 'unknown',
  DateTime? deadline,
  bool trusted = true,
}) =>
    Assignment(
      id: 'cx:activity:c:k:$id',
      source: AssignmentSource.classroomActivity,
      activityType: activityType,
      courseName: '正式课程',
      title: '课堂练习$id',
      deadlineAt: deadline,
      deadlineTrusted: trusted,
      requirementsText: '',
      status: status,
      lastSyncedAt: _now,
    );

void main() {
  test('FB-004 homework filter merges formal and supported classroom work', () {
    expect(homeTypeFilterChoices.map((choice) => choice.label),
        ['全部', '作业', '考试']);
    expect(normalizedHomeType(AssignmentTypeFilter.task),
        AssignmentTypeFilter.homework);
    expect(normalizedHomeType(AssignmentTypeFilter.examNotice),
        AssignmentTypeFilter.exam);

    final formal = _work('formal');
    final classroom = _classroom('task');
    final exam = Assignment(
      id: 'cx:exam:c:k:1',
      source: AssignmentSource.exam,
      courseName: '正式课程',
      title: '考试',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: _now,
      exam: const ExamInfo(examId: '1', courseId: 'c', clazzId: 'k'),
    );
    expect(AssignmentQuery.matchesType(formal, AssignmentTypeFilter.homework),
        isTrue);
    expect(
        AssignmentQuery.matchesType(classroom, AssignmentTypeFilter.homework),
        isTrue);
    expect(AssignmentQuery.matchesType(exam, AssignmentTypeFilter.homework),
        isFalse);

    final migrated = HomeFilters.decode(
        '{"query":"","deadline":"all","type":"task","sortOrder":"deadlineAsc"}');
    expect(migrated.type, AssignmentTypeFilter.homework);
  });

  test('FB-002 stale classroom practice leaves current and recovery scopes',
      () {
    final stale = _classroom(
      'old',
      deadline: _now.subtract(const Duration(days: 120)),
    );
    final formalUnknown = _work(
      'formal-unknown',
      status: 'unknown',
      deadline: _now.subtract(const Duration(days: 3)),
    );
    final untrusted = _classroom(
      'untrusted',
      deadline: _now.subtract(const Duration(days: 5)),
      trusted: false,
    );
    final records = [stale, formalUnknown, untrusted];

    expect(
      AssignmentQuery.currentDisplay(records, _now).map((item) => item.id),
      [formalUnknown.id, untrusted.id],
    );
    expect(
      AssignmentQuery.filterHome(
        records,
        includeHistorical: true,
        now: _now,
      ).map((item) => item.id),
      [formalUnknown.id, untrusted.id],
    );
    expect(
        AssignmentRecoveryScope.deadlinePending.matches(stale, _now), isFalse);
    expect(AssignmentRecoveryScope.deadlinePending.matches(formalUnknown, _now),
        isTrue);
    expect(AssignmentRecoveryScope.deadlinePending.matches(untrusted, _now),
        isTrue);
    expect(records, hasLength(3));
  });
}
