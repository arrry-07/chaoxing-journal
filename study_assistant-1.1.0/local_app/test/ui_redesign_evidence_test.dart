import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/login_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_settings_screen.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_dialog.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Store extends AssignmentStore {
  _Store()
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}

void main() {
  testWidgets('redesign candidates include real shell, states and text scaling',
      (t) async {
    await initializeDateFormatting('zh_CN');
    for (final f in ['JournalBody', 'JournalTitle', 'MaterialIcons']) {
      final loader = FontLoader(f)
        ..addFont(rootBundle.load(f == 'MaterialIcons'
            ? 'fonts/MaterialIcons-Regular.otf'
            : 'assets/type/$f.ttf'));
      if (f == 'JournalBody') {
        loader.addFont(rootBundle.load('assets/type/JournalBody-Semibold.ttf'));
      }
      await loader.load();
    }
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final now = DateTime.now();
    Assignment a(int i,
            {String status = 'pending',
            int? days = 1,
            bool trusted = true,
            bool failed = false,
            String? title}) =>
        Assignment(
            id: 'cx:work:1:${i % 2 + 2}:$i',
            courseName: i == 3 ? '样例 · 高等数学2（下）与2026专题课程' : '样例 · 大学物理B（下）',
            title: title ?? '第${i + 1}次课后练习',
            deadlineAt: days == null ? null : now.add(Duration(days: days)),
            requirementsText: '',
            status: status,
            lastSyncedAt: now,
            deadlineTrusted: trusted,
            deadlineReadFailed: failed);
    final root = Directory.current.resolveSymbolicLinksSync();
    final output =
        Directory('$root/../../artifacts/2026-11-05/journal-ui/candidates');
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      output.createSync(recursive: true);
    }
    Future<void> capture(
        String scene, double width, double height, double scale) async {
      final s = _Store();
      final rows = switch (scene) {
        'undated' => [
            for (var i = 0; i < 11; i++)
              a(i,
                  days: null,
                  status: i > 7 ? 'unknown' : 'pending',
                  title: i == 1
                      ? '实验报告：非常长的任务标题含数字2026与符号（第二部分）'
                      : '第${i + 1}次课后练习')
          ],
        'unknown' => [
            a(0, status: 'unknown'),
            a(1, days: null, trusted: false)
          ],
        'empty' || 'failed-empty' || 'stats-empty' => <Assignment>[],
        'stats' ||
        'stats-unknown' ||
        'stats-completed' ||
        'stats-pending' ||
        'stats-tiny' =>
          [
            for (var i = 0; i < (scene == 'stats-tiny' ? 1000 : 31); i++)
              a(i,
                  status: scene == 'stats-completed'
                      ? 'submitted'
                      : scene == 'stats-pending'
                          ? 'pending'
                          : scene == 'stats-tiny'
                              ? (i == 0 ? 'submitted' : 'pending')
                              : scene == 'stats-unknown'
                                  ? 'unknown'
                                  : i < 20
                                      ? 'submitted'
                                      : i < 28
                                          ? 'pending'
                                          : 'unknown')
          ],
        _ => [
            a(0, days: -2),
            a(1, days: 0),
            a(2),
            a(3),
            a(4, days: null),
            a(5, status: 'unknown'),
            a(6, days: 45)
          ]
      };
      s.replaceAssignmentsForTest(rows);
      s.syncReport = SyncReport(
          phase: scene == 'running'
              ? SyncPhase.running
              : scene.startsWith('failed')
                  ? SyncPhase.failed
                  : SyncPhase.success,
          lastDataSuccessAt: scene == 'failed-empty' ? null : now,
          issues: scene.startsWith('failed')
              ? [const SyncIssue(SyncIssueKind.network, 'fixture')]
              : []);
      final route = scene.startsWith('stats')
          ? '/stats'
          : [
              'calendar',
              'profile',
              'detail',
              'login',
              'reminders',
              'sync',
              'dialog'
            ].contains(scene)
              ? '/$scene'
              : '/assignments';
      final router = GoRouter(initialLocation: route, routes: [
        GoRoute(path: '/login', builder: (_, __) => LoginScreen(store: s)),
        ShellRoute(
            builder: (_, __, child) =>
                AppShell(assignmentStore: s, child: child),
            routes: [
              GoRoute(
                  path: '/assignments',
                  builder: (_, __) => AssignmentListScreen(store: s)),
              GoRoute(
                  path: '/stats', builder: (_, __) => StatsScreen(store: s)),
              GoRoute(
                  path: '/calendar',
                  builder: (_, __) => CalendarScreen(store: s)),
              GoRoute(
                  path: '/profile',
                  builder: (_, __) => ProfileScreen(store: s)),
              GoRoute(
                  path: '/detail',
                  builder: (_, __) => AssignmentDetailScreen(
                      store: s, assignmentId: rows.first.id)),
              GoRoute(
                  path: '/reminders',
                  builder: (_, __) =>
                      ReminderSettingsScreen(assignmentStore: s)),
              GoRoute(
                  path: '/sync',
                  builder: (_, __) => SyncStatusScreen(store: s)),
              GoRoute(path: '/dialog', builder: (_, __) => const SizedBox()),
            ])
      ]);
      final boundary = GlobalKey();
      t.view.physicalSize = Size(width, height);
      await t.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: StudyAssistantTheme.light,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                  data: MediaQueryData(
                      size: Size(width, height),
                      padding: const EdgeInsets.only(top: 24, bottom: 16),
                      textScaler: TextScaler.linear(scale)),
                  child: Column(children: [
                    Material(
                        color: const Color(0xFFF7F5EC),
                        child: SizedBox(
                            height: 18 * scale,
                            child: const Center(
                                child: Text('样例数据 · 布局验收',
                                    style: TextStyle(
                                        fontFamily: 'JournalBody',
                                        fontSize: 11,
                                        height: 1.2,
                                        color: Color(0xFF53645A),
                                        decoration: TextDecoration.none))))),
                    Expanded(child: child!)
                  ])))));
      await t.pump(const Duration(milliseconds: 250));
      await t.pump(const Duration(milliseconds: 250));
      if (scene == 'dialog') {
        final context = router.routerDelegate.navigatorKey.currentContext!;
        showDialog<void>(
            context: context,
            builder: (_) => UpdateDialog(service: AppUpdateService()));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull, reason: '$scene $width $scale');
      if (scene == 'mixed' && scale == 1) {
        final cards = find
            .byType(AssignmentCard)
            .evaluate()
            .map((e) => t.getRect(find.byWidget(e.widget)))
            .where((r) => r.bottom < height - 96 && r.top >= 0)
            .length;
        // Restored book heading and dated timeline intentionally use more room
        // than the previous compact toolbar. Keep a complete entry visible on
        // narrow phones and at least two on standard phones.
        expect(cards, greaterThanOrEqualTo(width == 320 ? 1 : 2),
            reason: 'first-screen density $width: $cards');
      }
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/$scene-${width.toInt()}-$scale.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.pumpWidget(const SizedBox());
      router.dispose();
      s.dispose();
    }

    for (final size in [
      const Size(320, 640),
      const Size(360, 800),
      const Size(432, 900)
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final scene in [
          'mixed',
          'undated',
          'unknown',
          'running',
          'failed-empty',
          'failed-cache',
          'empty',
          'stats',
          'stats-empty',
          'stats-unknown',
          'stats-completed',
          'stats-pending',
          'stats-tiny',
          'calendar',
          'profile',
          'detail',
          'login',
          'reminders',
          'sync',
          'dialog'
        ]) {
          await capture(scene, size.width, size.height, scale);
        }
      }
    }
  });
}
