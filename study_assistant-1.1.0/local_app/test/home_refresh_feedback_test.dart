import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Store extends AssignmentStore {
  _Store(
      {this.result = const SyncReport(phase: SyncPhase.success),
      this.throws = false})
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  final gate = Completer<void>();
  final SyncReport result;
  final bool throws;
  int calls = 0;
  @override
  Future<void> syncAssignments() async {
    calls++;
    // Simulate a queued operation: the store has not emitted loading yet.
    await gate.future;
    if (throws) throw StateError('fixture failure');
    syncReport = result;
    notifyListeners();
  }
}

void main() {
  Future<GoRouter> show(WidgetTester t, _Store s) async {
    s.replaceAssignmentsForTest([
      Assignment(
          id: 'cx:work:1:2:1',
          title: '上次的作业记录',
          courseName: '样例课程',
          deadlineAt: null,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: DateTime(2026))
    ]);
    final router = GoRouter(initialLocation: '/assignments', routes: [
      GoRoute(
          path: '/assignments',
          builder: (_, __) => Scaffold(body: AssignmentListScreen(store: s))),
      GoRoute(
          path: '/sync',
          builder: (_, __) => const Scaffold(body: Text('同步详情页面'))),
    ]);
    addTearDown(s.dispose);
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light, routerConfig: router));
    return router;
  }

  testWidgets(
      'refresh responds immediately, blocks duplicates and confirms success',
      (t) async {
    final s = _Store();
    await show(t, s);
    await t.tap(find.byTooltip('刷新作业'));
    await t.tap(find.byTooltip('刷新作业'));
    await t.pump();
    expect(s.calls, 1);
    expect(find.text('正在刷新作业…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('上次的作业记录'), findsOneWidget);
    expect(
        t
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '刷新作业'))
            .onPressed,
        isNull);
    s.gate.complete();
    await t.pumpAndSettle();
    expect(find.text('正在刷新作业…'), findsNothing);
    expect(find.text('作业已更新'), findsOneWidget);
    expect(
        t
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '刷新作业'))
            .onPressed,
        isNotNull);
  });

  testWidgets('failed refresh keeps records and opens actionable details',
      (t) async {
    final s = _Store(
        result: const SyncReport(
            phase: SyncPhase.failed,
            issues: [SyncIssue(SyncIssueKind.network, 'fixture')]));
    await show(t, s);
    await t.tap(find.byTooltip('刷新作业'));
    await t.pump();
    s.gate.complete();
    await t.pumpAndSettle();
    expect(find.text('更新失败，已保留上次记录'), findsOneWidget);
    expect(find.text('上次的作业记录'), findsOneWidget);
    await t.tap(find.text('查看详情'));
    await t.pumpAndSettle();
    expect(find.text('同步详情页面'), findsOneWidget);
  });

  testWidgets('partial refresh is not reported as complete success', (t) async {
    final s = _Store(
        result: const SyncReport(
            phase: SyncPhase.partial, succeededCourses: 3, failedCourses: 2));
    await show(t, s);
    await t.tap(find.byTooltip('刷新作业'));
    await t.pump();
    s.gate.complete();
    await t.pumpAndSettle();
    expect(find.text('已更新 3 门课程，2 门待重试'), findsOneWidget);
    expect(find.text('作业已更新'), findsNothing);
  });

  testWidgets('unexpected failure clears busy feedback and allows retry',
      (t) async {
    final s = _Store(throws: true);
    await show(t, s);
    await t.tap(find.byTooltip('刷新作业'));
    await t.pump();
    s.gate.complete();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('刷新未完成，请查看同步详情'), findsOneWidget);
    expect(
        t
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '刷新作业'))
            .onPressed,
        isNotNull);
  });

  testWidgets('leaving home during refresh causes no disposed widget update',
      (t) async {
    final s = _Store();
    final router = await show(t, s);
    await t.tap(find.byTooltip('刷新作业'));
    await t.pump();
    router.go('/sync');
    await t.pumpAndSettle();
    s.gate.complete();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('作业已更新'), findsNothing);
  });
}
