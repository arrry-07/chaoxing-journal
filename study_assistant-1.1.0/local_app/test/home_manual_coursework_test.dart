import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/manual_home_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
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

  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}

  @override
  Future<void> rescheduleSummary(
    List<Assignment> items,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {}
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
  String title = '学习通作业',
  DateTime? due,
  required DateTime syncedAt,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: '高等数学',
      title: title,
      deadlineAt: due,
      deadlineTrusted: due != null,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: syncedAt,
    );

ManualEntry _manual(
  String id, {
  String title = '手动复习',
  String kind = 'todo',
  String course = '高等数学',
  String location = '',
  DateTime? at,
  bool done = false,
}) =>
    ManualEntry(
      id: id,
      title: title,
      kind: kind,
      course: course,
      location: location,
      at: at,
      done: done,
    );

Future<AssignmentStore> _store(
  List<Assignment> items, {
  List<ManualEntry> entries = const [],
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  FlutterSecureStorage.setMockInitialValues({});
  final store = AssignmentStore(
    sessionStore: _MemorySessionStore(),
    notificationService: _Notifications(),
    widgetSnapshotService: _Snapshot(),
    clock: clock,
  );
  await store.restoreSession();
  await store.repository.mergeAndSave(items);
  await store.restoreSession();
  if (entries.isNotEmpty) {
    await store.saveNotebook(
      (_) => StudyNotebook(entries: entries),
      store.accountEpoch,
    );
  }
  return store;
}

Future<void> _pumpHome(
  WidgetTester tester,
  AssignmentStore store,
  DateTime now, {
  TextScaler? textScaler,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: StudyAssistantTheme.light,
      builder: (context, child) {
        if (textScaler == null) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      home: Scaffold(
        body: AssignmentListScreen(store: store, clock: () => now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 23, 10, 0);

  testWidgets('home add entry opens the shared manual editor', (tester) async {
    final store = await _store([]);
    addTearDown(store.dispose);
    await _pumpHome(tester, store, now);

    await tester.tap(find.byKey(const ValueKey('home-add-manual')));
    await tester.pumpAndSettle();
    expect(find.text('添加个人安排'), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
  });

  testWidgets('saving a new manual todo from the editor returns to home',
      (tester) async {
    final store = await _store([]);
    addTearDown(store.dispose);
    await _pumpHome(tester, store, now);

    await tester.tap(find.byKey(const ValueKey('home-add-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '新手动待办');
    await tester.enterText(find.byType(TextFormField).at(1), '高等数学');
    final editorList = find
        .descendant(
          of: find.byType(ManualEntryEditor),
          matching: find.byType(ListView),
        )
        .first;
    for (var i = 0; i < 3; i++) {
      await tester.drag(editorList, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('保存个人安排'));
    await tester.pumpAndSettle();

    expect(find.text('新手动待办'), findsOneWidget);
    expect(find.text('无截止日期'), findsWidgets);
    expect(store.notebook.entries.single.title, '新手动待办');
    expect(store.notebook.entries.single.course, '高等数学');
  });

  testWidgets('manual todo joins the same day group and sorts by time',
      (tester) async {
    final assignment = _work(
      'w1',
      title: '学习通作业',
      due: now.add(const Duration(hours: 3)),
      syncedAt: now,
    );
    final manual = _manual(
      'm1',
      title: '手动复习',
      at: now.add(const Duration(hours: 2)),
    );
    final store = await _store([assignment], entries: [manual]);
    addTearDown(store.dispose);
    await _pumpHome(tester, store, now);

    expect(find.text('手动复习'), findsOneWidget);
    expect(find.text('学习通作业'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('手动复习')).dy,
      lessThan(tester.getTopLeft(find.text('学习通作业')).dy),
    );
  });

  testWidgets('manual complete action leaves home and undo restores it',
      (tester) async {
    final manual = _manual(
      'm1',
      title: '需要完成的手动待办',
      at: now.add(const Duration(hours: 2)),
    );
    final store = await _store([], entries: [manual]);
    addTearDown(store.dispose);
    await _pumpHome(tester, store, now);

    await tester.tap(find.byKey(const ValueKey('complete-manual-m1')));
    await tester.pumpAndSettle();
    expect(find.text('需要完成的手动待办'), findsNothing);
    expect(find.text('撤销'), findsOneWidget);
    expect(store.notebook.entries.single.done, isTrue);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('需要完成的手动待办'), findsOneWidget);
    expect(store.notebook.entries.single.done, isFalse);
  });

  testWidgets('manual pin shares the pinned section and completion unpins it',
      (tester) async {
    final manual = _manual(
      'm1',
      title: '可置顶手动待办',
      at: now.add(const Duration(hours: 2)),
    );
    final store = await _store([], entries: [manual]);
    addTearDown(store.dispose);
    await _pumpHome(tester, store, now);

    await tester.longPress(find.text('可置顶手动待办'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    expect(store.isManualPinned(manual), isTrue);

    await tester.tap(find.byKey(const ValueKey('complete-manual-m1')));
    await tester.pumpAndSettle();
    expect(find.text('可置顶手动待办'), findsNothing);
    expect(find.text('置顶'), findsNothing);
    expect(store.pinnedKeys, isEmpty);
  });

  testWidgets(
      'type and deadline filters apply to manual and coursework together',
      (tester) async {
    final assignment = _work(
      'w1',
      title: '学习通普通作业',
      due: now.add(const Duration(hours: 3)),
      syncedAt: now,
    );
    final todo = _manual(
      'm-todo',
      title: '手动普通待办',
      at: now.add(const Duration(hours: 2)),
    );
    final overdue = _manual(
      'm-overdue',
      title: '手动逾期待办',
      at: now.subtract(const Duration(hours: 2)),
    );
    final exam = _manual(
      'm-exam',
      title: '手动考试安排',
      kind: 'exam',
      at: now.add(const Duration(days: 1)),
    );
    final store = await _store([assignment], entries: [todo, overdue, exam]);
    addTearDown(store.dispose);
    await _pumpHome(tester, store, now);

    Future<void> setFilters(HomeFilters filters) async {
      await store.saveHomeFilters(filters, store.accountEpoch);
      await tester.pumpAndSettle();
    }

    await setFilters(const HomeFilters(type: AssignmentTypeFilter.exam));
    expect(find.text('手动考试安排'), findsOneWidget);
    expect(find.text('手动普通待办'), findsNothing);
    expect(find.text('学习通普通作业'), findsNothing);

    await setFilters(const HomeFilters(
      deadline: AssignmentDeadlineFilter.overdue,
    ));
    expect(find.text('手动逾期待办'), findsOneWidget);
    expect(find.text('手动普通待办'), findsNothing);
    expect(find.text('手动考试安排'), findsNothing);

    await setFilters(const HomeFilters(
      type: AssignmentTypeFilter.homework,
      sortOrder: HomeSortOrder.deadlineDesc,
    ));
    expect(find.text('手动普通待办'), findsOneWidget);
    expect(find.text('学习通普通作业'), findsOneWidget);
    expect(find.text('手动逾期待办'), findsOneWidget);
    expect(find.text('手动考试'), findsNothing);
    expect(
      tester.getTopLeft(find.text('手动逾期待办')).dy,
      greaterThan(tester.getTopLeft(find.text('学习通普通作业')).dy),
    );
  });

  testWidgets('manual card stays overflow-free at 360dp and 1.5x text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entry = _manual(
      'm-long',
      title: '这是一条很长的手动待办标题，用来核对窄屏与大字号的换行和按钮避让',
      course: '一门名字很长很长的课程',
      location: '教学楼 A 区 101 教室',
      at: now.add(const Duration(hours: 2)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.5),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ManualHomeCard(
              entry: entry,
              now: now,
              countdown: true,
              onTap: () {},
              onToggleDone: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(entry.title), findsOneWidget);
    expect(find.text('标记完成'), findsOneWidget);
  });
}
