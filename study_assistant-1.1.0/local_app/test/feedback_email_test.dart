import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/app/app_version.dart';
import 'package:study_assistant_mobile/src/features/help_feedback_screen.dart';
import 'package:study_assistant_mobile/src/services/external_link_service.dart';

class _Links extends ExternalLinkService {
  _Links({required this.result});

  final bool result;
  final calls = <(String subject, String body)>[];
  final openedUrls = <String>[];

  @override
  Future<bool> composeFeedbackEmail(String subject, String body) async {
    calls.add((subject, body));
    return result;
  }

  @override
  Future<bool> openUrl(String url) async {
    openedUrls.add(url);
    return true;
  }
}

void main() {
  testWidgets('feedback copy content and copy email buttons validate and copy',
      (tester) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map?)?['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final links = _Links(result: true);
    await tester.pumpWidget(MaterialApp(home: FeedbackScreen(links: links)));

    await tester.tap(find.byKey(const ValueKey('feedback-copy-content')));
    await tester.pump();
    expect(find.text('请先描述遇到的问题'), findsOneWidget);
    expect(clipboardText, isNull);

    await tester.enterText(find.byType(TextField).at(0), '偶现通知不响铃');
    await tester.enterText(find.byType(TextField).at(1), '步骤 A -> B');
    await tester.tap(find.byKey(const ValueKey('feedback-copy-content')));
    await tester.pumpAndSettle();

    expect(clipboardText, contains('学习通课业手记 ${AppVersion.display}'));
    expect(clipboardText, contains('问题：偶现通知不响铃'));
    expect(clipboardText, contains('复现步骤：步骤 A -> B'));
    expect(find.text('反馈内容已复制，请粘贴发送（尚未自动发送）'), findsOneWidget);
    expect(find.textContaining('反馈已发送'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('feedback-copy-email')));
    await tester.pumpAndSettle();
    expect(clipboardText, '397079535@qq.com');
    expect(find.text('收件邮箱已复制'), findsOneWidget);
  });

  testWidgets('feedback email composes a versioned draft and keeps the form',
      (tester) async {
    final links = _Links(result: true);
    await tester.pumpWidget(MaterialApp(home: FeedbackScreen(links: links)));
    const problem = '同步后少了作业 & 状态不对？';
    const steps = '第一步：打开首页\n第二步：刷新 #1 50%';
    await tester.enterText(find.byType(TextField).at(0), problem);
    await tester.enterText(find.byType(TextField).at(1), steps);

    await tester.scrollUntilVisible(
      find.text('尝试用系统邮件发送'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('尝试用系统邮件发送'));
    await tester.pumpAndSettle();

    expect(links.calls, hasLength(1));
    expect(links.calls.single.$1, '学习通课业手记 ${AppVersion.display} 反馈');
    expect(links.calls.single.$2, contains('学习通课业手记 ${AppVersion.display}'));
    expect(
      links.calls.single.$2,
      contains(
          '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}'),
    );
    expect(links.calls.single.$2, contains('问题：$problem'));
    expect(links.calls.single.$2, contains('复现步骤：$steps'));
    expect(find.text('已打开邮件草稿，请在邮箱中确认发送'), findsOneWidget);
    expect(find.textContaining('反馈已发送'), findsNothing);
    expect(find.text(problem), findsOneWidget);
    expect(find.text(steps), findsOneWidget);
  });

  testWidgets('feedback email failure preserves input and offers copy recovery',
      (tester) async {
    final links = _Links(result: false);
    await tester.pumpWidget(MaterialApp(home: FeedbackScreen(links: links)));
    await tester.enterText(find.byType(TextField).at(0), '中文问题');

    await tester.scrollUntilVisible(
      find.text('尝试用系统邮件发送'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('尝试用系统邮件发送'));
    await tester.pumpAndSettle();

    expect(find.text('未能打开邮件草稿'), findsOneWidget);
    expect(find.text('复制反馈内容'), findsWidgets);
    expect(find.text('复制收件地址'), findsOneWidget);
    expect(find.text('中文问题'), findsOneWidget);
    expect(find.textContaining('反馈已发送'), findsNothing);
  });

  testWidgets('empty feedback cannot open an email draft', (tester) async {
    final links = _Links(result: true);
    await tester.pumpWidget(MaterialApp(home: FeedbackScreen(links: links)));

    await tester.scrollUntilVisible(
      find.text('尝试用系统邮件发送'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('尝试用系统邮件发送'));
    await tester.pump();

    expect(links.calls, isEmpty);
    expect(find.text('请先描述遇到的问题'), findsOneWidget);
  });

  testWidgets('feedback actions remain reachable at 320dp and double text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: FeedbackScreen(links: _Links(result: true)),
    ));

    expect(find.byKey(const ValueKey('feedback-copy-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-copy-email')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('打开 GitHub 反馈页面'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('尝试用系统邮件发送'), findsOneWidget);
    expect(find.text('打开 GitHub 反馈页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback text survives a paused and resumed app lifecycle',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: FeedbackScreen(links: _Links(result: true))),
    );
    await tester.enterText(find.byType(TextField).at(0), '切到邮箱再回来');
    await tester.enterText(find.byType(TextField).at(1), '步骤仍然保留');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('切到邮箱再回来'), findsOneWidget);
    expect(find.text('步骤仍然保留'), findsOneWidget);
  });
}
