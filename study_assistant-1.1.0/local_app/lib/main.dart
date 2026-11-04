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
import 'src/features/assignment_detail_screen.dart';
import 'src/features/assignment_list_screen.dart';
import 'src/features/calendar_screen.dart';
import 'src/features/login_screen.dart';
import 'src/features/profile_screen.dart';
import 'src/features/reminder_settings_screen.dart';
import 'src/features/stats_screen.dart';
import 'src/features/sync_status_screen.dart';
import 'src/services/app_update_service.dart';
import 'src/features/widgets/update_dialog.dart';
import 'src/app/app_version.dart';
import 'src/services/assignment_store.dart';
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
      '中文宋体标题': 'assets/type/OFL.txt',
      '中文正文字体': 'assets/type/OFL-Sans.txt',
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
  );

  await notificationService.initializeSafely();
  await assignmentStore.restoreSession();

  runApp(StudyAssistantApp(
    assignmentStore: assignmentStore,
    notificationService: notificationService,
  ));
}

class StudyAssistantApp extends StatefulWidget {
  const StudyAssistantApp({
    super.key,
    required this.assignmentStore,
    required this.notificationService,
  });

  final AssignmentStore assignmentStore;
  final LocalNotificationService notificationService;

  @override
  State<StudyAssistantApp> createState() => _StudyAssistantAppState();
}

class _StudyAssistantAppState extends State<StudyAssistantApp> {
  AssignmentStore get assignmentStore => widget.assignmentStore;
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter();
    widget.notificationService.setPayloadHandler(_handleNotificationPayload);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkUpdateOnStartup());
  }

  Future<void> _checkUpdateOnStartup() async {
    const manifest = String.fromEnvironment('UPDATE_MANIFEST_URL');
    if (manifest.isEmpty) return;
    final r = await AppUpdateService()
        .checkConfigured(currentVersionCode: AppVersion.code);
    final c = _navigatorKey.currentContext;
    if (mounted &&
        c != null &&
        c.mounted &&
        r.status == UpdateCheckStatus.available) {
      await showDialog<void>(
          context: c,
          builder: (_) => UpdateDialog(service: AppUpdateService()));
    }
  }

  @override
  void dispose() {
    _router.dispose();
    widget.notificationService.setPayloadHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '学习通课业手记',
      debugShowCheckedModeBanner: false,
      theme: StudyAssistantTheme.light,
      routerConfig: _router,
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
          ),
        ),
        ShellRoute(
          builder: (_, __, child) => AppShell(
            assignmentStore: assignmentStore,
            child: child,
          ),
          routes: [
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
          return '/login';
        }
        if (loggedIn && loggingIn && state.uri.queryParameters['reauth'] != '1') {
          return '/assignments';
        }
        return null;
      },
    );
  }

  void _handleNotificationPayload(String payload) {
    final location = AppDeepLinks.normalizeIncomingLocation(
      Uri.parse(payload),
    );
    if (location != null) {
      _router.go(location);
    }
  }
}
