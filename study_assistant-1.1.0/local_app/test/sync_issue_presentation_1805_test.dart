import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/sync_issue_presentation.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment _course(String id, String name) => Assignment(
      id: 'cx:work:$id:$id:one',
      courseName: name,
      title: '作业',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime(2026, 11, 16),
    );

void main() {
  test('FB-003 identical issues group by stage, kind and message', () {
    final issues = [
      for (var i = 0; i < 6; i++)
        SyncIssue(
          SyncIssueKind.schemaChanged,
          '课程考试列表页面结构无法识别（examPhoneSchema）',
          stage: 'exam',
          courseKey: 'c$i:k$i',
        ),
      const SyncIssue(
        SyncIssueKind.network,
        '网络不可用',
        stage: 'request',
      ),
    ];

    final groups = groupSyncIssues(issues);
    expect(groups, hasLength(2));
    expect(groups.first.count, 6);
    expect(groups.first.courseKeys, hasLength(6));
    expect(groups.first.message, contains('examPhoneSchema'));
    expect(syncIssueStageLabel('exam'), '课程考试');
    expect(syncIssueKindLabel(SyncIssueKind.schemaChanged), '页面结构未识别');
    expect(syncIssueNextAction(SyncIssueKind.schemaChanged), contains('原始条目'));
  });

  testWidgets('FB-003 sync screen exposes grouped courses and raw entries',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _Session(),
      notificationService: _Notifications(),
      widgetSnapshotService: _Snapshot(),
    );
    addTearDown(store.dispose);
    final rows = [
      _course('c1', '课程甲'),
      _course('c2', '课程乙'),
      _course('c3', '课程丙'),
    ];
    store.replaceAssignmentsForTest(rows);
    store.syncReport = SyncReport(
      phase: SyncPhase.partial,
      succeededCourses: 7,
      issues: [
        for (var i = 0; i < 6; i++)
          SyncIssue(
            SyncIssueKind.schemaChanged,
            '课程考试列表页面结构无法识别（examPhoneSchema）',
            stage: 'exam',
            courseKey: rows[i % rows.length].courseKey,
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncStatusScreen(store: store))),
    );
    await tester.scrollUntilVisible(
      find.text('问题明细（1 组，共 6 条）'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('sync-issue-groups')));
    await tester.pumpAndSettle();

    expect(find.text('课程考试 · 页面结构未识别 · 6 条\n涉及：课程甲、课程乙、课程丙'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-issue-group-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('下一步：先刷新重试'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('sync-issue-raw-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sync-issue-raw-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('课程考试 · schemaChanged'), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}

class _Session extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student';
  @override
  Future<String?> readChaoxingDisplayName() async => null;
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}
