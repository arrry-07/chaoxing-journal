import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
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
      'pending',
      'overdue',
    ]);
    expect(store.findAssignment('completed')?.id, 'completed');
  });
}

Assignment _assignment({required String id, required String status}) {
  return Assignment(
    id: id,
    courseName: '大学英语',
    title: id,
    deadlineAt: DateTime(2026, 5, 7, 8),
    requirementsText: '完成后提交',
    status: status,
    lastSyncedAt: DateTime(2026, 5, 5, 8),
  );
}

class _NoopNotificationService extends LocalNotificationService {
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
