import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

final _now = DateTime.utc(2026, 11, 16);

Assignment _work(
  String id,
  String title,
  DateTime due, {
  String status = 'pending',
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: '高等数学',
      title: title,
      deadlineAt: due,
      requirementsText: '',
      status: status,
      lastSyncedAt: _now,
    );

Assignment _examNotice() => Assignment(
      id: 'cx:examNotice:inbox:notice',
      source: AssignmentSource.exam,
      courseName: '大学英语',
      title: '开放性期中考试',
      deadlineAt: null,
      requirementsText: '考试时间：11-16 07:06:00 至 11-30 07:06:31',
      status: 'unknown',
      lastSyncedAt: _now,
      exam: const ExamInfo(
        examId: 'notice',
        relatedExamId: '3',
        courseId: '4',
        clazzId: '5',
        noticeOnly: true,
        durationMinutes: 60,
      ),
    );

Assignment _formalExam() => Assignment(
      id: 'cx:exam:4:5:3',
      source: AssignmentSource.exam,
      courseName: '大学英语',
      title: '开放性期中考试',
      deadlineAt: null,
      requirementsText: '以官方考试列表为准',
      status: 'unknown',
      lastSyncedAt: _now,
      exam: const ExamInfo(
        examId: '3',
        courseId: '4',
        clazzId: '5',
      ),
    );

class _Store extends AssignmentStore {
  _Store(this.rows)
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  final List<Assignment> rows;

  @override
  List<Assignment> get homeDisplayAssignments =>
      AssignmentQuery.currentDisplay(rows, _now);

  @override
  List<Assignment> get homeCatalogAssignments => rows;

  @override
  List<Assignment> get courseAssignments => rows;

  @override
  Assignment? findAssignment(String id) =>
      rows.where((assignment) => assignment.id == id).firstOrNull;

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    homeFilters = next;
    notifyListeners();
    return true;
  }
}

Future<void> _pump(WidgetTester tester, _Store store) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(store.dispose);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))),
  );
  await tester.pumpAndSettle();
}

List<String> _visibleTitles(WidgetTester tester) => tester
    .widgetList<AssignmentCard>(find.byType(AssignmentCard))
    .map((card) => card.assignment.title)
    .toList();

void main() {
  testWidgets('yearless exam is mixed chronologically instead of placed last',
      (tester) async {
    final store = _Store([
      _examNotice(),
      _formalExam(),
      _work('dec', '十二月作业', DateTime.utc(2026, 12, 2)),
      _work('jan', '一月作业', DateTime.utc(2027, 1, 30)),
    ])
      ..homeFilters = const HomeFilters(sortOrder: HomeSortOrder.deadlineAsc);

    await _pump(tester, store);

    expect(_visibleTitles(tester), ['开放性期中考试', '十二月作业', '一月作业']);
    expect(find.text('11月16日'), findsOneWidget);
    expect(find.text('07:06'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('type filter includes submitted homework while default does not',
      (tester) async {
    final rows = [
      _work('done-1', '已提交一', DateTime.utc(2026, 11, 1), status: 'submitted'),
      _work('done-2', '已提交二', DateTime.utc(2026, 11, 2), status: 'submitted'),
      _work('pending', '待提交', DateTime.utc(2026, 11, 20)),
    ];
    final store = _Store(rows);
    await _pump(tester, store);
    expect(_visibleTitles(tester), ['待提交']);

    store.homeFilters = const HomeFilters(
      type: AssignmentTypeFilter.homework,
      sortOrder: HomeSortOrder.deadlineAsc,
    );
    store.notifyListeners();
    await tester.pumpAndSettle();

    expect(_visibleTitles(tester), ['待提交', '已提交二', '已提交一']);
    expect(find.text('已提交'), findsNWidgets(2));
  });

  testWidgets('not-expired keeps a yearless open exam and excludes completed',
      (tester) async {
    final store = _Store([
      _examNotice(),
      _formalExam(),
      _work('pending', '未截止作业', DateTime.utc(2026, 11, 20)),
      _work('done', '已完成作业', DateTime.utc(2026, 11, 21), status: 'submitted'),
    ])
      ..homeFilters = const HomeFilters(
        deadline: AssignmentDeadlineFilter.notExpired,
        sortOrder: HomeSortOrder.deadlineAsc,
      );

    await _pump(tester, store);

    expect(_visibleTitles(tester), ['开放性期中考试', '未截止作业']);
    expect(find.text('已完成作业'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('course filter lists a course that only has historical records',
      (tester) async {
    final store = _Store([
      _work('done', '历史作业', DateTime.utc(2026, 11, 1), status: 'submitted'),
    ]);
    await _pump(tester, store);
    expect(find.text('历史作业'), findsNothing);

    await tester.tap(find.text('搜索与筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsWidgets);
  });
}
