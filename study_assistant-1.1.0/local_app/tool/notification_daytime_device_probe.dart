// ISOLATED SYNTHETIC DEVICE ONLY. Separate -t build; never a release target.
// Uses production storage, native gateway, receivers and pages without HTTP,
// real credentials or personal data.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/main.dart' as app;
import 'package:study_assistant_mobile/src/app/app_deep_links.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_health_screen.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

const _account = 'journal-notification-probe';
const _seedKey = 'qa_notification_daytime_probe_seeded_v1';
const _oldId = 'cx:work:qa-notify:class:old';
const _newId = 'cx:work:qa-notify:class:new';
const _deadlineId = 'cx:work:qa-notify:class:deadline';

final _probeKey = GlobalKey<_ProbeState>();

@pragma('vm:entry-point')
Future<void> backgroundMain() => app.backgroundMain();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  final notifications = LocalNotificationService();
  const gateway = BackgroundReminderGateway();
  final client = _QueueClient();
  final store = AssignmentStore(
    sessionStore: _ProbeSessionStore(),
    notificationService: notifications,
    widgetSnapshotService: WidgetSnapshotService(),
    repository: LocalAssignmentRepository(
      backgroundReminderGateway: gateway,
    ),
    chaoxingClient: client,
    backgroundReminderGateway: gateway,
    manageBackgroundSchedule: false,
    nativeReminderDeliveryEnabled: true,
  );
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seedKey) == true) {
    await notifications.initializeSafely();
    await store.restoreSession();
  }
  final incomingRoute = PlatformDispatcher.instance.defaultRouteName;
  final incomingLocation = AppDeepLinks.normalizeIncomingLocation(
    Uri.tryParse(incomingRoute) ?? Uri(),
  );
  runApp(
    MaterialApp(
      initialRoute: incomingLocation ?? '/',
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(
          builder: (_) => _initialPage(
            incomingLocation: incomingLocation,
            store: store,
            client: client,
            notifications: notifications,
          ),
        ),
      ],
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => _Probe(
          key: _probeKey,
          store: store,
          client: client,
          notifications: notifications,
        ),
      ),
    ),
  );
}

Widget _initialPage({
  required String? incomingLocation,
  required AssignmentStore store,
  required _QueueClient client,
  required LocalNotificationService notifications,
}) {
  final segments =
      Uri.tryParse(incomingLocation ?? '')?.pathSegments ?? const <String>[];
  if (incomingLocation == '/assignments') {
    return AssignmentListScreen(store: store);
  }
  if (segments.length == 2 &&
      segments.first == 'assignments' &&
      store.findAssignment(segments.last) != null) {
    return AssignmentDetailScreen(
      store: store,
      assignmentId: segments.last,
    );
  }
  return _Probe(
    key: _probeKey,
    store: store,
    client: client,
    notifications: notifications,
  );
}

class _Probe extends StatefulWidget {
  const _Probe({
    super.key,
    required this.store,
    required this.client,
    required this.notifications,
  });

  final AssignmentStore store;
  final _QueueClient client;
  final LocalNotificationService notifications;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final gateway = const BackgroundReminderGateway();
  String result = 'ISOLATED NOTIFICATION PROBE: tap SEED';
  bool seeded = false;

  AssignmentStore get store => widget.store;
  _QueueClient get client => widget.client;
  LocalNotificationService get notifications => widget.notifications;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => result = 'FAIL: $error');
    }
  }

  Future<void> _seedBaseline() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_seedKey) ?? false) && prefs.getKeys().isNotEmpty) {
      throw StateError('Refusing unknown app data; use a blank isolated clone');
    }
    await prefs.setBool(_seedKey, true);
    await notifications.initializeSafely();
    await store.restoreSession();
    await store.saveReminderRule(const [1]);
    client.results = [
      [_assignment(_oldId, 'QA 基线作业', const Duration(days: 1))],
    ];
    await store.syncAssignments();
    seeded = true;
    result = 'PASS baseline: ${store.assignments.length} assignment(s)';
  }

  Future<void> _addTwoNewAssignments() async {
    if (!seeded) throw StateError('Run SEED baseline first');
    final deadline = DateTime.now().add(const Duration(seconds: 75));
    client.results = [
      [
        _assignment(_oldId, 'QA 基线作业', const Duration(days: 1)),
        _assignment(_newId, 'QA 新增无截止', null),
        _assignment(
          _deadlineId,
          'QA 新增即将截止',
          deadline.difference(DateTime.now()),
        ),
      ],
    ];
    await store.syncAssignments();
    result = 'PASS two-new: ${store.assignments.length} assignment(s)';
  }

  Future<void> _syncDuplicate() async {
    await store.syncAssignments();
    result = 'PASS duplicate sync: ${store.assignments.length} assignment(s)';
  }

  Future<void> _hideDeadlineAssignment() async {
    final saved = await store.hideAssignment(_deadlineId);
    if (!saved) throw StateError('hideAssignment returned false');
    result = 'PASS hidden: ${store.assignments.length} visible';
  }

  Future<void> _resetDeadlineAssignment() async {
    await store.updateCompletion(_deadlineId, false);
    final deadline = DateTime.now().add(const Duration(seconds: 75));
    client.results = [
      [
        _assignment(_oldId, 'QA 基线作业', const Duration(days: 1)),
        _assignment(_newId, 'QA 新增无截止', null),
        _assignment(
          _deadlineId,
          'QA 新增即将截止',
          deadline.difference(DateTime.now()),
        ),
      ],
    ];
    await store.syncAssignments();
    result = 'PASS deadline reset for about 75 seconds from now';
  }

  Future<void> _scheduleWorkSoon() async {
    await gateway.reconcileDaytimeSchedule(
      targetAt: DateTime.now().add(const Duration(seconds: 15)),
      enabled: true,
      intervalMinutes: 240,
    );
    result = 'PASS WorkManager check scheduled for about 15 seconds';
  }

  void _openAssignments() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssignmentListScreen(store: store),
      ),
    );
  }

  void _openHealth() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReminderHealthScreen(store: store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ISOLATED NOTIFICATION PROBE')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(result),
          const SizedBox(height: 12),
          Text('accountHash=${store.accountHash ?? '-'}'),
          Text('windowEnabled=${store.backgroundCheckEnabled}'),
          Text('listenerEnabled=${store.notificationListenerEnabled}'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _run(_seedBaseline),
            child: const Text('1. SEED BASELINE'),
          ),
          OutlinedButton(
            onPressed: () => _run(_addTwoNewAssignments),
            child: const Text('2. ADD TWO NEW'),
          ),
          OutlinedButton(
            onPressed: () => _run(_syncDuplicate),
            child: const Text('3. SYNC DUPLICATE'),
          ),
          OutlinedButton(
            onPressed: () => _run(_hideDeadlineAssignment),
            child: const Text('4. HIDE DEADLINE ASSIGNMENT'),
          ),
          OutlinedButton(
            onPressed: () => _run(_resetDeadlineAssignment),
            child: const Text('5. RESET DEADLINE IN 75 SEC'),
          ),
          OutlinedButton(
            onPressed: _openAssignments,
            child: const Text('OPEN ASSIGNMENT LIST'),
          ),
          OutlinedButton(
            onPressed: _openHealth,
            child: const Text('OPEN REMINDER HEALTH'),
          ),
          OutlinedButton(
            onPressed: () => _run(_scheduleWorkSoon),
            child: const Text('6. SCHEDULE WORK IN 15 SEC'),
          ),
        ],
      ),
    );
  }
}

Assignment _assignment(
  String id,
  String title,
  Duration? remaining,
) {
  final deadline = remaining == null ? null : DateTime.now().add(remaining);
  return Assignment(
    id: id,
    courseName: 'QA 通知课程',
    title: title,
    deadlineAt: deadline,
    requirementsText: 'Synthetic offline notification fixture',
    status: 'pending',
    lastSyncedAt: DateTime.now(),
    deadlineTrusted: deadline != null,
  );
}

class _ProbeSessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => _account;

  @override
  Future<String?> readChaoxingPassword() async => 'SYNTHETIC_NOT_A_LOGIN';

  @override
  Future<String?> readChaoxingDisplayName() async => 'QA notification probe';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _QueueClient extends ChaoxingLocalClient {
  List<List<Assignment>> results = const [];

  @override
  bool get needsSessionInitialization => false;

  @override
  Future<List<Assignment>> fetchAssignments() async {
    final batch = results.isEmpty ? <Assignment>[] : results.last;
    succeededCourses = 1;
    failedCourses = 0;
    issues = [];
    lastSyncWarning = null;
    return batch;
  }
}
