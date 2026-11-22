import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _Session extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-ui-guard';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '手记同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

Future<AssignmentStore> _seededStore(DateTime now) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  FlutterSecureStorage.setMockInitialValues({});
  final store = AssignmentStore(
    sessionStore: _Session(),
    notificationService: _Notifications(),
    widgetSnapshotService: _Snapshot(),
  );
  await store.restoreSession();
  await store.repository.mergeAndSave([
    Assignment(
      id: 'cx:work:1:2:due-today',
      courseName: '数据结构',
      title: '红黑树实验报告',
      deadlineAt: now.add(const Duration(hours: 4)),
      deadlineTrusted: true,
      requirementsText: '提交 PDF 报告与核心代码',
      status: 'pending',
      lastSyncedAt: now,
    ),
    Assignment(
      id: 'cx:work:1:2:overdue',
      courseName: '高等数学',
      title: '定积分练习',
      deadlineAt: now.subtract(const Duration(days: 1)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    ),
    Assignment(
      id: 'cx:work:1:2:done',
      courseName: '大学英语',
      title: 'Unit 4 阅读反思',
      deadlineAt: now.add(const Duration(days: 2)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'submitted',
      lastSyncedAt: now,
    ),
  ]);
  await store.restoreSession();
  return store;
}

Directory _resolveFeaturesDir() {
  final direct = Directory('lib/src/features');
  if (direct.existsSync()) return direct;
  final nested = Directory('study_assistant-1.1.0/local_app/lib/src/features');
  if (nested.existsSync()) return nested;
  throw StateError(
    'Unable to locate lib/src/features from cwd ${Directory.current.path}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wave B-1 UI static design-system contract', () {
    test(
        'features contain zero legacy native pickers, popup menus, or eyebrows',
        () {
      final featuresDir = _resolveFeaturesDir();
      final legacyWidgetRe = RegExp(
        r'\b(?:DropdownButtonFormField|DropdownButton|PopupMenuButton|DropdownMenu|SimpleDialog)\b',
      );
      final eyebrowArgRe = RegExp(r'\beyebrow\s*:');
      final violations = <String>[];

      final dartFiles = featuresDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(dartFiles, isNotEmpty);

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//')) continue;
          if (legacyWidgetRe.hasMatch(trimmed)) {
            violations.add('${file.path}:${i + 1} legacy widget: $trimmed');
          }
          if (eyebrowArgRe.hasMatch(trimmed)) {
            violations
                .add('${file.path}:${i + 1} eyebrow regression: $trimmed');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'UI design-system static contract violated:\n'
            '${violations.join('\n')}',
      );
    });

    test('light and dark themes expose distinct Journal tokens and WenKai', () {
      final light = StudyAssistantTheme.light.extension<JournalPalette>();
      final dark = StudyAssistantTheme.dark.extension<JournalPalette>();
      expect(light, isNotNull);
      expect(dark, isNotNull);
      expect(light!.paper, isNot(equals(dark!.paper)));
      expect(light.sheet, isNot(equals(dark.sheet)));
      expect(light.ink, isNot(equals(dark.ink)));
      expect(Journal.titleFamily, 'LXGW WenKai Screen');
      expect(Journal.bodyFamily, 'LXGW WenKai Screen');
      expect(StudyAssistantTheme.light.textTheme.bodyMedium?.fontFamily,
          Journal.bodyFamily);
      expect(StudyAssistantTheme.dark.textTheme.bodyMedium?.fontFamily,
          Journal.bodyFamily);
    });
  });

  group('Wave B-1 dual-theme smoke rendering', () {
    final fixedNow = DateTime(2026, 11, 22, 10, 0);

    for (final mode in <({String name, ThemeData theme})>[
      (name: 'light', theme: StudyAssistantTheme.light),
      (name: 'dark', theme: StudyAssistantTheme.dark),
    ]) {
      testWidgets(
        'primary tabs and AppShell render cleanly in ${mode.name} theme',
        (tester) async {
          await initializeDateFormatting('zh_CN');
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final store = await _seededStore(fixedNow);
          addTearDown(store.dispose);
          final expectedJournal = mode.theme.extension<JournalPalette>()!;

          final pages = <({String title, Widget child})>[
            (
              title: '课业手记',
              child: AssignmentListScreen(store: store, clock: () => fixedNow),
            ),
            (
              title: '课业日历',
              child: CalendarScreen(store: store, clock: () => fixedNow),
            ),
            (
              title: '课业统计',
              child: StatsScreen(store: store, clock: () => fixedNow),
            ),
            (
              title: '我的手帐',
              child: ProfileScreen(store: store),
            ),
          ];

          for (final page in pages) {
            await tester.pumpWidget(
              MaterialApp(
                theme: mode.theme,
                home: Scaffold(body: page.child),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '${page.title} threw in ${mode.name}');
            expect(find.text(page.title), findsOneWidget,
                reason: '${page.title} missing in ${mode.name}');
            final ctx = tester.element(find.text(page.title));
            expect(Journal.of(ctx).paper, expectedJournal.paper,
                reason: '${page.title} paper token mismatch in ${mode.name}');
          }

          final router = GoRouter(
            initialLocation: '/assignments',
            routes: [
              ShellRoute(
                builder: (_, __, child) =>
                    AppShell(assignmentStore: store, child: child),
                routes: [
                  GoRoute(
                    path: '/assignments',
                    builder: (_, __) => AssignmentListScreen(
                      store: store,
                      clock: () => fixedNow,
                    ),
                  ),
                ],
              ),
            ],
          );
          addTearDown(router.dispose);

          await tester.pumpWidget(
            MaterialApp.router(
              theme: mode.theme,
              routerConfig: router,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'AppShell threw in ${mode.name}');
          for (final tab in ['首页', '日历', '统计', '我的']) {
            expect(find.text(tab), findsOneWidget,
                reason: 'Floating nav tab $tab missing in ${mode.name}');
          }
        },
      );
    }
  });
}
