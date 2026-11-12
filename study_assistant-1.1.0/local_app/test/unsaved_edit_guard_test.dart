import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
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
  _LaunchStore? suppliedStore,
}) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = suppliedStore ?? _LaunchStore(notifications: notifications);
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
  _LaunchStore({f.Notifications? notifications, f.Session? session})
      : super(
          sessionStore: session ?? f.Session(),
          notificationService: notifications ?? f.Notifications(),
          widgetSnapshotService: f.WidgetService(),
          chaoxingClient: f.Client(),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

class _GatedEditorStore extends _LaunchStore {
  Completer<bool>? saveGate;
  int saves = 0;

  @override
  Future<bool> savePersonal(
      PersonalWorkspace Function(PersonalWorkspace) update,
      int expectedEpoch) async {
    saves++;
    if (saveGate != null && !await saveGate!.future) return false;
    return super.savePersonal(update, expectedEpoch);
  }

  @override
  Future<bool> saveNotebook(
      StudyNotebook Function(StudyNotebook) update, int expectedEpoch) async {
    saves++;
    if (saveGate != null && !await saveGate!.future) return false;
    return super.saveNotebook(update, expectedEpoch);
  }
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
    // A confirmation without a navigation must not approve a future exit.
    expect(await guard.confirmLeave(), isTrue);
    expect(confirmations, 2);
  });

  testWidgets('approval belongs to one navigation and draft revision',
      (tester) async {
    final guard = UnsavedEditGuard();
    var revision = 0;
    var prompts = 0;
    var saving = false;
    guard.register(
      Object(),
      hasUnsavedChanges: () => true,
      draftRevision: () => revision,
      blocksNavigation: () => saving,
      confirmDiscard: () async {
        prompts++;
        return true;
      },
    );
    final answers = <bool>[];
    final navigation = guard.navigate(
      isCurrent: () => true,
      action: () async {
        answers.add(await guard.confirmLeave());
        revision++;
        answers.add(await guard.confirmLeave());
        saving = true;
        answers.add(await guard.confirmLeave());
      },
    );
    await tester.pumpAndSettle();
    await navigation;
    expect(answers, [true, true, false]);
    saving = false;
    expect(await guard.confirmLeave(), isTrue);
    // One prompt for the initial navigation, one after the revision changed,
    // one for the save-in-progress block, and one for the later fresh exit.
    expect(prompts, 4);
  });

  testWidgets('last valid navigation wins a shared confirmation',
      (tester) async {
    final guard = UnsavedEditGuard();
    final answer = Completer<bool>();
    var prompts = 0;
    final targets = <String>[];
    guard.register(Object(),
        hasUnsavedChanges: () => true,
        confirmDiscard: () {
          prompts++;
          return answer.future;
        });
    final requests = [
      for (final target in ['notification-one', 'notification-two', 'tab'])
        guard.navigate(
            isCurrent: () => true, action: () => targets.add(target)),
    ];
    expect(prompts, 1);
    answer.complete(true);
    await tester.pumpAndSettle();
    await Future.wait(requests);
    expect(targets, ['tab']);
  });

  test('registration replacement and invalidation reject old confirmations',
      () async {
    final guard = UnsavedEditGuard();
    final owner = Object();
    final old = Completer<bool>();
    guard.register(owner,
        hasUnsavedChanges: () => true, confirmDiscard: () => old.future);
    final pending = guard.confirmLeave();
    guard.invalidate();
    guard.register(owner,
        hasUnsavedChanges: () => true, confirmDiscard: () async => false);
    expect(await guard.confirmLeave(), isFalse);
    old.complete(true);
    expect(await pending, isFalse);
    expect(await guard.confirmLeave(), isFalse);
  });

  testWidgets('cancelled or failed navigation cannot retain approval',
      (tester) async {
    final guard = UnsavedEditGuard();
    var prompts = 0;
    guard.register(Object(),
        hasUnsavedChanges: () => true,
        confirmDiscard: () async {
          prompts++;
          return true;
        });
    final noNavigation = guard.navigate(isCurrent: () => true, action: () {});
    await tester.pumpAndSettle();
    await noNavigation;
    expect(await guard.confirmLeave(), isTrue);
    final failure = guard.navigate(
        isCurrent: () => true,
        action: () => throw StateError('navigation rejected'));
    final expectation = expectLater(failure, throwsStateError);
    await tester.pumpAndSettle();
    await expectation;
    expect(await guard.confirmLeave(), isTrue);
    expect(prompts, 4);
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

  testWidgets('two notifications and a tab commit only the latest target',
      (tester) async {
    final notifications = _CapturingNotifications();
    await _launchApp(tester, _personalLocation, notifications: notifications);
    await tester.enterText(find.byType(TextField).first, '竞争中的草稿');
    final router = GoRouter.of(tester.element(find.byType(PersonalWorkScreen)));
    final destinations = <String>[];
    void record() =>
        destinations.add(router.routeInformationProvider.value.uri.path);
    router.routeInformationProvider.addListener(record);
    addTearDown(() => router.routeInformationProvider.removeListener(record));
    notifications.handler!('p:first');
    notifications.handler!('d:summary');
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(1);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(destinations, ['/calendar']);
    expect(find.byType(CalendarScreen), findsOneWidget);
  });

  for (final switchAccount in [false, true]) {
    testWidgets(
        'pending dialog invalidated by ${switchAccount ? 'account switch' : 'logout'}',
        (tester) async {
      final session = f.Session();
      final notifications = _CapturingNotifications();
      final store =
          _LaunchStore(session: session, notifications: notifications);
      await _launchApp(tester, _personalLocation,
          notifications: notifications, suppliedStore: store);
      await tester.enterText(find.byType(TextField).first, '旧账号草稿');
      notifications.handler!('p:old');
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      if (switchAccount) {
        session.account = 'B';
        await store.restoreSession();
      } else {
        await store.logout();
      }
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsNothing);
      expect(find.byType(ManualAgendaScreen), findsNothing);
      if (!switchAccount) expect(find.byType(LoginScreen), findsOneWidget);
      // Neither a late completion nor old approval may steer the new session.
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ManualAgendaScreen), findsNothing);
      if (switchAccount) {
        final context = tester.element(find.byType(NavigationBar));
        GoRouter.of(context).go(_personalLocation);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '新账号草稿');
        notifications.handler!('d:summary');
        await tester.pumpAndSettle();
        expect(find.text('放弃未保存的修改？'), findsOneWidget);
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();
        expect(find.byType(PersonalWorkScreen), findsOneWidget);
      }
    });
  }

  testWidgets('same-location notification does not approve a pageless editor',
      (tester) async {
    final notifications = _CapturingNotifications();
    await _launchApp(tester, '/agenda', notifications: notifications);
    await tester.tap(find.text('添加个人安排'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '同址草稿');
    notifications.handler!('p:same');
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byType(ManualEntryEditor), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '同址后再次编辑');
    notifications.handler!('d:summary');
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '同址后再次编辑');
  });

  for (final manual in [false, true]) {
    testWidgets(
        '${manual ? 'manual' : 'personal'} delayed failed save retains draft and retries once',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final notifications = _CapturingNotifications();
      final store = _GatedEditorStore();
      await _launchApp(tester, manual ? '/agenda' : '/assignments',
          notifications: notifications, suppliedStore: store);
      if (manual) {
        await tester.tap(find.text('添加个人安排'));
      } else {
        final router =
            GoRouter.of(tester.element(find.byType(AssignmentListScreen)));
        unawaited(router.push<void>(_personalLocation));
      }
      await tester.pumpAndSettle();
      final editor = manual
          ? find.byType(ManualEntryEditor)
          : find.byType(PersonalWorkScreen);
      final field = find
          .descendant(
              of: editor,
              matching:
                  manual ? find.byType(TextFormField) : find.byType(TextField))
          .first;
      await tester.enterText(field, '延迟保存且失败后重试');
      final save = find.descendant(
          of: editor,
          matching:
              find.widgetWithText(FilledButton, manual ? '保存个人安排' : '保存个人记录'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      store.saveGate = Completer<bool>();
      await tester.tap(save);
      await tester.pump();
      notifications.handler!('d:summary');
      await tester.pump();
      expect(find.text('放弃未保存的修改？'), findsNothing);
      expect(store.saves, 1);
      store.saveGate!.complete(false);
      await tester.pumpAndSettle();
      expect(
          manual
              ? find.byType(ManualEntryEditor)
              : find.byType(PersonalWorkScreen),
          findsOneWidget);
      expect(
          manual
              ? tester.widget<TextFormField>(field).controller!.text
              : tester.widget<TextField>(field).controller!.text,
          '延迟保存且失败后重试');
      store.saveGate = Completer<bool>();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pump();
      store.saveGate!.complete(true);
      await tester.pumpAndSettle();
      expect(store.saves, 2);
      expect(
          manual
              ? find.byType(ManualEntryEditor)
              : find.byType(PersonalWorkScreen),
          findsNothing);
      expect(
          manual
              ? find.byType(ManualAgendaScreen)
              : find.byType(AssignmentListScreen),
          findsOneWidget);
      expect(find.text('放弃未保存的修改？'), findsNothing);
    });
  }

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
