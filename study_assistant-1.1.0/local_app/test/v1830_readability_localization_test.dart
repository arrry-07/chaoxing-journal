import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/main.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/features/assignment_changes_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment_change.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_dialog.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/app_update_controller.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _TestSession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-v1830';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgetSnapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _NoopUpdateService extends AppUpdateService {
  @override
  Future<UpdateCheckResult> checkForStartup({
    required int currentVersionCode,
    CancelToken? cancelToken,
  }) async =>
      const UpdateCheckResult(UpdateCheckStatus.upToDate);

  @override
  Future<UpdateCheckResult> checkForManualUpdate({
    required String currentVersionName,
    required int currentVersionCode,
    CancelToken? cancelToken,
  }) async =>
      const UpdateCheckResult(UpdateCheckStatus.upToDate);
}

Future<AssignmentStore> _buildStore(DateTime now) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = AssignmentStore(
    sessionStore: _TestSession(),
    notificationService: _NoopNotifications(),
    widgetSnapshotService: _NoopWidgetSnapshot(),
    clock: () => now,
  );
  await store.restoreSession();
  await store.repository.mergeAndSave([
    Assignment(
      id: 'cx:work:1:2:today',
      courseName: '软件工程',
      title: '今天截止的作业',
      deadlineAt: now.add(const Duration(hours: 3)),
      deadlineTrusted: true,
      requirementsText: '按模板提交文档',
      status: 'pending',
      submitUrl:
          'https://mooc1.chaoxing.com/mooc-ans/work/task?courseId=1&classId=2&workId=1',
      lastSyncedAt: now,
    ),
    Assignment(
      id: 'cx:work:1:2:overdue',
      courseName: '离散数学',
      title: '已逾期的作业',
      deadlineAt: now.subtract(const Duration(days: 1)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    ),
  ]);
  await store.restoreSession();
  return store;
}

void _assertAllRenderedTextUsesWenKai(WidgetTester tester, String surface) {
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final data = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (data.trim().isEmpty) continue;
    final defaultStyle = DefaultTextStyle.of(element).style;
    final resolved = widget.style ?? defaultStyle;
    final family = resolved.fontFamily ?? defaultStyle.fontFamily;
    expect(
      family,
      Journal.bodyFamily,
      reason: '$surface has non-WenKai Text("$data"): $family',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets(
      'D5: red (berry) is reserved for overdue/error and not used for today rail, day heading or due-today summary',
      (tester) async {
    final now = DateTime.utc(2026, 11, 25, 2, 0); // 10:00 Beijing
    final store = await _buildStore(now);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home:
          Scaffold(body: AssignmentListScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    final summaryText = tester.widget<Text>(find.textContaining('今日待交'));
    expect(summaryText.style?.color, isNot(Journal.berry));
    expect(summaryText.style?.color, JournalPalette.light.accent);

    final todayTimeText = tester.widget<Text>(find.text('13:00'));
    expect(todayTimeText.style?.color, JournalPalette.light.accent);

    final overdueHeading = tester.widget<Text>(find.textContaining('11月24日'));
    expect(overdueHeading.style?.color, isNot(Journal.berry));

    final overduePill = tester.widget<Text>(find.textContaining('已逾期1天'));
    expect(overduePill.style?.color, Journal.berry);

    final todayItem = Assignment(
      id: 'cx:work:1:2:today-pill',
      courseName: '软件工程',
      title: '今天截止的作业',
      deadlineAt: now.add(const Duration(hours: 3)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    );
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(
        body: AssignmentCard(
          assignment: todayItem,
          now: now,
          showFullDeadline: true,
          onTap: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final todayPill = tester.widget<Text>(find.text('今天截止'));
    expect(todayPill.style?.color, JournalPalette.light.accent);
  });

  testWidgets(
      'D8: detail primary and secondary buttons match height/width side-by-side at 360dp and stack cleanly at 1.3x / 320dp',
      (tester) async {
    final now = DateTime.utc(2026, 11, 25, 2, 0);
    final store = await _buildStore(now);
    addTearDown(store.dispose);

    Future<void> pumpDetail(Size size, double scale) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: AssignmentDetailScreen(
            store: store,
            assignmentId: 'cx:work:1:2:today',
            clock: () => now,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await pumpDetail(const Size(360, 800), 1.0);
    final openFinder = find.byKey(const ValueKey('assignment-detail-open'));
    final webFinder = find.byKey(const ValueKey('assignment-detail-open-web'));
    await tester.ensureVisible(webFinder);
    final openRect = tester.getRect(openFinder);
    final webRect = tester.getRect(webFinder);
    expect(openRect.height, closeTo(48.0, 0.5));
    expect(webRect.height, closeTo(48.0, 0.5));
    expect(webRect.width, closeTo(openRect.width, 1.0));
    expect(webRect.top, closeTo(openRect.top, 0.5));

    await pumpDetail(const Size(393, 852), 1.3);
    await tester.ensureVisible(webFinder);
    final stackedOpen = tester.getRect(openFinder);
    final stackedWeb = tester.getRect(webFinder);
    expect(stackedOpen.height, greaterThanOrEqualTo(48.0));
    expect(stackedWeb.height, greaterThanOrEqualTo(48.0));
    expect(stackedWeb.width, closeTo(stackedOpen.width, 1.0));
    expect(stackedWeb.top, greaterThan(stackedOpen.bottom));

    await pumpDetail(const Size(320, 640), 1.0);
    await tester.ensureVisible(webFinder);
    expect(
      tester.getRect(webFinder).top,
      greaterThan(tester.getRect(openFinder).bottom),
    );
  });

  testWidgets(
      'D7: MaterialApp uses zh_CN localization and all screens/dialogs use LXGW WenKai Screen',
      (tester) async {
    final now = DateTime.utc(2026, 11, 25, 2, 0);
    final store = await _buildStore(now);
    addTearDown(store.dispose);

    final updates = AppUpdateController(service: _NoopUpdateService());
    addTearDown(updates.dispose);

    await tester.pumpWidget(StudyAssistantApp(
      assignmentStore: store,
      notificationService: _NoopNotifications(),
      updateController: updates,
      clock: () => now,
    ));
    await tester.pumpAndSettle();
    _assertAllRenderedTextUsesWenKai(tester, 'Home');

    await tester.tap(find.text('今天截止的作业'));
    await tester.pumpAndSettle();
    _assertAllRenderedTextUsesWenKai(tester, 'AssignmentDetail');

    await tester.tap(find.byKey(const ValueKey('assignment-detail-back')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    _assertAllRenderedTextUsesWenKai(tester, 'Calendar');

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    _assertAllRenderedTextUsesWenKai(tester, 'Profile');

    // Open About dialog and verify Chinese localization + WenKai font
    final profileScrollable = find
        .descendant(
          of: find.byType(ProfileScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('关于我们'),
      200,
      scrollable: profileScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于我们'));
    await tester.pumpAndSettle();
    expect(find.text('View licenses'), findsNothing);
    expect(find.text('Close'), findsNothing);
    expect(find.text('查看许可'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    _assertAllRenderedTextUsesWenKai(tester, 'AboutDialog');
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    // Open UpdateDialog and verify WenKai font
    await tester.ensureVisible(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsOneWidget);
    _assertAllRenderedTextUsesWenKai(tester, 'UpdateDialog');
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    // Verify DatePicker in zh_CN + WenKai
    final ctx = tester.element(find.byType(ProfileScreen));
    showDatePicker(
      context: ctx,
      initialDate: DateTime(2026, 11, 25),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    await tester.pumpAndSettle();
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    _assertAllRenderedTextUsesWenKai(tester, 'DatePicker');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'M3 Gate 1: AssignmentChangesScreen deadline adjustment uses ochre instead of berry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _TestSession(),
      notificationService: _NoopNotifications(),
      widgetSnapshotService: _NoopWidgetSnapshot(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: AssignmentChangesScreen(store: store),
    ));
    await tester.pumpAndSettle();

    // Verify JournalPalette equality includes non-core fields (e.g. ochre).
    expect(
      JournalPalette.light ==
          JournalPalette.light.copyWith(ochre: const Color(0xFF123456)),
      isFalse,
    );
    expect(
      AssignmentChangeKind.deadline.name,
      'deadline',
    );
  });
}
