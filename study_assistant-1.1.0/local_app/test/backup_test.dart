import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Failure injection into the persistence boundary used by SharedPreferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/local_coursework_state.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/pinned_assignments.dart';
import 'package:study_assistant_mobile/src/models/reminder_rule_limits.dart';

Assignment record(String id, String title) => Assignment(
      id: id,
      courseName: '课程',
      title: title,
      deadlineAt: DateTime.utc(2026, 12),
      requirementsText: '要求',
      status: 'submitted',
      lastSyncedAt: DateTime.utc(2026, 11, 1),
      submitUrl: 'https://work.chaoxing.com/work?enc=secret',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalAssignmentRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'password': 'password-secret', 'cookie': 'cookie-secret'});
    repo = LocalAssignmentRepository();
    await repo.activateAccount('alice');
    await repo.mergeAndSave([record('cx:work:1:2:3', '旧标题')]);
  });

  test('backup whitelist excludes credentials and signed links', () async {
    final snapshot = await repo.createBackupSnapshot('alice');
    expect(snapshot.records, hasLength(1));
    expect(snapshot.encode(), isNot(contains('enc=secret')));
    expect(snapshot.encode(), isNot(contains('password-secret')));
    expect(snapshot.encode(), isNot(contains('cookie-secret')));
    expect(snapshot.encode(), isNot(contains('submitUrl')));
    expect(BackupSnapshot.decode(snapshot.encode()).owner,
        BackupSnapshot.ownerFor('alice'));
  });

  group('local file attachments and portable backups', () {
    const workId = 'cx:work:1:2:3';
    const file = PersonalLink('本机附件', 'content://documents/backup-fixture');
    const note = '要随备份保留的笔记';

    setUp(() async {
      await repo.savePersonalWorkspace(
        PersonalWorkspace(work: {
          workId: const PersonalWork(note: note, files: [file]),
        }),
        'alice',
      );
    });

    test('local reads retain file references and official exports omit them',
        () async {
      final local = await repo.loadPersonalWorkspace();
      expect(local.work[workId]!.files.single.toJson(), file.toJson());

      final exported = (await repo.createBackupSnapshot('alice')).encode();
      final portable = BackupSnapshot.decode(exported).personal.work[workId]!;
      expect(portable.note, note);
      expect(portable.files, isEmpty);
      expect(exported, isNot(contains(file.url)));
    });

    test('portable decoder rejects structurally valid nested file references',
        () async {
      final local = await repo.loadPersonalWorkspace();
      final raw =
          jsonDecode((await repo.createBackupSnapshot('alice')).encode())
              as Map<String, dynamic>;
      raw['personal'] = local.toJson();
      expect(
        PersonalWorkspace.fromJson(raw['personal'])
            .work[workId]!
            .files
            .single
            .toJson(),
        file.toJson(),
      );

      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    });

    test('portable decoder still rejects top-level personal.files', () async {
      final raw =
          jsonDecode((await repo.createBackupSnapshot('alice')).encode())
              as Map<String, dynamic>;
      final personal = raw['personal'] as Map<String, dynamic>;
      personal['files'] = [file.toJson()];

      expect(
          () => BackupSnapshot.decode(jsonEncode(raw)), throwsFormatException);
    });
  });

  test('restore only fills gaps and resets imported confirmation', () async {
    final backup = await repo.createBackupSnapshot('alice');
    await repo.mergeAndSave([
      record('cx:work:1:2:3', '当前标题')
          .copyWith(lastSyncedAt: DateTime.utc(2026, 11, 2))
    ]);
    await repo.restoreBackupSnapshot(backup, 'alice');
    expect((await repo.loadJournal()).single.title, '当前标题');
    await repo.activateAccount('bob');
    await repo.activateAccount('alice');
    final p = await SharedPreferences.getInstance();
    await p.remove('chaoxing_journal_v2');
    await repo.restoreBackupSnapshot(backup, 'alice');
    final restored = (await repo.loadJournal()).single;
    expect(restored.submitUrl, isNull);
    expect(restored.status, 'unknown');
    expect(restored.deadlineTrusted, isFalse);
    expect(restored.lastSyncedAt.millisecondsSinceEpoch, 0);
  });
  test('signed links embedded in source descriptions are excluded too',
      () async {
    await repo.mergeAndSave([
      record('cx:work:1:2:4', '正文链接').copyWith(
          requirementsText:
              '查看 https://mooc1.chaoxing.com/work/task?enc=body-secret')
    ]);
    final snapshot = await repo.createBackupSnapshot('alice');
    expect(snapshot.encode(), isNot(contains('body-secret')));
  });
  test('future backup clock cannot block the next genuine server observation',
      () async {
    final raw = jsonDecode((await repo.createBackupSnapshot('alice')).encode())
        as Map<String, dynamic>;
    (raw['records'] as List).single['lastSyncedAt'] =
        '2099-01-01T00:00:00.000Z';
    final snapshot = BackupSnapshot.decode(jsonEncode(raw));
    final p = await SharedPreferences.getInstance();
    await p.remove('chaoxing_journal_v2');
    await repo.restoreBackupSnapshot(snapshot, 'alice');
    await repo.mergeAndSave([
      record('cx:work:1:2:3', '服务端').copyWith(
          lastSyncedAt: DateTime.utc(2026, 11, 6),
          status: 'pending',
          deadlineTrusted: true)
    ]);
    final item = (await repo.loadJournal()).single;
    expect(item.status, 'pending');
    expect(item.deadlineTrusted, isTrue);
  });

  test('cross account restore is rejected without writes', () async {
    final backup = await repo.createBackupSnapshot('alice');
    await repo.activateAccount('bob');
    await expectLater(
        repo.restoreBackupSnapshot(backup, 'bob'), throwsStateError);
    expect(await repo.loadJournal(), isEmpty);
  });

  test('unknown schema malformed fields and excessive plaintext are rejected',
      () async {
    final data = jsonDecode((await repo.createBackupSnapshot('alice')).encode())
        as Map<String, dynamic>;
    expect(() => BackupSnapshot.decode(jsonEncode({...data, 'schema': 99})),
        throwsFormatException);
    expect(() => BackupSnapshot.decode(jsonEncode({...data, 'schema': 1.0})),
        throwsFormatException);
    expect(
        () => BackupSnapshot.decode(
            jsonEncode({...data, 'createdAt': '2026-02-30T00:00:00.000Z'})),
        throwsFormatException);
    final records = data['records'] as List;
    (records.single as Map)['lastSyncedAt'] = 'not-a-date';
    expect(
        () => BackupSnapshot.decode(jsonEncode(data)), throwsFormatException);
    expect(
        () =>
            BackupSnapshot.decode(' ' * (BackupSnapshot.maxPlaintextBytes + 1)),
        throwsFormatException);
  });

  test('legacy reminder rules survive encrypted-backup export and restore',
      () async {
    final legacyRules = [
      for (var value = 1; value <= 32; value++) value,
      400 * 24 * 60,
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'reminder_offsets_minutes',
      legacyRules.map((value) => '$value').toList(),
    );

    final snapshot = await repo.createBackupSnapshot('alice');

    expect(snapshot.reminderOffsets, unorderedEquals(legacyRules));
    await prefs.remove('reminder_offsets_minutes');
    await repo.restoreBackupSnapshot(snapshot, 'alice');
    final restored = prefs
        .getStringList('reminder_offsets_minutes')!
        .map(int.parse)
        .toList();
    expect(restored, unorderedEquals(legacyRules));
  });

  test('backup legacy reminder rules have bounded compatibility limits',
      () async {
    final data = jsonDecode((await repo.createBackupSnapshot('alice')).encode())
        as Map<String, dynamic>;
    data['reminderOffsets'] = List.generate(32, (index) => index + 1);
    expect(
        BackupSnapshot.decode(jsonEncode(data)).reminderOffsets, hasLength(32));

    data['reminderOffsets'] = List.generate(33, (index) => index + 1);
    expect(
        BackupSnapshot.decode(jsonEncode(data)).reminderOffsets, hasLength(33));
    data['reminderOffsets'] = List.generate(
        ReminderRuleLimits.maxLegacyRuleCount + 1, (index) => index + 1);
    expect(
      () => BackupSnapshot.decode(jsonEncode(data)),
      throwsFormatException,
    );
    data['reminderOffsets'] = [ReminderRuleLimits.maxLegacyOffsetMinutes + 1];
    expect(
      () => BackupSnapshot.decode(jsonEncode(data)),
      throwsFormatException,
    );
  });

  test('failed course write rolls journal and settings back, including disk',
      () async {
    final snapshot = await repo.createBackupSnapshot('alice');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chaoxing_journal_v2');
    await repo
        .loadJournal(); // establish an empty, valid journal before restore
    await prefs.setStringList('reminder_offsets_minutes', ['30']);
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    final failing = _FailOncePreferences(
        {for (final k in before.keys) 'flutter.$k': before[k]!});
    SharedPreferencesStorePlatform.instance = failing;
    await expectLater(
        repo.restoreBackupSnapshot(snapshot, 'alice'), throwsStateError);
    await prefs.reload();
    expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
    expect(await repo.loadJournal(), isEmpty);
  });

  test(
      'persisted interrupted checkpoint recovers before account becomes active',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final before = {
      for (final k in prefs.getKeys())
        if (k != 'password' && k != 'cookie' && k != 'journal_account_owner')
          k: prefs.get(k)
    };
    await prefs.setString(
        'journal_account_switch',
        jsonEncode(
            {'owner': BackupSnapshot.ownerFor('alice'), 'values': before}));
    await prefs.setString('course_refs', '[]');
    await prefs.setString(
        'chaoxing_journal_v2',
        jsonEncode({
          'schemaVersion': 1,
          'records': [],
          'hidden': [],
          'lastSync': null
        }));
    await LocalAssignmentRepository().activateAccount('alice');
    expect((await repo.loadJournal()).single.title, '旧标题');
    expect(prefs.containsKey('journal_account_switch'), isFalse);
  });

  group('Phase 2A BackupSnapshot schema 8 pinned state', () {
    test(
        'schema 8 exports ordered pins, decodes v1-7 cleanly, and merges on restore',
        () async {
      final v5 = await repo.createBackupSnapshot('alice');
      expect(jsonDecode(v5.encode())['schema'], 5);

      await repo.mergeAndSave([
        record('cx:work:1:2:4', '作业四')
            .copyWith(publishedAt: DateTime.utc(2026, 11, 1)),
        record('cx:work:1:2:5', '作业五'),
      ]);
      // v7 export when no pins exist stays schema 7.
      final v7 = await repo.createBackupSnapshot('alice');
      expect(jsonDecode(v7.encode())['schema'], 7);

      // Pin & reorder -> schema 8.
      await repo.savePinnedAssignments(
        PinnedAssignments(
          keys: ['cx:work:1:2:4', 'cx:work:1:2:3'],
          manuallyOrdered: true,
        ),
        'alice',
      );
      final v8 = await repo.createBackupSnapshot('alice');
      final rawV8 = jsonDecode(v8.encode()) as Map<String, dynamic>;
      expect(rawV8['schema'], 8);
      expect(rawV8['pinned'], {
        'keys': ['cx:work:1:2:4', 'cx:work:1:2:3'],
        'manuallyOrdered': true,
      });

      // Restoring schema 1-7 never overwrites existing local pins.
      await repo.restoreBackupSnapshot(v5, 'alice');
      await repo.restoreBackupSnapshot(v7, 'alice');
      expect(
        (await repo.loadPinnedAssignments('alice')).keys,
        ['cx:work:1:2:4', 'cx:work:1:2:3'],
      );

      // Merging schema 8 preserves local manual order and appends imported unique keys.
      await repo.savePinnedAssignments(
        PinnedAssignments(
          keys: ['cx:work:1:2:5'],
          manuallyOrdered: true,
        ),
        'alice',
      );
      await repo.restoreBackupSnapshot(v8, 'alice');
      final mergedLocalWins = await repo.loadPinnedAssignments('alice');
      expect(mergedLocalWins.manuallyOrdered, isTrue);
      expect(
        mergedLocalWins.keys,
        ['cx:work:1:2:5', 'cx:work:1:2:4', 'cx:work:1:2:3'],
      );

      // When local is not manually ordered, imported manual order leads.
      await repo.savePinnedAssignments(
        PinnedAssignments(
          keys: ['cx:work:1:2:5'],
          manuallyOrdered: false,
        ),
        'alice',
      );
      await repo.restoreBackupSnapshot(v8, 'alice');
      final mergedImportLeads = await repo.loadPinnedAssignments('alice');
      expect(mergedImportLeads.manuallyOrdered, isTrue);
      expect(
        mergedImportLeads.keys,
        ['cx:work:1:2:4', 'cx:work:1:2:3', 'cx:work:1:2:5'],
      );

      // Malformed / URL-carrying pinned field is rejected strictly.
      final badUrl = Map<String, dynamic>.from(rawV8)
        ..['pinned'] = {
          'keys': ['https://mooc1.chaoxing.com/work?enc=secret'],
          'manuallyOrdered': true,
        };
      expect(() => BackupSnapshot.decode(jsonEncode(badUrl)),
          throwsFormatException);
      final badDup = Map<String, dynamic>.from(rawV8)
        ..['pinned'] = {
          'keys': ['cx:work:1:2:3', 'cx:work:1:2:3'],
          'manuallyOrdered': true,
        };
      expect(() => BackupSnapshot.decode(jsonEncode(badDup)),
          throwsFormatException);
    });

    test(
        'Phase 2B schema 8 optional courseworkState backward compatible, merges cleanly, and rejects malformed entries',
        () async {
      // Old 2A schema 8 without courseworkState decodes cleanly as empty.
      await repo.savePinnedAssignments(
        PinnedAssignments(keys: ['cx:work:1:2:3'], manuallyOrdered: true),
        'alice',
      );
      final schema8WithoutCoursework = await repo.createBackupSnapshot('alice');
      final raw2A =
          jsonDecode(schema8WithoutCoursework.encode()) as Map<String, dynamic>;
      expect(raw2A['schema'], 8);
      expect(raw2A.containsKey('courseworkState'), isFalse);
      expect(BackupSnapshot.decode(jsonEncode(raw2A)).courseworkState.isEmpty,
          isTrue);

      // Export schema 8 with manualDeadlineAt, officialTakenOver & locallyCompleted.
      final manualAt = DateTime.utc(2026, 12, 5, 15, 59);
      final localState = LocalCourseworkState()
          .withManualDeadline('cx:work:1:2:9', const [], manualAt)
          .withLocallyCompleted('cx:work:1:2:11', const [], true)
          .withEntry(
            'cx:work:1:2:10',
            const [],
            LocalCourseworkEntry(
              manualDeadlineAt: DateTime.utc(2026, 12, 6, 12),
              officialTakenOver: true,
              locallyCompleted: true,
            ),
          );
      await repo.saveCourseworkState(localState, 'alice');
      final withCoursework = await repo.createBackupSnapshot('alice');
      final raw2B = jsonDecode(withCoursework.encode()) as Map<String, dynamic>;
      expect(raw2B['schema'], 8);
      expect(raw2B.containsKey('courseworkState'), isTrue);

      // Restore keeps local existing entries and fills missing ones without promoting trust.
      final overrideAt = DateTime.utc(2026, 12, 7, 10);
      await repo.saveCourseworkState(
        LocalCourseworkState()
            .withManualDeadline('cx:work:1:2:9', const [], overrideAt),
        'alice',
      );
      await repo.restoreBackupSnapshot(withCoursework, 'alice');
      final restored = await repo.loadCourseworkState('alice');
      expect(
        restored
            .entryForAliases(const ['cx:work:1:2:9'])!
            .manualDeadlineAt!
            .toUtc(),
        overrideAt,
      );
      expect(
        restored.entryForAliases(const ['cx:work:1:2:10'])!.officialTakenOver,
        isTrue,
      );
      expect(
        restored.entryForAliases(const ['cx:work:1:2:10'])!.locallyCompleted,
        isTrue,
      );
      expect(
        restored.entryForAliases(const ['cx:work:1:2:11'])!.locallyCompleted,
        isTrue,
      );

      // Malformed / URL / bad-timezone entries rejected strictly.
      final badUrl = Map<String, dynamic>.from(raw2B)
        ..['courseworkState'] = {
          'entries': {
            'https://mooc1.chaoxing.com/work?enc=secret': {
              'manualDeadlineAt': manualAt.toIso8601String(),
              'officialTakenOver': false,
            },
          },
        };
      expect(() => BackupSnapshot.decode(jsonEncode(badUrl)),
          throwsFormatException);

      final badExtra = Map<String, dynamic>.from(raw2B)
        ..['courseworkState'] = {
          'entries': {
            'cx:work:1:2:9': {
              'manualDeadlineAt': manualAt.toIso8601String(),
              'officialTakenOver': false,
              'extra': 1,
            },
          },
        };
      expect(() => BackupSnapshot.decode(jsonEncode(badExtra)),
          throwsFormatException);
    });

    test(
        'schema 9 roundtrips course metadata, preserves existing local metadata on old backups, and rejects invalid course metadata',
        () async {
      await repo.activateAccount('alice');
      const richCourse = CourseRef(
        courseId: '101',
        clazzId: '201',
        name: '编译原理',
        teacherNames: ['陈教授', '助教甲'],
        folderName: '2026年秋季学期',
      );
      const plainCourse = CourseRef(
        courseId: '102',
        clazzId: '202',
        name: '操作系统',
      );
      await repo.saveCourses([richCourse, plainCourse], account: 'alice');
      final v9 = await repo.createBackupSnapshot('alice');
      final rawV9 = jsonDecode(v9.encode()) as Map<String, dynamic>;
      expect(rawV9['schema'], 9);
      final decodedV9 = BackupSnapshot.decode(v9.encode());
      expect(decodedV9.courses.first.teacherNames, ['陈教授', '助教甲']);
      expect(decodedV9.courses.first.folderName, '2026年秋季学期');

      // Restoring an older backup without metadata must not wipe verified local metadata.
      final legacyV8 = BackupSnapshot.create(
        owner: BackupSnapshot.ownerFor('alice'),
        createdAt: DateTime.utc(2026, 11, 20),
        records: const [],
        hidden: const {},
        courses: const [
          CourseRef(courseId: '101', clazzId: '201', name: '编译原理'),
        ],
        unfollowed: const {},
        reminderOffsets: const [120],
        autoSyncIntervalMinutes: 60,
        pinned: PinnedAssignments(keys: ['cx:work:1:2:9']),
      );
      expect((jsonDecode(legacyV8.encode()) as Map)['schema'], 8);
      await repo.restoreBackupSnapshot(legacyV8, 'alice');
      final preserved = await repo.loadCourses(account: 'alice');
      expect(preserved.first.teacherNames, ['陈教授', '助教甲']);
      expect(preserved.first.folderName, '2026年秋季学期');

      // Missing course metadata in local storage is backfilled from schema 9 restore.
      await repo.saveCourses(const [
        CourseRef(courseId: '101', clazzId: '201', name: '编译原理'),
      ], account: 'alice');
      await repo.restoreBackupSnapshot(v9, 'alice');
      final filled = await repo.loadCourses(account: 'alice');
      expect(filled.first.teacherNames, ['陈教授', '助教甲']);
      expect(filled.first.folderName, '2026年秋季学期');

      // Strict validation rejects bad schema 9 course payloads and pre-v9 metadata.
      final badTeachersEmpty = jsonDecode(v9.encode()) as Map<String, dynamic>;
      (badTeachersEmpty['courses'] as List).first['teacherNames'] = <String>[];
      expect(() => BackupSnapshot.decode(jsonEncode(badTeachersEmpty)),
          throwsFormatException);

      final badExtraKey = jsonDecode(v9.encode()) as Map<String, dynamic>;
      (badExtraKey['courses'] as List).first['unknownField'] = 'x';
      expect(() => BackupSnapshot.decode(jsonEncode(badExtraKey)),
          throwsFormatException);
    });
  });
}

class _FailOncePreferences extends InMemorySharedPreferencesStore {
  _FailOncePreferences(super.data) : super.withData();
  bool _failed = false;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (!_failed && key == 'flutter.course_refs') {
      _failed = true;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
