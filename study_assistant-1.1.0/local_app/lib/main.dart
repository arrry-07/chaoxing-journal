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
import 'src/services/external_link_service.dart';
import 'src/app/app_version.dart';
import 'src/services/assignment_store.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/reminder_rule_store.dart';
import 'src/services/secure_session_store.dart';
import 'src/services/widget_snapshot_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdateOnStartup());
  }

  Future<void> _checkUpdateOnStartup() async {
    debugPrint('[UpdateCheck] _checkUpdateOnStartup START, version=${AppVersion.name}');
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        debugPrint('[UpdateCheck] Attempt $attempt...');
        final update = await AppUpdateService().checkForUpdate(
          currentVersionName: AppVersion.name,
          currentVersionCode: AppVersion.code,
        );
        debugPrint('[UpdateCheck] checkForUpdate result: $update');
        if (update == null || !mounted) return;
        // Use postFrameCallback to ensure Navigator is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showUpdateDialog(update);
        });
        return;
      } catch (e, stack) {
        debugPrint('[UpdateCheck] Attempt $attempt failed: $e');
        debugPrint('[UpdateCheck] Stack: $stack');
        if (attempt < 1) {
          await Future.delayed(const Duration(seconds: 3));
        }
      }
    }
  }

  void _showUpdateDialog(AppUpdateInfo update) {
    if (!mounted) return;
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;
    showDialog<void>(
      context: navigatorContext,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('v${update.versionName} 已发布，是否更新？\n\n${update.releaseNotes}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _downloadAndInstall(update);
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall(AppUpdateInfo update) async {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;

    showDialog<void>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogCtx) {
        var started = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            var received = 0;
            var total = 0;
            var done = false;
            var error = false;

            if (!started) {
              started = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _doDownload(
                  update: update,
                  onProgress: (r, t) {
                    if (ctx.mounted) {
                      setDialogState(() { received = r; total = t; });
                    }
                  },
                  onDone: () {
                    if (ctx.mounted) {
                      setDialogState(() => done = true);
                      try { Navigator.of(ctx).pop(); } catch (_) {}
                    }
                  },
                  onError: () {
                    if (ctx.mounted) {
                      setDialogState(() => error = true);
                    }
                  },
                );
              });
            }

            return AlertDialog(
              title: Text(error ? '\u4e0b\u8f7d\u5931\u8d25' : (done ? '\u4e0b\u8f7d\u5b8c\u6210' : '\u6b63\u5728\u4e0b\u8f7d\u66f4\u65b0\u5305...')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!error && !done) ...[
                    LinearProgressIndicator(
                      value: total > 0 ? received / total : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      total > 0
                          ? '${(received * 100 / total).toStringAsFixed(0)}%'
                          : '\u8fde\u63a5\u4e2d...',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  if (error) const Text('\u4e0b\u8f7d\u66f4\u65b0\u5305\u5931\u8d25\uff0c\u8bf7\u7a0d\u540e\u518d\u8bd5'),
                ],
              ),
              actions: error
                  ? [
                      TextButton(
                        onPressed: () { try { Navigator.of(ctx).pop(); } catch (_) {} },
                        child: const Text('\u5173\u95ed'),
                      ),
                    ]
                  : null,
            );
          },
        );
      },
    );
  }

  Future<void> _doDownload({
    required AppUpdateInfo update,
    required void Function(int, int) onProgress,
    required void Function() onDone,
    required void Function() onError,
  }) async {
    try {
      final file = await AppUpdateService().downloadApk(update, onProgress: onProgress);
      onDone();
      final success = await ExternalLinkService().installApk(file.path);
      final mc = _navigatorKey.currentContext;
      if (!success && mc != null && mc.mounted) {
        ScaffoldMessenger.of(mc).showSnackBar(
          const SnackBar(content: Text('\u65e0\u6cd5\u6253\u5f00\u7cfb\u7edf\u5b89\u88c5\u5668')),
        );
      }
    } catch (_) {
      onError();
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
      title: '课业手记',
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
        if (loggedIn && loggingIn) {
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
