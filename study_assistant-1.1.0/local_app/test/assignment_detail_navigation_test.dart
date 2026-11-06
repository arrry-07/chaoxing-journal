import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));
  const channel = MethodChannel('study_assistant/external_links');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Future<_DetailStore> launch(WidgetTester tester, {String? url = _url}) async {
    final store = _DetailStore(url);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssignmentDetailScreen(
                store: store, assignmentId: store.item.id))));
    return store;
  }

  testWidgets('detail renders the deadline in Beijing time', (tester) async {
    await launch(tester);
    expect(find.textContaining('2026年11月5日 08:30'), findsOneWidget);
  });
  testWidgets(
      'go to Chaoxing keeps original URL and uses browser fallback without completing work',
      (tester) async {
    final requests = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      requests.add(call);
      return call.method == 'openBrowser';
    });
    final store = await launch(tester);
    final button = find.text('去学习通完成');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(requests.map((c) => c.method),
        ['openChaoxingAssignment', 'openBrowser']);
    expect(requests.every((c) => c.arguments['url'] == _url), isTrue);
    expect(store.item.isCompleted, isFalse);
    expect(find.textContaining('已请求浏览器'), findsOneWidget);
  });

  testWidgets(
      'target missing from the current account offers refresh without stale data',
      (tester) async {
    final store = await launch(tester);
    store.missing = true;
    store.notifyListeners();
    await tester.pump();
    expect(find.textContaining('当前账号'), findsOneWidget);
    expect(find.text('合成作业'), findsNothing);
    expect(find.text('刷新作业信息'), findsOneWidget);
  });

  testWidgets('failed hiding retains detail and reports a retryable error',
      (tester) async {
    final store = await launch(tester);
    await tester.ensureVisible(find.text('在本机隐藏此作业'));
    await tester.tap(find.text('在本机隐藏此作业'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AssignmentDetailScreen), findsOneWidget);
    expect(find.textContaining('隐藏失败'), findsOneWidget);
    expect(store.item.isCompleted, isFalse);
  });

  testWidgets(
      'browser launch preserves signed URL and blocks rapid duplicate taps',
      (tester) async {
    final gate = Completer<bool>();
    final requests = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      requests.add(call);
      return gate.future;
    });
    final store = await launch(tester);
    final open = find.text('打开作业网页');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.tap(open);
    await tester.pump();
    expect(requests, hasLength(1));
    expect(requests.single.method, 'openBrowser');
    expect(requests.single.arguments, {'url': _url});
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(store.item.isCompleted, isFalse);
    expect(find.textContaining('可能需要另行登录'), findsOneWidget);
    expect(find.textContaining('已进入作业'), findsNothing);
  });

  testWidgets(
      'platform launch failure stays on detail with refresh and copy fallback',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'no_browser');
    });
    await launch(tester);
    await tester.ensureVisible(find.text('打开作业网页'));
    await tester.tap(find.text('打开作业网页'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('未能启动浏览器'), findsOneWidget);
    expect(find.text('刷新作业信息'), findsOneWidget);
    expect(find.text('复制作业链接'), findsOneWidget);
  });

  testWidgets('invalid cached URL is not passed to browser or clipboard',
      (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      calls++;
      return true;
    });
    await launch(tester, url: 'https://evil.example/work/task?workId=3');
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '打开作业网页'));
    expect(button.onPressed, isNull);
    expect(calls, 0);
    expect(find.textContaining('链接暂不可用'), findsOneWidget);
    final copy =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '复制作业链接'));
    expect(copy.onPressed, isNull);
  });

  testWidgets('manual refresh requests fresh assignment data', (tester) async {
    final store = await launch(tester, url: null);
    await tester.ensureVisible(find.text('刷新作业信息'));
    await tester.tap(find.text('刷新作业信息'));
    await tester.pumpAndSettle();
    expect(store.refreshes, 1);
  });

  testWidgets('copy requires an explicit warning confirmation', (tester) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await launch(tester);
    await tester.ensureVisible(find.text('复制作业链接'));
    await tester.tap(find.text('复制作业链接'));
    await tester.pumpAndSettle();
    expect(copied, isEmpty);
    expect(find.textContaining('本人设备'), findsOneWidget);
    await tester.tap(find.text('确认复制'));
    await tester.pumpAndSettle();
    expect(copied, [_url]);
  });
}

const _url =
    'https://mooc1.chaoxing.com/mooc-ans/work/task?courseId=1&classId=2&workId=3&enc=a%2Bb%3D&x=1&x=2';

class _DetailStore extends AssignmentStore {
  _DetailStore(String? url)
      : item = Assignment(
            id: 'cx:work:1:2:3',
            courseName: '合成课程',
            title: '合成作业',
            deadlineAt: DateTime.utc(2026, 11, 5, 0, 30),
            requirementsText: '',
            status: 'pending',
            submitUrl: url,
            lastSyncedAt: DateTime.utc(2026)),
        super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  final Assignment item;
  bool missing = false;
  int refreshes = 0;
  @override
  Assignment? findAssignment(String id) =>
      !missing && id == item.id ? item : null;
  @override
  Future<void> updateCompletion(String id, bool completed) async {
    throw StateError('disk full');
  }

  // Implemented by the owning store task; explicit result replaces navigation
  // after an ignored persistence failure.
  @override
  Future<bool> hideAssignment(String id) async => false;
  @override
  Future<void> syncAssignments() async {
    refreshes++;
  }
}
