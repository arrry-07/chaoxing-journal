import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  testWidgets('agreement panel stays readable with narrow large text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: LoginScreen(store: store),
    ));
    await tester.scrollUntilVisible(find.text('我已阅读并同意'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();

    expect(find.text('服务协议'), findsOneWidget);
    expect(find.text('隐私协议'), findsOneWidget);
    expect(find.textContaining('课程作业数据保存在本机'), findsOneWidget);
    final service =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '服务协议'));
    expect(service.style?.foregroundColor?.resolve({}), Journal.ink);
    final notice = tester.widget<Text>(find.textContaining('课程作业数据保存在本机'));
    expect(notice.style?.color, Journal.muted);
    expect(tester.takeException(), isNull);
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
