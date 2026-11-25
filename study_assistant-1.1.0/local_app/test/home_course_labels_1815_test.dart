import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
import 'package:study_assistant_mobile/src/services/home_course_filter.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Session extends SecureSessionStore {
  String? account = 'A';
  @override
  Future<String?> readChaoxingAccount() async => account;
  @override
  Future<String?> readChaoxingDisplayName() async => '合成测试';
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
  @override
  Future<void> clear() async {
    account = null;
  }
}

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _Store extends AssignmentStore {
  _Store({this.catalog = const []})
      : super(
          sessionStore: _Session(),
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
        );

  final List<CourseRef> catalog;
  int saveCalls = 0;

  @override
  List<CourseRef> get courses => List.unmodifiable(catalog);

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    saveCalls++;
    homeFilters = next;
    notifyListeners();
    return true;
  }
}

Assignment _work({
  required String workId,
  required String courseId,
  required String classId,
  String courseName = '同名课程',
}) =>
    Assignment(
      id: 'cx:work:$courseId:$classId:$workId',
      courseName: courseName,
      title: '作业$workId',
      requirementsText: '',
      status: 'pending',
      deadlineAt: DateTime.now().add(const Duration(days: 2)),
      deadlineTrusted: true,
      lastSyncedAt: DateTime.now(),
    );

List<CourseRef> _sameNameCatalog() {
  final current = AcademicTerm.fromInstant(DateTime.now());
  return [
    CourseRef(
        courseId: '1', clazzId: 'k1', name: '同名课程', folderName: current.label),
    CourseRef(
        courseId: '2', clazzId: 'k2', name: '同名课程', folderName: current.label),
    CourseRef(
        courseId: '3', clazzId: 'k3', name: '同名课程', folderName: current.label),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  _Store store, {
  Size size = const Size(420, 1000),
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

Future<void> _openFilters(WidgetTester tester) async {
  final sort = find.byKey(const ValueKey('current-home-sort'));
  await tester.ensureVisible(sort);
  await tester.tap(sort);
  await tester.pumpAndSettle();
}

Future<void> _openCourseMenu(WidgetTester tester) async {
  final courseRow = find.byKey(const ValueKey('home-course-filter'));
  await Scrollable.ensureVisible(tester.element(courseRow), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(courseRow);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('same-name classes use stable class labels and keep candidates scoped',
      () {
    final catalog = _sameNameCatalog();
    final pending = [_work(workId: 'w', courseId: '1', classId: 'k1')];
    final options = buildHomeCourseFilterOptions(
      assignments: pending,
      catalog: catalog,
      records: pending,
      selectedCourseKey: '2:k2',
    );
    expect(options.map((option) => option.courseKey), ['1:k1', '2:k2']);
    expect(options[0].label, '同名课程 · 班级 k1');
    expect(options[1].label, '同名课程 · 班级 k2');
    expect(options.any((option) => option.courseKey == '3:k3'), isFalse);
  });

  test('record reorder does not renumber or relabel classes', () {
    final catalog = _sameNameCatalog();
    final first = [
      _work(workId: 'a', courseId: '1', classId: 'k1'),
      _work(workId: 'b', courseId: '2', classId: 'k2'),
    ];
    final second = first.reversed.toList();
    List<String> labels(List<Assignment> records) =>
        buildHomeCourseFilterOptions(
          assignments: first,
          catalog: catalog,
          records: records,
          selectedCourseKey: '2:k2',
        ).map((option) => option.label).toList();
    expect(labels(second), labels(first));
    expect(labels(first), ['同名课程 · 班级 k1', '同名课程 · 班级 k2']);
  });

  test('same name and clazzId fall back to a compound identity', () {
    final options = buildHomeCourseFilterOptions(
      assignments: [
        _work(workId: 'a', courseId: '10', classId: '7'),
        _work(workId: 'b', courseId: '11', classId: '7'),
      ],
      catalog: const [
        CourseRef(courseId: '10', clazzId: '7', name: '同名课程'),
        CourseRef(courseId: '11', clazzId: '7', name: '同名课程'),
      ],
      records: const [],
    );
    expect(options[0].showCourseId, isTrue);
    expect(options[0].classLabel, '班级 7 · 课程 10');
    expect(options[1].classLabel, '班级 7 · 课程 11');
  });

  testWidgets('selected class without pending work remains identifiable',
      (tester) async {
    final store = _Store(catalog: _sameNameCatalog())
      ..homeFilters = const HomeFilters(
        courseKey: '2:k2',
        sortOrder: HomeSortOrder.deadlineDesc,
      )
      ..replaceAssignmentsForTest([
        _work(workId: 'w', courseId: '1', classId: 'k1'),
      ]);
    addTearDown(store.dispose);
    await _pump(tester, store);

    expect(find.text('课程：同名课程 · 班级 k2'), findsOneWidget);
    await _openFilters(tester);
    await _openCourseMenu(tester);
    expect(find.byKey(const ValueKey('course-option-1:k1')), findsOneWidget);
    expect(find.byKey(const ValueKey('course-option-2:k2')), findsOneWidget);
    expect(find.byKey(const ValueKey('course-option-3:k3')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('course-option-1:k1')),
        matching: find.text('1 项'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('course-option-3:k3')),
        matching: find.text('暂无'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('course-option-1:k1'))).dy,
      lessThan(tester
          .getTopLeft(find.byKey(const ValueKey('course-option-3:k3')))
          .dy),
    );
    expect(find.text('班级 k1'), findsOneWidget);
    expect(find.text('班级 k2'), findsWidgets);

    await tester.tap(find.text('班级 k1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(store.homeFilters.courseKey, '1:k1');
    expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
    expect(find.text('课程：同名课程 · 班级 k1'), findsOneWidget);
  });

  testWidgets('idle course shows empty state with add and clear actions',
      (tester) async {
    final store = _Store(catalog: _sameNameCatalog())
      ..homeFilters = const HomeFilters(
        courseKey: '3:k3',
        sortOrder: HomeSortOrder.deadlineDesc,
      )
      ..replaceAssignmentsForTest([
        _work(workId: 'w', courseId: '1', classId: 'k1'),
      ]);
    addTearDown(store.dispose);
    await _pump(tester, store);

    expect(find.text('这门课暂无作业和考试'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-course-empty-add')), findsOneWidget);
    expect(find.text('为这门课添加待办'), findsOneWidget);
    expect(find.text('已保留课程筛选，当前没有可显示的作业。可在搜索与筛选中更改条件。'), findsNothing);

    await tester.tap(find.text('查看全部课程'));
    await tester.pumpAndSettle();
    expect(store.homeFilters.courseKey, isNull);
    expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
    expect(find.text('这门课暂无作业和考试'), findsNothing);
  });

  testWidgets('course filter row clears the selection inline', (tester) async {
    final store = _Store(catalog: _sameNameCatalog())
      ..homeFilters = const HomeFilters(courseKey: '1:k1')
      ..replaceAssignmentsForTest([
        _work(workId: 'w', courseId: '1', classId: 'k1'),
      ]);
    addTearDown(store.dispose);
    await _pump(tester, store);
    await _openFilters(tester);

    final row = find.byKey(const ValueKey('home-course-filter'));
    await Scrollable.ensureVisible(tester.element(row), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row, matching: find.byType(Icon)).evaluate().where(
          (element) =>
              (element.widget as Icon).icon == Icons.menu_book_outlined),
      isEmpty,
    );
    final clear = find.byKey(const ValueKey('home-course-filter-clear'));
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(clear, findsNothing);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(store.homeFilters.courseKey, isNull);
  });

  testWidgets('long course names truncate on one line at 320dp and 2x',
      (tester) async {
    const longName = '计算方法与实践专题研讨课程同名班级超长名称示例';
    final store = _Store(catalog: const [
      CourseRef(courseId: '1', clazzId: 'k1', name: longName),
      CourseRef(courseId: '2', clazzId: 'k2', name: longName),
    ])
      ..homeFilters = const HomeFilters(courseKey: '1:k1')
      ..replaceAssignmentsForTest([
        _work(
          workId: 'w',
          courseId: '1',
          classId: 'k1',
          courseName: longName,
        ),
      ]);
    addTearDown(store.dispose);
    await _pump(tester, store, size: const Size(320, 900), scale: 2);
    expect(tester.takeException(), isNull);
    await _openFilters(tester);
    await _openCourseMenu(tester);
    final label = find.descendant(
      of: find.byKey(const ValueKey('course-option-1:k1')),
      matching: find.text(longName),
    );
    expect(label, findsOneWidget);
    final text = tester.widget<Text>(label);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(find.text('班级 k1 · 课程 1'), findsNothing);
    expect(find.text('班级 k1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('labels and filters survive restart and follow account switching',
      () async {
    final session = _Session();
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('A');
    await repo.saveCourses(_sameNameCatalog(), account: 'A');
    await repo.saveHomeFilters(
        const HomeFilters(
            courseKey: '1:k1', sortOrder: HomeSortOrder.courseName),
        'A');

    AssignmentStore makeStore() => AssignmentStore(
          sessionStore: session,
          notificationService: _Notifications(),
          widgetSnapshotService: _Snapshot(),
        );

    final first = makeStore();
    addTearDown(first.dispose);
    await first.restoreSession();
    first.replaceAssignmentsForTest([
      _work(workId: 'w', courseId: '1', classId: 'k1'),
    ]);
    List<String> labelsOf(AssignmentStore store) =>
        buildHomeCourseFilterOptions(
          assignments: store.homeDisplayAssignments,
          catalog: store.courses,
          records: store.assignments,
          selectedCourseKey: store.homeFilters.courseKey,
        ).map((option) => option.label).toList();
    expect(labelsOf(first), ['同名课程 · 班级 k1']);
    expect(first.homeFilters.sortOrder, HomeSortOrder.courseName);

    final restarted = makeStore();
    addTearDown(restarted.dispose);
    await restarted.restoreSession();
    restarted.replaceAssignmentsForTest([
      _work(workId: 'w', courseId: '1', classId: 'k1'),
    ]);
    expect(labelsOf(restarted), ['同名课程 · 班级 k1']);
    expect(restarted.homeFilters.courseKey, '1:k1');

    session.account = 'B';
    await restarted.restoreSession();
    expect(restarted.courses, isEmpty);
    expect(restarted.homeFilters.courseKey, isNull);
    expect(restarted.homeFilters.sortOrder, HomeSortOrder.deadlineAsc);

    session.account = 'A';
    await restarted.restoreSession();
    restarted.replaceAssignmentsForTest([
      _work(workId: 'w', courseId: '1', classId: 'k1'),
    ]);
    expect(labelsOf(restarted), ['同名课程 · 班级 k1']);
    expect(restarted.homeFilters.courseKey, '1:k1');
  });

  testWidgets(
      'course filter displays teacher names alongside duplicate class label, searches by teacher, and clips long teacher list at 320x900@2x',
      (tester) async {
    final store = _Store(catalog: const [
      CourseRef(
        courseId: '1',
        clazzId: 'k1',
        name: '大学物理',
        teacherNames: ['张老师', '王老师', '刘老师', '陈老师'],
      ),
      CourseRef(
        courseId: '2',
        clazzId: 'k2',
        name: '大学物理',
        teacherNames: ['李老师'],
      ),
      CourseRef(
        courseId: '3',
        clazzId: 'k3',
        name: '数据结构',
        teacherNames: ['独有教师赵某'],
      ),
    ])
      ..replaceAssignmentsForTest([
        _work(workId: 'w1', courseId: '1', classId: 'k1', courseName: '大学物理'),
        _work(workId: 'w2', courseId: '2', classId: 'k2', courseName: '大学物理'),
        _work(workId: 'w3', courseId: '3', classId: 'k3', courseName: '数据结构'),
      ]);
    addTearDown(store.dispose);

    await _pump(tester, store, size: const Size(320, 900), scale: 2);
    expect(tester.takeException(), isNull);
    await _openFilters(tester);
    await _openCourseMenu(tester);

    expect(find.textContaining('班级 k1 · 张老师、王老师'), findsOneWidget);
    expect(find.text('独有教师赵某'), findsOneWidget);
    final longSubtitle = tester.widget<Text>(
      find.textContaining('班级 k1 · 张老师、王老师'),
    );
    expect(longSubtitle.maxLines, 2);
    expect(longSubtitle.overflow, TextOverflow.ellipsis);

    // Search picker by teacher name finds matching course only.
    await tester.enterText(find.byType(TextField).last, '李老师');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-option-2:k2')), findsOneWidget);
    expect(find.byKey(const ValueKey('course-option-1:k1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'course filter sheet defaults to current term, filters past and all terms with teachers, keeps past selection clearable',
      (tester) async {
    final now = DateTime.utc(2026, 11, 20, 4);
    final store = _Store(catalog: const [
      CourseRef(
        courseId: '1',
        clazzId: 'k1',
        name: '在学高数',
        folderName: '2026年秋',
        teacherNames: ['在学王老师'],
      ),
      CourseRef(
        courseId: '2',
        clazzId: 'k2',
        name: '往期线代',
        folderName: '2025年秋',
        teacherNames: ['往期李老师'],
      ),
    ])
      ..replaceAssignmentsForTest([
        _work(
          workId: 'w1',
          courseId: '1',
          classId: 'k1',
          courseName: '在学高数',
        ),
        Assignment(
          id: 'cx:work:2:k2:w2',
          courseName: '往期线代',
          title: '往期遗留讨论',
          requirementsText: '',
          status: 'pending',
          deadlineAt: null,
          deadlineTrusted: false,
          lastSyncedAt: now,
        ),
      ]);
    addTearDown(store.dispose);

    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home:
          Scaffold(body: AssignmentListScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    // Past archived course is not in current-term home list or default picker.
    expect(find.text('本周作业'), findsNothing);
    expect(find.text('往期遗留讨论'), findsNothing);

    await _openFilters(tester);
    await _openCourseMenu(tester);
    expect(find.byKey(const ValueKey('course-option-1:k1')), findsOneWidget);
    expect(find.byKey(const ValueKey('course-option-2:k2')), findsNothing);

    // Switch picker chip to 往期 -> shows past course with teacher subtitle.
    await tester.tap(find.byKey(const ValueKey('picker-filter-pastTerms')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-option-2:k2')), findsOneWidget);
    expect(find.textContaining('往期李老师'), findsOneWidget);
    expect(find.byKey(const ValueKey('course-option-1:k1')), findsNothing);

    // Select past course -> retains selection & shows its record on Home until cleared.
    await tester.tap(find.byKey(const ValueKey('course-option-2:k2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('课程：往期线代'), findsOneWidget);
    expect(find.text('往期遗留讨论'), findsOneWidget);

    // Clear via 全部课程 restores clean current-term Home.
    await _openFilters(tester);
    await _openCourseMenu(tester);
    expect(find.byKey(const ValueKey('course-option-2:k2')), findsOneWidget);
    await tester.tap(find.text('全部课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('往期遗留讨论'), findsNothing);
  });

  testWidgets(
      'ungrouped silent courses are excluded from currentTerm picker and shown in ungrouped with filterNoticeBuilder',
      (tester) async {
    final now = DateTime.utc(2026, 11, 20, 4);
    final store = _Store(catalog: const [
      CourseRef(
        courseId: '99',
        clazzId: 'k99',
        name: '静默老课',
      ),
    ])
      ..replaceAssignmentsForTest(const []);
    addTearDown(store.dispose);

    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home:
          Scaffold(body: AssignmentListScreen(store: store, clock: () => now)),
    ));
    await tester.pumpAndSettle();

    await _openFilters(tester);
    await _openCourseMenu(tester);

    expect(find.byKey(const ValueKey('course-option-99:k99')), findsNothing);
    expect(
      find.text('本学期暂未识别出课程，可切换到「未分组」或「全部学期」查看'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('picker-filter-ungrouped')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-option-99:k99')), findsOneWidget);
    expect(find.text('未分组'), findsWidgets);
  });
}
