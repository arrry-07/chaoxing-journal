import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:study_assistant_mobile/src/services/app_update_controller.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_dialog.dart';

const next = AppUpdateInfo(
    versionName: '9.0.0',
    versionCode: 90,
    releaseUrl: '',
    apkName: 'test.apk',
    apkDownloadUrl: 'https://example.org/a.apk',
    releaseNotes: '');

class Releases extends AppUpdateService {
  int checks = 0;
  AppUpdateInfo candidate = next;
  @override
  Future<UpdateCheckResult> checkForStartup(
          {required int currentVersionCode, CancelToken? cancelToken}) =>
      checkConfigured(
          currentVersionCode: currentVersionCode, cancelToken: cancelToken);
  @override
  Future<UpdateCheckResult> checkConfigured(
      {required int currentVersionCode, CancelToken? cancelToken}) async {
    checks++;
    return UpdateCheckResult(UpdateCheckStatus.available, update: candidate);
  }
}

class DelayedRelease extends Releases {
  final pending = Completer<UpdateCheckResult>();
  @override
  Future<UpdateCheckResult> checkConfigured(
          {required int currentVersionCode, CancelToken? cancelToken}) =>
      pending.future;
}

class DelayedIgnore extends AppUpdateController {
  DelayedIgnore() : super(service: Releases());
  final pending = Completer<bool>();
  @override
  Future<bool> ignoreCurrentVersion() => pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('startup network failure stays silent', () async {
    final source = DelayedRelease();
    final task = AppUpdateController(service: source);
    final check = task.checkOnStartup();
    source.pending
        .complete(const UpdateCheckResult(UpdateCheckStatus.networkError));
    expect(await check, isFalse);
    task.dispose();
  });
  testWidgets('startup result waits for foreground before showing a dialog',
      (t) async {
    final source = DelayedRelease();
    final task = AppUpdateController(service: source);
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    await t.pumpWidget(StudyAssistantApp(
        assignmentStore: store,
        notificationService: LocalNotificationService(),
        updateController: task));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    source.pending.complete(
        const UpdateCheckResult(UpdateCheckStatus.available, update: next));
    await t.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    task.dispose();
    store.dispose();
  });
  testWidgets(
      'manual dismissal during startup checking suppresses later auto prompt',
      (t) async {
    final source = DelayedRelease();
    final task = AppUpdateController(service: source);
    final startup = task.checkOnStartup();
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showUpdateDialog(context, task),
                    child: const Text('手动打开'))))));
    await t.tap(find.text('手动打开'));
    await t.pump();
    await t.tap(find.text('关闭'));
    await t.pumpAndSettle();
    source.pending.complete(
        const UpdateCheckResult(UpdateCheckStatus.available, update: next));
    expect(await startup, isFalse);
    await t.pumpWidget(const SizedBox.shrink());
    task.dispose();
  });
  testWidgets(
      'ignore completing during dialog exit does not pop the underlying page',
      (t) async {
    final task = DelayedIgnore();
    await task.check();
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (context) => Scaffold(
                                appBar: AppBar(title: const Text('保留此页面')),
                                body: TextButton(
                                    onPressed: () =>
                                        showUpdateDialog(context, task),
                                    child: const Text('打开更新'))))),
                    child: const Text('进入页面'))))));
    await t.tap(find.text('进入页面'));
    await t.pumpAndSettle();
    await t.tap(find.text('打开更新'));
    await t.pumpAndSettle();
    await t.tap(find.text('忽略此版本'));
    await t.pump();
    await t.tap(find.text('稍后更新'));
    task.pending.complete(true);
    await t.pumpAndSettle();
    expect(find.text('保留此页面'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    task.dispose();
  });
  test('startup checks GitHub once per process even without custom manifest',
      () async {
    final source = Releases();
    final task = AppUpdateController(service: source);
    addTearDown(task.dispose);
    expect(await task.checkOnStartup(), isTrue);
    expect(await task.checkOnStartup(), isFalse);
    expect(source.checks, 1);
  });
  testWidgets(
      'real app shows available release on startup and ignore closes it',
      (t) async {
    final source = Releases();
    final task = AppUpdateController(service: source);
    final store = AssignmentStore(
        sessionStore: SecureSessionStore(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: WidgetSnapshotService());
    await t.pumpWidget(StudyAssistantApp(
        assignmentStore: store,
        notificationService: LocalNotificationService(),
        updateController: task));
    await t.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('忽略此版本'), findsOneWidget);
    await t.tap(find.text('忽略此版本'));
    await t.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    task.dispose();
    store.dispose();
    final restarted = AppUpdateController(service: source);
    expect(await restarted.checkOnStartup(), isFalse);
    restarted.dispose();
  });
  test(
      'ignore survives controller restart but manual check and newer version work',
      () async {
    final source = Releases();
    final first = AppUpdateController(service: source);
    await first.check();
    expect(await first.ignoreCurrentVersion(), isTrue);
    first.dispose();
    final second = AppUpdateController(service: source);
    expect(await second.checkOnStartup(), isFalse);
    await second.check();
    expect(second.update, next);
    second.dispose();
    source.candidate = const AppUpdateInfo(
        versionName: '9.0.1',
        versionCode: 91,
        releaseUrl: '',
        apkName: 'new.apk',
        apkDownloadUrl: 'https://example.org/new.apk',
        releaseNotes: '');
    final third = AppUpdateController(service: source);
    addTearDown(third.dispose);
    expect(await third.checkOnStartup(), isTrue);
  });
}
