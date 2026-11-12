import 'dart:async';

import 'src/services/app_update_controller.dart';
import 'src/features/assignment_changes_screen.dart';
import 'src/features/backup_screen.dart';
import 'src/features/daily_plan_screen.dart';
import 'src/features/manual_agenda_screen.dart';
import 'src/features/term_archives_screen.dart';
import 'src/features/personal_work_screen.dart';
import 'src/features/reminder_health_screen.dart';
import 'src/features/widgets/update_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'src/features/help_feedback_screen.dart';
import 'src/features/local_records_screen.dart';
import 'src/features/course_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'src/app/app_deep_links.dart';
import 'src/app/app_shell.dart';
import 'src/app/unsaved_edit_guard.dart';
import 'src/features/assignment_detail_screen.dart';
import 'src/features/assignment_list_screen.dart';
import 'src/features/calendar_screen.dart';
import 'src/features/login_screen.dart';
import 'src/features/profile_screen.dart';
import 'src/features/reminder_settings_screen.dart';
import 'src/features/stats_screen.dart';
import 'src/features/sync_status_screen.dart';
import 'src/features/widgets/update_dialog.dart';
import 'src/services/assignment_store.dart';
import 'src/services/background_reminder_gateway.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/reminder_rule_store.dart';
import 'src/services/secure_session_store.dart';
import 'src/services/widget_snapshot_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'HY': 'assets/licenses/HY.txt',
      'xuexitong-cli': 'assets/licenses/xuexitong-cli.txt',
      'LXGW WenKai Screen / 霞鹜文楷': 'assets/type/OFL-WenKai.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks(
          [entry.key], await rootBundle.loadString(entry.value));
    }
  });
  await initializeDateFormatting('zh_CN');

  final sessionStore = SecureSessionStore();
  final notificationService = LocalNotificationService();
  final widgetSnapshotService = WidgetSnapshotService();
  final reminderRuleStore = ReminderRuleStore();

  final assignmentStore = AssignmentStore(
    sessionStore: sessionStore,
    notificationService: notificationService,
    widgetSnapshotService: widgetSnapshotService,
    reminderRuleStore: reminderRuleStore,
    nativeReminderDeliveryEnabled: true,
  );

  await notificationService.initializeSafely();
  await assignmentStore.restoreSession();

  runApp(StudyAssistantApp(
    assignmentStore: assignmentStore,
    notificationService: notificationService,
  ));
}

@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('study_assistant/background_worker');
  AssignmentStore? activeStore;
  var cancelled = false;

  Future<void> run(Map<Object?, Object?> arguments) async {
    await initializeDateFormatting('zh_CN');
    final notificationService = LocalNotificationService();
    final store = AssignmentStore(
      sessionStore: SecureSessionStore(),
      notificationService: notificationService,
      widgetSnapshotService: WidgetSnapshotService(),
      reminderRuleStore: ReminderRuleStore(),
      manageBackgroundSchedule: false,
      nativeLeaseOwner: arguments['leaseOwner'] as String?,
      nativeReminderDeliveryEnabled: true,
    );
    activeStore = store;
    try {
      await store.restoreSession();
      if (cancelled) return;
      final expectedAccount = arguments['accountHash'] as String?;
      if (expectedAccount != null && expectedAccount != store.accountHash) {
        await channel.invokeMethod<void>('finished', {
          'success': false,
          'skipped': true,
          'nextTargetAt': null,
          'message': '后台任务所属账号已变化，已拒绝旧账号结果',
        });
        return;
      }
      final reason = arguments['reason'] as String?;
      final trigger = switch (reason) {
        'daytime' => BackgroundSyncTrigger.daytime,
        'notification_signal' => BackgroundSyncTrigger.notificationSignal,
        _ => BackgroundSyncTrigger.daytime,
      };
      final result = await store.runBackgroundAutomaticCheck(trigger);
      if (cancelled) return;
      await channel.invokeMethod<void>('finished', {
        'success': result.success,
        'skipped': result.skipped,
        'nextTargetAt': result.nextTargetAt?.millisecondsSinceEpoch,
        'message': result.message,
      });
    } catch (error) {
      if (!cancelled) {
        await channel.invokeMethod<void>('finished', {
          'success': false,
          'skipped': false,
          'nextTargetAt': null,
          'message': error.toString(),
        });
      }
    } finally {
      activeStore = null;
      store.dispose();
    }
  }

  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'run':
        final arguments =
            (call.arguments as Map<Object?, Object?>?) ?? const {};
        unawaited(run(arguments));
        return null;
      case 'cancel':
        cancelled = true;
        activeStore?.chaoxingClient.cancelActiveRequests();
        return null;
      default:
        throw MissingPluginException('未知后台任务 ${call.method}');
    }
  });
  await channel.invokeMethod<void>('ready');
}

class StudyAssistantApp extends StatefulWidget {
  const StudyAssistantApp({
    super.key,
    required this.assignmentStore,
    required this.notificationService,
    this.updateController,
  });

  final AssignmentStore assignmentStore;
  final LocalNotificationService notificationService;
  final AppUpdateController? updateController;

  @override
  State<StudyAssistantApp> createState() => _StudyAssistantAppState();
}

class _StudyAssistantAppState extends State<StudyAssistantApp>
    with WidgetsBindingObserver {
  AssignmentStore get assignmentStore => widget.assignmentStore;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _leaveGuard = UnsavedEditGuard();
  late final GoRouter _router;
  late final AppUpdateController _updates;
  bool _pendingUpdatePrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates = widget.updateController ?? AppUpdateController();
    _router = _buildRouter();
    widget.notificationService.setPayloadHandler(_handleNotificationPayload);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkUpdateOnStartup());
  }

  Future<void> _checkUpdateOnStartup() async {
    _pendingUpdatePrompt = await _updates.checkOnStartup();
    _showPendingUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _showPendingUpdate();
  }

  void _showPendingUpdate() {
    if (!mounted || !_pendingUpdatePrompt) return;
    if (_updates.hasShownDialog) {
      _pendingUpdatePrompt = false;
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final c = _navigatorKey.currentContext;
    if (c != null && c.mounted && _updates.phase == UpdatePhase.available) {
      _pendingUpdatePrompt = false;
      showUpdateDialog(c, _updates);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.updateController == null) _updates.dispose();
    _router.dispose();
    widget.notificationService.setPayloadHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedEditGuardScope(
      guard: _leaveGuard,
      child: AppUpdateScope(
          controller: _updates,
          child: MaterialApp.router(
            title: '学习通课业手记',
            debugShowCheckedModeBanner: false,
            theme: StudyAssistantTheme.light,
            routerConfig: _router,
          )),
    );
  }

  GoRouter _buildRouter() {
    return GoRouter(
      navigatorKey: _navigatorKey,
      refreshListenable: assignmentStore,
      initialLocation:
          assignmentStore.isAuthenticated ? '/assignments' : '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, state) => LoginScreen(
            store: assignmentStore,
            returnTo: state.uri.queryParameters['from'],
          ),
        ),
        ShellRoute(
          builder: (_, __, child) => AppShell(
            assignmentStore: assignmentStore,
            leaveGuard: _leaveGuard,
            child: child,
          ),
          routes: [
            GoRoute(
                path: '/agenda',
                onExit: (_, __) => _leaveGuard.confirmLeave(),
                builder: (_, __) => ManualAgendaScreen(store: assignmentStore)),
            GoRoute(
                path: '/terms',
                builder: (_, __) => TermArchivesScreen(store: assignmentStore)),
            GoRoute(
                path: '/plan',
                builder: (_, __) => DailyPlanScreen(store: assignmentStore)),
            GoRoute(
                path: '/personal/:id',
                onExit: (_, __) => _leaveGuard.confirmLeave(),
                builder: (_, s) => PersonalWorkScreen(
                    store: assignmentStore,
                    assignmentId: s.pathParameters['id']!)),
            GoRoute(
                path: '/reminder-health',
                builder: (_, __) =>
                    ReminderHealthScreen(store: assignmentStore)),
            GoRoute(
                path: '/changes',
                builder: (_, __) =>
                    AssignmentChangesScreen(store: assignmentStore)),
            GoRoute(
                path: '/backup',
                builder: (_, __) => BackupScreen(store: assignmentStore)),
            GoRoute(
              path: '/assignments',
              builder: (_, __) => AssignmentListScreen(store: assignmentStore),
            ),
            GoRoute(
              path: '/assignments/:id',
              builder: (_, state) => AssignmentDetailScreen(
                store: assignmentStore,
                assignmentId: state.pathParameters['id']!,
              ),
            ),
            GoRoute(
              path: '/calendar',
              builder: (_, __) => CalendarScreen(store: assignmentStore),
            ),
            GoRoute(
              path: '/stats',
              builder: (_, __) => StatsScreen(store: assignmentStore),
            ),
            GoRoute(
              path: '/sync',
              builder: (_, __) => SyncStatusScreen(store: assignmentStore),
            ),
            GoRoute(
              path: '/reminders',
              onExit: (_, __) => _leaveGuard.confirmLeave(),
              builder: (_, __) => ReminderSettingsScreen(
                assignmentStore: assignmentStore,
              ),
            ),
            GoRoute(
                path: '/help', builder: (_, __) => const HelpFeedbackScreen()),
            GoRoute(
                path: '/records',
                builder: (_, __) => LocalRecordsScreen(store: assignmentStore)),
            GoRoute(
                path: '/courses',
                builder: (_, __) => CourseListScreen(store: assignmentStore)),
            GoRoute(
              path: '/profile',
              builder: (_, __) => ProfileScreen(store: assignmentStore),
            ),
          ],
        ),
      ],
      redirect: (_, state) {
        final normalizedLocation =
            AppDeepLinks.normalizeIncomingLocation(state.uri);
        if (normalizedLocation != null) {
          return normalizedLocation;
        }

        final loggedIn = assignmentStore.isAuthenticated;
        final loggingIn = state.matchedLocation == '/login';
        if (!loggedIn && !loggingIn) {
          final target =
              AppDeepLinks.validatedAssignmentLocation(state.uri.toString());
          return target == null
              ? '/login'
              : Uri(path: '/login', queryParameters: {'from': target})
                  .toString();
        }
        if (loggedIn &&
            loggingIn &&
            state.uri.queryParameters['reauth'] != '1') {
          return loginSuccessLocation(state.uri.queryParameters['from']);
        }
        return null;
      },
    );
  }

  void _handleNotificationPayload(String payload) {
    unawaited(_navigateForNotification(payload));
  }

  Future<void> _navigateForNotification(String payload) async {
    final String? location;
    if (payload.startsWith('p:')) {
      location = '/agenda';
    } else if (payload == 'd:summary') {
      location = '/assignments';
    } else {
      final uri = Uri.tryParse(payload);
      location =
          uri == null ? null : AppDeepLinks.normalizeIncomingLocation(uri);
    }
    if (location == null) return;
    // A dirty editor must not be replaced by a notification deep link without
    // the same confirmation used for back navigation.
    if (!await _leaveGuard.confirmLeave()) return;
    if (!mounted) return;
    _router.go(location);
  }
}
