import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/help_feedback_screen.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Session extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => null;
  @override
  Future<String?> readChaoxingDisplayName() async => null;
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _Notification extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleAssignments(List<Assignment> a,
      {List<int>? offsetsMinutes}) async {}
}

class _Widget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> a) async {}
}

void main() {
  testWidgets('course page distinguishes loading empty errors and cached data',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = _CourseStateStore();
    addTearDown(s.dispose);
    final router = GoRouter(initialLocation: '/courses', routes: [
      GoRoute(path: '/courses', builder: (_, __) => CourseListScreen(store: s)),
      GoRoute(path: '/sync', builder: (_, __) => const Text('同步详情目标页')),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp.router(
        theme: StudyAssistantTheme.light, routerConfig: router));
    expect(find.text('尚未读取课程，请同步后重试。'), findsOneWidget);
    await t.tap(find.text('查看同步状态'));
    await t.pumpAndSettle();
    expect(find.text('同步详情目标页'), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();

    s.loading = true;
    s.publish();
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('尚未读取课程，请同步后重试。'), findsNothing);
    expect(find.text('查看同步状态'), findsNothing);

    s.cached = [CourseRef(courseId: '1', clazzId: '2', name: '缓存课程')];
    s.publish();
    await t.pump();
    expect(find.text('缓存课程'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    s.loading = false;
    s.message = '课程关注保存失败';
    s.publish();
    await t.pumpAndSettle();
    expect(find.text('当前提示：课程关注保存失败'), findsOneWidget);
    expect(find.text('缓存课程'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('课程加载失败'), findsNothing);
    expect(find.text('查看同步状态'), findsOneWidget);

    s.cached = [];
    s.publish();
    await t.pumpAndSettle();
    expect(find.text('当前提示：课程关注保存失败'), findsOneWidget);
    expect(find.text('尚未读取课程，请同步后重试。'), findsOneWidget);
    s.message = null;
    s.publish();
    await t.pumpAndSettle();
    expect(find.textContaining('当前提示：'), findsNothing);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('all 40 courses including long names fit $width at 2x text',
        (t) async {
      t.view.physicalSize = Size(width, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final s = _CourseStateStore()
        ..cached = [
          for (var i = 1; i <= 40; i++)
            CourseRef(
                courseId: '$i', clazzId: '$i', name: '课程 $i：这是用于检查窄屏换行的完整课程名称')
        ];
      addTearDown(s.dispose);
      await t.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: CourseListScreen(store: s)));
      await t.scrollUntilVisible(find.text('课程 40：这是用于检查窄屏换行的完整课程名称'), 350);
      expect(find.text('班级 40'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'help contains offline guidance and a credential-free feedback template',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: HelpFeedbackScreen()));
    expect(find.text('帮助中心'), findsOneWidget);
    expect(HelpFeedbackScreen.feedbackTemplate, contains('复现步骤'));
    expect(HelpFeedbackScreen.feedbackTemplate, contains('问题：'));
    expect(find.text('反馈成功'), findsNothing);
  });
  testWidgets('records keep other sources separate and restore hidden work',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = AssignmentStore(
        sessionStore: _Session(),
        notificationService: _Notification(),
        widgetSnapshotService: _Widget());
    addTearDown(s.dispose);
    Assignment a(String id, String title) => Assignment(
        id: id,
        courseName: '课',
        title: title,
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.now());
    await s.repository.mergeAndSave(
        [a('cx:work:1:2:3', '正式样例'), a('cx:activity:1:2:4', '活动样例')]);
    await s.refreshAssignments();
    await t.pumpWidget(MaterialApp(home: LocalRecordsScreen(store: s)));
    expect(find.text('正式样例'), findsOneWidget);
    expect(find.text('活动样例'), findsNothing);
    await t.tap(find.text('历史与其他来源'));
    await t.pumpAndSettle();
    expect(find.text('活动样例'), findsOneWidget);
    expect(find.text('正式样例'), findsNothing);
    await s.updateCompletion('cx:work:1:2:3', true);
    await t.tap(find.text('已隐藏'));
    await t.pumpAndSettle();
    await t.tap(find.text('恢复'));
    await t.pumpAndSettle();
    expect(s.hiddenAssignments, isEmpty);
    expect((await s.repository.loadJournal()).length, 2);
  });
  testWidgets('same-name classes remain separate and follow choice persists',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'course_refs': jsonEncode([
        for (final c in ['2', '3'])
          {'courseId': '1', 'clazzId': c, 'name': '概率论与数理统计'}
      ])
    });
    final s = AssignmentStore(
        sessionStore: _Session(),
        notificationService: _Notification(),
        widgetSnapshotService: _Widget());
    addTearDown(s.dispose);
    await s.restoreSession();
    await t.pumpWidget(MaterialApp(home: CourseListScreen(store: s)));
    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(find.text('班级 2'), findsOneWidget);
    expect(find.text('班级 3'), findsOneWidget);
    await t.tap(find.byType(SwitchListTile).first);
    await t.pumpAndSettle();
    expect(s.follows('1:2'), isFalse);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('unfollowed_courses'),
        ['1:2']);
  });
}

class _CourseStateStore extends AssignmentStore {
  _CourseStateStore()
      : super(
            sessionStore: _Session(),
            notificationService: _Notification(),
            widgetSnapshotService: _Widget());
  bool loading = false;
  String? message;
  List<CourseRef> cached = [];
  @override
  bool get isLoading => loading;
  @override
  String? get error => message;
  @override
  List<CourseRef> get courses => cached;
  void publish() => notifyListeners();
}
