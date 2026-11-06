import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Failure injection into the persistence boundary used by SharedPreferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';

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
