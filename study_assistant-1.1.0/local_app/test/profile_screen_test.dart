import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/features/open_source_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_records_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/external_link_service.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/local_record_query.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets('source open is an independent labeled button', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService());
    addTearDown(store.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: ProfileScreen(store: store))));
    await t.scrollUntilVisible(find.text('GitHub 项目'), 400);
    expect(find.byKey(const ValueKey('profile-github-copy')), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
  });

  testWidgets('profile uses tinted groups and berry destructive actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(body: ProfileScreen(store: store)),
    ));

    final courses = tester
        .widget<Card>(find.byKey(const ValueKey('profile-group-courses')));
    expect(courses.color, JournalPalette.light.sheet);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.school_outlined)).color,
      Journal.ink,
    );

    for (final (title, accent) in [
      ('同步与提醒', Journal.ink),
      ('记录与备份', Journal.ink),
      ('关于与更新', Journal.ink),
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      final titleText = tester.widget<Text>(find.text(title));
      final foreground = Color.lerp(Journal.ink, accent, .50);
      expect(titleText.style?.fontFamily, Journal.bodyFamily);
      expect(titleText.style?.color, foreground);
      final headerBox = tester
          .widget<Container>(find.byKey(ValueKey('profile-group-$title')));
      expect(
        (headerBox.decoration as BoxDecoration?)?.color,
        JournalPalette.light.sectionHeaderFill,
      );
      if (title == '同步与提醒') {
        final healthIcon = find.byIcon(Icons.notifications_none_rounded);
        expect(tester.widget<Icon>(healthIcon).color, foreground);
      }
      if (title == '关于与更新') {
        final updateIcon = find.byIcon(Icons.system_update_alt);
        expect(tester.widget<Icon>(updateIcon).color, foreground);
      }
    }

    await tester.scrollUntilVisible(
      find.text('退出登录并清理本机记录'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('退出登录并清理本机记录'));
    await tester.pumpAndSettle();
    final logout = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '退出登录并清理本机记录'),
    );
    expect(
      logout.style?.foregroundColor?.resolve(const <WidgetState>{}),
      Journal.ink,
    );
    expect(
      logout.style?.backgroundColor?.resolve(const <WidgetState>{}),
      Journal.sheet,
    );
    expect(
      logout.style?.side?.resolve(const <WidgetState>{}),
      BorderSide(color: Journal.rule, width: 0.8),
    );
    expect(
      StudyAssistantTheme.light.textButtonTheme.style?.foregroundColor
          ?.resolve(const <WidgetState>{}),
      Journal.ink,
    );
    await tester.tap(find.text('退出登录并清理本机记录'));
    await tester.pumpAndSettle();
    final dangerous = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '退出并清理本机记录'),
    );
    expect(
      dangerous.style?.backgroundColor?.resolve(const <WidgetState>{}),
      Journal.berry,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('hidden assignments can be restored from profile',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService());
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.repository.mergeAndSave([
      Assignment(
          id: 'cx:work:1:2:hidden-1',
          courseName: '数学',
          title: '隐藏样例',
          deadlineAt: null,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: DateTime.now())
    ]);
    await store.updateCompletion('cx:work:1:2:hidden-1', true);
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => Scaffold(body: ProfileScreen(store: store)),
      ),
      GoRoute(
        path: '/profile/records',
        builder: (_, __) => ProfileRecordsScreen(store: store),
      ),
      GoRoute(
        path: '/records',
        builder: (_, state) => LocalRecordsScreen(
          store: store,
          initialFilter: LocalRecordFilterSpec.fromQueryParameters(
            state.uri.queryParameters,
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.scrollUntilVisible(find.text('学习记录').hitTestable(), 180);
    await tester.tap(find.text('学习记录'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('已隐藏作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已隐藏作业'));
    await tester.pumpAndSettle();
    expect(find.text('隐藏样例'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('暂无隐藏作业'), findsOneWidget);
    expect(store.visibleAssignments.single.id, 'cx:work:1:2:hidden-1');
  });
  testWidgets('profile exposes appearance controls before learning settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ProfileScreen(store: store))));
    expect(tester.getTopLeft(find.text('外观与交互')).dy,
        lessThan(tester.getTopLeft(find.text('同步与提醒')).dy));
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(store.display.themeMode, JournalThemeMode.dark);
    await tester.tap(find.text('交互音效'));
    await tester.pumpAndSettle();
    expect(store.display.soundEnabled, isFalse);
    expect(store.display.hapticsEnabled, isTrue);
    await tester.tap(find.text('显示与小组件'));
    await tester.pumpAndSettle();
    expect(find.text('紧凑密度'), findsOneWidget);
  });

  testWidgets('profile offers learning account synchronization',
      (tester) async {
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
        avatarUrl: 'https://p.cldisk.com/star3/160_160c/sample-avatar.png',
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
      'https://p.cldisk.com/star3/160_160c/sample-avatar.png',
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
        avatarUrl: 'http://photo.chaoxing.com/p/200002_120?flag=1',
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
      'https://photo.chaoxing.com/p/200002_120?flag=1&psize=160_160c&ext=png',
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

    expect(find.textContaining('→ 1.0.7'), findsOneWidget);
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
    expect(find.text('后台下载'), findsOneWidget);

    updateService.completeDownload();
    await tester.pumpAndSettle();

    expect(externalLinkService.installedApkPaths, [downloadedApk.path]);
  });

  testWidgets(
      'source copies link while independent button opens it; about keeps credits accessible',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final external = _FakeExternalLinkService();
    final store = AssignmentStore(
        sessionStore: _MemorySessionStore(),
        notificationService: _NoopNotificationService(),
        widgetSnapshotService: _NoopWidgetSnapshotService());
    addTearDown(store.dispose);
    final copied = <String>[];
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProfileScreen(store: store, externalLinkService: external))));
    await t.scrollUntilVisible(find.text('GitHub 项目'), 400);
    await t.pumpAndSettle();
    await t.tap(find.text('GitHub 项目'));
    await t.pumpAndSettle();
    expect(
        external.openedUrls, ['https://github.com/arrry-07/chaoxing-journal']);
    expect(copied, isEmpty);
    await t.tap(find.byKey(const ValueKey('profile-github-copy')));
    await t.pumpAndSettle();
    expect(copied, ['https://github.com/arrry-07/chaoxing-journal']);
    expect(external.openedUrls.length, 1);
    await t.ensureVisible(find.text('关于我们'));
    await t.tap(find.text('关于我们'));
    await t.pumpAndSettle();
    expect(find.byType(AboutDialog), findsOneWidget);
    expect(find.textContaining('基于 HY'), findsNothing);
    expect(find.textContaining('维护者 arrry-07'), findsOneWidget);
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

    expect(find.text('设置'), findsNothing);
    expect(find.text('其他入口'), findsOneWidget);
    expect(find.text('提醒与通知'), findsOneWidget);
    expect(find.text('同步学习通'), findsOneWidget);
    for (final label in ['外观与交互', '显示与小组件', '个人待办与考试', '学习记录']) {
      await tester.scrollUntilVisible(find.text(label), 180);
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('帮助与反馈'), findsOneWidget);
    expect(find.text('关于我们'), findsOneWidget);
  });

  testWidgets('compact course entry updates count and opens all courses',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(
          path: '/profile',
          builder: (_, __) => Scaffold(body: ProfileScreen(store: store))),
      GoRoute(
          path: '/courses', builder: (_, __) => CourseListScreen(store: store)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light, routerConfig: router));

    for (final count in [0, 1, 5, 40]) {
      await store.repository.saveCourses([
        for (var index = 1; index <= count; index += 1)
          CourseRef(courseId: '$index', clazzId: '${index}0', name: '课程 $index')
      ], account: 'student');
      await store.restoreSession();
      await tester.pumpAndSettle();
      expect(find.text(count == 0 ? '暂无课程，前往查看与同步' : '已同步 $count 门课程'),
          findsOneWidget);
      expect(find.byType(CourseMark), findsNothing);
      expect(find.text('查看全部课程'), findsNothing);
    }

    // Tap the row's padding, rather than just its title or arrow.
    final entry = find.widgetWithText(ListTile, '我的课程');
    await tester.tapAt(tester.getTopLeft(entry) + const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(CourseListScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('课程 40'), 400);
    expect(find.text('课程 40'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('已同步 40 门课程'), findsOneWidget);
  });

  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('profile subtitles and routes fit $width at scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final store = AssignmentStore(
            sessionStore: _MemorySessionStore(),
            notificationService: _NoopNotificationService(),
            widgetSnapshotService: _NoopWidgetSnapshotService());
        addTearDown(store.dispose);
        const entries = {
          '同步学习通': ('更新课业与调整白天后台检查', '/sync'),
          '提醒与通知': ('权限状态、提前提醒时间与每日摘要', '/reminders'),
          '帮助与反馈': ('查看使用说明，反馈问题与建议', '/help'),
          '开源许可': ('查看应用使用的开源组件及许可证', null),
        };
        final router = GoRouter(initialLocation: '/profile', routes: [
          GoRoute(
              path: '/profile',
              builder: (_, __) => Scaffold(body: ProfileScreen(store: store))),
          for (final path in ['/sync', '/reminders', '/help'])
            GoRoute(
                path: path,
                builder: (_, __) =>
                    Scaffold(appBar: AppBar(title: Text('目标 $path')))),
          GoRoute(
              path: '/open-source',
              builder: (_, __) => const OpenSourceScreen()),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
            theme: StudyAssistantTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            routerConfig: router));
        for (final entry in entries.entries) {
          final row = find.widgetWithText(ListTile, entry.key);
          await tester.scrollUntilVisible(row, 180);
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          final tile = tester.widget<ListTile>(row);
          expect((tile.subtitle! as Text).data, entry.value.$1);
          expect(tile.subtitleTextStyle?.fontSize, 12);
          expect(tile.subtitleTextStyle?.color, Journal.muted);
          expect((tile.title! as Text).style, Journal.entryTitle);
          expect(tester.takeException(), isNull);
          await tester.tap(row);
          await tester.pumpAndSettle();
          if (entry.value.$2 case final path?) {
            expect(find.text('目标 $path'), findsOneWidget);
            await tester.pageBack();
          } else {
            expect(find.byType(OpenSourceScreen), findsOneWidget);
            await tester.tap(find.byTooltip('返回'));
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('profile settings are grouped by user task', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ProfileScreen(store: store))),
    );

    for (final title in ['外观与交互', '同步与提醒', '记录与备份', '关于与更新']) {
      await tester.scrollUntilVisible(find.text(title).hitTestable(), 180);
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('profile masks 11-digit mobile accounts while keeping others',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final phoneStore = AssignmentStore(
      sessionStore: _MemorySessionStore(
        account: '13974737522',
        displayName: '测试用户',
      ),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(phoneStore.dispose);
    await phoneStore.restoreSession();

    await tester
        .pumpWidget(MaterialApp(home: ProfileScreen(store: phoneStore)));
    expect(find.text('139****7522'), findsOneWidget);
    expect(find.text('13974737522'), findsNothing);

    final plainStore = AssignmentStore(
      sessionStore: _MemorySessionStore(
        account: 'student',
        displayName: '测试用户',
      ),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(plainStore.dispose);
    await plainStore.restoreSession();

    await tester
        .pumpWidget(MaterialApp(home: ProfileScreen(store: plainStore)));
    expect(find.text('student'), findsOneWidget);
  });

  testWidgets('theme swatch selects light mode and adapts to large text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(body: ProfileScreen(store: store)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('浅色'), 180);
    await tester.ensureVisible(find.text('浅色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(store.display.themeMode, JournalThemeMode.light);
    expect(tester.takeException(), isNull);
  });
}

class _FakeUpdateService extends AppUpdateService {
  _FakeUpdateService({this.update, this.downloadedApk});

  final AppUpdateInfo? update;
  final File? downloadedApk;
  AppUpdateInfo? downloadedUpdate;

  @override
  Future<UpdateCheckResult> checkConfigured(
          {required int currentVersionCode, CancelToken? cancelToken}) async =>
      UpdateCheckResult(
          update == null
              ? UpdateCheckStatus.upToDate
              : UpdateCheckStatus.available,
          update: update);

  @override
  Future<File> downloadApk(
    AppUpdateInfo update, {
    String? targetDirectory,
    CancelToken? cancelToken,
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
  Future<UpdateCheckResult> checkConfigured(
      {required int currentVersionCode, CancelToken? cancelToken}) async {
    return const UpdateCheckResult(UpdateCheckStatus.available,
        update: AppUpdateInfo(
          versionName: '1.0.11',
          releaseUrl:
              'https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.0.11',
          apkName: 'study-assistant-v1.0.11.apk',
          apkDownloadUrl:
              'https://github.com/arrry-07/chaoxing-journal/releases/download/v1.0.11/study-assistant-v1.0.11.apk',
          releaseNotes: '',
        ));
  }

  @override
  Future<File> downloadApk(
    AppUpdateInfo update, {
    String? targetDirectory,
    CancelToken? cancelToken,
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
  Future<Map<String, dynamic>> inspectApk(String filePath) async =>
      {'compatible': true};
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
  _MemorySessionStore({
    this.account = 'student',
    this.displayName,
    this.avatarUrl,
  });

  final String account;
  final String? displayName;
  final String? avatarUrl;

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingDisplayName() async => displayName;

  @override
  Future<String?> readChaoxingAvatarUrl() async => avatarUrl;
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
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
