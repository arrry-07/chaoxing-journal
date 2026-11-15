import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';

const _journalKey = 'chaoxing_journal_v2';
const _account = 'synthetic-account';

Assignment _task({
  String? id,
  String course = 'course',
  String clazz = 'class',
  String active = 'task',
  int? type = 35,
  String status = 'pending',
  AssignmentAvailability availability = AssignmentAvailability.available,
  DateTime? observedAt,
}) =>
    Assignment(
      id: id ?? 'cx:activity:$course:$clazz:$active',
      source: AssignmentSource.classroomActivity,
      activityType: type,
      persistedCourseTaskKey:
          type == 77 ? 'cx:activity:$course:$clazz:$active' : null,
      aiPracticePublishUuid:
          type == 77 ? '11111111-1111-4111-8111-111111111111' : null,
      availability: availability,
      courseName: '合成课程',
      title: '同名合成任务',
      requirementsText:
          'https://mobilelearn.chaoxing.com/task?enc=synthetic-body-secret',
      status: status,
      deadlineAt: DateTime.utc(2026, 12, 2),
      deadlineRawText: '2026-12-02 08:00',
      lastSyncedAt: observedAt ?? DateTime.utc(2026, 11, 15),
      submitUrl: type == 77
          ? 'https://mooc2-ans.chaoxing.com/ai-evaluate/v2/redirect/active/stu?courseid=$course&clazzid=$clazz&publishUuid=11111111-1111-4111-8111-111111111111'
          : 'https://mobilelearn.chaoxing.com/page/renwu/task'
              '?courseId=$course&classId=$clazz&activeId=$active'
              '&enc=synthetic-link-secret',
    );

Future<void> _seedJournal(List<Assignment> rows,
    {int? version = 1,
    Set<String> hidden = const {},
    bool legacyFields = false}) async {
  final prefs = await SharedPreferences.getInstance();
  final records = rows.map((a) {
    final record = a.toJson();
    if (legacyFields) {
      record.remove('activityType');
      record.remove('availability');
    }
    return record;
  }).toList();
  await prefs.setString(
      _journalKey,
      jsonEncode({
        if (version != null) 'schemaVersion': version,
        'records': records,
        'hidden': hidden.toList(),
        'lastSync': '2026-11-15T00:00:00.000Z',
      }));
}

PersonalWorkspace _personal(Iterable<String> ids) => PersonalWorkspace(
      work: {
        for (final id in ids)
          id: PersonalWork(note: 'note-$id', files: const [
            PersonalLink('合成附件', 'content://synthetic-documents/report'),
          ]),
      },
      plans: [
        for (final id in ids) DailyPlanItem(id, '2026-11-15', 30),
      ],
    );

BackupSnapshot _backup(List<Assignment> rows) => BackupSnapshot.create(
      owner: BackupSnapshot.ownerFor(_account),
      createdAt: DateTime.utc(2026, 11, 15),
      records: rows,
      hidden: {},
      courses: [],
      unfollowed: {},
      reminderOffsets: [60],
      autoSyncIntervalMinutes: 30,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('duplicate typed aliases stop stale pending reminders after submission',
      () async {
    final old = _task(id: 'cx:activity:old-alias');
    final canonical = _task();
    await _seedJournal([old, canonical], version: 2);
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave(
        [_task(status: 'submitted', observedAt: DateTime.utc(2026, 11, 16))]);
    final rows = await repo.loadJournal();
    expect(rows.length, 2);
    expect(rows.singleWhere((a) => a.id == old.id).status, 'unknown');
    expect(rows.singleWhere((a) => a.id == old.id).isPendingConfirmed, isFalse);
    expect(rows.singleWhere((a) => a.id == canonical.id).isCompleted, isTrue);
    expect(repo.identityConflictSources, {'classroomActivity:35'});
    expect((await repo.lastSyncAt())!.toUtc(), DateTime.utc(2026, 11, 15));
  });

  test('restored opaque task remains in scope when personal detail fails',
      () async {
    final original = _task(id: 'cx:activity:opaque');
    final repo = LocalAssignmentRepository();
    await repo.activateAccount(_account);
    await repo.restoreBackupSnapshot(_backup([original]), _account);
    await repo.mergeAndSave([
      _task(
              status: 'unknown',
              availability: AssignmentAvailability.unknown,
              observedAt: DateTime.utc(2026, 11, 16))
          .copyWith(
              clearSubmitUrl: true,
              clearDeadlineAt: true,
              deadlineTrusted: false)
    ]);
    final restored = (await LocalAssignmentRepository().loadJournal()).single;
    expect(restored.id, original.id);
    expect(restored.submitUrl, isNull);
    expect(restored.courseTaskKey, 'cx:activity:course:class:task');
    expect(restored.isInAssignmentScope, isTrue);
    expect(restored.status, 'unknown');
    expect(restored.isPendingConfirmed, isFalse);
  });

  for (final type in [35, 42, 77]) {
    for (final availability in AssignmentAvailability.values) {
      test('type $type and $availability survive JSON copy and journal reload',
          () async {
        final original = _task(type: type, availability: availability);
        final copied =
            Assignment.fromJson(original.toJson()).copyWith(title: '更新标题');
        expect(copied.activityType, type);
        expect(copied.availability, availability);
        expect(copied.courseTaskKey, original.courseTaskKey);
        final repo = LocalAssignmentRepository();
        await repo.mergeAndSave([copied]);
        final restored =
            (await LocalAssignmentRepository().loadJournal()).single;
        expect(restored.activityType, type);
        expect(restored.availability, availability);
        expect(restored.isInAssignmentScope,
            availability != AssignmentAvailability.unavailable);
        final prefs = await SharedPreferences.getInstance();
        expect(jsonDecode(prefs.getString(_journalKey)!)['schemaVersion'], 2);
      });
    }

    for (final status in ['pending', 'returned', 'overdue', 'unknown']) {
      test('type $type replaces completed status with current $status',
          () async {
        final old = _task(type: type, status: 'submitted')
            .copyWith(completedAt: DateTime.utc(2026, 11, 14));
        final repo = LocalAssignmentRepository();
        await repo.mergeAndSave([old]);
        final current = _task(
                type: type,
                status: status,
                availability: AssignmentAvailability.unknown,
                observedAt: DateTime.utc(2026, 11, 16))
            .copyWith(completedAt: old.completedAt);
        final pending = await repo.mergeAndSave([current]);
        expect(pending.single.status, status);
        expect(pending.single.completedAt, isNull);
        final restored =
            (await LocalAssignmentRepository().loadJournal()).single;
        expect(restored.status, status);
        expect(restored.completedAt, isNull);
        expect(restored.availability, AssignmentAvailability.unknown);
      });
    }

    test('type $type rejects stale personal state and accepts fresh completion',
        () async {
      final repo = LocalAssignmentRepository();
      final submitted = _task(
              type: type,
              status: 'submitted',
              observedAt: DateTime.utc(2026, 11, 16))
          .copyWith(completedAt: DateTime.utc(2026, 11, 16));
      await repo.mergeAndSave([submitted]);
      await repo.mergeAndSave([_task(type: type, status: 'unknown')]);
      expect((await repo.loadJournal()).single.status, 'submitted');
      expect((await repo.loadJournal()).single.completedAt?.toUtc(),
          submitted.completedAt?.toUtc());
      await repo.mergeAndSave(
          [_task(type: type, observedAt: DateTime.utc(2026, 11, 17))]);
      expect((await repo.loadJournal()).single.completedAt, isNull);
      await repo.mergeAndSave(
          [submitted.copyWith(lastSyncedAt: DateTime.utc(2026, 11, 18))]);
      expect((await repo.loadJournal()).single.status, 'submitted');
      expect(await repo.loadAssignments(), isEmpty);
    });

    test('type $type personal pending overrides legacy peer-review labels',
        () async {
      final repo = LocalAssignmentRepository();
      await repo.mergeAndSave([_task(type: type, status: 'submitted')]);
      final current = _task(type: type, observedAt: DateTime.utc(2026, 11, 16))
          .copyWith(requirementsText: '互评作业 已完成');
      expect((await repo.mergeAndSave([current])).single.status, 'pending');
      expect((await repo.loadAssignments()).single.status, 'pending');
    });

    for (final legacyId in [
      'cx:activity:course:class:task',
      'cx:activity:old',
      'web:old-activity',
    ]) {
      test('type $type upgrades $legacyId in place preserving personal links',
          () async {
        final repo = LocalAssignmentRepository();
        await repo.activateAccount(_account);
        final old = _task(id: legacyId, type: null, status: 'submitted')
            .copyWith(
                source: legacyId.startsWith('web:')
                    ? AssignmentSource.legacyUnknown
                    : AssignmentSource.classroomActivity,
                completedAt: DateTime.utc(2026, 11, 14));
        await _seedJournal([old], hidden: {legacyId}, legacyFields: true);
        final personal = _personal([legacyId]);
        await repo.savePersonalWorkspace(personal, _account);
        await repo.mergeAndSave([
          _task(type: type, observedAt: DateTime.utc(2026, 11, 16))
              .copyWith(title: '新个人状态'),
        ]);
        expect(await repo.loadJournal(), isEmpty);
        final hidden = (await repo.loadHiddenAssignments()).single;
        expect(hidden.id, legacyId);
        expect(hidden.courseTaskKey, 'cx:activity:course:class:task');
        expect(hidden.activityType, type);
        expect(hidden.status, 'pending');
        expect(hidden.completedAt, isNull);
        expect(
            (await repo.loadPersonalWorkspace()).encode(), personal.encode());
        await repo.updateCompletion(legacyId, false);
        expect((await repo.loadAssignments()).single.id, legacyId);
        await repo.mergeAndSave([
          _task(type: type, observedAt: DateTime.utc(2026, 11, 17)),
        ]);
        expect((await repo.loadJournal()).single.id, legacyId);
      });
    }

    test('type $type portable restore retains an opaque ID for the next sync',
        () async {
      const legacyId = 'cx:activity:opaque';
      const identity = 'cx:activity:course:class:task';
      final repo = LocalAssignmentRepository();
      await repo.activateAccount(_account);
      await _seedJournal([_task(id: legacyId, type: null)], legacyFields: true);
      final personal = _personal([legacyId]);
      await repo.savePersonalWorkspace(personal, _account);
      await repo.mergeAndSave([_task(type: type)]);
      await repo.updateCompletion(legacyId, true);
      final encoded = (await repo.createBackupSnapshot(_account)).encode();
      final record = (jsonDecode(encoded)['records'] as List).single as Map;
      expect(record['id'], legacyId);
      expect(record['courseTaskKey'], identity);
      expect(encoded, isNot(contains('synthetic-link-secret')));
      expect(encoded, isNot(contains('submitUrl')));

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_journalKey);
      await prefs.remove('personal_workspace_v1');
      await repo.restoreBackupSnapshot(
          BackupSnapshot.decode(encoded), _account);
      final reloaded = LocalAssignmentRepository();
      final restored = (await reloaded.loadHiddenAssignments()).single;
      expect(restored.id, legacyId);
      expect(restored.activityType, type);
      expect(restored.status, 'unknown');
      expect(restored.submitUrl, isNull);

      // Re-export before a sync must retain identity independently of a URL.
      final repeated = (await reloaded.createBackupSnapshot(_account)).encode();
      expect((jsonDecode(repeated)['records'] as List).single['courseTaskKey'],
          identity);
      await prefs.remove(_journalKey);
      await reloaded.restoreBackupSnapshot(
          BackupSnapshot.decode(repeated), _account);
      await reloaded.mergeAndSave([
        _task(type: type, observedAt: DateTime.utc(2026, 11, 16)),
      ]);
      expect(await reloaded.loadJournal(), isEmpty);
      final confirmed = (await reloaded.loadHiddenAssignments()).single;
      expect(confirmed.id, legacyId);
      expect(confirmed.courseTaskKey, identity);
      expect(confirmed.status, 'pending');
      expect(confirmed.deadlineTrusted, isTrue);
      final imported = await reloaded.loadPersonalWorkspace();
      expect(imported.work[legacyId]!.note, personal.work[legacyId]!.note);
      expect(imported.plans.single.assignmentId, legacyId);
      // Device-local content references intentionally do not enter a backup.
      expect(imported.work[legacyId]!.files, isEmpty);
      expect(reloaded.identityConflictCount, 0);
    });

    test(
        'type $type retains the last deadline on failure then accepts unlimited',
        () async {
      final repo = LocalAssignmentRepository();
      final old = _task(type: type);
      await repo.mergeAndSave([old]);
      await repo.mergeAndSave([
        _task(type: type, observedAt: DateTime.utc(2026, 11, 16)).copyWith(
            clearDeadlineAt: true,
            deadlineReadFailed: true,
            deadlineTrusted: false,
            deadlineRawText: '合成读取失败'),
      ]);
      final failed = (await repo.loadJournal()).single;
      expect(failed.deadlineAt?.toUtc(), old.deadlineAt?.toUtc());
      expect(failed.deadlineTrusted, old.deadlineTrusted);
      expect(failed.deadlineRawText, old.deadlineRawText);
      expect(failed.deadlineReadFailed, isTrue);
      await repo.mergeAndSave([
        _task(type: type, observedAt: DateTime.utc(2026, 11, 17))
            .copyWith(clearDeadlineAt: true, clearDeadlineRawText: true),
      ]);
      final unlimited = (await repo.loadJournal()).single;
      expect(unlimited.deadlineAt, isNull);
      expect(unlimited.deadlineTrusted, isTrue);
      expect(unlimited.deadlineReadFailed, isFalse);
    });
  }

  for (final version in [null, 1]) {
    test('journal $version reads old fields and writes schema 2 on merge',
        () async {
      final old = _task(type: null);
      await _seedJournal([old], version: version, legacyFields: true);
      final repo = LocalAssignmentRepository();
      final restored = (await repo.loadJournal()).single;
      expect(restored.activityType, isNull);
      expect(restored.availability, AssignmentAvailability.available);
      expect((await repo.lastSyncAt())?.toUtc(), DateTime.utc(2026, 11, 15));
      await repo.mergeAndSave([_task(type: 42)]);
      expect((await repo.loadJournal()).single.activityType, 42);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(_journalKey)!)['schemaVersion'], 2);
    });
  }

  test('legacy preference migration writes schema 2 without guessing type',
      () async {
    final record = _task(type: null).toJson()
      ..remove('activityType')
      ..remove('availability');
    SharedPreferences.setMockInitialValues({
      'local_assignments': jsonEncode([record]),
      'local_hidden_completed_assignment_ids': <String>[],
    });
    final repo = LocalAssignmentRepository();
    expect((await repo.loadJournal()).single.activityType, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('local_assignments'), isFalse);
    expect(jsonDecode(prefs.getString(_journalKey)!)['schemaVersion'], 2);
  });

  for (final version in [3, 99, 2.0, '2']) {
    test('unsupported journal schema $version refuses all ordinary writes',
        () async {
      final repo = LocalAssignmentRepository();
      await repo.activateAccount(_account);
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        'schemaVersion': version,
        'records': [_task().toJson()],
        'hidden': [],
        'lastSync': null,
      });
      await prefs.setString(_journalKey, encoded);
      final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      await expectLater(repo.loadJournal(), throwsStateError);
      await expectLater(repo.mergeAndSave([_task()]), throwsStateError);
      await expectLater(
          repo.updateCompletion(_task().id, true), throwsStateError);
      await expectLater(repo.createBackupSnapshot(_account), throwsStateError);
      await expectLater(
          repo.restoreBackupSnapshot(_backup([]), _account), throwsStateError);
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    });
  }

  test('same titles and tail IDs stay separate across course class and source',
      () async {
    final repo = LocalAssignmentRepository();
    final formal = _task().copyWith(
        id: 'cx:work:course:class:task',
        source: AssignmentSource.courseWork,
        submitUrl: 'https://mooc1.chaoxing.com/work'
            '?courseId=course&classId=class&workId=task&activeId=task');
    final task = _task().copyWith(submitUrl: formal.submitUrl);
    await repo.mergeAndSave([
      formal,
      task,
      _task(course: 'other-course'),
      _task(clazz: 'other-class'),
      _task(active: 'other-task'),
    ]);
    final rows = await repo.loadJournal();
    expect(rows, hasLength(5));
    expect(rows.map((a) => a.id), contains(task.id));
    expect(rows.singleWhere((a) => a.id == task.id).source,
        AssignmentSource.classroomActivity);
    expect(rows.singleWhere((a) => a.id == formal.id).source,
        AssignmentSource.courseWork);
    expect(repo.identityConflictCount, 0);
    // A later signed-work response must not absorb a known 35/42 task either.
    await repo.mergeAndSave([
      formal.copyWith(lastSyncedAt: DateTime.utc(2026, 11, 16)),
    ]);
    expect(await repo.loadJournal(), hasLength(5));
  });

  for (final hasExactId in [false, true]) {
    test(
        'ambiguous aliases preserve every ID and association exact=$hasExactId',
        () async {
      final repo = LocalAssignmentRepository();
      await repo.activateAccount(_account);
      final first = _task(id: 'cx:activity:old-a', type: null);
      final second =
          _task(id: hasExactId ? _task().id : 'cx:activity:old-b', type: null);
      final ids = [first.id, second.id];
      await _seedJournal([first, second], hidden: {first.id});
      final personal = _personal(ids);
      await repo.savePersonalWorkspace(personal, _account);
      final current = _task(observedAt: DateTime.utc(2026, 11, 16))
          .copyWith(title: '服务端最新标题');
      await repo.mergeAndSave([current]);
      expect(repo.identityConflictCount, 1);
      expect((await repo.loadHiddenAssignments()).single.id, first.id);
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString(_journalKey)!)['records'] as List;
      expect(stored.map((r) => r['id']), unorderedEquals({...ids, current.id}));
      expect(
          stored.singleWhere((r) => r['id'] == first.id)['title'], first.title);
      expect(stored.singleWhere((r) => r['id'] == current.id)['title'],
          current.title);
      expect((await repo.loadPersonalWorkspace()).encode(), personal.encode());
      await repo.mergeAndSave([current]);
      expect(repo.identityConflictCount, 1);
      final retried =
          jsonDecode(prefs.getString(_journalKey)!)['records'] as List;
      expect(retried, hasLength(hasExactId ? 2 : 3));
    });
  }

  test('untyped activity cannot downgrade a known classroom task', () async {
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([_task(type: 42, status: 'submitted')]);
    await repo.mergeAndSave([
      _task(
          type: null,
          status: 'unknown',
          observedAt: DateTime.utc(2026, 11, 16)),
    ]);
    final stored = (await repo.loadJournal()).single;
    expect(stored.activityType, 42);
    expect(stored.status, 'submitted');
  });

  for (final source in [
    AssignmentSource.classroomActivity,
    AssignmentSource.legacyUnknown,
  ]) {
    test('untyped $source response cannot duplicate a retained opaque task',
        () async {
      const legacyId = 'cx:activity:opaque';
      final repo = LocalAssignmentRepository();
      await repo.activateAccount(_account);
      await repo.mergeAndSave([
        _task(id: legacyId, type: 42, status: 'submitted'),
      ]);
      await repo.updateCompletion(legacyId, true);
      final personal = _personal([legacyId]);
      await repo.savePersonalWorkspace(personal, _account);
      await repo.mergeAndSave([
        _task(
                type: null,
                status: 'unknown',
                observedAt: DateTime.utc(2026, 11, 16))
            .copyWith(source: source),
      ]);
      expect(await repo.loadJournal(), isEmpty);
      final stored = (await repo.loadHiddenAssignments()).single;
      expect(stored.id, legacyId);
      expect(stored.activityType, 42);
      expect(stored.status, 'submitted');
      expect((await repo.loadPersonalWorkspace()).encode(), personal.encode());
      expect(repo.identityConflictCount, 0);
    });
  }

  for (final incomingUrl in [
    null,
    'https://mooc1.chaoxing.com/work'
        '?courseId=course&classId=class&workId=other&activeId=task',
    'https://mobilelearn.chaoxing.com/page/renwu/task'
        '?courseId=other-course&classId=class&activeId=other-task',
  ]) {
    test(
        'opaque activity keeps verified identity with replacement URL $incomingUrl',
        () async {
      final old = _task(id: 'cx:activity:opaque', type: null);
      await _seedJournal([old], legacyFields: true);
      final repo = LocalAssignmentRepository();
      final incoming = _task(observedAt: DateTime.utc(2026, 11, 16)).copyWith(
          submitUrl: incomingUrl, clearSubmitUrl: incomingUrl == null);
      await repo.mergeAndSave([incoming]);
      final stored = (await repo.loadJournal()).single;
      expect(stored.id, old.id);
      expect(stored.courseTaskKey, incoming.courseTaskKey);
      expect(stored.isSupportedClassroomTask, isTrue);
      expect(stored.submitUrl, old.submitUrl);
    });
  }

  for (final status in ['pending', 'unknown']) {
    test('formal completed protection still applies to $status', () async {
      final repo = LocalAssignmentRepository();
      final formal = Assignment(
        id: 'cx:work:course:class:work',
        courseName: '合成课程',
        title: '正式作业',
        deadlineAt: DateTime.utc(2026, 12),
        requirementsText: '',
        status: 'submitted',
        completedAt: DateTime.utc(2026, 11, 14),
        lastSyncedAt: DateTime.utc(2026, 11, 15),
      );
      await repo.mergeAndSave([formal]);
      await repo.mergeAndSave([
        formal.copyWith(
            status: status,
            clearCompletedAt: true,
            lastSyncedAt: DateTime.utc(2026, 11, 16)),
      ]);
      final stored = (await repo.loadJournal()).single;
      expect(stored.status, 'submitted');
      expect(stored.completedAt?.toUtc(), formal.completedAt?.toUtc());
    });
  }

  test('backup 4 preserves type availability and personal IDs through restore',
      () async {
    final repo = LocalAssignmentRepository();
    await repo.activateAccount(_account);
    final rows = [
      _task(type: 35, status: 'submitted').copyWith(
          completedAt: DateTime.utc(2026, 11, 14),
          lastSyncedAt: DateTime.utc(2099)),
      _task(
          type: 42,
          active: 'quiz',
          availability: AssignmentAvailability.unknown),
      _task(
          type: 35,
          active: 'deleted',
          availability: AssignmentAvailability.unavailable),
    ];
    await repo.mergeAndSave(rows);
    await repo.updateCompletion(rows.first.id, true);
    final personal = _personal(rows.map((a) => a.id));
    await repo.savePersonalWorkspace(personal, _account);
    final snapshot = await repo.createBackupSnapshot(_account);
    final encoded = snapshot.encode();
    expect(jsonDecode(encoded)['schema'], 4);
    expect(encoded, isNot(contains('synthetic-link-secret')));
    expect(encoded, isNot(contains('synthetic-body-secret')));
    expect(encoded, isNot(contains('submitUrl')));
    expect(encoded, isNot(contains('content://')));
    final decoded = BackupSnapshot.decode(encoded);
    expect(decoded.records.map((a) => a.activityType), [35, 42, 35]);
    expect(decoded.records.map((a) => a.availability), [
      AssignmentAvailability.available,
      AssignmentAvailability.unknown,
      AssignmentAvailability.unavailable,
    ]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_journalKey);
    await prefs.remove('personal_workspace_v1');
    await repo.restoreBackupSnapshot(decoded, _account);
    final restored = [
      ...await repo.loadJournal(),
      ...await repo.loadHiddenAssignments(),
    ];
    expect(restored, hasLength(3));
    for (final record in restored) {
      final original = rows.singleWhere((a) => a.id == record.id);
      expect(record.activityType, original.activityType);
      expect(record.availability, original.availability);
      expect(record.deadlineAt?.toUtc(), original.deadlineAt?.toUtc());
      expect(record.deadlineTrusted, isFalse);
      expect(record.status, 'unknown');
      expect(record.completedAt, isNull);
      expect(record.submitUrl, isNull);
      expect(record.requirementsText, isEmpty);
      expect(record.lastSyncedAt.millisecondsSinceEpoch, 0);
    }
    final importedPersonal = await repo.loadPersonalWorkspace();
    expect(importedPersonal.work.keys, unorderedEquals(personal.work.keys));
    expect(importedPersonal.work[rows.first.id]!.note,
        personal.work[rows.first.id]!.note);
    expect(importedPersonal.work.values.every((w) => w.files.isEmpty), isTrue);
    expect(importedPersonal.plans.map((p) => p.assignmentId),
        unorderedEquals(rows.map((a) => a.id)));
    await repo.mergeAndSave([_task(status: 'pending')]);
    final confirmed = (await repo.loadHiddenAssignments()).single;
    expect(confirmed.id, rows.first.id);
    expect(confirmed.status, 'pending');
    expect(confirmed.deadlineTrusted, isTrue);
  });

  for (final version in [1, 2, 3]) {
    test('backup $version restores old activity then upgrades in place',
        () async {
      final original = _task(type: 42, status: 'submitted');
      final raw =
          jsonDecode(_backup([original]).encode()) as Map<String, dynamic>;
      raw['schema'] = version;
      if (version < 3) raw.remove('notebook');
      if (version < 2) raw.remove('personal');
      final record = (raw['records'] as List).single as Map;
      record.remove('activityType');
      record.remove('availability');
      record.remove('courseTaskKey');
      // Historical backups can contain server descriptions with access data.
      record['requirementsText'] = original.requirementsText;
      final decoded = BackupSnapshot.decode(jsonEncode(raw));
      expect(decoded.records.single.activityType, isNull);
      expect(decoded.records.single.availability,
          AssignmentAvailability.available);
      final repo = LocalAssignmentRepository();
      await repo.activateAccount(_account);
      await repo.restoreBackupSnapshot(decoded, _account);
      final restored = (await repo.loadJournal()).single;
      expect(restored.id, original.id);
      expect(restored.status, 'unknown');
      expect(restored.deadlineTrusted, isFalse);
      expect(restored.submitUrl, isNull);
      expect(restored.requirementsText, isEmpty);
      await repo.mergeAndSave([_task(type: 42)]);
      final confirmed = (await repo.loadJournal()).single;
      expect(confirmed.id, original.id);
      expect(confirmed.activityType, 42);
      expect(confirmed.status, 'pending');
      expect(
          jsonDecode(
              (await repo.createBackupSnapshot(_account)).encode())['schema'],
          4);
    });
  }

  for (final type in [35, 42, 77]) {
    test('backup 4 retains opaque type $type identity without signed access',
        () async {
      final repo = LocalAssignmentRepository();
      await repo.activateAccount(_account);
      final original = _task(id: 'cx:activity:opaque', type: type);
      await _seedJournal([original], version: 2);
      await repo.savePersonalWorkspace(_personal([original.id]), _account);
      final snapshot = await repo.createBackupSnapshot(_account);
      final encoded = snapshot.encode();
      expect(encoded, isNot(contains('synthetic-link-secret')));
      expect(encoded, isNot(contains('synthetic-body-secret')));
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_journalKey);
      await prefs.remove('personal_workspace_v1');
      await repo.restoreBackupSnapshot(
          BackupSnapshot.decode(encoded), _account);
      final restored = (await repo.loadJournal()).single;
      expect(restored.id, original.id);
      expect(restored.activityType, type);
      expect(restored.status, 'unknown');
      expect(restored.deadlineTrusted, isFalse);
      expect(restored.submitUrl, isNull);
      expect(snapshot.courseTaskKeys[original.id], original.courseTaskKey);
      await repo.mergeAndSave([_task(type: type)]);
      final confirmed = (await repo.loadJournal()).single;
      expect(confirmed.id, original.id);
      expect(confirmed.submitUrl, original.submitUrl);
      expect(confirmed.status, 'pending');
      expect((await repo.loadPersonalWorkspace()).plans.single.assignmentId,
          original.id);
    });
  }

  test('backup activity identity rejects a conflicting source', () {
    final raw = jsonDecode(_backup([_task(id: 'cx:activity:opaque')]).encode())
        as Map<String, dynamic>;
    final record = (raw['records'] as List).single as Map;
    for (final invalid in ['courseWork', 'manual', 'exam', 'legacyUnknown']) {
      record['source'] = invalid;
      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    }
  });

  test('backup activity identity rejects malformed and conflicting keys', () {
    final raw = jsonDecode(_backup([_task()]).encode()) as Map<String, dynamic>;
    final record = (raw['records'] as List).single as Map;
    for (final invalid in [
      35,
      'cx:work:course:class:task',
      'cx:activity:course::task',
      'cx:activity:course:class:task:extra',
      'cx:activity:other-course:class:task',
    ]) {
      record['courseTaskKey'] = invalid;
      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    }
  });

  test('backup 4 rejects invalid new fields and future schemas', () {
    final raw = jsonDecode(_backup([_task()]).encode()) as Map<String, dynamic>;
    final record = (raw['records'] as List).single as Map;
    for (final invalid in ['35', 35.0, true]) {
      record['activityType'] = invalid;
      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    }
    record['activityType'] = 35;
    for (final invalid in [null, 'deleted', 0]) {
      record['availability'] = invalid;
      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    }
    record['availability'] = 'available';
    for (final version in [5, 99]) {
      raw['schema'] = version;
      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    }
  });
}
