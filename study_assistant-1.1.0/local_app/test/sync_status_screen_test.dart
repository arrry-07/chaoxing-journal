import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  const verification = SyncIssue(SyncIssueKind.verificationRequired, '需要验证');
  const missingCourseCredential = SyncIssue(
      SyncIssueKind.schemaChanged, '示例课程 课程页未生成作业读取凭证，可在应用内检查访问',
      stage: 'coursePage');
  const examRedirect =
      SyncIssue(SyncIssueKind.schemaChanged, '考试页面跳转未通过安全检查', stage: 'exam');

  test('sync summary does not hide detail and exam failures behind one source',
      () {
    const report = SyncReport(
      phase: SyncPhase.partial,
      sourceResults: [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
          detailUnconfirmedCount: 1,
        ),
        SyncSourceResult(
          source: 'exam',
          phase: SyncSourcePhase.partial,
          failedCourses: 1,
        ),
      ],
    );
    expect(report.summary, '部分课业信息未更新');
  });

  test(
      'not-enabled group history does not turn a detail retry into a source failure',
      () {
    const report = SyncReport(
      phase: SyncPhase.partial,
      sourceResults: [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
          detailUnconfirmedCount: 1,
        ),
        SyncSourceResult(
          source: 'groupHistory',
          phase: SyncSourcePhase.notEnabled,
        ),
      ],
    );
    expect(report.summary, '作业列表已更新，部分截止时间待确认');
  });

  test('classroom failure is counted once without a generic multi-source label',
      () {
    const report = SyncReport(
      phase: SyncPhase.partial,
      failedCourses: 1,
      sourceResults: [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
        ),
        SyncSourceResult(
          source: 'classroomActivity:42',
          phase: SyncSourcePhase.partial,
          failedCourses: 1,
        ),
      ],
    );
    expect(report.summary, '作业记录已更新，部分课堂任务未更新');
  });

  testWidgets('restored verification report without target asks for a refresh',
      (tester) async {
    await _pumpRestoredReport(tester, [verification]);
    expect(find.text('在应用内检查访问'), findsNothing);
    await tester.ensureVisible(find.text('完成安全验证'));
    await tester.tap(find.text('完成安全验证'));
    await tester.pump();
    expect(find.text('请先刷新作业数据，再完成安全验证'), findsOneWidget);
  });

  testWidgets('restored course credential issue offers an access check',
      (tester) async {
    await _pumpRestoredReport(tester, [missingCourseCredential]);
    expect(find.text('完成安全验证'), findsNothing);
    await tester.ensureVisible(find.text('在应用内检查访问'));
    await tester.tap(find.text('在应用内检查访问'));
    await tester.pump();
    expect(find.text('请先刷新作业数据，再检查访问'), findsOneWidget);
  });

  for (final scenario in [
    (
      name: 'exam redirect failure alone offers neither browser action',
      issues: [examRedirect],
      action: null
    ),
    (
      name: 'generic course page parse failure offers neither browser action',
      issues: [
        const SyncIssue(SyncIssueKind.schemaChanged, '学习通响应无法解析，请稍后重试',
            stage: 'coursePage')
      ],
      action: null
    ),
    (
      name: 'exam redirect failure preserves the access check',
      issues: [examRedirect, missingCourseCredential],
      action: '在应用内检查访问'
    ),
    (
      name: 'exam redirect failure preserves the real verification action',
      issues: [examRedirect, verification],
      action: '完成安全验证'
    ),
    (
      name: 'real verification takes priority over the access check',
      issues: [examRedirect, missingCourseCredential, verification],
      action: '完成安全验证'
    ),
  ]) {
    testWidgets(scenario.name, (tester) async {
      await _pumpRestoredReport(tester, scenario.issues);
      for (final label in ['完成安全验证', '在应用内检查访问']) {
        expect(find.text(label),
            label == scenario.action ? findsOneWidget : findsNothing);
      }
    });
  }

  testWidgets('sync status links to the single background-check setting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncStatusScreen(store: store))),
    );

    expect(find.text('白天后台检查'), findsOneWidget);
    expect(find.text('调整后台检查与提醒'), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-sync-option-15')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-30')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-60')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-custom')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-off')), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('legacy disabled background check remains visibly disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncStatusScreen(store: store))),
    );

    expect(store.backgroundCheckEnabled, isFalse);
    expect(find.textContaining('已关闭；手动刷新'), findsOneWidget);
  });

  testWidgets('issue query opens grouped details immediately', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    store.syncReport = const SyncReport(
      phase: SyncPhase.partial,
      issues: [
        SyncIssue(
          SyncIssueKind.schemaChanged,
          '作业详情未识别',
          stage: 'detail',
          courseKey: '1:2',
        ),
      ],
    );
    final router = GoRouter(initialLocation: '/sync?expand=issues', routes: [
      GoRoute(
        path: '/sync',
        builder: (_, state) => SyncStatusScreen(
          store: store,
          expandIssues: state.uri.queryParameters['expand'] == 'issues',
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('问题明细（1 组，共 1 条）'), findsOneWidget);
    expect(find.textContaining('作业详情未识别'), findsOneWidget);
    expect(find.textContaining('涉及：课程信息待刷新'), findsOneWidget);
  });
}

Future<void> _pumpRestoredReport(
    WidgetTester tester, List<SyncIssue> issues) async {
  final report = SyncReport(phase: SyncPhase.partial, issues: issues);
  SharedPreferences.setMockInitialValues({
    'sync_report_v1': jsonEncode(report.toJson()),
  });
  final store = AssignmentStore(
    sessionStore: _MemorySessionStore(),
    notificationService: _NoopNotificationService(),
    widgetSnapshotService: _NoopWidgetSnapshotService(),
  );
  addTearDown(store.dispose);
  await store.restoreSession();
  await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
}

class _MemorySessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student';

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
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
