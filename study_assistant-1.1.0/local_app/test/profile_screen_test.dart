import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/external_link_service.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets('profile offers learning account synchronization', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: ProfileScreen(store: store)));

    expect(find.text('同步学习通'), findsOneWidget);
  });

  testWidgets('profile uses Chaoxing student display name', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(
        displayName: '李雷',
        avatarUrl: 'https://photo.chaoxing.com/p/998877_160',
      ),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(MaterialApp(home: ProfileScreen(store: store)));

    expect(find.text('李雷'), findsOneWidget);
    expect(find.text('小明同学'), findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url,
        'https://photo.chaoxing.com/p/998877_160?psize=160_160c&ext=png');
  });

  testWidgets('profile avatar sends Chaoxing image headers', (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(
        displayName: '鏉庨浄',
        avatarUrl:
            'https://p.cldisk.com/star3/160_160c/05055cacb0d79d5f723c99d1beca393a.png',
      ),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(MaterialApp(home: ProfileScreen(store: store)));

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(
      provider.url,
      'https://p.cldisk.com/star3/160_160c/05055cacb0d79d5f723c99d1beca393a.png',
    );
    expect(provider.headers?['Referer'], 'https://photo.chaoxing.com/');
    expect(provider.headers?['User-Agent'], contains('Mozilla/5.0'));
  });

  testWidgets('profile avatar normalizes old Chaoxing photo URLs',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(
        displayName: '鏉庨浄',
        avatarUrl: 'http://photo.chaoxing.com/p/402733611_120?flag=1',
      ),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(MaterialApp(home: ProfileScreen(store: store)));

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(
      provider.url,
      'https://photo.chaoxing.com/p/402733611_120?flag=1&psize=160_160c&ext=png',
    );
    expect(provider.headers?['Referer'], 'https://photo.chaoxing.com/');
  });

  testWidgets('profile checks app update and offers apk download',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final downloadedApk = File(
      '${Directory.systemTemp.path}/study-assistant-v1.0.7.apk',
    );
    final updateService = _FakeUpdateService(
      update: const AppUpdateInfo(
        versionName: '1.0.7',
        releaseUrl:
            'https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.0.7',
        apkName: 'study-assistant-v1.0.7.apk',
        apkDownloadUrl:
            'https://github.com/arrry-07/chaoxing-journal/releases/download/v1.0.7/study-assistant-v1.0.7.apk',
        releaseNotes: '修复问题',
      ),
      downloadedApk: downloadedApk,
    );
    final externalLinkService = _FakeExternalLinkService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            updateService: updateService,
            externalLinkService: externalLinkService,
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 1.0.7'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);

    await tester.tap(find.text('下载并安装'));
    await tester.pumpAndSettle();

    expect(updateService.downloadedUpdate?.apkDownloadUrl,
        contains('github.com/arrry-07/chaoxing-journal/releases/download'));
    expect(externalLinkService.openedUrls, isEmpty);
    expect(externalLinkService.installedApkPaths, [downloadedApk.path]);
  });

  testWidgets('profile shows download progress while updating', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final downloadedApk = File(
      '${Directory.systemTemp.path}/study-assistant-v1.0.11.apk',
    );
    final updateService = _SlowUpdateService(downloadedApk: downloadedApk);
    final externalLinkService = _FakeExternalLinkService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            updateService: updateService,
            externalLinkService: externalLinkService,
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载并安装'));
    await tester.pump();
    updateService.emitProgress(5, 10);
    await tester.pump();

    expect(find.text('正在下载更新包'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);

    updateService.completeDownload();
    await tester.pumpAndSettle();

    expect(externalLinkService.installedApkPaths, [downloadedApk.path]);
  });

  testWidgets(
      'feedback opens issues, source opens repository, about opens credits',
      (tester) async {
    final external = _FakeExternalLinkService();
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService());
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProfileScreen(store: store, externalLinkService: external))));
    for (final label in ['帮助与反馈', 'GitHub 源码', '检查更新', '关于我们']) {
      final row = find.widgetWithText(ListTile, label);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
    }
    expect(external.openedUrls, [
      'https://github.com/arrry-07/chaoxing-journal/issues',
      'https://github.com/arrry-07/chaoxing-journal',
      'https://github.com/arrry-07/chaoxing-journal/releases'
    ]);
    expect(find.byType(AboutDialog), findsOneWidget);
  });

  testWidgets('profile settings contain reminder and sync entries',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileScreen(store: store)),
      ),
    );

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('提醒设置'), findsOneWidget);
    expect(find.text('同步学习通'), findsOneWidget);
    final storage =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '本地记录'));
    expect(storage.onTap, isNull);
    expect(storage.trailing, isNull);
    expect(find.text('帮助与反馈'), findsOneWidget);
    expect(find.text('关于我们'), findsOneWidget);
  });
}

class _FakeUpdateService extends AppUpdateService {
  _FakeUpdateService({this.update, this.downloadedApk});

  final AppUpdateInfo? update;
  final File? downloadedApk;
  AppUpdateInfo? downloadedUpdate;

  @override
  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersionName,
    required int currentVersionCode,
  }) async {
    return update;
  }

  @override
  Future<File> downloadApk(
    AppUpdateInfo update, {
    String? targetDirectory,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    downloadedUpdate = update;
    final file =
        downloadedApk ?? File('${Directory.systemTemp.path}/${update.apkName}');
    onProgress?.call(4, 10);
    onProgress?.call(10, 10);
    return file;
  }
}

class _SlowUpdateService extends AppUpdateService {
  _SlowUpdateService({required this.downloadedApk});

  final File downloadedApk;
  void Function(int receivedBytes, int totalBytes)? progressCallback;
  Completer<File>? downloadCompleter;

  @override
  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersionName,
    required int currentVersionCode,
  }) async {
    return const AppUpdateInfo(
      versionName: '1.0.11',
      releaseUrl:
          'https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.0.11',
      apkName: 'study-assistant-v1.0.11.apk',
      apkDownloadUrl:
          'https://github.com/arrry-07/chaoxing-journal/releases/download/v1.0.11/study-assistant-v1.0.11.apk',
      releaseNotes: '',
    );
  }

  @override
  Future<File> downloadApk(
    AppUpdateInfo update, {
    String? targetDirectory,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) {
    progressCallback = onProgress;
    downloadCompleter = Completer<File>();
    return downloadCompleter!.future;
  }

  void emitProgress(int receivedBytes, int totalBytes) {
    progressCallback?.call(receivedBytes, totalBytes);
  }

  void completeDownload() {
    downloadCompleter?.complete(downloadedApk);
  }
}

class _FakeExternalLinkService extends ExternalLinkService {
  final openedUrls = <String>[];
  final installedApkPaths = <String>[];

  @override
  Future<bool> openUrl(String url) async {
    openedUrls.add(url);
    return true;
  }

  @override
  Future<bool> installApk(String filePath) async {
    installedApkPaths.add(filePath);
    return true;
  }
}

class _MemorySessionStore extends SecureSessionStore {
  _MemorySessionStore({this.displayName, this.avatarUrl});

  final String? displayName;
  final String? avatarUrl;

  @override
  Future<String?> readChaoxingAccount() async => 'student';

  @override
  Future<String?> readChaoxingDisplayName() async => displayName;

  @override
  Future<String?> readChaoxingAvatarUrl() async => avatarUrl;
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}
