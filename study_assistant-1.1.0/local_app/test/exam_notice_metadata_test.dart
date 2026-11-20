import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/services/exam_schedule_presentation.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_exam_parser.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'exam_sync_test.dart' show pcRow, course, ExamFixture;

Map<String, dynamic> noticePayload(String body,
        {String uuid = 'opaque:notice',
        String title = '通知',
        String examId = '99',
        String course = '7',
        String clazz = '11',
        String? url,
        String sendTime = '2040-01-01',
        bool attachment = true}) =>
    {
      'status': true,
      'notices': {
        'list': [
          {
            'uuid': uuid,
            'title': title,
            'content': body,
            'attachment': jsonEncode(attachment
                ? [
                    {
                      'attachmentType': 15,
                      'att_web': {
                        'examOrWork': 'exam',
                        'examOrWorkId': int.parse(examId),
                        'courseId': int.parse(course),
                        'clazzId': int.parse(clazz),
                        'title': '合成期末考试',
                        'url': url ??
                            'https://mooc1-api.chaoxing.com/examApi/intoexamorwork?taskrefId=$examId&courseId=$course&classId=$clazz&workOrExam=exam&enc=synthetic'
                      }
                    }
                  ]
                : []),
            'sendTime': sendTime,
            'completeTime': '2040-01-02'
          }
        ]
      }
    };

void main() {
  const full =
      '课程名称：合成课程\r考试名称：合成期末考试\r开始时间：2030-04-01 09:00\r结束时间：2030-04-01 11:00\r答题时长：60分钟';
  const yearless = '试卷名称：合成期末考试\r考试时间：04-01 09:00:00 至 04-01 11:00:00';
  Assignment parse(Map<String, dynamic> payload) =>
      ChaoxingExamParser.notices(payload)!.rows.single;
  test('title timestamp anchors a June exam and archives it in autumn', () {
    final now = DateTime.utc(2026, 11, 20);
    final payload = noticePayload('考试时间：06-10 08:00 至 06-10 10:00',
        title: '新建试卷20260609232000');
    final row = ChaoxingExamParser.notices(payload, now: now)!.rows.single;
    expect(row.exam!.startTrusted, isTrue);
    expect(row.exam!.endTrusted, isTrue);
    expect(row.exam!.startAt!.toUtc(), DateTime.utc(2026, 6, 10));
    expect(row.exam!.endAt!.toUtc(), DateTime.utc(2026, 6, 10, 2));
    expect(AssignmentQuery.isArchivedPastTerm(row, now), isTrue);
    expect(AssignmentQuery.currentDisplay([row], now), isEmpty);
  });
  test('official send date anchors a valid range across Beijing New Year', () {
    final payload = noticePayload('考试时间：12-31 23:30 至 01-01 00:30',
        sendTime: '2026-12-29 12:30:00');
    final row =
        ChaoxingExamParser.notices(payload, now: DateTime.utc(2026, 12, 30))!
            .rows
            .single;
    expect(row.publishedAt!.toUtc(), DateTime.utc(2026, 12, 29, 4, 30));
    expect(row.exam!.startAt!.toUtc(), DateTime.utc(2026, 12, 31, 15, 30));
    expect(row.exam!.endAt!.toUtc(), DateTime.utc(2026, 12, 31, 16, 30));
    expect(row.exam!.endTrusted, isTrue);
  });
  test('conflicting years from title and send date cannot archive an exam', () {
    final now = DateTime.utc(2026, 6, 9, 23);
    final payload = noticePayload('考试时间：06-10 08:00 至 06-10 10:00',
        title: '新建试卷20260609232000', sendTime: '2025-06-09 12:00');
    final row = ChaoxingExamParser.notices(payload, now: now)!.rows.single;
    expect(row.exam!.startAt, isNull);
    expect(row.exam!.endAt, isNull);
    expect(row.timelineTrusted, isFalse);
    expect(AssignmentQuery.isArchivedPastTerm(row, now), isFalse);
    expect(AssignmentQuery.currentDisplay([row], now), [row]);
  });
  test('multiple title dates cannot hide an eligible conflicting year', () {
    final now = DateTime.utc(2026, 6, 9, 23);
    final payload = noticePayload('考试时间：06-10 08:00 至 06-10 10:00',
        title: '旧卷20250609232000 新卷20260609232000',
        sendTime: '2025-06-09 12:00');
    final row = ChaoxingExamParser.notices(payload, now: now)!.rows.single;
    expect(row.exam!.startAt, isNull);
    expect(row.exam!.endAt, isNull);
    expect(AssignmentQuery.currentDisplay([row], now), [row]);
  });
  test('completeTime is neither publication nor a year anchor', () {
    for (final send in [null, '2027-06-09 12:00', 'invalid']) {
      final payload = noticePayload('考试时间：06-10 08:00 至 06-10 10:00');
      final raw = (payload['notices']['list'] as List).single as Map;
      if (send == null) {
        raw.remove('sendTime');
      } else {
        raw['sendTime'] = send;
      }
      raw['completeTime'] = '2026-06-09 12:00';
      final row =
          ChaoxingExamParser.notices(payload, now: DateTime.utc(2026, 11, 20))!
              .rows
              .single;
      expect(row.publishedAt, isNull);
      expect(row.exam!.startAt, isNull);
      expect(row.exam!.endAt, isNull);
      expect(row.timelineTrusted, isFalse);
    }
  });

  test('an old title outside the anchor window keeps the year unconfirmed', () {
    final now = DateTime.utc(2026, 11, 20);
    final payload = noticePayload('考试时间：06-10 08:00 至 06-10 10:00',
        title: '重考：新建试卷20250110080000', sendTime: '2026-06-09 12:00');
    final row = ChaoxingExamParser.notices(payload, now: now)!.rows.single;
    expect(row.publishedAt!.toUtc(), DateTime.utc(2026, 6, 9, 4));
    expect(row.exam!.startAt, isNull);
    expect(row.exam!.endAt, isNull);
    expect(row.timelineTrusted, isFalse);
    expect(AssignmentQuery.isArchivedPastTerm(row, now), isFalse);
  });

  test('compatible title dates can independently agree on both endpoints', () {
    final now = DateTime.utc(2026, 11, 20);
    final payload = noticePayload('考试时间：06-10 08:00 至 06-10 10:00',
        title: '试卷20260608080000 更新20260609080000');
    final row = ChaoxingExamParser.notices(payload, now: now)!.rows.single;
    expect(row.publishedAt, isNull);
    expect(row.exam!.startAt!.toUtc(), DateTime.utc(2026, 6, 10));
    expect(row.exam!.endAt!.toUtc(), DateTime.utc(2026, 6, 10, 2));
  });

  test('anchor cannot promote a reversed or distant range to trusted time', () {
    for (final range in [
      '06-10 10:00 至 06-10 08:00',
      '11-10 08:00 至 11-10 10:00'
    ]) {
      final payload = noticePayload('考试时间：$range', sendTime: '2026-06-09');
      final row =
          ChaoxingExamParser.notices(payload, now: DateTime.utc(2026, 11, 20))!
              .rows
              .single;
      expect(row.exam!.startAt, isNull);
      expect(row.exam!.endAt, isNull);
      expect(row.timelineTrusted, isFalse);
    }
  });
  test(
      'notice reads actual exam name absolute dates duration and physical place',
      () {
    final row = ChaoxingExamParser.notices(noticePayload(
            '课程名称：合成课程\r考试名称：合成期末考试\r开始时间：2030-04-01 09:00\r结束时间：2030-04-01 11:00\r答题时长：60分钟\r考试地点：合成教学楼A301'))!
        .rows
        .single;
    expect(row.title, '合成期末考试');
    expect(row.courseName, '合成课程');
    expect(row.exam!.startAt!.toUtc(), DateTime.utc(2030, 4, 1, 1));
    expect(row.exam!.endAt!.toUtc(), DateTime.utc(2030, 4, 1, 3));
    expect(row.exam!.startTrusted, isTrue);
    expect(row.exam!.durationMinutes, 60);
    expect(row.exam!.location, '合成教学楼A301');
  });
  test('HTML notice preserves labeled range while missing venue stays absent',
      () {
    final row = ChaoxingExamParser.notices(noticePayload(
            '<p>试卷名称：合成期末考试</p><p>考试时间：2030-04-01 23:00 至 2030-04-02 01:00</p><p>答题时长：90分钟</p>'))!
        .rows
        .single;
    expect(row.title, '合成期末考试');
    expect(row.timelineTrusted, isTrue);
    expect(row.exam!.endAt!.toUtc(), DateTime.utc(2030, 4, 1, 17));
    expect(row.exam!.durationMinutes, 90);
    expect(row.exam!.location, isEmpty);
    expect(row.status, 'unknown');
  });
  test(
      'ordinary notice mentioning examination policy does not become an exam event',
      () {
    final parsed = ChaoxingExamParser.notices(
        noticePayload('请遵守考试纪律，诚信应考。', title: '校园行为须知', attachment: false));
    expect(parsed!.rows, isEmpty);
  });
  test(
      'same structured exam identity resolves month-day notice using unique matching evidence',
      () {
    final a = parse(noticePayload(full, uuid: 'notice:full'));
    final b = parse(noticePayload(yearless, uuid: 'notice:yearless'));
    expect(a.exam!.relatedExamId, '99');
    expect(a.courseId, '7');
    expect(a.clazzId, '11');
    expect(b.timelineTrusted, isFalse);
    final joined = ChaoxingExamParser.enrichNotices([a, b]).last;
    expect(joined.id, b.id);
    expect(joined.timelineTrusted, isTrue);
    expect(joined.exam!.startAt!.toUtc(), DateTime.utc(2030, 4, 1, 1));
    expect(joined.exam!.endAt!.toUtc(), DateTime.utc(2030, 4, 1, 3));
    expect(joined.exam!.durationMinutes, 60);
    expect(joined.status, 'unknown');
  });
  test('same name with different exam or class never provides time evidence',
      () {
    final a = parse(noticePayload(full, uuid: 'notice:full'));
    for (final b in [
      parse(noticePayload(yearless, uuid: 'different-exam', examId: '100')),
      parse(noticePayload(yearless, uuid: 'different-class', clazz: '12'))
    ]) {
      final joined = ChaoxingExamParser.enrichNotices([a, b]).last;
      expect(joined.timelineTrusted, isFalse);
      expect(joined.timelineAt, isNull);
    }
  });
  test('contradicting years and unmatched month-day remain uncertain', () {
    final a = parse(noticePayload(full, uuid: 'full:2030'));
    final other = parse(
        noticePayload(full.replaceAll('2030', '2031'), uuid: 'full:2031'));
    final b = parse(noticePayload(yearless, uuid: 'missing:year'));
    expect(ChaoxingExamParser.enrichNotices([a, other, b]).last.timelineTrusted,
        isFalse);
    final mismatch = parse(noticePayload(yearless.replaceAll('04-01', '04-02'),
        uuid: 'wrong:day'));
    expect(ChaoxingExamParser.enrichNotices([a, mismatch]).last.timelineTrusted,
        isFalse);
  });
  test(
      'verified current exam supplies changed schedule and personal submission without changing notice ID',
      () {
    final notice = parse(noticePayload(yearless));
    final exam = ChaoxingExamParser.make(
        id: '99',
        title: '合成期末考试（改期）',
        courseId: '7',
        clazzId: '11',
        courseName: '合成课程',
        status: 'submitted',
        start: DateTime.utc(2032, 5, 2, 1),
        end: DateTime.utc(2032, 5, 2, 3),
        duration: 90,
        location: '合成机房B202');
    final result = ChaoxingExamParser.enrichNotices([exam, notice]).last;
    expect(result.id, notice.id);
    expect(result.isCompleted, isTrue);
    expect(result.title, exam.title);
    expect(result.timelineAt, exam.timelineAt);
    expect(result.exam!.location, '合成机房B202');
    expect(result.exam!.durationMinutes, 90);
    final wrong = exam.copyWith(
        id: 'cx:exam:7:11:100',
        exam: const ExamInfo(examId: '100', courseId: '7', clazzId: '11'));
    expect(ChaoxingExamParser.enrichNotices([wrong, notice]).last.isCompleted,
        isFalse);
  });
  test(
      'embedded card rejects mismatched aliases external hosts and malformed identities',
      () {
    for (final url in [
      'https://mooc1-api.chaoxing.com/examApi/intoexamorwork?taskrefId=99&courseId=7&classId=12&workOrExam=exam',
      'https://mooc1-api.chaoxing.com/examApi/intoexamorwork?taskrefId=99&courseId=7&classId=11&clazzId=12&workOrExam=exam',
      'https://evil.example/examApi/intoexamorwork?taskrefId=99&courseId=7&classId=11&workOrExam=exam'
    ]) {
      final row = parse(noticePayload(full, url: url));
      expect(row.exam!.relatedExamId, isNull);
      expect(row.courseId, isNull);
      expect(row.status, 'unknown');
    }
    final row = parse(noticePayload(full));
    expect(row.submitUrl, 'https://notice.chaoxing.com/pc/notice/myNotice');
    expect(row.toJson().toString(), isNot(contains('enc=synthetic')));
  });
  test(
      'PC list metadata reads duration and venue from matching exam notes only',
      () {
    final html = pcRow() +
        r'''<script>TestRelationInfo={"99":{"limitTime":60,"pcExamNotes":"考试地点：合成A301"},"100":{"limitTime":120,"pcExamNotes":"考试地点：不可借用B202"}};</script>''';
    final exam = ChaoxingExamParser.coursePc(html, course)!.rows.single;
    expect(exam.exam!.durationMinutes, 60);
    expect(exam.exam!.location, '合成A301');
    final noMatch = ChaoxingExamParser.coursePc(
            pcRow() +
                r'''<script>TestRelationInfo={"100":{"limitTime":120}};</script>''',
            course)!
        .rows
        .single;
    expect(noMatch.exam!.durationMinutes, isNull);
  });
  test('missing venue is omitted while trusted schedule and duration remain',
      () {
    final row = parse(noticePayload(full));
    expect(row.exam!.location, isEmpty);
    expect(
      AssignmentCard.examScheduleLines(row),
      orderedEquals([
        '开考 2030年4月1日 09:00',
        '结束 2030年4月1日 11:00',
        '时长 60 分钟',
      ]),
    );
    final withVenue = parse(noticePayload('$full\r考试地点：合成教学楼A301'));
    expect(
      AssignmentCard.examScheduleLines(withVenue),
      orderedEquals([
        '开考 2030年4月1日 09:00',
        '结束 2030年4月1日 11:00',
        '时长 60 分钟',
        '地点 合成教学楼A301',
      ]),
    );
  });
  test('an unqueried cached exam cannot override a fresh reschedule', () async {
    final payload = noticePayload('考试时间：2030-04-02 09:00 至 2030-04-02 11:00');
    final f = ExamFixture()
      ..unsignedCoursePage = '<main>课程入口</main>'
      ..emptyPhone = true
      ..noticeRows = List<Map<String, dynamic>>.from(
          (payload['notices'] as Map)['list'] as List);
    final old = ChaoxingExamParser.make(
      id: '99',
      title: '旧考试',
      courseId: '7',
      clazzId: '11',
      status: 'pending',
      start: DateTime.utc(2030, 4, 1, 1),
      end: DateTime.utc(2030, 4, 1, 3),
    ).copyWith(availability: AssignmentAvailability.available);
    final client = f.client()..previousAssignments = {old.id: old};
    final notice = (await client.fetchAssignments())
        .singleWhere((row) => row.exam!.noticeOnly);
    expect(notice.exam!.startAt!.toUtc(), DateTime.utc(2030, 4, 2, 1));
    expect(notice.exam!.endAt!.toUtc(), DateTime.utc(2030, 4, 2, 3));
    expect(notice.timelineTrusted, isTrue);
  });
  test(
      'a newer notice is flagged for verification when the formal time stayed cached',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    final payload = noticePayload(
        '考试时间：2026-11-26 09:00 至 2026-11-26 11:00\r考试地点：新地点',
        sendTime: '2026-11-19 12:00');
    final f = ExamFixture()
      ..unsignedCoursePage = '<main>课程入口</main>'
      ..emptyPhone = true
      ..noticeRows = List<Map<String, dynamic>>.from(
          (payload['notices'] as Map)['list'] as List);
    final old = ChaoxingExamParser.make(
      id: '99',
      title: '旧考试',
      courseId: '7',
      clazzId: '11',
      status: 'pending',
      now: DateTime.utc(2026, 11, 17),
      start: DateTime.utc(2026, 11, 18, 1),
      end: DateTime.utc(2026, 11, 18, 3),
    );
    await repo.mergeAndSave([old]);
    final client = f.client()..previousAssignments = {old.id: old};
    await repo.mergeAndSave(await client.fetchAssignments(),
        completeSync: false);
    final records = await repo.loadJournal();
    final formal = AssignmentQuery.projectDisplay(records).single;
    expect(formal.id, old.id);
    expect(formal.exam!.startAt?.toUtc(), old.exam!.startAt?.toUtc());
    expect(formal.exam!.location, '新通知地点：新地点（请核对）');
    final result = ExamSchedulePresentation.build(formal, records: records);
    expect(result.verificationNote, '有较新的通知与本机考试时间不一致，请核对官方最新安排');
    expect(result.detailTimeLines,
        contains('考试时间：2026-11-26 09:00 至 2026-11-26 11:00'));
  });

  for (final explicitVenue in [false, true]) {
    test(
        'newer notice venue must come from its own text (explicit=$explicitVenue)',
        () {
      final formal = ChaoxingExamParser.make(
        id: '99',
        title: '缓存考试',
        courseId: '7',
        clazzId: '11',
        status: 'pending',
        now: DateTime.utc(2026, 11, 17),
        start: DateTime.utc(2026, 11, 18, 1),
        end: DateTime.utc(2026, 11, 18, 3),
        location: explicitVenue ? '旧地点' : '',
      );
      final earlier = parse(noticePayload(
          '考试时间：2026-11-18 09:00 至 2026-11-18 11:00\r考试地点：旧地点',
          uuid: 'older-notice',
          sendTime: '2026-11-14 12:00'));
      final newer = parse(noticePayload(
          '考试时间：2026-11-26 09:00 至 2026-11-26 11:00'
          '${explicitVenue ? '\r考试地点：新地点' : ''}',
          uuid: 'newer-notice',
          sendTime: '2026-11-19 12:00'));
      final records = [
        formal,
        ...ChaoxingExamParser.enrichNotices([earlier, newer])
      ];
      final projected = AssignmentQuery.projectDisplay(records).single;
      final display =
          ExamSchedulePresentation.build(projected, records: records);
      expect(projected.exam!.location, formal.exam!.location);
      expect(display.cardTimeLines,
          ['开考 2026年11月18日 09:00', '结束 2026年11月18日 11:00']);
      if (explicitVenue) {
        expect(display.detailTimeLines, contains('新通知地点：新地点（请核对）'));
      } else {
        expect(display.detailTimeLines.join(), isNot(contains('新通知地点')));
      }
    });
  }

  test('normal full client refresh enriches notice records before persistence',
      () async {
    final payload = noticePayload(full);
    final f = ExamFixture()
      ..noticeRows = List<Map<String, dynamic>>.from(
          (payload['notices'] as Map)['list'] as List)
      ..pcMetadata =
          r'''<script>TestRelationInfo={"99":{"limitTime":60}};</script>''';
    final c = f.client();
    final rows = await c.fetchAssignments();
    final notice = rows.singleWhere((a) => a.exam!.noticeOnly);
    final exam = rows.singleWhere((a) => !a.exam!.noticeOnly);
    expect(notice.title, exam.title);
    expect(notice.isCompleted, isTrue);
    expect(notice.timelineAt, exam.timelineAt);
    expect(notice.exam!.durationMinutes, 60);
    expect(
        c.sourceResults
            .singleWhere((s) => s.source == 'examNotice')
            .unconfirmedCount,
        0);
  });
  test(
      'current reschedule supersedes old notice duration and marks an unconfirmed old venue',
      () {
    final notice = parse(noticePayload('$full\r考试地点：旧合成A301'));
    final exam = ChaoxingExamParser.make(
        id: '99',
        title: '合成改期考试',
        courseId: '7',
        clazzId: '11',
        status: 'pending',
        start: DateTime.utc(2031, 4, 1, 1),
        end: DateTime.utc(2031, 4, 1, 3),
        duration: 90);
    final joined = ChaoxingExamParser.enrichNotices([exam, notice]).last;
    expect(joined.exam!.durationMinutes, 90);
    expect(joined.exam!.location, '通知原地点：旧合成A301（已改期，请核对）');
    expect(joined.isCompleted, isFalse);
  });
  test('invalid ranges and conflicting labeled fields do not schedule a notice',
      () {
    final row = parse(noticePayload(full.replaceAll('11:00', '08:00')));
    expect(row.exam!.startTrusted, isFalse);
    expect(row.exam!.endTrusted, isFalse);
    final mixed = parse(noticePayload('$full\r开始时间：2031-04-01 09:00'));
    expect(mixed.exam!.startTrusted, isFalse);
    expect(row.reminderAnchorAt, isNull);
  });
  test('plain text and RTF exam entry URLs never persist access parameters',
      () {
    const link =
        'https://mooc1-api.chaoxing.com/examApi/intoexamorwork?taskrefId=99&enc=do-not-persist-token';
    for (final rich in [false, true]) {
      final payload = noticePayload(full);
      final row = ((payload['notices'] as Map)['list'] as List).single as Map;
      row[rich ? 'rtf_content' : 'content'] = '$full\r官方入口：$link';
      final saved = parse(payload);
      expect(
          saved.toJson().toString(), isNot(contains('do-not-persist-token')));
      expect(saved.toJson().toString(),
          isNot(contains('/examApi/intoexamorwork')));
      expect(saved.title, '合成期末考试');
      expect(saved.timelineTrusted, isTrue);
    }
  });
  test('separate partial notices cannot manufacture a trusted year-long range',
      () {
    final start = parse(
        noticePayload('考试名称：合成考试\r开始时间：2030-04-01 09:00', uuid: 'start:only'));
    final end = parse(
        noticePayload('考试名称：合成考试\r结束时间：2031-04-01 11:00', uuid: 'end:only'));
    final missing = parse(noticePayload(yearless, uuid: 'missing:both'));
    final result = ChaoxingExamParser.enrichNotices([start, end, missing]).last;
    expect(result.exam!.startTrusted, isFalse);
    expect(result.exam!.endTrusted, isFalse);
    expect(result.reminderAnchorAt, isNull);
  });

  test('December sendTime and title timestamp agree on early January exam', () {
    final now = DateTime.utc(2026, 12, 30);
    final payload = noticePayload('考试时间：01-03 09:00 至 01-03 11:00',
        title: '期末考试20261229120000', sendTime: '2026-12-29 12:00:00');
    final row = ChaoxingExamParser.notices(payload, now: now)!.rows.single;
    expect(row.exam!.startTrusted, isTrue);
    expect(row.exam!.endTrusted, isTrue);
    expect(row.exam!.startAt!.toUtc(), DateTime.utc(2027, 1, 3, 1));
    expect(row.exam!.endAt!.toUtc(), DateTime.utc(2027, 1, 3, 3));
  });

  test(
      'conflicting cross-year title timestamp stays unconfirmed for January exam',
      () {
    final now = DateTime.utc(2026, 12, 30);
    final payload = noticePayload('考试时间：01-03 09:00 至 01-03 11:00',
        title: '旧卷20251229120000', sendTime: '2026-12-29 12:00:00');
    final row = ChaoxingExamParser.notices(payload, now: now)!.rows.single;
    expect(row.exam!.startAt, isNull);
    expect(row.exam!.endAt, isNull);
    expect(row.timelineTrusted, isFalse);
  });

  test(
      'yearless notice anchored by sendTime flags cross-year reschedule and conflict',
      () {
    final formal2025 = ChaoxingExamParser.make(
      id: '99',
      title: '跨年测试考试',
      courseId: '7',
      clazzId: '11',
      status: 'pending',
      now: DateTime.utc(2025, 6, 1),
      start: DateTime.utc(2025, 6, 10, 0),
      end: DateTime.utc(2025, 6, 10, 2),
    );
    final anchored2026 = parse(noticePayload(
        '考试时间：06-10 08:00 至 06-10 10:00\r考试地点：新教学楼',
        uuid: 'notice:2026',
        sendTime: '2026-06-09 12:00:00'));
    final anchored2025 = parse(noticePayload('考试时间：06-10 08:00 至 06-10 10:00',
        uuid: 'notice:2025', sendTime: '2025-06-09 12:00:00'));
    final display = ExamSchedulePresentation.build(formal2025,
        records: [formal2025, anchored2026]);
    expect(display.verificationNote, '有较新的通知与本机考试时间不一致，请核对官方最新安排');
    expect(display.detailTimeLines,
        contains('考试时间：2026-06-10 08:00 至 2026-06-10 10:00'));
    final projected =
        AssignmentQuery.projectDisplay([anchored2025, anchored2026]).single;
    final conflictingRanges = AssignmentQuery.displayNoticeRanges(projected,
        records: [anchored2025, anchored2026]);
    expect(conflictingRanges, hasLength(2));
  });
}
