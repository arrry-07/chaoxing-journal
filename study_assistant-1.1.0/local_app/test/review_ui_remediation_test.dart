import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/agreement_screen.dart';
import 'package:study_assistant_mobile/src/features/login_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/reminder_settings_screen.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/reminder_rule_store.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'auto_sync_interval_minutes': 0,
      }));

  testWidgets('login requires active consent and exposes a labeled checkbox',
      (t) async {
    final s = _store();
    addTearDown(s.dispose);
    final semantics = t.ensureSemantics();
    await t.pumpWidget(MaterialApp(home: LoginScreen(store: s)));
    await t.enterText(find.byType(TextField).first, 'synthetic-student');
    await t.enterText(find.byType(TextField).last, 'synthetic-password');
    await t.pump();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    final checkbox = find.byType(Checkbox);
    await t.ensureVisible(checkbox);
    expect(t.getSize(checkbox).width, greaterThanOrEqualTo(48));
    expect(t.getSize(checkbox).height, greaterThanOrEqualTo(48));
    expect(
        t.getSemantics(checkbox),
        matchesSemantics(
          label: '我已阅读并同意服务协议和隐私协议',
          hasCheckedState: true,
          isChecked: false,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ));
    await t.tap(checkbox);
    await t.pump();
    expect(t.widget<Checkbox>(checkbox).value, isTrue);
    expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    semantics.dispose();
  });

  testWidgets('both agreement buttons open readable content and preserve input',
      (t) async {
    final s = _store();
    addTearDown(s.dispose);
    await t.pumpWidget(MaterialApp(home: LoginScreen(store: s)));
    await t.enterText(find.byType(TextField).first, 'synthetic-student');
    await t.enterText(find.byType(TextField).last, 'synthetic-password');
    for (final label in ['服务协议', '隐私协议']) {
      final entry = find.widgetWithText(TextButton, label);
      expect(entry, findsOneWidget);
      await t.ensureVisible(entry);
      await t.tap(entry);
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, label), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField).first).controller!.text,
          'synthetic-student');
      expect(t.widget<TextField>(find.byType(TextField).last).controller!.text,
          'synthetic-password');
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    }
  });

  testWidgets('canceling logout preserves the account and local records',
      (t) async {
    final s = _store();
    addTearDown(s.dispose);
    await s.repository.mergeAndSave([_assignment]);
    await s.restoreSession();
    await t
        .pumpWidget(MaterialApp(home: Scaffold(body: ProfileScreen(store: s))));
    await t.scrollUntilVisible(find.text('退出登录'), 400);
    await t.pumpAndSettle();
    await t.tap(find.text('退出登录'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('隐藏状态'), findsOneWidget);
    expect(find.textContaining('提醒设置'), findsWidgets);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(s.isAuthenticated, isTrue);
    expect((await s.repository.loadJournal()).single.id, _assignment.id);
  });

  testWidgets('failed logout stays signed in and gives retry feedback',
      (t) async {
    final s = _store(session: _Session(failClear: true));
    addTearDown(s.dispose);
    await s.restoreSession();
    await t
        .pumpWidget(MaterialApp(home: Scaffold(body: ProfileScreen(store: s))));
    await t.scrollUntilVisible(find.text('退出登录'), 400);
    await t.pumpAndSettle();
    await t.tap(find.text('退出登录'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('确认退出'));
    await t.pumpAndSettle();
    expect(s.isAuthenticated, isTrue);
    expect(find.textContaining('退出未完成'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('failed reminder save preserves selection and allows retry',
      (t) async {
    final s = _store(rules: _FailOnceRuleStore());
    addTearDown(s.dispose);
    await s.restoreSession();
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ReminderSettingsScreen(assignmentStore: s),
    )));
    await t.ensureVisible(find.text('添加'));
    await t.enterText(find.byType(TextField).last, '45');
    await t.tap(find.text('添加'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('保存提醒规则'));
    await t.tap(find.text('保存提醒规则'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('提前 45 分钟'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, '保存提醒规则');
    expect(t.widget<FilledButton>(button).onPressed, isNotNull);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(s.reminderOffsetsMinutes, contains(45));
    expect(find.text('提醒时间已保存，作业通知已更新'), findsOneWidget);
  });

  testWidgets('auto sync exposes exactly one selected option in a radio group',
      (t) async {
    final s = _store();
    addTearDown(s.dispose);
    await s.restoreSession();
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: SyncStatusScreen(store: s))));
    final off = find.byKey(const ValueKey('auto-sync-option-off'));
    final fifteen = find.byKey(const ValueKey('auto-sync-option-15'));
    expect(t.getSemantics(off).flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(t.getSemantics(fifteen).flagsCollection.isSelected,
        ui.Tristate.isFalse);
    expect(t.getSemantics(fifteen).flagsCollection.isInMutuallyExclusiveGroup,
        isTrue);
    await t.tap(fifteen);
    await t.pumpAndSettle();
    expect(
        t.getSemantics(fifteen).flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(t.getSemantics(off).flagsCollection.isSelected, ui.Tristate.isFalse);
    expect(s.autoSyncIntervalMinutes, 15);
    await s.saveAutoSyncIntervalMinutes(0);
    semantics.dispose();
  });

  testWidgets('remediated screens stay usable at narrow width and large text',
      (t) async {
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final s = _store();
    addTearDown(s.dispose);
    await s.restoreSession();
    final root = Directory.current.resolveSymbolicLinksSync();
    final output =
        Directory('$root/../../artifacts/current/review-remediation/ui');
    for (final size in [const Size(393, 852), const Size(320, 640)]) {
      final scale = size.width == 320 ? 2.0 : 1.0;
      t.view.physicalSize = size;
      final boundary = GlobalKey();
      Future<void> mount(Widget child) async {
        await t.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: StudyAssistantTheme.light,
            builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                  size: size, textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: child,
          ),
        ));
        await t.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        expect(t.takeException(), isNull, reason: '$name ${size.width} $scale');
        if (!const bool.fromEnvironment('CAPTURE_UI')) return;
        await t.runAsync(() async {
          output.createSync(recursive: true);
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/$name-${size.width.toInt()}-$scale.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await mount(LoginScreen(store: s));
      await capture('login');
      await t.ensureVisible(find.byType(Checkbox));
      await t.pumpAndSettle();
      await capture('consent');
      for (final kind in AgreementKind.values) {
        await mount(AgreementScreen(kind: kind));
        await capture('agreement-${kind.name}');
      }
      await mount(Scaffold(body: ProfileScreen(store: s)));
      await t.scrollUntilVisible(find.text('退出登录'), 400);
      await t.pumpAndSettle();
      await t.tap(find.text('退出登录'));
      await t.pumpAndSettle();
      await capture('logout-confirmation');
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      await mount(Scaffold(body: ReminderSettingsScreen(assignmentStore: s)));
      await t.ensureVisible(find.text('保存提醒规则'));
      await t.pumpAndSettle();
      await capture('reminders');
      await mount(Scaffold(body: SyncStatusScreen(store: s)));
      await t.scrollUntilVisible(
          find.byKey(const ValueKey('auto-sync-option-off')), 250,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await capture('sync');
      await t.pumpWidget(const SizedBox());
    }
  });
}

AssignmentStore _store({_Session? session, ReminderRuleStore? rules}) =>
    AssignmentStore(
      sessionStore: session ?? _Session(),
      reminderRuleStore: rules,
      notificationService: _Notifications(),
      widgetSnapshotService: _Widget(),
    );

final _assignment = Assignment(
    id: 'cx:work:1:2:3',
    courseName: '合成课程',
    title: '合成作业',
    deadlineAt: null,
    requirementsText: '',
    status: 'pending',
    lastSyncedAt: DateTime.utc(2026, 11, 5));

class _Session extends SecureSessionStore {
  _Session({this.failClear = false});
  final bool failClear;
  @override
  Future<String?> readChaoxingAccount() async => 'synthetic-student';
  @override
  Future<String?> readChaoxingDisplayName() async => null;
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
  @override
  Future<void> clear() async {
    if (failClear) throw StateError('synthetic storage failure');
  }
}

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {}

  @override
  Future<void> rescheduleAssignments(List<Assignment> a,
      {List<int>? offsetsMinutes}) async {}
}

class _Widget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> a) async {}
}

class _FailOnceRuleStore extends ReminderRuleStore {
  bool _failed = false;
  @override
  Future<List<int>> saveOffsetsMinutes(List<int> offsetsMinutes) async {
    if (!_failed) {
      _failed = true;
      throw StateError('synthetic storage failure');
    }
    return super.saveOffsetsMinutes(offsetsMinutes);
  }
}
