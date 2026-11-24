import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/app/app_deep_links.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/course_study_hub_screen.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'review_core_remediation_test.dart' as f;

class _Store extends AssignmentStore {
  _Store({f.Session? session})
      : super(
            sessionStore: session ?? f.Session(),
            notificationService: f.Notifications(),
            widgetSnapshotService: f.WidgetService(),
            chaoxingClient: f.Client());
  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

class _GatedSession extends f.Session {
  final gate = Completer<void>();
  @override
  Future<String?> readChaoxingAccount() async {
    await gate.future;
    return super.readChaoxingAccount();
  }
}

void main() {
  test('only fully valid notification URI shapes may override cold startup',
      () {
    for (final raw in [
      'studyassistant://assignments',
      'studyassistant:///assignments',
      'studyassistant://assignments/cx%3A1',
      'studyassistant:///assignments/cx%3A1',
    ]) {
      expect(AppDeepLinks.isOwnedNotificationUri(Uri.parse(raw)), isTrue,
          reason: raw);
    }
    for (final raw in [
      'studyassistant://assignments?injected=1',
      'studyassistant:///assignments#fragment',
      'studyassistant://assignments/a/b',
      'studyassistant:///unregistered',
      'studyassistant:///assignments/%FF',
      'studyassistant:///assignments/%2Fbad',
      'studyassistant:assignments',
      'studyassistant://evil.example/assignments',
    ]) {
      expect(AppDeepLinks.isOwnedNotificationUri(Uri.parse(raw)), isFalse,
          reason: raw);
    }
  });
  test('production startup waits for local restoration before consuming links',
      () async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final session = _GatedSession();
    final store = _Store(session: session);
    addTearDown(store.dispose);
    await store.repository.activateAccount('A');
    await store.repository.mergeAndSave([f.sample('restored')]);
    var launched = false;
    final startup = launchRestoredApp(store, () {
      launched = true;
      expect(store.isAuthenticated, isTrue);
      expect(store.findAssignment(f.sample('restored').id), isNotNull);
    });
    await Future<void>.delayed(Duration.zero);
    expect(launched, isFalse);
    session.gate.complete();
    await startup;
    expect(launched, isTrue);
  });
  test('digest payload never performs assignment lookup; missing ID is safe',
      () {
    for (final payload in [
      'studyassistant://assignments',
      'studyassistant:///assignments',
      'd:summary'
    ]) {
      expect(
          AppDeepLinks.notificationLocation(payload,
              containsAssignment: (_) => throw StateError('digest has no ID')),
          '/assignments');
    }
    expect(
        AppDeepLinks.notificationLocation(
            'a:studyassistant:///assignments/gone',
            containsAssignment: (_) => false),
        '/assignments');
    expect(
        AppDeepLinks.notificationLocation(
            'a:studyassistant:///assignments/cx%3A1',
            containsAssignment: (id) => id == 'cx:1'),
        '/assignments/cx%3A1');
    expect(
        AppDeepLinks.notificationLocation('https://evil.example',
            containsAssignment: (_) => true),
        '/assignments');
    expect(
        AppDeepLinks.notificationLocation(
          'p:entry-1',
          containsAssignment: (_) => false,
          containsManualEntry: (id) => id == 'entry-1',
        ),
        '/assignments/manual/entry-1');
    expect(
        AppDeepLinks.notificationLocation(
          'p:missing',
          containsAssignment: (_) => false,
          containsManualEntry: (_) => false,
        ),
        '/agenda');
    expect(
        AppDeepLinks.notificationLocation(
          'p:../bad',
          containsAssignment: (_) => false,
          containsManualEntry: (_) => true,
        ),
        '/agenda');
    expect(
        AppDeepLinks.notificationLocation(
          't:manual-notification-test',
          containsAssignment: (_) => false,
        ),
        '/assignments');
  });

  for (final cold in [true, false]) {
    testWidgets(
        'native digest opens safe list on ${cold ? 'cold' : 'warm'} launch',
        (tester) async {
      await initializeDateFormatting('zh_CN');
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final store = _Store();
      await store.restoreSession();
      addTearDown(store.dispose);
      if (cold) {
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            'studyassistant://assignments';
        addTearDown(
            tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
      }
      await tester.pumpWidget(StudyAssistantApp(
          assignmentStore: store, notificationService: f.Notifications()));
      await tester.pumpAndSettle();
      if (!cold) {
        final context = tester.element(find.byType(AssignmentListScreen));
        GoRouter.of(context).go('studyassistant://assignments');
        await tester.pumpAndSettle();
      }
      expect(find.byType(AssignmentListScreen), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(AssignmentListScreen));
      GoRouter.of(context).go('/unregistered-internal-route');
      await tester.pumpAndSettle();
      expect(find.byType(AssignmentListScreen), findsNothing,
          reason: 'ordinary route errors must not fall back to the list');
      expect(find.textContaining('no routes for location'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'system back from stackless notification detail link returns to home without exiting',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final notifications = _RecordingNotifications();
    final store = _Store()..replaceAssignmentsForTest([f.sample('restored')]);
    await store.restoreSession();
    await store.repository.activateAccount('A');
    await store.repository.mergeAndSave([f.sample('restored')]);
    await store.refreshAssignments();
    addTearDown(store.dispose);

    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        'studyassistant:///assignments/cx%3Awork%3A1%3A2%3Arestored';
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);

    var exitCalls = 0;
    await tester.pumpWidget(StudyAssistantApp(
      assignmentStore: store,
      notificationService: notifications,
      onExitApp: () async => exitCalls++,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentDetailScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exitCalls, 0);
    expect(find.byType(AssignmentDetailScreen), findsNothing);
    expect(find.byType(AssignmentListScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'deep link detail pushes /course-hub?courseKey=1:2 slice and returns cleanly to detail',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = _Store();
    await store.restoreSession();
    await store.repository.activateAccount('A');
    await store.repository.mergeAndSave([f.sample('restored')]);
    await store.refreshAssignments();
    addTearDown(store.dispose);

    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        'studyassistant:///assignments/cx%3Awork%3A1%3A2%3Arestored';
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);

    await tester.pumpWidget(StudyAssistantApp(
      assignmentStore: store,
      notificationService: f.Notifications(),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentDetailScreen), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('assignment-detail-course-link')));
    await tester.pumpAndSettle();
    expect(find.byType(CourseStudyHubScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('course-hub-course-slice')), findsOneWidget);

    await tester.tap(find.byTooltip('返回我的'));
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentDetailScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _RecordingNotifications extends f.Notifications {
  NotificationPayloadHandler? handler;

  @override
  void setPayloadHandler(NotificationPayloadHandler? onPayload) {
    handler = onPayload;
  }
}
