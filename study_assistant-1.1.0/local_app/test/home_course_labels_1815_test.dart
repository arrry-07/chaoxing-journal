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

List<CourseRef> _sameNameCatalog() => const [
      CourseRef(courseId: '1', clazzId: 'k1', name: '同名课程'),
      CourseRef(courseId: '2', clazzId: 'k2', name: '同名课程'),
      CourseRef(courseId: '3', clazzId: 'k3', name: '同名课程'),
    ];

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
  final courseRow = find.text('所选课程');
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
    expect(find.byKey(const ValueKey('course-option-3:k3')), findsNothing);
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
}
