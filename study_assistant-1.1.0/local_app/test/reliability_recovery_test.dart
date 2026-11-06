import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment item() => Assignment(
    id: 'work-1',
    courseName: '数学',
    title: '作业',
    deadlineAt: DateTime.now().add(const Duration(days: 2)),
    requirementsText: '',
    status: 'pending',
    lastSyncedAt: DateTime.now());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a second damaged journal is backed up before replacement', () async {
    SharedPreferences.setMockInitialValues({'chaoxing_journal_v2': '{first'});
    final repo = LocalAssignmentRepository();
    await repo.loadJournal();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chaoxing_journal_v2', '{second');
    await repo.mergeAndSave([item()]);
    expect(prefs.getString('chaoxing_journal_v2_recovery_backup'), '{first');
    expect(prefs.getStringList('chaoxing_journal_v2_recovery_backups'),
        contains('{second'));
  });
  test('broken journal is backed up and subsequent sync can recover', () async {
    SharedPreferences.setMockInitialValues({'chaoxing_journal_v2': '{broken'});
    final repo = LocalAssignmentRepository();
    expect(await repo.loadJournal(), isEmpty);
    expect(repo.recoveryWarning, isNotNull);
    await repo.mergeAndSave([item()]);
    expect((await repo.loadJournal()).single.id, 'work-1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chaoxing_journal_v2_recovery_backup'), '{broken');
  });
  test('one invalid record does not discard valid journal records', () async {
    SharedPreferences.setMockInitialValues({
      'chaoxing_journal_v2': jsonEncode({
        'records': [
          item().toJson(),
          {'id': 'broken'}
        ],
        'hidden': []
      })
    });
    final repo = LocalAssignmentRepository();
    expect((await repo.loadJournal()).single.id, 'work-1');
    expect(repo.recoveryWarning, isNotNull);
  });
  test('future schema is preserved and writes are refused', () async {
    final raw = jsonEncode({'schemaVersion': 99, 'records': [], 'hidden': []});
    SharedPreferences.setMockInitialValues({'chaoxing_journal_v2': raw});
    final repo = LocalAssignmentRepository();
    await expectLater(repo.mergeAndSave([item()]), throwsStateError);
    expect(
        (await SharedPreferences.getInstance())
            .getString('chaoxing_journal_v2'),
        raw);
  });
  test('hidden assignment can be recovered without losing server status',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([item()]);
    await repo.updateCompletion('work-1', true);
    expect(await repo.loadJournal(), isEmpty);
    expect((await repo.loadHiddenAssignments()).single.status, 'pending');
    await repo.updateCompletion('work-1', false);
    expect((await repo.loadJournal()).single.id, 'work-1');
    expect(await repo.loadHiddenAssignments(), isEmpty);
  });
  test('widget failure leaves restored assignments available with warning',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([item()]);
    final store = AssignmentStore(
        sessionStore: _Session(),
        repository: repo,
        notificationService: _Notifications(),
        widgetSnapshotService: _BrokenWidget());
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.assignments.single.id, 'work-1');
    expect(store.error, contains('小组件更新失败'));
  });
  test('secure storage failure is recoverable at startup', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
        sessionStore: _BrokenSession(),
        notificationService: _Notifications(),
        widgetSnapshotService: _BrokenWidget());
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.isAuthenticated, isFalse);
    expect(store.error, contains('本机数据恢复未完成'));
  });
}

class _Session extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => null;
  @override
  Future<String?> readChaoxingDisplayName() async => null;
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _BrokenSession extends _Session {
  @override
  Future<String?> readChaoxingAccount() async =>
      throw PlatformException(code: 'locked');
}

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(List<Assignment> assignments,
      {List<int>? offsetsMinutes}) async {}
}

class _BrokenWidget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async =>
      throw StateError('plugin failed');
}
