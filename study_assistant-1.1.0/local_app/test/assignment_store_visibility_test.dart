import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  test('visibleAssignments only contains unfinished assignments', () {
    final store = AssignmentStore(
      sessionStore: SecureSessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    store.replaceAssignmentsForTest([
      _assignment(id: 'pending', status: 'pending'),
      _assignment(id: 'overdue', status: 'overdue'),
      _assignment(id: 'completed', status: 'completed'),
    ]);

    expect(store.visibleAssignments.map((item) => item.id), [
      'cx:work:1:2:pending',
      'cx:work:1:2:overdue',
    ]);
    expect(store.findAssignment('cx:work:1:2:completed')?.id,
        'cx:work:1:2:completed');
  });

  test(
      'Phase 2C locallyCompleted hides from visible todo, prunes pin, keeps official status untouched, and official completed wins',
      () async {
    SharedPreferences.setMockInitialValues({});
    const account = 'vis-2c-student';
    final session = _VisSession(account);
    final repo = LocalAssignmentRepository();
    await repo.activateAccount(account);
    final pending = _assignment(id: 'local-done', status: 'pending');
    final officialDone = _assignment(id: 'official-done', status: 'submitted');
    await repo.mergeAndSave([pending, officialDone], completeSync: true);

    final store = AssignmentStore(
      sessionStore: session,
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      repository: repo,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    expect(await store.togglePin(pending), isTrue);
    expect(store.isPinned(pending), isTrue);

    expect(await store.setLocallyCompleted(pending, true), isTrue);
    expect(store.isLocallyCompleted(pending), isTrue);
    expect(store.isEffectivelyCompleted(pending), isTrue);
    expect(store.isPinned(pending), isFalse);
    expect(store.findAssignment(pending.id)!.isCompleted, isFalse);
    expect(store.hiddenCourseworkGroups, isEmpty);
    expect(
      store.visibleAssignments.map((a) => a.id),
      isNot(contains(pending.id)),
    );

    // Undo restores to visible todo.
    expect(await store.setLocallyCompleted(pending, false), isTrue);
    expect(store.visibleAssignments.map((a) => a.id), contains(pending.id));

    // When official status is already completed, official priority holds even if local bit is set & undone.
    expect(await store.setLocallyCompleted(officialDone, true), isTrue);
    expect(store.isLocallyCompleted(officialDone), isFalse);
    expect(store.isEffectivelyCompleted(officialDone), isTrue);
    expect(await store.setLocallyCompleted(officialDone, false), isTrue);
    expect(store.isEffectivelyCompleted(officialDone), isTrue);
  });
}

Assignment _assignment({required String id, required String status}) {
  return Assignment(
    id: 'cx:work:1:2:$id',
    courseName: '大学英语',
    title: id,
    deadlineAt: DateTime.now().add(const Duration(days: 3)),
    requirementsText: '完成后提交',
    status: status,
    lastSyncedAt: DateTime.now(),
  );
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _VisSession extends SecureSessionStore {
  _VisSession(this.account);
  final String? account;
  @override
  Future<String?> readChaoxingAccount() async => account;
  @override
  Future<String?> readChaoxingPassword() async => 'pw';
  @override
  Future<String?> readChaoxingDisplayName() async => null;
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}
