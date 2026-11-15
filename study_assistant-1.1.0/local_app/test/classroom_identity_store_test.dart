import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'review_core_remediation_test.dart' as f;

Assignment task(String id, String status) => Assignment(
    id: id,
    source: AssignmentSource.classroomActivity,
    activityType: 35,
    courseName: '合成课程',
    title: '合成任务',
    deadlineAt: DateTime.utc(2030),
    requirementsText: '',
    status: status,
    lastSyncedAt: DateTime.utc(2026),
    submitUrl:
        'https://mobilelearn.chaoxing.com/page/renwuNew/stu/taskDetailStuForAnswer_new?courseId=1&classId=2&activeId=task');

class IdentityClient extends f.Client {
  @override
  Future<List<Assignment>> fetchAssignments() async {
    sourceResults = const [
      SyncSourceResult(
          source: 'classroomActivity:35', phase: SyncSourcePhase.success)
    ];
    return [
      task('cx:activity:1:2:task', 'submitted')
          .copyWith(lastSyncedAt: DateTime.utc(2027))
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('identity conflicts report partial and cannot complete source baseline',
      () async {
    final store = f.makeStore(f.Session(), client: IdentityClient());
    await store.restoreSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'chaoxing_journal_v2',
        jsonEncode({
          'schemaVersion': 2,
          'records': [
            task('cx:activity:old', 'pending').toJson(),
            task('cx:activity:1:2:task', 'pending').toJson()
          ],
          'hidden': [],
          'lastSync': '2026-01-01T00:00:00.000Z'
        }));
    await store.refreshAssignments();
    await store.syncAssignments();
    expect(store.syncReport.phase, SyncPhase.partial);
    expect(store.syncReport.issues.any((i) => i.stage == 'identity'), isTrue);
    expect(
        store.syncReport.sourceResults.single.phase, SyncSourcePhase.partial);
    expect(store.syncReport.sourceResults.single.reasonCodes,
        contains('identityConflict'));
    expect(
        store.findAssignment('cx:activity:old')!.isPendingConfirmed, isFalse);
    store.dispose();
  });
}
