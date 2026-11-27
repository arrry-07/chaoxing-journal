import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _Store extends AssignmentStore {
  _Store({this.failSaves = false})
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
        );

  final bool failSaves;
  int saveCalls = 0;

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    saveCalls++;
    if (failSaves) return false;
    homeFilters = next;
    notifyListeners();
    return true;
  }
}

Assignment _work({
  String id = 'w',
  String courseName = '课程',
  String courseId = 'c',
  String classId = 'k',
}) =>
    Assignment(
      id: 'cx:work:$courseId:$classId:$id',
      courseName: courseName,
      title: '作业',
      requirementsText: '',
      status: 'pending',
      deadlineAt: DateTime.now().add(const Duration(days: 2)),
      deadlineTrusted: true,
      lastSyncedAt: DateTime.now(),
    );

Future<void> _pump(
  WidgetTester tester,
  _Store store, {
  Size size = const Size(420, 1200),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: StudyAssistantTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: AssignmentListScreen(store: store)),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _tagInk(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('active filter tags are 48dp targets and remove one condition',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final store = _Store()
        ..homeFilters = const HomeFilters(
          query: '数学',
          courseKey: 'c:k',
          type: AssignmentTypeFilter.homework,
          deadline: AssignmentDeadlineFilter.overdue,
          sortOrder: HomeSortOrder.deadlineDesc,
        )
        ..replaceAssignmentsForTest([_work()]);
      addTearDown(store.dispose);
      await _pump(tester, store);

      final queryTag = _tagInk('关键词：数学');
      final size = tester.getSize(queryTag);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(
        find.semantics.byLabel('移除筛选：关键词：数学'),
        findsOneWidget,
      );
      expect(
        find.semantics.byLabel('移除筛选：课程：课程'),
        findsOneWidget,
      );

      final rect = tester.getRect(queryTag);
      await tester.tapAt(rect.topLeft + const Offset(3, 3));
      await tester.pumpAndSettle();
      expect(store.homeFilters.query, '');
      expect(store.homeFilters.courseKey, 'c:k');
      expect(store.homeFilters.type, AssignmentTypeFilter.homework);
      expect(store.homeFilters.deadline, AssignmentDeadlineFilter.overdue);
      expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
      expect(find.text('关键词：数学'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('filter tags activate through semantics exactly once',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final store = _Store()
        ..homeFilters = const HomeFilters(query: '数学')
        ..replaceAssignmentsForTest([_work()]);
      addTearDown(store.dispose);
      await _pump(tester, store);

      tester.semantics.tap(find.semantics.byLabel('移除筛选：关键词：数学'));
      await tester.pumpAndSettle();
      expect(store.homeFilters.query, '');
      expect(store.saveCalls, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reset keeps sort, uses a 48dp target and reports save failure',
      (tester) async {
    final store = _Store(failSaves: true)
      ..homeFilters = const HomeFilters(
        query: '数学',
        courseKey: 'c:k',
        deadline: AssignmentDeadlineFilter.overdue,
        sortOrder: HomeSortOrder.deadlineDesc,
      )
      ..replaceAssignmentsForTest([_work()]);
    addTearDown(store.dispose);
    await _pump(tester, store);

    final reset = find.widgetWithText(TextButton, '清空条件');
    final size = tester.getSize(reset);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(store.homeFilters.query, '数学');
    expect(store.homeFilters.courseKey, 'c:k');
    expect(store.homeFilters.deadline, AssignmentDeadlineFilter.overdue);
    expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
    expect(find.text('搜索、筛选与排序未能保存，请重试；原偏好已保留'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final success = _Store()
      ..homeFilters = const HomeFilters(
        query: '数学',
        deadline: AssignmentDeadlineFilter.overdue,
        sortOrder: HomeSortOrder.deadlineDesc,
      )
      ..replaceAssignmentsForTest([_work()]);
    addTearDown(success.dispose);
    await _pump(tester, success);
    await tester.tap(find.widgetWithText(TextButton, '清空条件'));
    await tester.pumpAndSettle();
    expect(success.homeFilters.query, '');
    expect(success.homeFilters.deadline, AssignmentDeadlineFilter.all);
    expect(success.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
  });

  testWidgets('long filter labels wrap at 320dp and 2x without overflow',
      (tester) async {
    final store = _Store()
      ..homeFilters = const HomeFilters(
        query: '非常长的关键词用于检查换行与触控区域是否仍然完整',
        courseKey: 'c:k',
        sortOrder: HomeSortOrder.deadlineDesc,
      )
      ..replaceAssignmentsForTest([
        _work(courseName: '计算方法与实践专题研讨课程（同名班级示例）'),
      ]);
    addTearDown(store.dispose);
    await _pump(tester, store, size: const Size(320, 900), scale: 2);
    expect(tester.takeException(), isNull);
    final tag = _tagInk('关键词：非常长的关键词用于检查换行与触控区域是否仍然完整');
    expect(tester.getSize(tag).height, greaterThanOrEqualTo(48));
    expect(find.widgetWithText(TextButton, '清空条件'), findsOneWidget);
  });
}
