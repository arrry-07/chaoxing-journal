import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'review_core_remediation_test.dart' as f;
import 'package:study_assistant_mobile/src/models/assignment.dart';

class FailingSummaryNotifications extends f.Notifications {
  bool fail = false;
  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {
    if (fail) throw StateError('summary cancellation failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('failed summary cancellation warns on disable and logout', () async {
    final notifications = FailingSummaryNotifications();
    final store = f.makeStore(f.Session(), notifications: notifications);
    addTearDown(store.dispose);
    await store.restoreSession();
    notifications.fail = true;
    expect(
        await store.savePersonal(
            (w) => w.withSummary(false, 20, 0), store.accountEpoch),
        isTrue);
    expect(store.error, contains('摘要'));
    await store.logout();
    expect(store.isAuthenticated, isFalse);
    expect(store.error, contains('账号已退出'));
    expect(store.error, contains('系统'));
  });
  test('failed old summary cleanup prevents cross-account activation',
      () async {
    final notifications = FailingSummaryNotifications();
    final session = f.Session();
    final store = f.makeStore(session, notifications: notifications);
    addTearDown(store.dispose);
    await store.restoreSession();
    notifications.fail = true;
    await store.loginChaoxing(
        account: 'B', password: 'dummy', agreementAccepted: true);
    expect(store.account, 'A');
    expect(session.account, 'A');
    expect(store.error, contains('摘要'));
  });
  test(
      'account scope persists personal progress independently and rejects wrong owner',
      () async {
    final r = LocalAssignmentRepository();
    await r.activateAccount('A');
    final w = PersonalWorkspace(work: {
      'id': const PersonalWork(
          note: '备注', steps: [PersonalStep('检查报告', done: true)])
    }, plans: [
      const DailyPlanItem('id', '2026-11-06', 90, done: true)
    ]);
    await r.savePersonalWorkspace(w, 'A');
    await r.activateAccount('B');
    expect((await r.loadPersonalWorkspace()).plans, isEmpty);
    await expectLater(r.savePersonalWorkspace(w, 'A'), throwsStateError);
    await r.activateAccount('A');
    expect((await r.loadPersonalWorkspace()).work['id']!.steps.single.done,
        isTrue);
  });
  test('strict limits links and duplicate or impossible dates are rejected',
      () {
    final j = PersonalWorkspace().toJson();
    for (final day in ['2026-02-30', '2026-11-06']) {
      final p = {'id': 'id', 'day': day, 'minutes': 30, 'done': false};
      expect(
          () => PersonalWorkspace.decode(jsonEncode({
                ...j,
                'plans': [p, p]
              })),
          throwsFormatException);
    }
    expect(PersonalWorkspace.validUrl('javascript:alert(1)'), isFalse);
    expect(PersonalWorkspace.validUrl('https://user@evil.example'), isFalse);
    expect(PersonalWorkspace.validFile('file:///secret'), isFalse);
  });
  test('portable data excludes device document grants while keeping user notes',
      () {
    final w = PersonalWorkspace(work: {
      'id': const PersonalWork(
          note: 'my note',
          files: [PersonalLink('report', 'content://documents/report')])
    });
    final restored = PersonalWorkspace.decode(w.encode(portable: true));
    expect(restored.work['id']!.files, isEmpty);
    expect(restored.work['id']!.note, 'my note');
  });
  test(
      'backup v1 stays readable, v2 preserves personal notes with missing-only restore',
      () async {
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    final workspace = PersonalWorkspace(work: {
      'id': const PersonalWork(
          note: '备份备注',
          files: [PersonalLink('file', 'content://documents/report')])
    }, plans: [
      const DailyPlanItem('id', '2026-11-06', 30)
    ]);
    await repo.savePersonalWorkspace(workspace, 'A');
    final backup = await repo.createBackupSnapshot('A');
    expect(backup.personal.work['id']!.note, '备份备注');
    expect(backup.personal.work['id']!.files, isEmpty);
    final old = jsonDecode(backup.encode()) as Map<String, dynamic>;
    old.remove('personal');
    old['schema'] = 1;
    expect(BackupSnapshot.decode(jsonEncode(old)).personal.work, isEmpty);
    await repo.savePersonalWorkspace(
        PersonalWorkspace(work: {'id': const PersonalWork(note: '本机较新')}), 'A');
    await repo.restoreBackupSnapshot(backup, 'A');
    final restored = await repo.loadPersonalWorkspace();
    expect(restored.work['id']!.note, '本机较新');
    expect(restored.plans.length, 1);
    expect(restored.summaryEnabled, isFalse);
  });
  test('stale personal editor cannot write after account epoch changes',
      () async {
    final store = f.makeStore(f.Session());
    await store.restoreSession();
    final epoch = store.accountEpoch;
    await store.logout();
    expect(
        await store.savePersonal(
            (w) => w.withWork('id', const PersonalWork(note: 'old')), epoch),
        isFalse);
    expect(store.personal.work, isEmpty);
    store.dispose();
  });
}
