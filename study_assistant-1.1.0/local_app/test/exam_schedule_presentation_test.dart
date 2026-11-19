import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/exam_schedule_presentation.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';

Assignment notice(String body, {String suffix = 'n', String examId = '3'}) =>
    Assignment(
        id: 'cx:examNotice:inbox:$suffix',
        source: AssignmentSource.exam,
        title: '合成考试',
        courseName: '合成课程',
        deadlineAt: null,
        requirementsText: body,
        status: 'unknown',
        lastSyncedAt: DateTime.utc(2026),
        exam: ExamInfo(
            examId: suffix,
            relatedExamId: examId,
            courseId: '1',
            clazzId: '2',
            noticeOnly: true,
            durationMinutes: 60));
Assignment formal({DateTime? start, DateTime? end}) => Assignment(
    id: 'cx:exam:1:2:3',
    source: AssignmentSource.exam,
    title: '合成考试',
    courseName: '合成课程',
    deadlineAt: end,
    requirementsText: '以官方列表为准',
    status: 'pending',
    lastSyncedAt: DateTime.utc(2026),
    exam: ExamInfo(
        examId: '3',
        courseId: '1',
        clazzId: '2',
        startAt: start,
        endAt: end,
        startTrusted: start != null,
        endTrusted: end != null,
        lifecycle: 'scheduled'));
void main() {
  test('same-day mixed trusted and yearless endpoints use one date heading',
      () {
    final start = formal(start: DateTime.utc(2026, 11, 16, 0));
    final n1 = notice('考试时间：11-16 08:00 至 11-16 09:00');
    expect(
        ExamSchedulePresentation.build(start, records: [start, n1])
            .timeline!
            .heading,
        '2026年11月16日 周一');
    final end = formal(end: DateTime.utc(2026, 11, 16, 1));
    final n2 = notice('考试时间：11-16 08:00 至 11-16 09:00');
    expect(
        ExamSchedulePresentation.build(end, records: [end, n2])
            .timeline!
            .heading,
        '11月16日');
  });
  test('trusted end needs no year warning when notice supplies only same end',
      () {
    final a = formal(end: DateTime.utc(2026, 11, 30, 1, 0));
    final n = notice('结束时间：11-30 09:00');
    final p = ExamSchedulePresentation.build(a, records: [a, n]);
    expect(p.yearUnconfirmed, isFalse);
    expect(p.verificationNote, isNull);
    expect(p.detailTimeLines, ['结束 2026年11月30日 09:00']);
  });

  test('mixed trusted and yearless cross-year endpoints never show null year',
      () {
    final start = formal(start: DateTime.utc(2026, 12, 31, 14));
    final endOnlyNotice = notice('考试时间：12-31 22:00 至 1-01 01:00');
    final first =
        ExamSchedulePresentation.build(start, records: [start, endOnlyNotice]);
    expect(first.timeline!.heading, isNot(contains('null')));
    expect(first.yearUnconfirmed, isTrue);
    final end = formal(end: DateTime.utc(2027, 1, 1, 1));
    final startOnlyNotice = notice('考试时间：12-31 22:00 至 1-01 09:00');
    final second =
        ExamSchedulePresentation.build(end, records: [end, startOnlyNotice]);
    expect(second.timeline!.heading, isNot(contains('null')));
    expect(second.yearUnconfirmed, isTrue);
  });
  test('notice timeline keeps month-day without guessing a year or weekday',
      () {
    final a = notice('考试时间：11-16 07:06:00 至 11-30 07:06:31');
    final before = a.toJson();
    final stamp = ExamSchedulePresentation.build(a).timeline!;
    expect(stamp.heading, '11月16日–11月30日');
    expect(stamp.clock, '07:06');
    expect(stamp.key, 'range:notice:11:16:notice:11:30');
    expect(stamp.heading, isNot(contains('年')));
    expect(stamp.heading, isNot(contains('周')));
    expect(a.toJson(), before);
    expect(a.timelineAt, isNull);
    expect(a.timelineTrusted, isFalse);
  });
  test('year and weekday are shown only from explicit date evidence', () {
    final p = ExamSchedulePresentation.build(
        notice('考试时间：2026-11-16 07:06 至 2026-11-30 07:06'));
    expect(p.timeline!.heading, '2026年11月16日 周一–11月30日');
    expect(p.timeline!.clock, '07:06');
    final trusted = ExamSchedulePresentation.build(
        formal(start: DateTime.utc(2026, 11, 16, 0)));
    expect(trusted.timeline!.heading, '2026年11月16日 周一');
    expect(trusted.timeline!.clock, '08:00');
  });
  test('end-only or conflicting notices cannot supply an opening-time rail',
      () {
    expect(ExamSchedulePresentation.build(notice('结束时间：11-30 07:06')).timeline,
        isNull);
    final a = formal();
    expect(
        ExamSchedulePresentation.build(a, records: [
          a,
          notice('考试时间：11-16 08:00 至 11-17 08:00'),
          notice('考试时间：12-01 08:00 至 12-02 08:00', suffix: 'second')
        ]).timeline,
        isNull);
  });
  test('month-day notification is visible without manufacturing an instant',
      () {
    final a =
        notice('试卷名称：合成考试 考试时间：11-16 07:06:00 至 11-30 07:06:31 答题时长：60分钟');
    final before = a.toJson();
    final p = ExamSchedulePresentation.build(a);
    expect(p.cardTimeLines, ['考试时间：11-16 07:06:00 至 11-30 07:06:31']);
    expect(p.verificationNote, '通知未注明年份，暂不作为定时依据');
    expect(a.toJson(), before);
    expect(a.exam!.startAt, isNull);
    expect(AssignmentQuery.isCalendarDated(a, DateTime.utc(2026)), isFalse);
    expect(
        AssignmentReminderSnapshot(assignment: a, hidden: false, followed: true)
            .eligibleAt(DateTime.utc(2026)),
        isFalse);
  });
  test('formal row gets only strictly linked notice display', () {
    final a = formal();
    final good = notice('考试时间：11-16 07:06 至 11-30 07:06');
    final wrong =
        notice('考试时间：12-01 08:00 至 12-02 08:00', suffix: 'other', examId: '4');
    expect(
        ExamSchedulePresentation.build(a, records: [a, good, wrong])
            .cardTimeLines,
        ['考试时间：11-16 07:06 至 11-30 07:06']);
    expect(ExamSchedulePresentation.build(a, records: [a, wrong]).cardTimeLines,
        isEmpty);
  });
  test('trusted full dates win and nonzero seconds survive', () {
    final a = formal(
        start: DateTime.utc(2026, 11, 16, 0),
        end: DateTime.utc(2026, 11, 30, 0, 0, 31));
    final p = ExamSchedulePresentation.build(a,
        records: [a, notice('考试时间：12-01 08:00 至 12-02 08:00')]);
    expect(
        p.cardTimeLines, ['开考 2026年11月16日 08:00', '结束 2026年11月30日 08:00:31']);
    expect(p.verificationNote, isNull);
  });
  test('conflicting notifications are not chosen by read order or stitched',
      () {
    final a = formal();
    final one = notice('考试时间：11-16 08:00 至 11-17 08:00');
    final two = notice('考试时间：12-01 08:00 至 12-02 08:00', suffix: 'second');
    final p = ExamSchedulePresentation.build(a, records: [a, one, two]);
    expect(p.cardTimeLines, isEmpty);
    expect(p.detailTimeLines, hasLength(2));
    expect(p.verificationNote, '通知时间存在不一致，请查看官方通知');
  });
  test('notice publication time is never an exam time', () {
    expect(
        ExamSchedulePresentation.build(
                notice('学习通知 11-16 07:08 试卷名称：考试 答题时长：60分钟'))
            .cardTimeLines,
        isEmpty);
  });
  test('single explicitly labeled endpoints are supported', () {
    expect(
        ExamSchedulePresentation.build(notice('开考时间：11-16 07:06'))
            .cardTimeLines,
        ['开考（通知） 11-16 07:06']);
  });
  test('cross-year and leap day stay textual', () {
    for (final body in [
      '考试时间：12-31 23:00 至 01-01 01:00',
      '考试时间：02-29 08:00 至 03-01 08:00'
    ]) {
      final a = notice(body);
      expect(ExamSchedulePresentation.build(a).cardTimeLines, hasLength(1));
      expect(a.exam!.startAt, isNull);
    }
  });
  test('malformed dates and clocks do not become display evidence', () {
    for (final t in [
      '02-30 08:00',
      '04-31 08:00',
      '13-01 08:00',
      '11-16 24:00',
      '11-16 08:60',
      '11-16 08:00:60'
    ]) {
      expect(
          ExamSchedulePresentation.build(notice('考试时间：$t 至 11-30 08:00'))
              .cardTimeLines,
          isEmpty,
          reason: t);
    }
  });
  test('missing body after private backup restore has no invented placeholders',
      () {
    expect(ExamSchedulePresentation.build(notice('')).cardTimeLines, isEmpty);
  });
  test('registration deadlines are not exam ending fields', () {
    expect(
        ExamSchedulePresentation.build(notice('报名截止时间：11-16 08:00'))
            .cardTimeLines,
        isEmpty);
  });
  test('description examples cannot fill a pending exam field', () {
    expect(
        ExamSchedulePresentation.build(
                notice('考试时间：待定\n答题说明：示例练习区间为11-16 08:00 至11-30 08:00'))
            .cardTimeLines,
        isEmpty);
  });
  test('malformed extended seconds cannot fall back to minutes', () {
    expect(
        ExamSchedulePresentation.build(
                notice('考试时间：11-16 08:00:600 至11-30 08:00'))
            .cardTimeLines,
        isEmpty);
  });
  test('unlabeled instruction on next line does not hide a valid range', () {
    final a = notice('考试时间：11-16 08:00 至 11-16 10:00\n请提前到场');
    expect(ExamSchedulePresentation.build(a).cardTimeLines,
        ['考试时间：11-16 08:00 至 11-16 10:00']);
  });
  test('conflicting duplicate fields never select the first schedule', () {
    final a = notice(
        '考试时间：11-16 08:00 至 11-16 10:00\n考试时间：11-17 08:00 至 11-17 10:00');
    expect(ExamSchedulePresentation.build(a).cardTimeLines, isEmpty);
    final same = notice(
        '考试时间：11-16 08:00 至 11-16 10:00\n考试时间：11-16 08:00 至 11-16 10:00');
    expect(ExamSchedulePresentation.build(same).cardTimeLines, hasLength(1));
  });
  test('trusted notification preserves explicitly supplied zero seconds', () {
    final a = notice('考试时间：2030-04-01 09:00:00 至 2030-04-01 10:00:00').copyWith(
        exam: ExamInfo(
            examId: 'n',
            relatedExamId: '3',
            courseId: '1',
            clazzId: '2',
            noticeOnly: true,
            startAt: DateTime.utc(2030, 4, 1, 1),
            endAt: DateTime.utc(2030, 4, 1, 2),
            startTrusted: true,
            endTrusted: true));
    expect(ExamSchedulePresentation.build(a).cardTimeLines,
        ['开考 2030年4月1日 09:00:00', '结束 2030年4月1日 10:00:00']);
  });
}
