import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_assignment_parser.dart';

void main() {
  test(
      'same-work absolute start anchors year only when displayed start matches',
      () {
    final historical = DateTime.utc(2024, 10, 27, 0, 0);
    final e = ChaoxingAssignmentParser.readDetailDeadline(
        '作答时间：10-27 08:00 至 11-05 23:59',
        startedAt: historical);
    expect(e.deadlineAt!.toUtc(), DateTime.utc(2024, 11, 5, 15, 59));
    final mismatch = ChaoxingAssignmentParser.readDetailDeadline(
        '作答时间：10-28 08:00 至 11-05 23:59',
        startedAt: historical);
    expect(mismatch.missingYear, isTrue);
    expect(mismatch.deadlineAt, isNull);
    final cross = ChaoxingAssignmentParser.readDetailDeadline(
        '作答时间：12-31 08:00 至 01-01 23:59',
        startedAt: DateTime.utc(2025, 12, 31));
    expect(cross.deadlineAt!.toUtc(), DateTime.utc(2026, 1, 1, 15, 59));
    final alone = ChaoxingAssignmentParser.readDetailDeadline(
        '截止时间：11-05 23:59',
        startedAt: historical);
    expect(alone.deadlineAt, isNull);
  });
  test(
      'details distinguish exact dates, no-limit, ambiguous years and invalid dates',
      () {
    for (final body in [
      '截止时间：不限',
      '作答时间：2026-11-04 08:00 至 无截止时间',
      '<b>截止时间</b><span>长期有效</span>'
    ]) {
      final e = ChaoxingAssignmentParser.readDetailDeadline(body);
      expect(e.noLimit, isTrue);
      expect(e.deadlineAt, isNull);
    }
    final cross = ChaoxingAssignmentParser.readDetailDeadline(
        '作答时间：2026年12月30日 08:00 至 01月02日 23:59');
    expect(cross.deadlineAt!.toUtc(), DateTime.utc(2027, 1, 2, 15, 59));
    final noYear = ChaoxingAssignmentParser.readDetailDeadline(
        '作答时间：11-04 08:00 至 11-09 23:59');
    expect(noYear.missingYear, isTrue);
    expect(noYear.rawText, '11-09 23:59');
    expect(noYear.deadlineAt, isNull);
    for (final body in [
      '截止时间：2026-02-30 23:59',
      '<script>var text="截止时间：不限";</script>',
      '作业说明：剩余2天',
      '发布时间：2026-11-09 23:59'
    ]) {
      final e = ChaoxingAssignmentParser.readDetailDeadline(body);
      expect(e.deadlineAt, isNull);
      expect(e.noLimit, isFalse);
    }
  });
}
