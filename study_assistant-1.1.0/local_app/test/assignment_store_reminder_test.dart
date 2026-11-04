import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  test(
    'saveReminderRule persists custom offsets and reschedules assignments',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notificationService = _RecordingNotificationService();
      final store = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: notificationService,
        widgetSnapshotService: _NoopWidgetSnapshotService(),
      );
      addTearDown(store.dispose);
      store.replaceAssignmentsForTest([_assignment(id: 'work-1')]);

      await store.saveReminderRule([30, 1440, 30, 5]);

      expect(store.reminderOffsetsMinutes, [1440, 30, 5]);
      expect(notificationService.lastOffsets, [1440, 30, 5]);

      final restored = AssignmentStore(
        sessionStore: _MemorySessionStore(account: 'student'),
        notificationService: _RecordingNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService(),
      );
      addTearDown(restored.dispose);
      await restored.restoreSession();

      expect(restored.reminderOffsetsMinutes, [1440, 30, 5]);
    },
  );
}

Assignment _assignment({required String id}) {
  return Assignment(
    id: id,
    courseName: '大学英语',
    title: '章节作业',
    deadlineAt: DateTime.now().add(const Duration(days: 2)),
    requirementsText: '完成后提交',
    status: 'pending',
    lastSyncedAt: DateTime.now(),
  );
}

class _RecordingNotificationService extends LocalNotificationService {
  List<int>? lastOffsets;

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    lastOffsets = offsetsMinutes;
  }
}

class _MemorySessionStore extends SecureSessionStore {
  _MemorySessionStore({this.account});

  final String? account;

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}
