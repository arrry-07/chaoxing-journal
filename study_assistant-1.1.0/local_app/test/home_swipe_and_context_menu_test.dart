import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _MemorySessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-1';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '测试同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

Assignment _work(
  String id, {
  String title = '高等数学作业',
  DateTime? due,
  String? submitUrl,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: '高等数学',
      title: title,
      deadlineAt: due,
      deadlineTrusted: due != null,
      requirementsText: '',
      status: 'pending',
      submitUrl: submitUrl,
      lastSyncedAt: DateTime.now(),
    );

Future<AssignmentStore> _authenticatedStore(List<Assignment> items) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  FlutterSecureStorage.setMockInitialValues({});
  final store = AssignmentStore(
    sessionStore: _MemorySessionStore(),
    notificationService: _Notifications(),
    widgetSnapshotService: _Snapshot(),
  );
  await store.restoreSession();
  await store.repository.mergeAndSave(items);
  await store.restoreSession();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'right swipe toggles today plan (30 min default) and left swipe toggles pin',
      (tester) async {
    final due = DateTime.now().add(const Duration(days: 1));
    final item = _work('w1', title: '手势作业一', due: due);
    final store = await _authenticatedStore([item]);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: AssignmentListScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(ValueKey('assignment-${item.id}'));
    expect(tile, findsOneWidget);

    // Right swipe beyond 72dp threshold adds to today's plan with 30 minutes.
    await tester.drag(tile, const Offset(140, 0));
    await tester.pumpAndSettle();

    final day = PersonalWorkspace.dayKey(DateTime.now());
    expect(
      store.personal.plans
          .where((p) => p.day == day && p.assignmentId == item.id)
          .single
          .minutes,
      30,
    );
    expect(find.text('已加入今日计划（30 分钟）'), findsOneWidget);

    // Second right swipe removes from today's plan.
    await tester.drag(tile, const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(
      store.personal.plans
          .where((p) => p.day == day && p.assignmentId == item.id),
      isEmpty,
    );
    expect(find.text('已移出今日计划'), findsOneWidget);

    // Left swipe beyond -68dp threshold pins and then unpins.
    await tester.drag(tile, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(store.isPinned(item), isTrue);
    expect(find.text('置顶'), findsOneWidget);

    await tester.drag(tile, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(store.isPinned(item), isFalse);
  });

  testWidgets('long press opens context menu and supports hide with undo',
      (tester) async {
    final due = DateTime.now().add(const Duration(days: 2));
    final item = _work(
      'w2',
      title: '长按菜单作业',
      due: due,
      submitUrl: 'https://mooc1.chaoxing.com/work/view?workid=w2',
    );
    final store = await _authenticatedStore([item]);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: AssignmentListScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('长按菜单作业'));
    await tester.pumpAndSettle();

    expect(find.text('在学习通打开'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('加入今日计划'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('在本机隐藏'), findsOneWidget);

    await tester.tap(find.text('在本机隐藏'));
    await tester.pumpAndSettle();

    expect(find.text('长按菜单作业'), findsNothing);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('长按菜单作业'), findsOneWidget);
  });

  testWidgets('home deduplicates today badge and merges pinned countdown line',
      (tester) async {
    final now = DateTime.now();
    final todayDue = now.add(const Duration(hours: 3));
    final item = _work('w3', title: '今日合并时间作业', due: todayDue);
    final store = await _authenticatedStore([item]);
    addTearDown(store.dispose);
    await store.saveDisplay(const DisplayPreferences(countdown: true));

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(body: AssignmentListScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    // Group header owns '今天'; card must not repeat '今天截止' pill.
    expect(find.text('今天截止'), findsNothing);
    expect(find.textContaining('剩余'), findsOneWidget);

    // Pin the item and check merged single metadata line in pinned section.
    await store.togglePin(item);
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').startsWith('截止 ') &&
            (w.data ?? '').contains(' · 剩余'),
      ),
      findsOneWidget,
    );

    // Standalone AssignmentCard with showFullDeadline=true still keeps '今天截止'.
    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: AssignmentCard(
            assignment: item,
            now: now,
            showFullDeadline: true,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天截止'), findsOneWidget);
  });
}
