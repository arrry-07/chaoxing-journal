import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/display_settings_screen.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';
import 'package:flutter/material.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';

class _CourseSession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'synthetic-filter';
  @override
  Future<String?> readChaoxingDisplayName() async => null;
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _Widgets extends WidgetSnapshotService {
  List<Assignment> items = [];
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {
    items = assignments;
  }
}

AssignmentStore store() => AssignmentStore(
    sessionStore: SecureSessionStore(),
    notificationService: LocalNotificationService(),
    widgetSnapshotService: _Widgets());
void main() {
  testWidgets('settings save and restore without publishing logged-out records',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = store();
    addTearDown(s.dispose);
    await t.pumpWidget(MaterialApp(home: DisplaySettingsScreen(store: s)));
    await t.tap(find.text('紧凑密度'));
    await t.pumpAndSettle();
    expect(s.display.compact, true);
    final prefs = await SharedPreferences.getInstance();
    expect(
        DisplayPreferences.decode(prefs.getString('display_preferences_v1'))
            .compact,
        true);
    expect((s.widgetSnapshotService as _Widgets).items, isEmpty);
  });
  testWidgets(
      'course filter uses class identity and preserves stored assignments',
      (t) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final s = AssignmentStore(
        sessionStore: _CourseSession(),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: _Widgets());
    await s.restoreSession();
    addTearDown(s.dispose);
    final now = DateTime.now();
    s.replaceAssignmentsForTest([
      for (var i = 1; i <= 2; i++)
        Assignment(
            id: 'cx:work:1:$i:1',
            title: '作业$i',
            courseName: '同名课程',
            deadlineAt: now.add(const Duration(hours: 2)),
            status: 'pending',
            requirementsText: '',
            lastSyncedAt: now)
    ]);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    await t.tap(find.text('搜索与筛选'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('同名课程（2班）').last);
    await t.pumpAndSettle();
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(find.text('作业1'), findsNothing);
    expect(find.text('作业2'), findsOneWidget);
    expect(s.assignments.length, 2);
    expect(s.follows('1:1'), true);
  });
  testWidgets('compact countdown stays readable at 320 width and double text',
      (t) async {
    t.view.physicalSize = const Size(320, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026);
    final a = Assignment(
        id: 'cx:work:1:2:1',
        title: '很长的作业名称与课程安排',
        courseName: '课程',
        deadlineAt: now.add(const Duration(hours: 2)),
        status: 'pending',
        requirementsText: '',
        lastSyncedAt: now);
    await t.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: AssignmentCard(
                        assignment: a,
                        now: now,
                        compact: true,
                        countdown: true,
                        onTap: () {},
                        onOpenAssignment: () {}))))));
    expect(find.text('剩余2小时'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test('preferences round trip and recover malformed/unknown settings', () {
    final d = DisplayPreferences.decode(const DisplayPreferences(
            compact: true, countdown: true, widgetRange: WidgetRange.week)
        .encode());
    expect(d.compact, true);
    expect(d.countdown, true);
    expect(d.widgetRange, WidgetRange.week);
    expect(DisplayPreferences.decode('bad').compact, false);
    expect(DisplayPreferences.decode('{"range":"future"}').widgetRange,
        WidgetRange.all);
  });
  test('widget ranges use Beijing midnight and exclude expired deadlines', () {
    final now = DateTime.utc(2026, 11, 6, 15);
    Assignment a(String id, DateTime? date) => Assignment(
        id: 'cx:work:1:2:$id',
        title: id,
        courseName: '课',
        deadlineAt: date,
        status: 'pending',
        requirementsText: '',
        lastSyncedAt: now);
    final items = [
      a('1', now.subtract(const Duration(minutes: 1))),
      a('2', now.add(const Duration(minutes: 30))),
      a('3', now.add(const Duration(hours: 1))),
      a('4', now.add(const Duration(days: 6))),
      a('5', now.add(const Duration(days: 7))),
      a('6', null)
    ];
    expect(
        const DisplayPreferences(widgetRange: WidgetRange.today)
            .forWidget(items, now)
            .map((a) => a.title),
        ['2']);
    expect(
        const DisplayPreferences(widgetRange: WidgetRange.week)
            .forWidget(items, now)
            .map((a) => a.title),
        ['2', '3', '4']);
    expect(const DisplayPreferences().forWidget(items, now).length, 6);
  });
  test('countdown rounds up without early expiry', () {
    final now = DateTime.utc(2026);
    expect(
        DisplayPreferences.remaining(now.add(const Duration(seconds: 1)), now),
        '剩余1分钟');
    expect(DisplayPreferences.remaining(now, now), '已截止');
  });
}
