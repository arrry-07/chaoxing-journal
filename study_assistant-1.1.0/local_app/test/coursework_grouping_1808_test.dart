import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/services/assignment_grouping.dart';
import 'package:study_assistant_mobile/src/services/assignment_statistics.dart';

Assignment _exam({
  required String id,
  String? course = '1',
  String? clazz = '2',
  required String examId,
  String? related,
  bool notice = false,
  String title = '高等数学期末考试',
  String status = 'unknown',
}) =>
    Assignment(
      id: id,
      source: AssignmentSource.exam,
      exam: ExamInfo(
        examId: examId,
        relatedExamId: related,
        courseId: course,
        clazzId: clazz,
        startAt: DateTime.utc(2026, 11, 20, 1),
        endAt: DateTime.utc(2026, 11, 20, 2),
        startTrusted: !notice,
        endTrusted: !notice,
        lifecycle: notice ? 'unknown' : 'scheduled',
        noticeOnly: notice,
      ),
      courseName: '高等数学',
      title: title,
      deadlineAt: null,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.utc(2026, 11, 16, 8),
    );

Assignment _work(String id, {String title = '章节作业'}) => Assignment(
      id: id,
      courseName: '大学英语',
      title: title,
      deadlineAt: DateTime.utc(2026, 11, 30, 10),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.utc(2026, 11, 16, 8),
    );

void main() {
  test('formal exam and two notices form one raw-primary group', () {
    final formal = _exam(
      id: 'cx:exam:1:2:3',
      examId: '3',
      status: 'unknown',
    );
    final noticeA = _exam(
      id: 'cx:examNotice:inbox:101',
      examId: '101',
      related: '3',
      notice: true,
      status: 'submitted',
    );
    final noticeB = _exam(
      id: 'cx:examNotice:inbox:102',
      examId: '102',
      related: '3',
      notice: true,
      status: 'submitted',
    );

    final groups = AssignmentGrouping.group([noticeA, formal, noticeB]);

    expect(groups, hasLength(1));
    expect(groups.single.primary.id, formal.id);
    expect(groups.single.primary.status, 'unknown');
    expect(groups.single.sourceCount, 3);
    expect(groups.single.sources.map((item) => item.id).toSet(), {
      formal.id,
      noticeA.id,
      noticeB.id,
    });
  });

  test('notice-only groups choose deterministically and never infer status',
      () {
    final later = _exam(
      id: 'cx:examNotice:inbox:202',
      examId: '202',
      related: '3',
      notice: true,
      status: 'submitted',
    );
    final earlier = _exam(
      id: 'cx:examNotice:inbox:201',
      examId: '201',
      related: '3',
      notice: true,
      status: 'unknown',
    );

    final groups = AssignmentGrouping.group([later, earlier]);

    expect(groups.single.primary.id, earlier.id);
    expect(groups.single.primary.status, 'unknown');
    expect(groups.single.sourceLabel, '考试 · 2 条来源');
  });

  test('missing identity, different class and same-title work stay independent',
      () {
    final missing = _exam(
      id: 'cx:examNotice:inbox:301',
      examId: '301',
      notice: true,
    );
    final otherClass = _exam(
      id: 'cx:exam:1:9:3',
      clazz: '9',
      examId: '3',
    );
    final workA = _work('cx:work:1:2:a', title: '同名作业');
    final workB = _work('cx:work:1:2:b', title: '同名作业');

    final groups = AssignmentGrouping.group([
      missing,
      otherClass,
      workA,
      workB,
    ]);

    expect(groups, hasLength(4));
    expect(groups.map((group) => group.sourceCount), everyElement(1));
  });

  test('any hidden source hides the whole group, including a new notice', () {
    final formal = _exam(id: 'cx:exam:1:2:3', examId: '3');
    final notice = _exam(
      id: 'cx:examNotice:inbox:401',
      examId: '401',
      related: '3',
      notice: true,
    );

    final hidden = AssignmentGrouping.group(
      [formal, notice],
      hiddenIds: {formal.id},
    );

    expect(hidden.single.hidden, isTrue);
    expect(hidden.single.sourceCount, 2);
  });

  test('statistics use raw primary status and one denominator per group', () {
    final formal = _exam(
      id: 'cx:exam:1:2:3',
      examId: '3',
      status: 'unknown',
    );
    final notice = _exam(
      id: 'cx:examNotice:inbox:501',
      examId: '501',
      related: '3',
      notice: true,
      status: 'submitted',
    );
    final work = _work('cx:work:1:2:a');
    final groups = AssignmentGrouping.group([formal, notice, work]);
    final stats = AssignmentStatistics(
      groups.map((group) => group.primary).toList(),
      now: DateTime.utc(2026, 11, 16, 8),
    );

    expect(groups, hasLength(2));
    expect(stats.total, 2);
    expect(stats.unknown, 1);
    expect(stats.counts[0], 0);
  });

  test('backup round trip keeps all sources and the same grouped count', () {
    final formal = _exam(id: 'cx:exam:1:2:3', examId: '3');
    final noticeA = _exam(
      id: 'cx:examNotice:inbox:601',
      examId: '601',
      related: '3',
      notice: true,
    );
    final noticeB = _exam(
      id: 'cx:examNotice:inbox:602',
      examId: '602',
      related: '3',
      notice: true,
    );
    final work = _work('cx:work:1:2:a');
    final snapshot = BackupSnapshot.create(
      owner: 'a' * 64,
      createdAt: DateTime.utc(2026, 11, 16, 8),
      records: [formal, noticeA, noticeB, work],
      hidden: {noticeA.id},
      courses: const [],
      unfollowed: const {},
      reminderOffsets: const [60],
      autoSyncIntervalMinutes: 240,
    );
    final restored = BackupSnapshot.decode(snapshot.encode());
    final groups = AssignmentGrouping.group(
      restored.records,
      hiddenIds: restored.hidden,
    );

    expect(restored.records, hasLength(4));
    expect(groups, hasLength(2));
    expect(groups.singleWhere((group) => group.isExam).sourceCount, 3);
    expect(groups.singleWhere((group) => group.isExam).hidden, isTrue);
  });
}
