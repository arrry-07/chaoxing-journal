import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/interaction_feedback_service.dart';
import 'review_core_remediation_test.dart' as f;

class TargetClient extends f.Client {
  int targets = 0;
  bool fail = false;
  String targetStatus = 'submitted';
  Completer<List<Assignment>>? fullGate;
  @override
  Future<List<Assignment>> fetchAssignments() =>
      fullGate?.future ?? super.fetchAssignments();
  @override
  Future<List<Assignment>> fetchAssignmentsForCourse(
      {required String courseId, required String clazzId}) async {
    targets++;
    if (fail) throw StateError('network timeout');
    return [f.sample('shared', status: targetStatus)];
  }
}

Assignment classroomSample(String status) => Assignment(
    id: 'cx:activity:1:2:task',
    activityType: 35,
    courseName: '合成课程',
    title: '合成个人任务',
    deadlineAt: DateTime.utc(2030),
    requirementsText: '',
    status: status,
    lastSyncedAt: DateTime.now(),
    submitUrl:
        'https://mobilelearn.chaoxing.com/page/renwuNew/stu/taskDetailStuForAnswer_new?courseId=1&classId=2&activeId=task');

class ClassroomTargetClient extends TargetClient {
  @override
  Future<List<Assignment>> fetchAssignmentsForCourse(
          {required String courseId, required String clazzId}) async =>
      [classroomSample(targetStatus)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'classroom return persists unknown and removes pending reminder eligibility',
      () async {
    final client = ClassroomTargetClient()..targetStatus = 'unknown';
    final store = f.makeStore(f.Session(), client: client);
    await store.restoreSession();
    await store.repository.mergeAndSave([classroomSample('pending')]);
    await store.refreshAssignments();
    expect(store.visibleAssignments.any((a) => a.id == 'cx:activity:1:2:task'),
        isTrue);
    store.beginAssignmentVisit('cx:activity:1:2:task');
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    final saved = store.findAssignment('cx:activity:1:2:task')!;
    expect(saved.status, 'unknown');
    expect(saved.isPendingConfirmed, isFalse);
    expect(store.returnCheckMessage, contains('未能确认'));
    store.dispose();
  });
  test('verified classroom reopening updates previous completed status',
      () async {
    final client = ClassroomTargetClient()..targetStatus = 'pending';
    final store = f.makeStore(f.Session(), client: client);
    await store.restoreSession();
    await store.repository.mergeAndSave([classroomSample('submitted')]);
    await store.refreshAssignments();
    store.beginAssignmentVisit('cx:activity:1:2:task');
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    expect(store.findAssignment('cx:activity:1:2:task')!.status, 'pending');
    expect(store.returnCheckMessage, contains('仍为'));
    store.dispose();
  });
  test('queued return uses the latest confirmed state from preceding full sync',
      () async {
    final client = TargetClient()
      ..targetStatus = 'pending'
      ..fullGate = Completer<List<Assignment>>();
    final store = f.makeStore(f.Session(), client: client);
    await store.restoreSession();
    store.replaceAssignmentsForTest([f.sample('shared')]);
    final full = store.syncAssignments();
    store.beginAssignmentVisit('cx:work:1:2:shared');
    store.markAssignmentVisitLeftApp();
    final checking = store.checkReturnedAssignment();
    client.fullGate!.complete([f.sample('shared', status: 'submitted')]);
    await full;
    await checking;
    expect(store.findAssignment('cx:work:1:2:shared')!.status, 'submitted');
    expect(store.returnCheckMessage, contains('未能确认'));
    store.dispose();
  });
  test('unknown target keeps its previous pending record', () async {
    final client = TargetClient()..targetStatus = 'unknown';
    final store = f.makeStore(f.Session(), client: client);
    await store.restoreSession();
    await store.repository.mergeAndSave([f.sample('shared')]);
    await store.refreshAssignments();
    store.beginAssignmentVisit('cx:work:1:2:shared');
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    expect(store.findAssignment('cx:work:1:2:shared')!.status, 'pending');
    expect(store.returnCheckMessage, contains('未能确认'));
    store.dispose();
  });
  test(
      'logout invalidates return results even while reminder update is awaiting',
      () async {
    final client = TargetClient();
    final n = f.Notifications();
    final store = f.makeStore(f.Session(), client: client, notifications: n);
    await store.restoreSession();
    store.replaceAssignmentsForTest([f.sample('shared')]);
    final gate = Completer<void>();
    n.gate = gate;
    n.started = Completer<void>();
    store.beginAssignmentVisit('cx:work:1:2:shared');
    store.markAssignmentVisitLeftApp();
    final checking = store.checkReturnedAssignment();
    await n.started!.future;
    final logout = store.logout();
    gate.complete();
    await checking;
    await logout;
    expect(store.isAuthenticated, isFalse);
    expect(store.returnCheckMessage, isNull);
    expect(store.changes, isEmpty);
    store.dispose();
  });
  test('return check only runs after leaving and confirms server result',
      () async {
    final client = TargetClient();
    final store = AssignmentStore(
        sessionStore: f.Session(),
        notificationService: f.Notifications(),
        widgetSnapshotService: f.WidgetService(),
        chaoxingClient: client);
    await store.restoreSession();
    store.replaceAssignmentsForTest([f.sample('shared')]);
    store.beginAssignmentVisit('cx:work:1:2:shared');
    await store.checkReturnedAssignment();
    expect(client.targets, 0);
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    expect(client.targets, 1);
    expect(store.returnCheckMessage, contains('已确认提交'));
    await store.checkReturnedAssignment();
    expect(client.targets, 1);
    store.dispose();
  });
  test('failed refresh preserves pending state and does not claim submission',
      () async {
    final client = TargetClient()..fail = true;
    final store = AssignmentStore(
        sessionStore: f.Session(),
        notificationService: f.Notifications(),
        widgetSnapshotService: f.WidgetService(),
        chaoxingClient: client);
    await store.restoreSession();
    store.replaceAssignmentsForTest([f.sample('shared')]);
    store.beginAssignmentVisit('cx:work:1:2:shared');
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    expect(store.findAssignment('cx:work:1:2:shared')!.isCompleted, isFalse);
    expect(store.returnCheckMessage, contains('未能确认'));
    store.dispose();
  });

  test(
      'Phase 2C fetchReturnedWork hits only target work/classroom and avoids 9010 full-sync fallback',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <String>[];
    var workStatusCode = 4; // submitted on Chaoxing
    var blockWith9010 = false;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add('${options.uri.path}?${options.uri.query}');
        if (blockWith9010 && options.uri.path == '/mooc-ans/work/api/task') {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'result': 0, 'status': false, 'code': 9010, 'msg': '请完成验证'},
          ));
          return;
        }
        final dynamic data = switch (options.uri.path) {
          '/mycourse/backclazzdata' => {
              'courses': [
                {'courseId': '1', 'clazzId': '2', 'courseName': '计算机网络'}
              ]
            },
          '/visit/stucoursemiddle' =>
            '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>',
          '/mooc2-ans/coursemanagev3/stu-base-info' => {
              'status': true,
              'navigationList': []
            },
          '/mooc-ans/work/api/task'
              when options.uri.queryParameters['pageNum'] == '1' =>
            {
              'status': true,
              'total': 3,
              'data': [
                {
                  'title': '目标单份作业',
                  'stuStatus': workStatusCode,
                  'evaluation': 0,
                  'endTime': 1796119200000,
                  'taskUrl':
                      'https://mooc1.chaoxing.com/work/task?workId=target&courseId=1&classId=2'
                },
                {
                  'title': '同课无需水合的其它作业',
                  'stuStatus': 0,
                  'evaluation': 0,
                  'endTime': 0,
                  'taskUrl':
                      'https://mooc1.chaoxing.com/work/task?workId=other-work&courseId=1&classId=2'
                },
              ]
            },
          _ => throw StateError('unexpected request: ${options.uri}'),
        };
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: data),
        );
      }));
    final client = _MockAuthChaoxingClient(dio);
    final notifications = f.Notifications();
    final session = f.Session()..account = 'return-2c-student';
    final store = AssignmentStore(
      sessionStore: session,
      notificationService: notifications,
      widgetSnapshotService: f.WidgetService(),
      chaoxingClient: client,
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    final priorSync = DateTime.utc(2026, 11, 20, 1);
    final targetWork = Assignment(
      id: 'cx:work:1:2:target',
      courseName: '计算机网络',
      title: '目标单份作业',
      deadlineAt: DateTime.utc(2026, 12, 1, 10),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: priorSync,
      submitUrl:
          'https://mooc1.chaoxing.com/work/task?workId=target&courseId=1&classId=2',
    );
    final siblingWork = Assignment(
      id: 'cx:work:1:2:sibling',
      courseName: '计算机网络',
      title: '同课未被改写作业',
      deadlineAt: DateTime.utc(2026, 12, 5, 10),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: priorSync,
    );
    await store.repository.mergeAndSave(
      [targetWork, siblingWork],
      completeSync: true,
    );
    await store.refreshAssignments();
    final savedLastSync = store.lastSyncAt;

    store.beginAssignmentVisit(targetWork.id);
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();

    expect(requests.any((r) => r.contains('pageNum=2')), isFalse);
    expect(requests.any((r) => r.contains('activelist')), isFalse);
    expect(requests.any((r) => r.contains('exam')), isFalse);
    expect(requests.any((r) => r.contains('other-work')), isFalse);
    expect(store.findAssignment(targetWork.id)!.isCompleted, isTrue);
    expect(store.findAssignment(siblingWork.id)!.status, 'pending');
    expect(store.lastSyncAt, savedLastSync);
    expect(store.returnCheckMessage, '《目标单份作业》已确认提交');
    expect(store.pendingReturnConfirmation?.assignmentId, targetWork.id);

    // Repeated check without new visit does nothing and emits no confirmation.
    store.consumeReturnCheckConfirmation();
    await store.checkReturnedAssignment();
    expect(store.pendingReturnConfirmation, isNull);

    // Pending work hit with 9010 keeps pending status without full-sync fallback.
    final pending9010 = Assignment(
      id: 'cx:work:1:2:target9010',
      courseName: '计算机网络',
      title: '需验证单份作业',
      deadlineAt: DateTime.utc(2026, 12, 1, 10),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: priorSync,
      submitUrl:
          'https://mooc1.chaoxing.com/work/task?workId=target9010&courseId=1&classId=2',
    );
    await store.repository.mergeAndSave([pending9010]);
    await store.refreshAssignments();
    blockWith9010 = true;
    store.beginAssignmentVisit(pending9010.id);
    store.markAssignmentVisitLeftApp();
    await store.checkReturnedAssignment();
    expect(store.findAssignment(pending9010.id)!.status, 'pending');
    expect(store.returnCheckMessage, contains('未能确认'));
    expect(store.pendingReturnConfirmation, isNull);
  });

  testWidgets(
      'Phase 2C AppShell consumes return confirmation once and plays complete sound only on pending -> submitted',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    InteractionFeedback.debugReset();
    addTearDown(InteractionFeedback.debugReset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const channel = MethodChannel('study_assistant/interaction_sound');
      final played = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'feedback') {
          played.add((call.arguments as Map)['kind'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final client = TargetClient()..targetStatus = 'pending';
      final store = f.makeStore(f.Session(), client: client);
      addTearDown(store.dispose);
      await store.restoreSession();
      final target = f.sample('shared', status: 'pending');
      await store.repository.mergeAndSave([target], completeSync: true);
      await store.refreshAssignments();

      final router = GoRouter(
        initialLocation: '/assignments',
        routes: [
          ShellRoute(
            builder: (_, __, child) =>
                AppShell(assignmentStore: store, child: child),
            routes: [
              GoRoute(
                path: '/assignments',
                builder: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      // Pending -> still pending: no confirmation banner/sound.
      store.beginAssignmentVisit(target.id);
      store.markAssignmentVisitLeftApp();
      await store.checkReturnedAssignment();
      await tester.pump();
      expect(played.where((k) => k == 'complete'), isEmpty);

      // Pending -> submitted: shows 《shared》已确认提交 and plays complete sound ONCE.
      client.targetStatus = 'submitted';
      store.beginAssignmentVisit(target.id);
      store.markAssignmentVisitLeftApp();
      await store.checkReturnedAssignment();
      await tester.pump();
      expect(find.text('《shared》已确认提交'), findsOneWidget);
      expect(played.where((k) => k == 'complete').toList(), ['complete']);

      // Already submitted -> submitted again: does NOT replay sound.
      store.beginAssignmentVisit(target.id);
      store.markAssignmentVisitLeftApp();
      await store.checkReturnedAssignment();
      await tester.pump();
      expect(played.where((k) => k == 'complete').toList(), ['complete']);

      // Cleanly unmount & let TimedReturnCheck timer drain before exit.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _MockAuthChaoxingClient extends ChaoxingLocalClient {
  _MockAuthChaoxingClient(Dio dio)
      : super(enableExams: true, enableClassroomTasks: true, dio: dio);

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async =>
      const ChaoxingLoginResult(success: true);
}
