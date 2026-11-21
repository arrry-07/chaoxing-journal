import 'dart:async';

import 'src/services/app_update_controller.dart';
import 'src/features/assignment_changes_screen.dart';
import 'src/features/backup_screen.dart';
import 'src/features/course_study_hub_screen.dart';
import 'src/features/daily_plan_screen.dart';
import 'src/features/manual_agenda_screen.dart';
import 'src/features/term_archives_screen.dart';
import 'src/features/personal_work_screen.dart';
import 'src/features/profile_arrangements_screen.dart';
import 'src/features/profile_records_screen.dart';
import 'src/features/reminder_health_screen.dart';
import 'src/features/reminder_history_screen.dart';
import 'src/features/reminder_status_screen.dart';
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
import 'src/app/journal_binding.dart';
import 'src/app/transient_feedback.dart';
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
import 'src/models/display_preferences.dart';
import 'src/services/assignment_store.dart';
import 'src/services/background_reminder_gateway.dart';
import 'src/services/interaction_feedback_service.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/local_record_query.dart';
import 'src/services/reminder_rule_store.dart';
import 'src/services/secure_session_store.dart';
import 'src/services/widget_snapshot_service.dart';

Future<void> main() async {
  JournalBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'HY': 'assets/licenses/HY.txt',
      'lpinyin': 'assets/licenses/lpinyin.txt',
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
    reminderHistoryEnabled: true,
    nativeReminderDeliveryEnabled: true,
  );
  InteractionFeedback.systemClickPrefs = () => assignmentStore.display;

  await notificationService.initializeSafely();
  await launchRestoredApp(assignmentStore, () {
    runApp(StudyAssistantApp(
      assignmentStore: assignmentStore,
      notificationService: notificationService,
    ));
  });
}

/// Notification navigation must not observe an empty, unrestored snapshot.
/// Keep this ordering shared by production startup and its gated regression.
Future<void> launchRestoredApp(
    AssignmentStore store, VoidCallback launch) async {
  await store.restoreSession();
  launch();
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
    final expectedAccount = arguments['accountHash'] as String?;
    final expectedEpoch = (arguments['sessionEpoch'] as num?)?.toInt();
    final claimToken = arguments['claimToken'] as String?;
    final workerId = arguments['workerId'] as String?;
    final remoteStart = expectedAccount != null &&
            expectedEpoch != null &&
            expectedEpoch > 0 &&
            claimToken != null &&
            claimToken.isNotEmpty &&
            workerId != null &&
            workerId.isNotEmpty
        ? NotificationRemoteStartContext(
            accountHash: expectedAccount,
            sessionEpoch: expectedEpoch,
            claimToken: claimToken,
            workerId: workerId,
          )
        : null;
    final store = AssignmentStore(
      sessionStore: SecureSessionStore(),
      notificationService: notificationService,
      widgetSnapshotService: WidgetSnapshotService(),
      reminderRuleStore: ReminderRuleStore(),
      manageBackgroundSchedule: false,
      nativeLeaseOwner: arguments['leaseOwner'] as String?,
      notificationRemoteStart: remoteStart,
      backgroundSignalVersion: (arguments['signalVersion'] as num?)?.toInt(),
      reminderHistoryEnabled: true,
      nativeReminderDeliveryEnabled: true,
    );
    activeStore = store;
    try {
      await store.restoreSession();
      if (cancelled) return;
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
        'skipReason': result.skipReason,
        'remoteReadInvoked': result.remoteReadInvoked,
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
        activeStore?.cancelSynchronization();
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
  final _notificationFeedback = TransientFeedbackController();
  late final GoRouter _router;
  late final AppUpdateController _updates;
  bool _pendingUpdatePrompt = false;
  bool _notificationRouterReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates = widget.updateController ?? AppUpdateController();
    _router = _buildRouter();
    widget.notificationService.setPayloadHandler(_handleNotificationPayload);
    _lastAuthenticated = assignmentStore.isAuthenticated;
    _lastAccountEpoch = assignmentStore.accountEpoch;
    _lastAccountHash = assignmentStore.accountHash;
    _themeMode = assignmentStore.display.themeMode;
    assignmentStore.addListener(_handleStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notificationRouterReady = true;
      _checkUpdateOnStartup();
    });
  }

  late JournalThemeMode _themeMode;
  bool _lastAuthenticated = false;
  int _lastAccountEpoch = 0;
  String? _lastAccountHash;

  void _handleStoreChanged() {
    final mode = assignmentStore.display.themeMode;
    if (_themeMode != mode) setState(() => _themeMode = mode);
    _handleStoreIdentityChanged();
  }

  /// Account replacement must invalidate the old dialog/approval before a new
  /// page can inherit it. Other store notifications leave the guard alone.
  void _handleStoreIdentityChanged() {
    final authenticated = assignmentStore.isAuthenticated;
    final epoch = assignmentStore.accountEpoch;
    final accountHash = assignmentStore.accountHash;
    if (authenticated == _lastAuthenticated &&
        epoch == _lastAccountEpoch &&
        accountHash == _lastAccountHash) {
      return;
    }
    _lastAuthenticated = authenticated;
    _lastAccountEpoch = epoch;
    _lastAccountHash = accountHash;
    _leaveGuard.invalidate();
    _notificationFeedback.dismiss();
    // A private editor belongs to the old identity. Leaving it mounted after
    // an in-place account restore would let edits appear to belong to the new
    // account even though the page is stale.
    if (authenticated) {
      final location = _router.routeInformationProvider.value.uri.path;
      if (location.startsWith('/personal/') ||
          location == '/agenda' ||
          location == '/reminders' ||
          location.startsWith('/reminder-history') ||
          location.startsWith('/reminder-status/')) {
        _router.go('/assignments');
      }
    }
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
    assignmentStore.removeListener(_handleStoreChanged);
    _notificationFeedback.dispose();
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
            darkTheme: StudyAssistantTheme.dark,
            themeAnimationDuration: Duration.zero,
            themeMode: switch (_themeMode) {
              JournalThemeMode.system => ThemeMode.system,
              JournalThemeMode.light => ThemeMode.light,
              JournalThemeMode.dark => ThemeMode.dark,
            },
            routerConfig: _router,
          )),
    );
  }

  GoRouter _buildRouter() {
    final platformUri = Uri.tryParse(
        WidgetsBinding.instance.platformDispatcher.defaultRouteName);
    final ownedInitialLink =
        platformUri != null && AppDeepLinks.isOwnedNotificationUri(platformUri);
    return GoRouter(
      navigatorKey: _navigatorKey,
      refreshListenable: assignmentStore,
      // go_router 14.8.1 _effectiveInitialLocation rebuilds an empty-path
      // platform URI as Uri(path: '/', queryParameters: {}). That loses the
      // scheme/host of native digest links and yields '/?' before redirect.
      // Preserve only recognized app links here; ordinary errors stay errors.
      overridePlatformDefaultLocation: ownedInitialLink,
      initialLocation: ownedInitialLink
          ? _notificationTarget(platformUri.toString())
          : assignmentStore.isAuthenticated
              ? '/assignments'
              : '/login',
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
                onExit: (_, __) =>
                    _leaveGuard.confirmLeave(routeScope: '/agenda'),
                builder: (_, __) => ManualAgendaScreen(store: assignmentStore)),
            GoRoute(
                path: '/terms',
                builder: (_, __) => TermArchivesScreen(store: assignmentStore)),
            GoRoute(
                path: '/plan',
                builder: (_, __) => DailyPlanScreen(store: assignmentStore)),
            GoRoute(
                path: '/personal/:id',
                onExit: (_, __) =>
                    _leaveGuard.confirmLeave(routeScope: '/personal'),
                builder: (_, s) => PersonalWorkScreen(
                    store: assignmentStore,
                    assignmentId: s.pathParameters['id']!)),
            GoRoute(
                path: '/reminder-health',
                builder: (_, __) =>
                    ReminderHealthScreen(store: assignmentStore)),
            GoRoute(
                path: '/reminder-history',
                builder: (_, __) =>
                    ReminderHistoryScreen(store: assignmentStore)),
            GoRoute(
              path: '/reminder-status/:kind/:id',
              builder: (_, state) => ReminderStatusScreen(
                store: assignmentStore,
                kind: state.pathParameters['kind']!,
                id: state.pathParameters['id']!,
                hasUnsavedEdits: state.uri.queryParameters['unsaved'] == '1',
              ),
            ),
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
              builder: (_, state) => SyncStatusScreen(
                store: assignmentStore,
                expandIssues: state.uri.queryParameters['expand'] == 'issues',
              ),
            ),
            GoRoute(
              path: '/reminders',
              onExit: (_, __) =>
                  _leaveGuard.confirmLeave(routeScope: '/reminders'),
              builder: (_, __) => ReminderSettingsScreen(
                assignmentStore: assignmentStore,
              ),
            ),
            GoRoute(
                path: '/help', builder: (_, __) => const HelpFeedbackScreen()),
            GoRoute(
              path: '/records',
              builder: (_, state) => LocalRecordsScreen(
                store: assignmentStore,
                initialFilter: LocalRecordFilterSpec.fromQueryParameters(
                  state.uri.queryParameters,
                ),
              ),
            ),
            GoRoute(
                path: '/courses',
                builder: (_, __) => CourseListScreen(store: assignmentStore)),
            GoRoute(
              path: '/profile',
              builder: (_, __) => ProfileScreen(store: assignmentStore),
            ),
            GoRoute(
              path: '/profile/arrangements',
              builder: (_, __) =>
                  ProfileArrangementsScreen(store: assignmentStore),
            ),
            GoRoute(
              path: '/profile/records',
              builder: (_, __) => ProfileRecordsScreen(store: assignmentStore),
            ),
            GoRoute(
              path: '/course-hub',
              builder: (_, state) => CourseStudyHubScreen(
                store: assignmentStore,
                initialTab: state.uri.queryParameters['tab'],
                initialCourseKey: state.uri.queryParameters['courseKey'],
              ),
            ),
          ],
        ),
      ],
      redirect: (_, state) {
        // Only owned external links use notification recovery. Internal
        // routing failures keep go_router's normal error page and diagnosis.
        if (AppDeepLinks.isOwnedNotificationUri(state.uri)) {
          return _notificationTarget(state.uri.toString());
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

  String _notificationTarget(String payload) {
    var missing = false;
    final target =
        AppDeepLinks.notificationLocation(payload, containsAssignment: (id) {
      final exists = assignmentStore.findAssignment(id) != null;
      missing = !exists;
      return exists;
    });
    if (missing) {
      debugPrint(
          '[NotificationRoute] assignment_missing_from_current_snapshot');
      final epoch = assignmentStore.accountEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != assignmentStore.accountEpoch) return;
        final context = _navigatorKey.currentContext;
        if (context != null) {
          _notificationFeedback.show(
              context, const SnackBar(content: Text('通知对应的课业暂不可用，已返回课业列表')));
        }
      });
    }
    return target;
  }

  Future<void> _navigateForNotification(String payload) async {
    final epoch = assignmentStore.accountEpoch;
    // Only a cached click delivered during initState needs the first frame.
    // Warm clicks must enter the shared guard immediately: delaying them a
    // frame would let older notifications supersede a newer tab selection.
    if (!_notificationRouterReady) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || assignmentStore.accountEpoch != epoch) return;
    final target = _notificationTarget(payload);
    // A notification for the current route must not ask to discard a draft or
    // approve a future exit; a later different destination asks normally.
    if (_router.routeInformationProvider.value.uri.path == target) return;
    // A dirty editor must not be replaced by a notification deep link without
    // the same confirmation used for back navigation. `navigate` also makes
    // concurrent notifications/tabs resolve to one winning destination.
    await _leaveGuard.navigate(
      isCurrent: () => mounted && assignmentStore.accountEpoch == epoch,
      // A same-account sync can remove the record while the discard dialog
      // is open. Resolve again at commit, without delaying guard ordering.
      action: () => _router.go(_notificationTarget(payload)),
    );
  }
}
