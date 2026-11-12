import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Failure injection into the persistence boundary used by SharedPreferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
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
  // This simulates the fallback path with no native cross-engine reload. It
  // proves what the Dart layer must do; it does not claim every Android sync
  // loses data when the native engine later reloads SharedPreferences.
  test('failedJournalWriteCannotReappearFromCache', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([journalItem('durable')]);
    final durableSyncAt = await repo.lastSyncAt();
    expect(durableSyncAt, isNotNull);
    final store = AssignmentStore(
      sessionStore: _SignedInSession(),
      repository: repo,
      notificationService: _QuietNotifications(),
      widgetSnapshotService: _QuietWidget(),
      chaoxingClient: _ProgressClient(),
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.assignments.map((a) => a.id), ['cx:work:1:2:durable']);

    final prefs = await SharedPreferences.getInstance();
    _installFailingStore(prefs, {'flutter.chaoxing_journal_v2'});

    await store.syncAssignments();

    expect(store.assignments.map((a) => a.id), ['cx:work:1:2:durable'],
        reason: '失败后必须保留旧可见作业');
    expect(store.homeSyncProgress, isNull, reason: '失败后必须清理同步预览');
    expect(store.lastSyncAt, durableSyncAt, reason: '失败的写入不能推进完整同步时间');
    expect(store.error, contains('未能保存本机作业记录'));
    expect(
        store.syncReport.issues
            .any((issue) => issue.kind == SyncIssueKind.storage),
        isTrue,
        reason: '本机写入失败必须归类为存储问题，而不是网络问题');
    expect((await repo.loadJournal()).map((a) => a.id), ['cx:work:1:2:durable'],
        reason: '同进程读取不能再看到未落盘的缓存值');
    await prefs.reload();
    expect((await LocalAssignmentRepository().loadJournal()).map((a) => a.id),
        ['cx:work:1:2:durable'],
        reason: '重新打开仓库后仍应与真实持久值一致');
  });
  test('falseWriteWithDurableValueIsVerified', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.mergeAndSave([journalItem('durable')]);
    final prefs = await SharedPreferences.getInstance();
    _installWriteThenRejectStore(prefs, {'flutter.chaoxing_journal_v2'});

    await repo.mergeAndSave([journalItem('durable'), journalItem('written')]);

    expect((await repo.loadJournal()).map((a) => a.id),
        unorderedEquals(['cx:work:1:2:durable', 'cx:work:1:2:written']),
        reason: '平台返回 false 但值已经落盘时，不应回滚或报失败');
    await prefs.reload();
    expect((await LocalAssignmentRepository().loadJournal()).map((a) => a.id),
        unorderedEquals(['cx:work:1:2:durable', 'cx:work:1:2:written']));

    await repo.activateAccount('student');
    await repo.saveCourses([course('old')], account: 'student');
    _installWriteThenRejectStore(prefs, const {},
        throwKeys: {'flutter.course_refs'});
    await repo.saveCourses([course('thrown')], account: 'student');
    expect((await repo.loadCourses(account: 'student')).map((c) => c.name),
        ['thrown'],
        reason: '平台抛错但值已落盘时同样应按真实持久值处理');

    _installWriteThenRejectStore(prefs, {'flutter.course_refs'});
    await repo.saveCourses([course('old'), course('new')], account: 'student');
    expect((await repo.loadCourses(account: 'student')).map((c) => c.name),
        ['old', 'new'],
        reason: '课程写入同样必须以真实持久值为准');
  });
  test('failedCourseWriteKeepsDurableCourses', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('student');
    await repo.saveCourses([course('old')], account: 'student');
    final prefs = await SharedPreferences.getInstance();
    _installFailingStore(prefs, {'flutter.course_refs'});

    await expectLater(
        repo.saveCourses([course('old'), course('new')], account: 'student'),
        throwsA(isA<LocalStorageWriteException>()));

    expect((await repo.loadCourses(account: 'student')).map((c) => c.name),
        ['old'],
        reason: '未落盘的新课程不能从缓存回读');
    await prefs.reload();
    expect(
        (await LocalAssignmentRepository().loadCourses(account: 'student'))
            .map((c) => c.name),
        ['old']);
  });
  test('savingStagePrecedesCoursePersistence', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _SignedInSession(),
      notificationService: _QuietNotifications(),
      widgetSnapshotService: _QuietWidget(),
      chaoxingClient: _ProgressClient(),
      manageBackgroundSchedule: false,
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    final blocking = _BlockCourseWrites(_prefsSnapshot(prefs));
    SharedPreferencesStorePlatform.instance = blocking;

    final sync = store.syncAssignments();
    await blocking.started.future;
    expect(blocking.blockedKey, 'flutter.course_refs');
    expect(store.homeSyncProgress?.stage, AssignmentSyncStage.saving,
        reason: '首次持久化等待期间必须已经标记保存阶段');

    blocking.release.complete();
    await sync;
    expect(store.homeSyncProgress, isNull);
    expect(store.courses.single.name, '数学');
    expect(prefs.getString('course_refs'), contains('数学'));
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
  final store = _FailSelectedWrites(_prefsSnapshot(prefs), failingKeys);
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

_WriteThenRejectStore _installWriteThenRejectStore(
    SharedPreferences prefs, Set<String> rejectKeys,
    {Set<String> throwKeys = const {}}) {
  final store =
      _WriteThenRejectStore(_prefsSnapshot(prefs), rejectKeys, throwKeys);
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

Map<String, Object> _prefsSnapshot(SharedPreferences prefs) =>
    {for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!};

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

/// Mirrors a platform that stores the value but still reports a failed write.
class _WriteThenRejectStore extends InMemorySharedPreferencesStore {
  _WriteThenRejectStore(super.data, this.rejectKeys, this.throwKeys)
      : super.withData();

  final Set<String> rejectKeys;
  final Set<String> throwKeys;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final stored = await super.setValue(valueType, key, value);
    if (throwKeys.contains(key)) {
      throw PlatformException(code: 'synthetic-write-failure');
    }
    if (rejectKeys.contains(key)) return false;
    return stored;
  }
}

class _SignedInSession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student';
  @override
  Future<String?> readChaoxingPassword() async => 'dummy';
  @override
  Future<String?> readChaoxingDisplayName() async => 'Tester';
  @override
  Future<String?> readChaoxingAvatarUrl() async =>
      'https://example.invalid/avatar.png';
}

class _ProgressClient extends ChaoxingLocalClient {
  @override
  bool get needsSessionInitialization => false;
  @override
  Future<List<Assignment>> fetchAssignments() async {
    hasCourseResponse = true;
    courses = [
      const ChaoxingCourseRef(courseId: '1', clazzId: '2', courseName: '数学')
    ];
    onProgress?.call(AssignmentSyncProgress(
      stage: AssignmentSyncStage.details,
      assignments: [journalItem('preview')],
      pendingDetailIds: const {},
      resolvedCount: 1,
      attemptedCount: 1,
    ));
    return [journalItem('preview')];
  }
}

class _QuietNotifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(List<Assignment> assignments,
      {List<int>? offsetsMinutes}) async {}
  @override
  Future<void> rescheduleSummary(List<Assignment> assignments,
      PersonalWorkspace personal, DateTime? lastSync) async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}
  @override
  Future<void> removeLegacyAssignmentSchedules() async {}
}

class _QuietWidget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _BlockCourseWrites extends InMemorySharedPreferencesStore {
  _BlockCourseWrites(super.data) : super.withData();

  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  String? blockedKey;
  bool _blocked = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (!_blocked && key == 'flutter.course_refs') {
      _blocked = true;
      blockedKey = key;
      started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

Assignment journalItem(String id) => Assignment(
    id: 'cx:work:1:2:$id',
    courseName: '数学',
    title: id,
    deadlineAt: DateTime(2030, 11, 6, 23, 59),
    requirementsText: '',
    status: 'pending',
    lastSyncedAt: DateTime(2030, 11, 1));

CourseRef course(String name) =>
    CourseRef(courseId: name, clazzId: '1', name: name);
