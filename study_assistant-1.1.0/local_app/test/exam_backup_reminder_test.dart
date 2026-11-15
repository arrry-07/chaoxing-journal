import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/assignment_reminder_planner.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';

final _now = DateTime(2026, 11, 16, 9);
final _start = DateTime(2026, 11, 17, 10);
final _end = DateTime(2026, 11, 17, 12);

Assignment _exam({
  String lifecycle = 'scheduled',
  String status = 'pending',
  bool trusted = true,
  bool endTrusted = true,
  bool notice = false,
  bool entry = true,
  String? relatedExamId,
  DateTime? start,
}) =>
    Assignment(
      id: notice ? 'cx:examNotice:inbox:notice1' : 'cx:exam:1:2:exam1',
      source: AssignmentSource.exam,
      courseName: '合成课程',
      title: notice ? '合成考试通知' : '合成考试',
      deadlineAt: _end,
      deadlineTrusted: endTrusted,
      requirementsText: '历史说明 https://example.test/?enc=private-body',
      status: status,
      lastSyncedAt: _now,
      submitUrl: entry
          ? 'https://mooc1-api.chaoxing.com/phone/moocAnalysis/examList?courseId=1&classId=2'
          : null,
      exam: ExamInfo(
        examId: notice ? 'notice1' : 'exam1',
        relatedExamId: relatedExamId,
        courseId: '1',
        clazzId: '2',
        startAt: start ?? _start,
        endAt: _end,
        startTrusted: trusted,
        endTrusted: endTrusted,
        durationMinutes: 120,
        location: '合成考场',
        lifecycle: lifecycle,
        noticeOnly: notice,
      ),
    );

AssignmentReminderPlan _plan(
  List<Assignment> records, {
  Set<String> sources = const {'courseWork', 'exam', 'examNotice'},
  Set<String> completed = const {},
  Set<String> hidden = const {},
  Set<String> unfollowed = const {},
  List<int> offsets = const [30],
  bool newEnabled = true,
}) =>
    AssignmentReminderPlanner.planAfterSync(
      accountHash: 'synthetic-account',
      sessionEpoch: 1,
      assignments: records,
      hiddenAssignmentIds: hidden,
      unfollowedCourseKeys: unfollowed,
      knownAssignmentIds: const {},
      sentNewAssignmentIds: const {},
      baselineCompleted: true,
      completeSync: true,
      detectNewAssignments: true,
      newAssignmentReminderEnabled: newEnabled,
      reminderOffsetsMinutes: offsets,
      now: _now,
      baselinedSources: sources,
      completedSourceKeys: completed,
    );

BackupSnapshot _backup(List<Assignment> records) => BackupSnapshot.create(
      owner: BackupSnapshot.ownerFor('synthetic-owner'),
      createdAt: _now,
      records: records,
      hidden: const {},
      courses: const [],
      unfollowed: const {},
      reminderOffsets: const [30],
      autoSyncIntervalMinutes: 240,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exam uses trusted start even when its end is untrusted', () {
    final exam = _exam(endTrusted: false);
    final plan = _plan([exam]);
    final event = plan.deadlineEvents.single;
    expect(event.eventKind, 'examStart');
    expect(event.notifyAt, _start.subtract(const Duration(minutes: 30)));
    expect(event.deadlineAt, _start);
    expect(exam.deadlineAt, _end);
    expect(event.toJson()['eventKind'], 'examStart');
    expect(plan.snapshotJson.single['deadlineAt'],
        _start.toUtc().toIso8601String());
    expect(plan.snapshotJson.single['deadlineTrusted'], isTrue);
    expect(plan.snapshotJson.single['eventKind'], 'examStart');
    expect(plan.newEvents.single.eventKind, 'examStart');
  });

  test(
      'first exam and notice sources backfill silently then baseline independently',
      () {
    final first = _plan([_exam(), _exam(notice: true)],
        sources: const {'courseWork'}, completed: const {'exam', 'examNotice'});
    expect(first.newEvents, isEmpty);
    expect(
        first.knownAssignmentIds,
        containsAll([
          'cx:exam:1:2:exam1',
          'cx:examNotice:inbox:notice1',
        ]));
    expect(first.baselinedSources, {'courseWork', 'exam', 'examNotice'});
    // Baseline suppresses discovery noise, not future scheduled reminders.
    expect(first.deadlineEvents.single.eventKind, 'examStart');
    expect(
        _plan([_exam()], sources: const {'courseWork', 'examNotice'}).newEvents,
        isEmpty);
    expect(_plan([_exam()], sources: const {'exam'}).newEvents, hasLength(1));
  });

  test('cancelled ended started unknown and notice-only exams never remind',
      () {
    for (final item in [
      _exam(lifecycle: 'cancelled'),
      _exam(lifecycle: 'ended'),
      _exam(lifecycle: 'inProgress'),
      _exam(lifecycle: 'unknown'),
      _exam(status: 'unknown'),
      _exam(status: 'submitted'),
      _exam(trusted: false),
      _exam(entry: false),
      _exam(notice: true),
      _exam(start: _now),
    ]) {
      final plan = _plan([item]);
      expect(plan.deadlineEvents, isEmpty,
          reason: '${item.status}/${item.exam!.lifecycle}');
      expect(plan.newEvents, isEmpty);
    }
    expect(_exam(lifecycle: 'ended').isCompleted, isFalse);
  });

  test('hidden unfollowed and disabled offsets preserve reminder switches', () {
    final item = _exam();
    expect(_plan([item], hidden: {item.id}).eventJson, isEmpty);
    expect(_plan([item], unfollowed: {'1:2'}).eventJson, isEmpty);
    final disabledNew = _plan([item], newEnabled: false);
    expect(disabledNew.newEvents, isEmpty);
    expect(disabledNew.deadlineEvents, hasLength(1));
    expect(_plan([item], offsets: const []).deadlineEvents, isEmpty);
  });

  test('changing start invalidates the stable exam reminder identity', () {
    final first = _plan([_exam()]).deadlineEvents.single;
    final same = _plan([_exam()]).deadlineEvents.single;
    final changed =
        _plan([_exam(start: _start.add(const Duration(minutes: 10)))])
            .deadlineEvents
            .single;
    expect(first.eventId, same.eventId);
    expect(changed.eventId, isNot(first.eventId));
    expect(first.eventId, contains('|examStart:'));
  });

  test('course exam success does not baseline account exams', () {
    final account = _exam().copyWith(
      id: 'cx:exam:account:account:exam1',
      exam: ExamInfo(
          examId: 'exam1',
          startAt: _start,
          endAt: _end,
          startTrusted: true,
          endTrusted: true,
          lifecycle: 'scheduled'),
      submitUrl:
          'https://mooc1-api.chaoxing.com/exam-ans/exam/test/examcode/examlist',
    );
    expect(account.reminderSourceKey, 'examAccount');
    expect(
        _plan([account],
            sources: const {'courseWork', 'exam'},
            completed: const {'exam'}).newEvents,
        isEmpty);
    final baseline = _plan([account],
        sources: const {'exam'}, completed: const {'examAccount'});
    expect(baseline.newEvents, isEmpty);
    expect(baseline.baselinedSources, {'exam', 'examAccount'});
    expect(_plan([account], sources: const {'examAccount'}).newEvents,
        hasLength(1));
  });

  test('backup preserves exam metadata without an entry or live trust', () {
    final snapshot = _backup([_exam(), _exam(notice: true)]);
    final encoded = snapshot.encode();
    expect(jsonDecode(encoded)['schema'], 5);
    expect(encoded, isNot(contains('submitUrl')));
    expect(encoded, isNot(contains('private-body')));
    final restored = BackupSnapshot.decode(encoded).records;
    final exam = restored.first.exam!;
    expect(exam.examId, 'exam1');
    expect(exam.courseId, '1');
    expect(exam.clazzId, '2');
    expect(exam.startAt, _start);
    expect(exam.endAt, _end);
    expect(exam.durationMinutes, 120);
    expect(exam.location, '合成考场');
    expect(exam.lifecycle, 'scheduled');
    expect(exam.startTrusted, isFalse);
    expect(exam.endTrusted, isFalse);
    expect(restored.last.exam!.noticeOnly, isTrue);
    expect(_plan(restored).eventJson, isEmpty);
  });

  test('notice model persists related exam without replacing notice identity',
      () {
    final notice = _exam(notice: true, relatedExamId: '123456');
    final decoded = Assignment.fromJson(notice.toJson());
    expect(decoded.exam!.relatedExamId, '123456');
    expect(decoded.exam!.examId, 'notice1');
    expect(decoded.id, 'cx:examNotice:inbox:notice1');
    expect(decoded.courseTaskKey, notice.courseTaskKey);
    expect(decoded.exam!.noticeOnly, isTrue);
    expect(_plan([decoded]).eventJson, isEmpty);

    final historical =
        _exam(notice: true).exam!.retainingHistoricalTimes(decoded.exam!);
    expect(historical.relatedExamId, '123456');
    expect(ExamInfo.fromJson(historical.toJson()).relatedExamId, '123456');
    final changed = _exam(notice: true, relatedExamId: '987654')
        .exam!
        .retainingHistoricalTimes(decoded.exam!);
    expect(changed.relatedExamId, '987654');
    for (final different in [
      const ExamInfo(
          examId: 'another-notice',
          courseId: '1',
          clazzId: '2',
          noticeOnly: true),
      const ExamInfo(
          examId: 'notice1', courseId: '3', clazzId: '2', noticeOnly: true),
      const ExamInfo(
          examId: 'notice1', courseId: '1', clazzId: '3', noticeOnly: true),
      const ExamInfo(examId: 'notice1', noticeOnly: true),
    ]) {
      expect(different.retainingHistoricalTimes(decoded.exam!).relatedExamId,
          isNull);
    }
  });

  test('model rejects malformed or incomplete notice exam association', () {
    final original =
        _exam(notice: true, relatedExamId: '123456').exam!.toJson();
    for (final invalid in <Map<String, dynamic>>[
      {'relatedExamId': ''},
      {'relatedExamId': 'exam123'},
      {'relatedExamId': '123:456'},
      {'relatedExamId': '123\n'},
      {'relatedExamId': 123456},
      {'relatedExamId': true},
      {'noticeOnly': false},
      {'courseId': null},
      {'clazzId': null},
      {'courseId': ''},
      {'clazzId': ' '},
    ]) {
      expect(() => ExamInfo.fromJson({...original, ...invalid}),
          throwsFormatException);
    }
  });

  test(
      'schema 5 backup accepts related notice identity and missing optional field',
      () {
    final notice = _exam(notice: true, relatedExamId: '123456');
    final encoded = _backup([notice]).encode();
    expect(jsonDecode(encoded)['schema'], 5);
    final restored = BackupSnapshot.decode(encoded).records.single;
    expect(restored.id, notice.id);
    expect(restored.exam!.examId, 'notice1');
    expect(restored.exam!.relatedExamId, '123456');
    expect(restored.exam!.courseId, '1');
    expect(restored.exam!.clazzId, '2');
    expect(restored.exam!.startTrusted, isFalse);
    expect(restored.exam!.endTrusted, isFalse);
    expect(restored.submitUrl, isNull);
    expect(_plan([restored]).eventJson, isEmpty);

    final legacy = jsonDecode(encoded) as Map<String, dynamic>;
    final info =
        (legacy['records'] as List).single['exam'] as Map<String, dynamic>;
    info.remove('relatedExamId');
    final old = BackupSnapshot.decode(jsonEncode(legacy)).records.single;
    expect(old.exam!.relatedExamId, isNull);
    expect(old.id, notice.id);
    expect(ExamInfo.fromJson(info).relatedExamId, isNull);
    info['relatedExamId'] = null;
    expect(
        BackupSnapshot.decode(jsonEncode(legacy))
            .records
            .single
            .exam!
            .relatedExamId,
        isNull);
  });

  test('backup rejects invalid related identity and incomplete notice scope',
      () {
    final encoded =
        _backup([_exam(notice: true, relatedExamId: '123456')]).encode();
    for (final invalid in <Map<String, dynamic>>[
      {'relatedExamId': ''},
      {'relatedExamId': 'exam123'},
      {'relatedExamId': '123:456'},
      {'relatedExamId': '123\n'},
      {'relatedExamId': 123456},
      {'relatedExamId': true},
      {'relatedExamId': '1' * 501},
      {'noticeOnly': false},
      {'courseId': null},
      {'clazzId': null},
      {'courseId': ''},
      {'clazzId': ' '},
    ]) {
      final raw = jsonDecode(encoded) as Map<String, dynamic>;
      final record = (raw['records'] as List).single as Map<String, dynamic>;
      final info = record['exam'] as Map<String, dynamic>;
      info.addAll(invalid);
      if (invalid['noticeOnly'] == false) {
        // Keep the normal exam identity valid so rejection checks the relation.
        record['id'] = 'cx:exam:1:2:notice1';
      }
      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    }
  });

  test('repository restores related notice without trusting it as a live exam',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('synthetic-owner');
    final notice = _exam(notice: true, relatedExamId: '123456');
    await repo.restoreBackupSnapshot(_backup([notice]), 'synthetic-owner');
    final restored = (await repo.loadJournal()).single;
    expect(restored.id, notice.id);
    expect(restored.exam!.examId, 'notice1');
    expect(restored.exam!.relatedExamId, '123456');
    expect(restored.status, 'unknown');
    expect(restored.exam!.startTrusted, isFalse);
    expect(restored.exam!.endTrusted, isFalse);
    expect(restored.submitUrl, isNull);
    expect(_plan([restored]).eventJson, isEmpty);
  });

  test('daily summary counts exam start instead of exam end as a deadline', () {
    final exam = _exam();
    final summaries = DailySummary.build(
        [exam],
        PersonalWorkspace(
            summaryEnabled: true, summaryHour: 8, summaryMinute: 0),
        _now,
        _now);
    final examDay = summaries.singleWhere((s) =>
        PersonalWorkspace.dayKey(s.at) == PersonalWorkspace.dayKey(_start));
    expect(examDay.body, contains('今日截止 0 项 · 今日开考 1 项'));
    final restored = DailySummary.build(
        _backup([exam]).records,
        PersonalWorkspace(
            summaryEnabled: true, summaryHour: 8, summaryMinute: 0),
        _now,
        _now);
    expect(restored.every((s) => !s.body.contains('今日开考')), isTrue);
  });

  test('backup rejects mismatched identity source malformed times and metadata',
      () {
    final original = _backup([_exam()]).encode();
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (r) => r['id'] = 'cx:exam:1:2:other',
      (r) => r['source'] = 'courseWork',
      (r) => r['exam']['courseId'] = 'other',
      (r) => r['exam']['examId'] = 'bad:id',
      (r) => r['exam']['startAt'] = '2026-11-17T10:00:00',
      (r) => r['exam']['endAt'] = '2026-11-01T00:00:00.000Z',
      (r) => r['exam']['durationMinutes'] = -1,
      (r) => r['exam']['startTrusted'] = 'true',
      (r) => r['exam']['noticeOnly'] = 'false',
      (r) => r['exam']['lifecycle'] = 'submitted',
      (r) => r['exam']['submitUrl'] = 'https://example.test/',
    ]) {
      final raw = jsonDecode(original) as Map<String, dynamic>;
      mutate((raw['records'] as List).single as Map<String, dynamic>);
      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    }
  });

  test('schema 1 through 4 still import old exam-source and manual records',
      () {
    final oldExam = Assignment(
      id: 'cx:exam:old',
      source: AssignmentSource.exam,
      courseName: '旧课程',
      title: '旧考试',
      deadlineAt: _end,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: _now,
    );
    final manual =
        oldExam.copyWith(id: 'cx:manual:old', source: AssignmentSource.manual);
    final original = _backup([oldExam, manual]).encode();
    for (var version = 1; version <= 4; version++) {
      final raw = jsonDecode(original) as Map<String, dynamic>;
      raw['schema'] = version;
      if (version < 3) raw.remove('notebook');
      if (version < 2) raw.remove('personal');
      for (final r in raw['records'] as List) {
        r.remove('exam');
        if (version < 4) {
          r.remove('activityType');
          r.remove('availability');
          r.remove('courseTaskKey');
        }
      }
      final restored = BackupSnapshot.decode(jsonEncode(raw)).records;
      expect(restored.map((a) => a.source),
          [AssignmentSource.exam, AssignmentSource.manual]);
      expect(restored.every((a) => a.exam == null), isTrue);
      expect(_plan(restored).eventJson, isEmpty);
    }
  });

  test('repository restore retains exam and notice metadata until genuine sync',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('synthetic-owner');
    await repo.restoreBackupSnapshot(
        _backup([_exam(), _exam(notice: true)]), 'synthetic-owner');
    final records = await repo.loadJournal();
    expect(records, hasLength(2));
    for (final item in records) {
      expect(item.exam, isNotNull);
      expect(item.exam!.startTrusted, isFalse);
      expect(item.exam!.endTrusted, isFalse);
      expect(item.status, 'unknown');
      expect(item.submitUrl, isNull);
      expect(item.lastSyncedAt.millisecondsSinceEpoch, 0);
    }
    expect(_plan(records).eventJson, isEmpty);
    await repo.mergeAndSave([_exam()]);
    final synced =
        (await repo.loadJournal()).singleWhere((a) => !a.exam!.noticeOnly);
    expect(_plan([synced]).deadlineEvents.single.eventKind, 'examStart');
    await repo.activateAccount('another-owner');
    await expectLater(
        repo.restoreBackupSnapshot(_backup([_exam()]), 'another-owner'),
        throwsStateError);
  });
}
