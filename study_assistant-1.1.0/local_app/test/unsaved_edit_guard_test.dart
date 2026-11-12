import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/app/unsaved_edit_guard.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/login_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/personal_work_screen.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';

import 'review_core_remediation_test.dart' as f;

const _personalLocation = '/personal/cx%3Awork%3A1%3A2%3Ashared';

Future<AssignmentStore> _store() async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = f.makeStore(f.Session());
  await store.restoreSession();
  await store.repository.mergeAndSave([f.sample('shared')]);
  await store.refreshAssignments();
  return store;
}

Future<AssignmentStore> _launchApp(
  WidgetTester tester,
  String location, {
  f.Notifications? notifications,
}) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = _LaunchStore(notifications: notifications);
  addTearDown(store.dispose);
  await store.restoreSession();
  await store.repository.mergeAndSave([f.sample('shared')]);
  await store.refreshAssignments();
  tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  await tester.pumpWidget(StudyAssistantApp(
    assignmentStore: store,
    notificationService: notifications ?? f.Notifications(),
  ));
  await tester.pumpAndSettle();
  return store;
}

class _LaunchStore extends AssignmentStore {
  _LaunchStore({f.Notifications? notifications})
      : super(
          sessionStore: f.Session(),
          notificationService: notifications ?? f.Notifications(),
          widgetSnapshotService: f.WidgetService(),
          chaoxingClient: f.Client(),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

Future<void> _push(
  WidgetTester tester,
  Widget page,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => page),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

class _CapturingNotifications extends f.Notifications {
  NotificationPayloadHandler? handler;

  @override
  void setPayloadHandler(NotificationPayloadHandler? onPayload) {
    handler = onPayload;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  test('concurrent leave requests share one confirmation', () async {
    final guard = UnsavedEditGuard();
    final owner = Object();
    final gate = Completer<bool>();
    var confirmations = 0;
    guard.register(
      owner,
      hasUnsavedChanges: () => true,
      confirmDiscard: () {
        confirmations++;
        return gate.future;
      },
    );

    final first = guard.confirmLeave();
    final second = guard.confirmLeave();
    expect(confirmations, 1);

    gate.complete(true);
    expect(await first, isTrue);
    expect(await second, isTrue);
    // The approved entry no longer blocks the following route exit.
    expect(await guard.confirmLeave(), isTrue);
    expect(confirmations, 1);
  });

  test('cancelling keeps the draft and allows a later prompt', () async {
    final guard = UnsavedEditGuard();
    var confirmations = 0;
    var leave = false;
    guard.register(
      Object(),
      hasUnsavedChanges: () => true,
      confirmDiscard: () async {
        confirmations++;
        return leave;
      },
    );

    expect(await guard.confirmLeave(), isFalse);
    expect(confirmations, 1);
    leave = true;
    expect(await guard.confirmLeave(), isTrue);
    expect(confirmations, 2);
  });

  test('stale draft does not block account cleanup', () async {
    final guard = UnsavedEditGuard();
    var stale = false;
    var confirmations = 0;
    guard.register(
      Object(),
      hasUnsavedChanges: () => true,
      isStale: () => stale,
      confirmDiscard: () async {
        confirmations++;
        return false;
      },
    );

    expect(guard.hasUnsavedChanges, isTrue);
    stale = true;
    expect(guard.hasUnsavedChanges, isFalse);
    expect(await guard.confirmLeave(), isTrue);
    expect(confirmations, 0);
  });

  testWidgets('personal notes back navigation asks before discarding edits',
      (tester) async {
    final store = await _store();
    addTearDown(store.dispose);

    await _push(
      tester,
      PersonalWorkScreen(
        store: store,
        assignmentId: 'cx:work:1:2:shared',
      ),
    );
    await tester.enterText(find.byType(TextField).first, '未保存的备注');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);

    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('个人清单与备注'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('个人清单与备注'), findsNothing);
  });

  testWidgets('manual agenda editor asks before discarding edits',
      (tester) async {
    final store = await _store();
    addTearDown(store.dispose);

    await _push(tester, ManualEntryEditor(store: store));
    await tester.enterText(find.byType(TextFormField).first, '未保存的待办');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);

    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('添加个人安排'), findsNothing);
  });

  testWidgets('dirtyPersonalEditorBlocksTabReplacement', (tester) async {
    await _launchApp(tester, _personalLocation);
    expect(find.byType(PersonalWorkScreen), findsOneWidget);

    final noteField = find.byType(TextField).first;
    await tester.enterText(noteField, '未保存的备注');
    await tester.pump();

    final calendarTab = find.descendant(
        of: find.byType(NavigationBar), matching: find.text('日历'));
    await tester.tap(calendarTab);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    expect(find.byType(PersonalWorkScreen), findsOneWidget);
    expect(tester.widget<TextField>(noteField).controller?.text, '未保存的备注');

    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsNothing);
    expect(find.byType(PersonalWorkScreen), findsOneWidget);
    expect(tester.widget<TextField>(noteField).controller?.text, '未保存的备注');

    await tester.tap(calendarTab);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(PersonalWorkScreen), findsNothing);
  });

  testWidgets('dirty personal editor asks once on system back', (tester) async {
    await _launchApp(tester, _personalLocation);
    await tester.enterText(find.byType(TextField).first, '未保存的备注');
    await tester.pump();

    // The pop future completes only after the route exit is decided; awaiting
    // it before pumping the confirmation dialog would deadlock the test.
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    expect(find.byType(PersonalWorkScreen), findsOneWidget);

    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byType(PersonalWorkScreen), findsOneWidget);
  });

  testWidgets('notificationNavigationRespectsDirtyEditor', (tester) async {
    final notifications = _CapturingNotifications();
    await _launchApp(tester, _personalLocation, notifications: notifications);
    await tester.enterText(find.byType(TextField).first, '未保存的备注');
    await tester.pump();

    notifications.handler!('p:synthetic');
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(PersonalWorkScreen), findsOneWidget);
    expect(find.byType(ManualAgendaScreen), findsNothing);

    notifications.handler!('p:synthetic');
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(PersonalWorkScreen), findsNothing);
    expect(find.byType(ManualAgendaScreen), findsOneWidget);
  });

  testWidgets('notificationNavigationRespectsDirtyManualAgendaEditor',
      (tester) async {
    final notifications = _CapturingNotifications();
    await _launchApp(tester, '/agenda', notifications: notifications);
    await tester.tap(find.text('添加个人安排'));
    await tester.pumpAndSettle();
    expect(find.byType(ManualEntryEditor), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '未保存的待办');
    await tester.pump();

    notifications.handler!('d:summary');
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(ManualEntryEditor), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller
            ?.text,
        '未保存的待办');

    notifications.handler!('d:summary');
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(ManualEntryEditor), findsNothing);
    expect(find.byType(AssignmentListScreen), findsOneWidget);
  });

  testWidgets('successfulSaveExitsExactlyOnce', (tester) async {
    final store = await _launchApp(tester, '/assignments');
    final card = find.byKey(const ValueKey('assignment-cx:work:1:2:shared'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentDetailScreen), findsOneWidget);

    final personalEntry = find.text('个人清单与备注');
    await tester.ensureVisible(personalEntry);
    await tester.pumpAndSettle();
    await tester.tap(personalEntry);
    await tester.pumpAndSettle();
    expect(find.byType(PersonalWorkScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '保存后离开');
    await tester.pump();
    final saveButton = find.widgetWithText(FilledButton, '保存个人记录');
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byType(PersonalWorkScreen), findsNothing);
    expect(find.byType(AssignmentDetailScreen), findsOneWidget);
    expect(store.personal.work['cx:work:1:2:shared']?.note, '保存后离开');
  });

  testWidgets('accountChangeBypassesOldDraftPrompt', (tester) async {
    final store = await _launchApp(tester, _personalLocation);
    await tester.enterText(find.byType(TextField).first, '未保存的备注');
    await tester.pump();

    await store.logout();
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byType(PersonalWorkScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
