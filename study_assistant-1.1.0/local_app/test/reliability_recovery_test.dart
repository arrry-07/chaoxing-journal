import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Failure injection into the persistence boundary used by SharedPreferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
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
  test('course cache reads and writes require the active account owner',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('account-A');
    await repo.saveCourses([
      const CourseRef(courseId: '1', clazzId: '2', name: 'A course'),
    ], account: 'account-A');
    await repo.activateAccount('account-B');
    await repo.saveCourses([
      const CourseRef(courseId: '3', clazzId: '4', name: 'B course'),
    ], account: 'account-B');
    await expectLater(repo.loadCourses(account: 'account-A'), throwsStateError);
    await expectLater(
      repo.saveCourses(
          const [CourseRef(courseId: '9', clazzId: '9', name: 'stale')],
          account: 'account-A'),
      throwsStateError,
    );
    expect(
        (await repo.loadCourses(account: 'account-B')).single.name, 'B course');
    await repo.activateAccount('account-A');
    expect(
        (await repo.loadCourses(account: 'account-A')).single.name, 'A course');
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
  test('damaged personal and notebook data are backed up before fallback',
      () async {
    SharedPreferences.setMockInitialValues(
        {'personal_workspace_v1': '{personal', 'notebook_v1': '{notebook'});
    final repo = LocalAssignmentRepository();

    expect((await repo.loadPersonalWorkspace()).work, isEmpty);
    expect((await repo.loadNotebook()).entries, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString('personal_workspace_v1_recovery_backup'), '{personal');
    expect(prefs.getString('notebook_v1_recovery_backup'), '{notebook');
    expect(repo.recoveryWarning, contains('部分个人计划与记录无法读取'));
    expect(repo.recoveryWarning, contains('部分个人待办与学期归档无法读取'));
  });
  test('failed recovery status is replaced after same source retry succeeds',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('student');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal');
    final failing = _installFailingStore(prefs, {
      'flutter.personal_workspace_v1_recovery_backup',
      'flutter.personal_workspace_v1_recovery_backups',
    });

    await expectLater(repo.loadPersonalWorkspace(), throwsA(isA<StateError>()));
    expect(repo.recoveryWarning, contains('恢复副本未保存'));

    failing.enabled = false;
    expect((await repo.loadPersonalWorkspace()).work, isEmpty);
    expect(repo.recoveryWarning, contains('部分个人计划与记录无法读取'));
    expect(repo.recoveryWarning, isNot(contains('恢复副本未保存')));
  });
  test('one source failure does not hide another source success', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('student');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal');
    await prefs.setString('notebook_v1', '{notebook');
    _installFailingStore(prefs, {
      'flutter.personal_workspace_v1_recovery_backup',
      'flutter.personal_workspace_v1_recovery_backups',
    });

    await expectLater(repo.loadPersonalWorkspace(), throwsA(isA<StateError>()));
    await repo.loadNotebook();

    expect(repo.recoveryWarning, contains('恢复副本未保存'));
    expect(repo.recoveryWarning, contains('部分个人待办与学期归档无法读取'));
    expect(repo.recoveryWarning, isNot(contains('部分个人计划与记录无法读取')));
  });
  test('failed personal backup blocks empty overwrite', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('student');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal');
    _installFailingStore(prefs, {
      'flutter.personal_workspace_v1_recovery_backup',
      'flutter.personal_workspace_v1_recovery_backups'
    });

    await expectLater(repo.loadPersonalWorkspace(), throwsA(isA<StateError>()));
    expect(repo.recoveryWarning, contains('恢复副本未保存'));
    expect(repo.recoveryWarning, contains('原始损坏数据仍保留'));
    expect(repo.recoveryWarning, isNot(contains('已保留备份')));
    await expectLater(
        repo.savePersonalWorkspace(PersonalWorkspace(), 'student'),
        throwsA(isA<StateError>()));

    await prefs.reload();
    expect(prefs.getString('personal_workspace_v1'), '{personal');
  });
  test('failed notebook backup blocks empty overwrite', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('student');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notebook_v1', '{notebook');
    _installFailingStore(prefs, {
      'flutter.notebook_v1_recovery_backup',
      'flutter.notebook_v1_recovery_backups'
    });

    await expectLater(repo.loadNotebook(), throwsA(isA<StateError>()));
    expect(repo.recoveryWarning, contains('恢复副本未保存'));
    expect(repo.recoveryWarning, contains('原始损坏数据仍保留'));
    await expectLater(repo.saveNotebook(StudyNotebook(), 'student'),
        throwsA(isA<StateError>()));

    await prefs.reload();
    expect(prefs.getString('notebook_v1'), '{notebook');
  });
  test('repeated personal and notebook damage keeps prior recovery copies',
      () async {
    SharedPreferences.setMockInitialValues({
      'personal_workspace_v1': '{personal-one',
      'notebook_v1': '{notebook-one'
    });
    final repo = LocalAssignmentRepository();
    await repo.loadPersonalWorkspace();
    await repo.loadNotebook();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal-two');
    await prefs.setString('notebook_v1', '{notebook-two');
    await repo.loadPersonalWorkspace();
    await repo.loadNotebook();

    expect(prefs.getString('personal_workspace_v1_recovery_backup'),
        '{personal-one');
    expect(prefs.getStringList('personal_workspace_v1_recovery_backups'),
        ['{personal-two']);
    expect(prefs.getString('notebook_v1_recovery_backup'), '{notebook-one');
    expect(
        prefs.getStringList('notebook_v1_recovery_backups'), ['{notebook-two']);
  });
  test('personal and notebook recovery copies remain account isolated',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal-a');
    await prefs.setString('notebook_v1', '{notebook-a');
    await repo.loadPersonalWorkspace();
    await repo.loadNotebook();

    await repo.activateAccount('B');
    expect(repo.recoveryWarning, isNull);
    expect(prefs.containsKey('personal_workspace_v1_recovery_backup'), isFalse);
    expect(prefs.containsKey('notebook_v1_recovery_backup'), isFalse);
    await prefs.setString('personal_workspace_v1', '{personal-b');
    await prefs.setString('notebook_v1', '{notebook-b');
    await repo.loadPersonalWorkspace();
    await repo.loadNotebook();
    expect(prefs.getString('personal_workspace_v1_recovery_backup'),
        '{personal-b');
    expect(prefs.getString('notebook_v1_recovery_backup'), '{notebook-b');

    await repo.activateAccount('A');
    expect(repo.recoveryWarning, isNull);
    expect(prefs.getString('personal_workspace_v1_recovery_backup'),
        '{personal-a');
    expect(prefs.getString('notebook_v1_recovery_backup'), '{notebook-a');
  });
  test('normal personal and notebook save and backup remain readable',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('student');
    final personal = PersonalWorkspace(
        plans: [const DailyPlanItem('cx:work:1:2:3', '2026-11-07', 45)]);
    final notebook = StudyNotebook(
        entries: [const ManualEntry(id: 'm1', title: '复习', kind: 'todo')]);

    await repo.savePersonalWorkspace(personal, 'student');
    await repo.saveNotebook(notebook, 'student');

    expect((await repo.loadPersonalWorkspace()).plans.single.minutes, 45);
    expect((await repo.loadNotebook()).entries.single.title, '复习');
    final snapshot = await repo.createBackupSnapshot('student');
    expect(snapshot.personal.plans.single.minutes, 45);
    expect(snapshot.notebook.entries.single.title, '复习');
  });
  test('backup export refuses empty fallback for damaged notebook', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('student');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notebook_v1', '{notebook-broken');

    await expectLater(
      repo.createBackupSnapshot('student'),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('恢复警告'),
      )),
    );

    expect(prefs.getString('notebook_v1'), '{notebook-broken');
    expect(
      prefs.getString('notebook_v1_recovery_backup'),
      '{notebook-broken',
    );
  });
  test('recovery copies stop at the bounded history instead of evicting',
      () async {
    SharedPreferences.setMockInitialValues({'personal_workspace_v1': '{one'});
    final repo = LocalAssignmentRepository();
    await repo.loadPersonalWorkspace();
    final prefs = await SharedPreferences.getInstance();
    for (final value in ['{two', '{three', '{four']) {
      await prefs.setString('personal_workspace_v1', value);
      await repo.loadPersonalWorkspace();
    }

    await prefs.setString('personal_workspace_v1', '{five');
    await expectLater(repo.loadPersonalWorkspace(), throwsA(isA<StateError>()));
    expect(repo.recoveryWarning, contains('恢复副本已达上限'));
    expect(repo.recoveryWarning, contains('恢复副本未保存'));
    expect(repo.recoveryWarning, isNot(contains('原始数据已保留备份')));

    expect(prefs.getString('personal_workspace_v1'), '{five');
    expect(
      prefs.getStringList('personal_workspace_v1_recovery_backups'),
      ['{two', '{three', '{four'],
    );
  });
  test('oversized damaged data is preserved but not duplicated as backup',
      () async {
    final oversized = 'x' * (4 * 1024 * 1024 + 1);
    SharedPreferences.setMockInitialValues({'notebook_v1': oversized});
    final repo = LocalAssignmentRepository();

    await expectLater(repo.loadNotebook(), throwsA(isA<StateError>()));
    expect(repo.recoveryWarning, contains('超过恢复副本容量上限'));
    expect(repo.recoveryWarning, contains('恢复副本未保存'));
    expect(repo.recoveryWarning, contains('原始损坏数据仍保留'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('notebook_v1'), oversized);
    expect(prefs.containsKey('notebook_v1_recovery_backup'), isFalse);
  });
  test('recovery failure warning stays within the affected account', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{one');
    await repo.loadPersonalWorkspace();
    for (final value in ['{two', '{three', '{four', '{five']) {
      await prefs.setString('personal_workspace_v1', value);
      if (value == '{five') {
        await expectLater(
            repo.loadPersonalWorkspace(), throwsA(isA<StateError>()));
      } else {
        await repo.loadPersonalWorkspace();
      }
    }
    expect(repo.recoveryWarning, contains('恢复副本未保存'));

    await repo.activateAccount('B');
    expect(repo.recoveryWarning, isNull);
    expect(await repo.loadPersonalWorkspace(), isA<PersonalWorkspace>());
    expect(repo.recoveryWarning, isNull);

    await repo.activateAccount('A');
    expect(repo.recoveryWarning, isNull);
    await expectLater(repo.loadPersonalWorkspace(), throwsA(isA<StateError>()));
    expect(repo.recoveryWarning, contains('恢复副本未保存'));
  });
  test('keyed recovery warnings remain isolated across account switches',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal-a');
    _installFailingStore(prefs, {
      'flutter.personal_workspace_v1_recovery_backup',
      'flutter.personal_workspace_v1_recovery_backups',
    });
    await expectLater(repo.loadPersonalWorkspace(), throwsA(isA<StateError>()));

    await repo.activateAccount('B');
    expect(repo.recoveryWarning, isNull);
    await prefs.setString('notebook_v1', '{notebook-b');
    await repo.loadNotebook();
    expect(repo.recoveryWarning, contains('部分个人待办与学期归档无法读取'));
    expect(repo.recoveryWarning, isNot(contains('恢复副本未保存')));

    await repo.activateAccount('A');
    expect(repo.recoveryWarning, isNull);
    await expectLater(repo.loadPersonalWorkspace(), throwsA(isA<StateError>()));
    expect(repo.recoveryWarning, contains('恢复副本未保存'));
    expect(repo.recoveryWarning, isNot(contains('部分个人待办与学期归档无法读取')));
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

_FailSelectedWrites _installFailingStore(
    SharedPreferences prefs, Set<String> failingKeys) {
  final values = {
    for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!
  };
  final store = _FailSelectedWrites(values, failingKeys);
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

class _FailSelectedWrites extends InMemorySharedPreferencesStore {
  _FailSelectedWrites(super.data, this.failingKeys) : super.withData();

  final Set<String> failingKeys;
  bool enabled = true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (enabled && failingKeys.contains(key)) return false;
    return super.setValue(valueType, key, value);
  }
}
