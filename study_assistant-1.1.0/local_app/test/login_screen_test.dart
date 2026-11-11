import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/features/login_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets('shows the learning account and password fields', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: LoginScreen(store: store)));

    expect(find.text('学习通登录'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('keeps agreement default and validates before login',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: LoginScreen(store: store)));

    final login = find.widgetWithText(FilledButton, '登录学习通');
    final checkbox = find.byType(Checkbox);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    expect(tester.widget<FilledButton>(login).onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(0), 'student');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.pump();
    expect(tester.widget<FilledButton>(login).onPressed, isNull);

    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(tester.widget<FilledButton>(login).onPressed, isNotNull);

    await tester.tap(checkbox);
    await tester.pump();
    expect(tester.widget<FilledButton>(login).onPressed, isNull);
  });

  testWidgets('login failure is shown without additional typing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      chaoxingClient: _FailingChaoxingClient(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: LoginScreen(store: store)));
    await tester.enterText(find.byType(TextField).at(0), 'student');
    await tester.enterText(find.byType(TextField).at(1), 'bad-password');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('登录学习通'));
    await tester.pumpAndSettle();

    expect(find.textContaining('登录失败'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('agreement links navigate independently', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: LoginScreen(store: store)));
    await tester.scrollUntilVisible(find.text('《服务协议》'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('《服务协议》'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '服务协议'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('《隐私协议》'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('《隐私协议》'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '隐私协议'), findsOneWidget);
  });

  testWidgets('agreement panel has readable links and full-size tap targets',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await (FontLoader(Journal.bodyFamily)
          ..addFont(rootBundle.load('assets/type/LXGWWenKaiScreen.ttf')))
        .load();
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scenario in [
      (width: 320.0, scale: 1.0),
      (width: 320.0, scale: 2.0),
      (width: 390.0, scale: 1.0),
      (width: 390.0, scale: 2.0),
    ]) {
      final boundary = GlobalKey();
      tester.view.physicalSize = Size(scenario.width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scenario.scale),
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: boundary,
          child: LoginScreen(store: store),
        ),
      ));
      await tester.scrollUntilVisible(find.text('我已阅读并同意'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = Directory(
              '${Directory.systemTemp.path}/learning-assistant-visual');
          await out.create(recursive: true);
          await File(
            '${out.path}/login-${scenario.width.toInt()}-${scenario.scale}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(find.text('我已阅读并同意'), findsOneWidget);
      expect(find.text('《服务协议》'), findsOneWidget);
      expect(find.text('《隐私协议》'), findsOneWidget);
      expect(find.text('课程与作业数据保存在本机。'), findsOneWidget);
      expect(find.bySemanticsLabel('查看《服务协议》'), findsOneWidget);
      expect(find.bySemanticsLabel('查看《隐私协议》'), findsOneWidget);
      expect(find.byType(FittedBox), findsNothing);

      final service = tester.getSize(
        find.widgetWithText(TextButton, '《服务协议》'),
      );
      final privacy = tester.getSize(
        find.widgetWithText(TextButton, '《隐私协议》'),
      );
      expect(service.height, greaterThanOrEqualTo(48));
      expect(privacy.height, greaterThanOrEqualTo(48));
      expect(service.width, greaterThanOrEqualTo(48));
      expect(privacy.width, greaterThanOrEqualTo(48));

      final serviceButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '《服务协议》'),
      );
      expect(
        serviceButton.style?.foregroundColor?.resolve({}),
        Journal.ink,
      );
      final notice = tester.widget<Text>(find.text('课程与作业数据保存在本机。'));
      expect(notice.style?.color, Journal.muted);
      expect(
        find.text('账号密码保存在本机安全存储中。'),
        findsNothing,
      );
      expect(
        find.text('登录与同步直接连接学习通，不经过开发者服务器。'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });
}

class _MemorySessionStore extends SecureSessionStore {}

class _FailingChaoxingClient extends ChaoxingLocalClient {
  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async {
    return const ChaoxingLoginResult(success: false, message: '登录失败');
  }
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
