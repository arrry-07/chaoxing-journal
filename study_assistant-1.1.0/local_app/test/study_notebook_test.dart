import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'review_core_remediation_test.dart' as f;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'manual entries persist separately, isolate accounts and backup roundtrip',
      () async {
    final r = LocalAssignmentRepository();
    await r.activateAccount('A');
    final n = StudyNotebook(entries: [
      ManualEntry(
          id: 'm1',
          title: '复习',
          kind: 'exam',
          at: DateTime.utc(2030),
          remind: true)
    ]);
    await r.saveNotebook(n, 'A');
    final b =
        BackupSnapshot.decode((await r.createBackupSnapshot('A')).encode());
    expect(b.notebook.entries.single.kind, 'exam');
    await r.activateAccount('B');
    expect((await r.loadNotebook()).entries, isEmpty);
    await expectLater(r.saveNotebook(n, 'A'), throwsStateError);
    await r.activateAccount('A');
    expect((await r.loadNotebook()).entries.single.at, DateTime.utc(2030));
  });
  test('snapshot excludes source access links and file associations', () {
    final archive = TermArchive.capture(
        id: 't1',
        label: '测试学期',
        rows: [f.sample('one')],
        personal: PersonalWorkspace(work: {
          'cx:work:1:2:one': const PersonalWork(
              note: '笔记',
              files: [PersonalLink('file', 'content://documents/1')])
        }),
        entries: []);
    final raw = StudyNotebook(terms: [archive]).encode();
    expect(raw, isNot(contains('content://')));
    expect(raw, isNot(contains('submitUrl')));
    expect(StudyNotebook.decode(raw).terms.single.rows.single.note.note, '笔记');
  });
  test('invalid exam without date, duplicate IDs and unsafe dates rejected',
      () {
    expect(
        () => StudyNotebook.decode(StudyNotebook(entries: [
              const ManualEntry(id: 'm', title: '考试', kind: 'exam')
            ]).encode()),
        throwsFormatException);
    const e = ManualEntry(id: 'm', title: '事', kind: 'todo');
    expect(() => StudyNotebook.decode(StudyNotebook(entries: [e, e]).encode()),
        throwsFormatException);
    expect(
        () =>
            ManualEntry.fromJson({...e.toJson(), 'at': '2030-01-01T12:00:00'}),
        throwsFormatException);
  });
  test('stale notebook editor rejected and source homework remains unchanged',
      () async {
    final s = f.makeStore(f.Session());
    await s.restoreSession();
    await s.repository.mergeAndSave([f.sample('one')]);
    await s.refreshAssignments();
    final epoch = s.accountEpoch;
    expect(
        await s.saveNotebook(
            (_) => StudyNotebook(entries: [
                  const ManualEntry(
                      id: 'm', title: 'done', kind: 'todo', done: true)
                ]),
            epoch),
        isTrue);
    expect(s.assignments.single.status, 'pending');
    await s.logout();
    expect(await s.saveNotebook((n) => n, epoch), isFalse);
    s.dispose();
  });
  test(
      'schema2 backup remains readable and notebook restore only fills missing IDs',
      () async {
    final r = LocalAssignmentRepository();
    await r.activateAccount('A');
    await r.saveNotebook(
        StudyNotebook(
            entries: [const ManualEntry(id: 'm', title: 'old', kind: 'todo')]),
        'A');
    final snapshot = await r.createBackupSnapshot('A');
    final old = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    old.remove('notebook');
    old['schema'] = 2;
    expect(BackupSnapshot.decode(jsonEncode(old)).notebook.entries, isEmpty);
    await r.saveNotebook(
        StudyNotebook(
            entries: [const ManualEntry(id: 'm', title: 'new', kind: 'todo')]),
        'A');
    await r.restoreBackupSnapshot(snapshot, 'A');
    expect((await r.loadNotebook()).entries.single.title, 'new');
  });
}
