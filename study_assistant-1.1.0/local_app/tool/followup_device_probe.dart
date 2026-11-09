// ISOLATED SYNTHETIC DEVICE ONLY. Separate -t build; never the release candidate.
// Uses production storage/services/pages. No real login, HTTP or credentials.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/daily_plan_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

final controlledPlugin = ControlledPlugin();
final probeKey = GlobalKey<_ProbeState>();

class ControlledPlugin extends AndroidFlutterLocalNotificationsPlugin {
  Completer<void>? gate;
  @override
  Future<void> show(int id, String? title, String? body,
      {AndroidNotificationDetails? notificationDetails,
      String? payload}) async {
    final pending = gate;
    if (pending != null) await pending.future;
    await super.show(id, title, body,
        notificationDetails: notificationDetails, payload: payload);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  FlutterLocalNotificationsPlatform.instance = controlledPlugin;
  runApp(MaterialApp(
      home: Probe(key: probeKey),
      builder: (context, child) => Stack(children: [
            child!,
            Positioned(
                top: 32,
                right: 0,
                child: Material(
                    child: Row(children: [
                  TextButton(
                      onPressed: () => probeKey.currentState
                          ?.act(probeKey.currentState!.failRead),
                      child: const Text('FAIL_READ')),
                  TextButton(
                      onPressed: () => probeKey.currentState
                          ?.act(probeKey.currentState!.occupyBudget),
                      child: const Text('OCCUPY_BUDGET')),
                ])))
          ])));
}

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  final session = SecureSessionStore();
  final plugin = controlledPlugin;
  late final notifications = LocalNotificationService();
  late final store = AssignmentStore(
      sessionStore: session,
      notificationService: notifications,
      widgetSnapshotService: WidgetSnapshotService());
  String result = 'PROBE: offline synthetic data only';
  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => result = 'PASS');
    } catch (e) {
      if (mounted) setState(() => result = 'FAIL: $e');
    }
  }

  Future<void> seed() async {
    final p = await SharedPreferences.getInstance();
    if (!p.getBool('qa_followup_fixture').orFalse && p.getKeys().isNotEmpty) {
      throw StateError(
          'Refusing unknown app data; use a blank isolated instance');
    }
    await p.setBool('qa_followup_fixture', true);
    await p.setInt('auto_sync_interval_minutes', 0);
    await session.saveChaoxingAccount(
        account: 'journal-followup-fixture-A',
        password: 'SYNTHETIC_NOT_A_LOGIN',
        displayName: 'QA synthetic offline');
    await store.restoreSession();
    await store.repository.mergeAndSave([
      for (final key in ['Dated', 'NoDeadline', 'ReadFailed', 'Existing'])
        Assignment(
            id: 'cx:work:qa:class:$key',
            title: 'QA_$key',
            courseName: 'QA_Course',
            deadlineAt:
                key == 'NoDeadline' ? null : DateTime.utc(2030, 11, 6, 16, 30),
            requirementsText: 'Synthetic offline only',
            status: 'pending',
            deadlineReadFailed: key == 'ReadFailed',
            lastSyncedAt: DateTime.now())
    ]);
    await store.refreshAssignments();
    await store.savePersonal(
        (w) => w.withPlans([
              DailyPlanItem('cx:work:qa:class:Existing',
                  PersonalWorkspace.dayKey(DateTime.now()), 15)
            ]),
        store.accountEpoch);
  }

  Future<void> failRead() async {
    final old = store.findAssignment('cx:work:qa:class:Dated')!;
    await store.repository.mergeAndSave(
        [old.copyWith(deadlineReadFailed: true)],
        completeSync: false);
    await store.refreshAssignments();
  }

  Future<void> occupyBudget() async {
    await store.savePersonal(
        (w) => w.withPlans([
              ...w.plans
                  .where((p) => p.assignmentId != 'cx:work:qa:class:Existing'),
              DailyPlanItem('cx:work:qa:class:Existing',
                  PersonalWorkspace.dayKey(DateTime.now()), 50)
            ]),
        store.accountEpoch);
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ISOLATED PROBE')),
      body: ListView(children: [
        Text(result),
        TextButton(onPressed: () => act(seed), child: const Text('SEED_A')),
        TextButton(
            onPressed: () => act(store.restoreSession),
            child: const Text('RESTORE')),
        TextButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => DailyPlanScreen(store: store))),
            child: const Text('PLAN')),
        TextButton(
            onPressed: () => act(() async {
                  final old = store.findAssignment('cx:work:qa:class:Dated')!;
                  await store.repository.mergeAndSave(
                      [old.copyWith(deadlineReadFailed: true)],
                      completeSync: false);
                  await store.refreshAssignments();
                }),
            child: const Text('FAIL_DEADLINE_READ')),
        TextButton(
            onPressed: () => act(() async {
                  plugin.gate = Completer<void>();
                  unawaited(notifications.showTestNotification());
                }),
            child: const Text('START_BLOCKED_NOTIFICATION')),
        TextButton(
            onPressed: () => act(() async {
                  unawaited(store.logout());
                }),
            child: const Text('LOGOUT_IN_FLIGHT')),
        TextButton(
            onPressed: () => act(() async {
                  plugin.gate?.complete();
                  plugin.gate = null;
                }),
            child: const Text('RELEASE_NOTIFICATION')),
        TextButton(
            onPressed: () => act(() async {
                  if (!await notifications.showTestNotification()) {
                    throw StateError('show returned false');
                  }
                }),
            child: const Text('NORMAL_NOTIFICATION')),
      ]));
}

extension on bool? {
  bool get orFalse => this ?? false;
}
