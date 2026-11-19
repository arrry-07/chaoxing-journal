import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

Assignment _work(
  String id, {
  required String course,
  required String title,
  DateTime? due,
  String status = 'pending',
  bool trusted = true,
  String courseId = '1',
  String classId = '2',
}) =>
    Assignment(
      id: 'cx:work:$courseId:$classId:$id',
      courseName: course,
      title: title,
      deadlineAt: due,
      deadlineTrusted: trusted,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.now(),
    );

Assignment _exam(
  String id, {
  String course = '大学英语',
  String title = '考试',
  DateTime? start,
  DateTime? end,
  String status = 'unknown',
  String lifecycle = 'unknown',
  bool notice = false,
  String? related,
  int? duration,
  String requirements = '',
  String courseId = '4',
  String classId = '5',
}) =>
    Assignment(
      id: notice ? 'cx:examNotice:inbox:$id' : 'cx:exam:$courseId:$classId:$id',
      source: AssignmentSource.exam,
      courseName: course,
      title: title,
      deadlineAt: null,
      requirementsText: requirements,
      status: status,
      lastSyncedAt: DateTime.now(),
      exam: ExamInfo(
        examId: id,
        relatedExamId: related,
        courseId: courseId,
        clazzId: classId,
        startAt: start,
        endAt: end,
        startTrusted: start != null,
        endTrusted: end != null,
        lifecycle: lifecycle,
        noticeOnly: notice,
        durationMinutes: duration,
      ),
    );

class _ScreenStore extends AssignmentStore {
  _ScreenStore()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );
  int syncCalls = 0;
  @override
  Future<void> syncAssignments() async {
    syncCalls++;
  }

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    homeFilters = next;
    notifyListeners();
    return true;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AssignmentStore store, {
  Size size = const Size(900, 2600),
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

List<String> _cardIds(WidgetTester tester) => tester
    .widgetList<AssignmentCard>(find.byType(AssignmentCard))
    .map((card) => card.assignment.id)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AssignmentQuery.debugResetDisplayCaches();
  });

  group('unfinished home scope', () {
    testWidgets('home hides submitted and ended but keeps unfinished union',
        (tester) async {
      final now = DateTime.now();
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('submitted',
              course: '高等数学',
              title: '已提交作业',
              due: now.subtract(const Duration(days: 60)),
              status: 'submitted'),
          _work('pending',
              course: '高等数学',
              title: '待提交作业',
              due: now.add(const Duration(days: 10))),
          _work('overdue',
              course: '高等数学',
              title: '逾期待提交作业',
              due: now.subtract(const Duration(days: 5))),
          _work('unknown',
              course: '高等数学',
              title: '状态未知作业',
              due: now.add(const Duration(days: 20)),
              status: 'unknown'),
          _exam('ended',
              title: '已结束考试',
              start: now.subtract(const Duration(days: 2)),
              end: now.subtract(const Duration(days: 1)),
              lifecycle: 'ended'),
          _exam('submitted',
              title: '已提交考试',
              start: now.subtract(const Duration(days: 2)),
              end: now.subtract(const Duration(days: 1)),
              status: 'submitted'),
          _exam('open',
              title: '窗口内考试',
              start: now.subtract(const Duration(days: 1)),
              end: now.add(const Duration(days: 10))),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);

      final all = _cardIds(tester).toSet();
      expect(all, {
        'cx:work:1:2:pending',
        'cx:work:1:2:overdue',
        'cx:work:1:2:unknown',
        'cx:exam:4:5:open',
      });

      store.homeFilters =
          const HomeFilters(type: AssignmentTypeFilter.homework);
      store.notifyListeners();
      await tester.pumpAndSettle();
      final homework = _cardIds(tester).toSet();
      expect(homework, {
        'cx:work:1:2:pending',
        'cx:work:1:2:overdue',
        'cx:work:1:2:unknown'
      });

      store.homeFilters = const HomeFilters(type: AssignmentTypeFilter.exam);
      store.notifyListeners();
      await tester.pumpAndSettle();
      final exam = _cardIds(tester).toSet();
      expect(exam, {'cx:exam:4:5:open'});
      expect(all, homework.union(exam));

      store.homeFilters = const HomeFilters();
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(_cardIds(tester).toSet(), all);
      expect(store.syncCalls, 0);
    });

    testWidgets('course dropdown omits courses with only historical records',
        (tester) async {
      final now = DateTime.now();
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('history',
              course: '历史课程',
              title: '历史作业',
              due: now.subtract(const Duration(days: 30)),
              status: 'submitted',
              courseId: '5',
              classId: '5'),
          _work('current',
              course: '当前课程',
              title: '待提交作业',
              due: now.add(const Duration(days: 3))),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      expect(find.text('历史作业'), findsNothing);

      await tester.tap(find.text('搜索与筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('历史课程'), findsNothing);
      expect(find.text('当前课程'), findsWidgets);
    });

    testWidgets('empty home points to local records when only history exists',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('submitted',
              course: '高等数学',
              title: '已提交作业',
              due: DateTime.now().subtract(const Duration(days: 30)),
              status: 'submitted'),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      expect(find.textContaining('已完成'), findsOneWidget);
      expect(find.text('查看全部本地记录'), findsOneWidget);
    });
  });

  group('undated layout', () {
    testWidgets('undated rows keep the rail and share one group heading',
        (tester) async {
      final now = DateTime.now();
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('dated',
              course: '数学',
              title: '有日期作业',
              due: now.add(const Duration(days: 1))),
          _exam('undated', title: '无时间考试', course: '安全教育'),
          _work('nodeadline', course: '语文', title: '无截止作业'),
          _work('untrusted',
              course: '英语',
              title: '不可信作业',
              due: now.add(const Duration(days: 2)),
              trusted: false),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);

      expect(find.text('待定'), findsNWidgets(2));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('无截止日期'), findsWidgets);
      expect(find.text('无日期与待确认'), findsOneWidget);
      final datedTitle = tester.getTopLeft(find.text('有日期作业'));
      final undatedTitle = tester.getTopLeft(find.text('无时间考试'));
      expect(undatedTitle.dx, datedTitle.dx);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recovery scope does not add the undated heading',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('nd', course: '课程', title: '无截止作业'),
        ]);
      addTearDown(store.dispose);
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: '/assignments?scope=noDeadline',
        routes: [
          GoRoute(
            path: '/assignments',
            builder: (context, state) => AssignmentListScreen(store: store),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('无日期与待确认'), findsNothing);
      expect(find.text('无截止作业'), findsOneWidget);
    });

    testWidgets('large text keeps rail placeholder without overflow',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('dated',
              course: '数学',
              title: '有日期作业',
              due: DateTime.now().add(const Duration(days: 1))),
          _exam('undated', title: '无时间考试', course: '安全教育'),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store, size: const Size(320, 800), scale: 2);
      expect(find.text('待定'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('exam range display', () {
    testWidgets('cross-day trusted exam heading shows the range',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _exam('range',
              title: '跨天考试',
              start: DateTime.utc(2026, 11, 15, 23, 6),
              end: DateTime.utc(2026, 11, 29, 23, 6)),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      expect(find.text('2026年11月16日 周一–11月30日'), findsOneWidget);
      expect(find.text('07:06'), findsOneWidget);
      final semantics = tester.widget<Semantics>(find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').contains('跨天考试')));
      expect(semantics.properties.label, contains('结束'));
    });

    testWidgets('same-day exam heading stays single date', (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _exam('same',
              title: '同日考试',
              start: DateTime.utc(2026, 12, 1, 1, 0),
              end: DateTime.utc(2026, 12, 1, 3, 0)),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      expect(find.text('2026年12月1日 周二'), findsOneWidget);
      expect(find.textContaining('–'), findsNothing);
    });

    testWidgets('yearless notice range heading omits year', (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _exam('n',
              title: '无年份通知考试',
              notice: true,
              duration: 60,
              requirements: '考试时间：11-16 07:06 至 11-30 07:06'),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      expect(find.text('11月16日–11月30日'), findsOneWidget);
      expect(find.textContaining('结束（通知）'), findsNothing);
    });

    testWidgets('undated exam with trusted end shows range line in card',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _exam('endonly',
              title: '只有结束时间考试', end: DateTime.utc(2026, 11, 30, 1, 0)),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      expect(find.text('无日期与待确认'), findsOneWidget);
      expect(find.textContaining('结束 2026年11月30日'), findsOneWidget);
      expect(find.text('待定'), findsOneWidget);
    });

    testWidgets('contiguous same-range exams share one heading',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _exam('a',
              title: '范围考试一',
              start: DateTime.utc(2026, 11, 15, 23, 6),
              end: DateTime.utc(2026, 11, 29, 23, 6)),
          _exam('b',
              title: '范围考试二',
              courseId: '6',
              classId: '7',
              start: DateTime.utc(2026, 11, 15, 23, 6),
              end: DateTime.utc(2026, 11, 29, 23, 6)),
          _exam('c',
              title: '另一范围考试',
              courseId: '8',
              classId: '9',
              start: DateTime.utc(2026, 12, 1, 1, 0),
              end: DateTime.utc(2026, 12, 5, 1, 0)),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      expect(find.text('2026年11月16日 周一–11月30日'), findsOneWidget);
      expect(find.text('2026年12月1日 周二–12月5日'), findsOneWidget);
    });
  });
}
