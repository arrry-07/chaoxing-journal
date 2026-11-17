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
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/exam_schedule_presentation.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

final _now = DateTime.utc(2026, 11, 16, 2);

DateTime _bj(int year, int month, int day, int hour, int minute) =>
    DateTime.utc(year, month, day, hour - 8, minute);

Assignment _work(
  String id, {
  required String course,
  required String title,
  DateTime? due,
  String status = 'pending',
  bool trusted = true,
  bool failed = false,
  String courseId = '1',
  String classId = '2',
}) =>
    Assignment(
      id: 'cx:work:$courseId:$classId:$id',
      courseName: course,
      title: title,
      deadlineAt: due,
      deadlineTrusted: trusted,
      deadlineReadFailed: failed,
      requirementsText: '',
      status: status,
      lastSyncedAt: _now,
    );

Assignment _activity(
  String id, {
  required int type,
  required String course,
  required String title,
  DateTime? due,
  String status = 'pending',
  bool trusted = true,
  String courseId = '1',
  String classId = '2',
}) =>
    Assignment(
      id: 'cx:activity:$courseId:$classId:$id',
      source: AssignmentSource.classroomActivity,
      courseName: course,
      title: title,
      deadlineAt: due,
      deadlineTrusted: trusted,
      requirementsText: '',
      status: status,
      lastSyncedAt: _now,
      activityType: type,
      persistedCourseTaskKey:
          type == 77 ? 'cx:activity:$courseId:$classId:$id' : null,
    );

Assignment _exam(
  String id, {
  String course = '大学英语',
  String title = '考试',
  DateTime? start,
  DateTime? end,
  String lifecycle = 'unknown',
  String status = 'unknown',
  String? courseId = '4',
  String? classId = '5',
  bool notice = false,
  String? related,
  int? duration,
  String requirements = '',
}) =>
    Assignment(
      id: notice
          ? 'cx:examNotice:inbox:$id'
          : 'cx:exam:${courseId ?? 'account'}:${classId ?? 'account'}:$id',
      source: AssignmentSource.exam,
      courseName: course,
      title: title,
      deadlineAt: null,
      requirementsText: requirements,
      status: status,
      lastSyncedAt: _now,
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

List<Assignment> _catalog() => AssignmentQuery.scope([
      _work('pending',
          course: '高等数学', title: '待提交作业', due: _bj(2026, 12, 2, 23, 55)),
      _work('submitted',
          course: '高等数学',
          title: '已提交作业',
          due: _bj(2026, 9, 21, 11, 5),
          status: 'submitted'),
      _work('unknown',
          course: '高等数学',
          title: '状态未知作业',
          due: _bj(2027, 1, 30, 8, 0),
          status: 'unknown'),
      _work('untrusted',
          course: '高等数学',
          title: '时间待确认作业',
          due: _bj(2026, 12, 5, 8, 0),
          trusted: false),
      _activity('a35',
          type: 35,
          course: '高等数学',
          title: '随堂任务',
          due: _bj(2026, 12, 3, 10, 0)),
      _activity('a42',
          type: 42,
          course: '高等数学',
          title: '过期随堂练习',
          due: _bj(2026, 11, 1, 10, 0),
          status: 'unknown'),
      _activity('a77',
          type: 77,
          course: '人工智能',
          title: 'AI实践',
          due: _bj(2026, 12, 4, 10, 0),
          courseId: '3',
          classId: '4'),
      _exam('future',
          title: '未来考试', start: _bj(2027, 1, 10, 9, 0), lifecycle: 'scheduled'),
      _exam('ended',
          title: '已结束考试',
          start: _bj(2026, 11, 16, 7, 6),
          end: _bj(2026, 11, 16, 9, 6),
          lifecycle: 'ended'),
      _exam('open', title: '开考未知结束考试', start: _bj(2026, 11, 15, 9, 0)),
      _exam('account',
          title: '账号考试',
          course: '账号考试',
          start: _bj(2026, 12, 20, 9, 0),
          courseId: null,
          classId: null,
          lifecycle: 'scheduled'),
      _exam('n9',
          course: '线性代数',
          title: '线性代数期中考试',
          notice: true,
          related: '9',
          courseId: '6',
          classId: '7',
          duration: 60,
          requirements: '考试时间：12-01 09:00 至 12-01 11:00'),
      _exam('9',
          course: '线性代数', title: '线性代数期中考试', courseId: '6', classId: '7'),
      _exam('9',
          course: '概率论',
          title: '线性代数期中考试',
          courseId: '8',
          classId: '9',
          start: _bj(2026, 12, 8, 9, 0),
          lifecycle: 'scheduled'),
      _work('history',
          course: '历史课程',
          title: '历史-only作业',
          due: _bj(2026, 8, 1, 8, 0),
          status: 'submitted',
          courseId: '5',
          classId: '5'),
    ], {});

Set<String> _ids(
  List<Assignment> catalog, {
  AssignmentTypeFilter type = AssignmentTypeFilter.all,
  AssignmentDeadlineFilter deadline = AssignmentDeadlineFilter.all,
  String query = '',
  String? courseKey,
  Set<String> followed = const {},
}) =>
    AssignmentQuery.filterHome(
      catalog,
      type: type,
      deadline: deadline,
      query: query,
      courseKey: courseKey,
      followed: followed,
      includeHistorical: false,
      now: _now,
    ).map((assignment) => assignment.id).toSet();

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
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? StudyAssistantTheme.light,
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
    ExamSchedulePresentation.debugResetCache();
  });

  group('query scope union', () {
    test('all equals homework union exam across deadline search and course',
        () {
      final catalog = _catalog();
      final snapshot = List<Assignment>.of(catalog);
      for (final deadline in homeDeadlineFilterChoices) {
        for (final query in ['', '考试', '高等数学', '不存在']) {
          for (final courseKey in [null, '1:2', '4:5', '5:5', '6:7']) {
            final all = _ids(catalog,
                deadline: deadline, query: query, courseKey: courseKey);
            final homework = _ids(catalog,
                type: AssignmentTypeFilter.homework,
                deadline: deadline,
                query: query,
                courseKey: courseKey);
            final exam = _ids(catalog,
                type: AssignmentTypeFilter.exam,
                deadline: deadline,
                query: query,
                courseKey: courseKey);
            expect(all, homework.union(exam),
                reason: 'deadline=$deadline query=$query course=$courseKey');
            expect(all, containsAll(homework));
            expect(all, containsAll(exam));
          }
        }
      }
      final followedAll = _ids(catalog, followed: {'1:2'});
      expect(
          followedAll,
          _ids(catalog, type: AssignmentTypeFilter.homework, followed: {'1:2'})
              .union(_ids(catalog,
                  type: AssignmentTypeFilter.exam, followed: {'1:2'})));
      expect(catalog, snapshot);
    });

    test('account exams stay without a course filter and leave with one', () {
      final catalog = _catalog();
      const accountId = 'cx:exam:account:account:account';
      expect(_ids(catalog), contains(accountId));
      expect(
          _ids(catalog, type: AssignmentTypeFilter.exam), contains(accountId));
      expect(_ids(catalog, courseKey: '1:2'), isNot(contains(accountId)));
      expect(_ids(catalog, deadline: AssignmentDeadlineFilter.notExpired),
          contains(accountId));
    });

    test('formal exams merge with notices by identity not by title', () {
      final catalog = _catalog();
      final examIds = _ids(catalog, type: AssignmentTypeFilter.exam);
      expect(examIds, contains('cx:exam:6:7:9'));
      expect(examIds, isNot(contains('cx:examNotice:inbox:n9')));
      expect(examIds, contains('cx:exam:8:9:9'));
      expect(examIds.where((id) => id.contains(':9')).length,
          greaterThanOrEqualTo(2));
    });

    test('archived classroom practice stays local history for every filter',
        () {
      final catalog = _catalog();
      const archived = 'cx:activity:1:2:a42';
      for (final type in homeTypeFilterChoices) {
        for (final deadline in homeDeadlineFilterChoices) {
          expect(_ids(catalog, type: type, deadline: deadline),
              isNot(contains(archived)));
        }
      }
      expect(_ids(catalog), contains('cx:work:1:2:unknown'));
      expect(_ids(catalog), contains('cx:activity:1:2:a35'));
      expect(_ids(catalog), contains('cx:activity:3:4:a77'));
      expect(catalog.map((assignment) => assignment.id), contains(archived));
    });
  });

  group('real time ordering', () {
    List<Assignment> sample() => [
          _work('a',
              course: 'Zulu课程',
              title: 'A九月已提交作业',
              due: _bj(2026, 9, 21, 11, 5),
              status: 'submitted'),
          _exam('b',
              course: 'Yankee课程',
              title: 'B十一月已结束考试',
              start: _bj(2026, 11, 16, 7, 6),
              end: _bj(2026, 11, 16, 9, 6),
              lifecycle: 'ended'),
          _work('c',
              course: 'Xray课程',
              title: 'C十二月待提交作业',
              due: _bj(2026, 12, 2, 23, 55)),
          _work('d',
              course: 'Whiskey课程',
              title: 'D次年一月状态未知作业',
              due: _bj(2027, 1, 30, 8, 0),
              status: 'unknown'),
          _work('e', course: 'Alpha课程', title: 'E无时间作业'),
          _work('f',
              course: 'Bravo课程',
              title: 'F早逾期作业',
              due: _bj(2026, 11, 10, 12, 0)),
          _work('g',
              course: 'Charlie课程',
              title: 'G晚逾期作业',
              due: _bj(2026, 11, 14, 12, 0)),
        ];

    test('FB-005 1.8.06 history sorts by real time and overdue stays bottom',
        () {
      final records = sample();
      final original = List<Assignment>.of(records);
      List<String> titles(HomeSortOrder order) => AssignmentQuery.sortHome(
            records,
            order,
            now: _now,
          ).map((assignment) => assignment.title).toList();
      expect(titles(HomeSortOrder.deadlineAsc), [
        'A九月已提交作业',
        'B十一月已结束考试',
        'C十二月待提交作业',
        'D次年一月状态未知作业',
        'E无时间作业',
        'F早逾期作业',
        'G晚逾期作业',
      ]);
      expect(titles(HomeSortOrder.deadlineDesc), [
        'D次年一月状态未知作业',
        'C十二月待提交作业',
        'B十一月已结束考试',
        'A九月已提交作业',
        'E无时间作业',
        'G晚逾期作业',
        'F早逾期作业',
      ]);
      expect(records, original);
    });

    test('FB-005 middle tier keeps course name identity order both ways', () {
      final dated = _work('dated',
          course: '数学', title: '有时间作业', due: _now.add(const Duration(days: 1)));
      final completedUntrusted = _work('cu',
          course: '英语',
          title: '已完成但时间不可信',
          due: _now.subtract(const Duration(days: 2)),
          status: 'submitted',
          trusted: false);
      final noDeadline = _work('nd', course: '语文', title: '无截止作业');
      final unknown = _work('uk',
          course: '物理',
          title: '状态未知作业',
          due: _now.add(const Duration(days: 2)),
          status: 'unknown');
      final overdueEarly = _work('oe',
          course: '化学',
          title: '早逾期',
          due: _now.subtract(const Duration(days: 5)));
      final overdueLate = _work('ol',
          course: '生物',
          title: '晚逾期',
          due: _now.subtract(const Duration(days: 1)));
      final records = [
        overdueLate,
        noDeadline,
        dated,
        overdueEarly,
        completedUntrusted,
        unknown,
      ];
      List<String> titles(HomeSortOrder order) => AssignmentQuery.sortHome(
            records,
            order,
            now: _now,
          ).map((assignment) => assignment.title).toList();
      expect(titles(HomeSortOrder.deadlineAsc), [
        '有时间作业',
        '状态未知作业',
        '已完成但时间不可信',
        '无截止作业',
        '早逾期',
        '晚逾期',
      ]);
      expect(titles(HomeSortOrder.deadlineDesc), [
        '状态未知作业',
        '有时间作业',
        '已完成但时间不可信',
        '无截止作业',
        '晚逾期',
        '早逾期',
      ]);
    });

    test('time ties fall back to course title class and record identity', () {
      final due = _now.add(const Duration(days: 1));
      final records = [
        _work('2', course: '数学', title: '同名作业', due: due, classId: '3'),
        _work('1', course: '数学', title: '同名作业', due: due, classId: '2'),
        _work('b', course: '数学', title: 'Beta', due: due),
        _work('a', course: '数学', title: 'Alpha', due: due),
        _work('w', course: '物理', title: 'Alpha', due: due),
      ];
      expect(
        AssignmentQuery.sortHome(records, HomeSortOrder.deadlineAsc, now: _now)
            .map((assignment) => assignment.id),
        [
          'cx:work:1:2:a',
          'cx:work:1:2:b',
          'cx:work:1:2:1',
          'cx:work:1:3:2',
          'cx:work:1:2:w',
        ],
      );
    });

    test('beijing midnight exact due and cross year boundaries', () {
      final midnight = _bj(2026, 11, 17, 0, 0);
      final records = [
        _work('exact', course: '课程', title: '恰好到期', due: _now),
        _work('micro',
            course: '课程',
            title: '微秒之后',
            due: _now.add(const Duration(microseconds: 1))),
        _work('midnight', course: '课程', title: '北京零点', due: midnight),
        _work('nextYear',
            course: '课程', title: '跨年', due: _bj(2027, 1, 1, 0, 0)),
      ];
      expect(
        AssignmentQuery.sortHome(records, HomeSortOrder.deadlineAsc, now: _now)
            .map((assignment) => assignment.title),
        ['微秒之后', '北京零点', '跨年', '恰好到期'],
      );
      expect(
        AssignmentQuery.filterHome(records,
            deadline: AssignmentDeadlineFilter.overdue,
            includeHistorical: true,
            now: _now),
        [records.first],
      );
      expect(AssignmentQuery.dayKey(midnight), DateTime(2026, 11, 17));
    });

    test('untrusted and conflicting times never join the time tiers', () {
      final formal = _exam('9',
          course: '线性代数', title: '冲突考试', courseId: '6', classId: '7');
      final noticeA = _exam('n1',
          course: '线性代数',
          title: '冲突考试',
          notice: true,
          related: '9',
          courseId: '6',
          classId: '7',
          duration: 60);
      final noticeB = _exam('n2',
          course: '线性代数',
          title: '冲突考试',
          notice: true,
          related: '9',
          courseId: '6',
          classId: '7',
          duration: 90);
      final untrusted = _work('u',
          course: '语文',
          title: '不可信作业',
          due: _now.add(const Duration(days: 1)),
          trusted: false);
      final failed = _work('f',
          course: '英语',
          title: '读取失败作业',
          due: _now.add(const Duration(days: 1)),
          failed: true);
      final dated = _work('d',
          course: '数学', title: '有时间作业', due: _now.add(const Duration(days: 2)));
      final records = [formal, noticeA, noticeB, untrusted, failed, dated];
      final projected = AssignmentQuery.projectDisplay(records);
      expect(projected.map((assignment) => assignment.id),
          contains('cx:exam:6:7:9'));
      expect(
        AssignmentQuery.sortHome(projected, HomeSortOrder.deadlineAsc,
                now: _now, sourceRecords: records)
            .map((assignment) => assignment.title),
        ['有时间作业', '冲突考试', '读取失败作业', '不可信作业'],
      );
      expect(
        AssignmentQuery.sortHome(projected, HomeSortOrder.deadlineDesc,
                now: _now, sourceRecords: records)
            .map((assignment) => assignment.title),
        ['有时间作业', '冲突考试', '读取失败作业', '不可信作业'],
      );
    });
  });

  group('exam not expired', () {
    test('not expired needs a future opening or a future end', () {
      final futureStart = _exam('future',
          title: '未来开考',
          start: _now.add(const Duration(hours: 1)),
          lifecycle: 'scheduled');
      final pastNoEnd = _exam('past',
          title: '开考已过结束未知', start: _now.subtract(const Duration(hours: 1)));
      final inProgress = _exam('progress',
          title: '进行中',
          start: _now.subtract(const Duration(hours: 1)),
          end: _now.add(const Duration(hours: 1)));
      final pastDuration = _exam('duration',
          title: '时长已结束',
          start: _now.subtract(const Duration(hours: 2)),
          duration: 60);
      final ended = _exam('ended',
          title: '官方已结束',
          start: _now.subtract(const Duration(hours: 1)),
          end: _now.add(const Duration(hours: 1)),
          lifecycle: 'ended');
      final cancelled = _exam('cancelled',
          title: '官方已取消',
          start: _now.add(const Duration(hours: 1)),
          lifecycle: 'cancelled');
      final submitted = _exam('submitted',
          title: '已提交考试',
          start: _now.add(const Duration(hours: 1)),
          status: 'submitted');
      final openNotice = _exam('nopen',
          title: '无年份开放通知',
          notice: true,
          duration: 60,
          requirements: '考试时间：11-16 07:06 至 11-30 07:06');
      final pastNotice = _exam('npast',
          title: '无年份过期通知',
          notice: true,
          duration: 60,
          requirements: '考试时间：11-01 07:06 至 11-02 07:06');
      final rows = [
        futureStart,
        pastNoEnd,
        inProgress,
        pastDuration,
        ended,
        cancelled,
        submitted,
        openNotice,
        pastNotice,
      ];
      final notExpired = AssignmentQuery.filterHome(rows,
              deadline: AssignmentDeadlineFilter.notExpired,
              includeHistorical: true,
              now: _now)
          .map((assignment) => assignment.title)
          .toSet();
      expect(notExpired, {'未来开考', '进行中', '无年份开放通知'});
      final all =
          AssignmentQuery.filterHome(rows, includeHistorical: true, now: _now)
              .map((assignment) => assignment.title)
              .toSet();
      expect(
          all,
          containsAll(
              ['开考已过结束未知', '时长已结束', '无年份过期通知', '官方已结束', '官方已取消', '已提交考试']));
      expect(
          AssignmentQuery.filterHome(rows,
              deadline: AssignmentDeadlineFilter.overdue,
              includeHistorical: true,
              now: _now),
          isEmpty);
      expect(openNotice.exam!.startTrusted, isFalse);
      expect(openNotice.exam!.startAt, isNull);
    });
  });

  group('home screen', () {
    testWidgets(
        'default home shows the unfinished catalog and type switches keep the union',
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
          _exam('ended',
              title: '已结束考试',
              start: now.subtract(const Duration(days: 1)),
              end: now.subtract(const Duration(hours: 1)),
              lifecycle: 'ended'),
          _exam('future',
              title: '未来考试',
              start: now.add(const Duration(days: 60)),
              lifecycle: 'scheduled'),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);

      final all = _cardIds(tester).toSet();
      expect(all, {
        'cx:work:1:2:pending',
        'cx:exam:4:5:future',
      });

      store.homeFilters =
          const HomeFilters(type: AssignmentTypeFilter.homework);
      store.notifyListeners();
      await tester.pumpAndSettle();
      final homework = _cardIds(tester).toSet();
      expect(homework, {'cx:work:1:2:pending'});

      store.homeFilters = const HomeFilters(type: AssignmentTypeFilter.exam);
      store.notifyListeners();
      await tester.pumpAndSettle();
      final exam = _cardIds(tester).toSet();
      expect(exam, {'cx:exam:4:5:future'});
      expect(all, homework.union(exam));

      store.homeFilters = const HomeFilters();
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(_cardIds(tester).toSet(), all);
      expect(store.syncCalls, 0);
    });

    testWidgets('sort entry opens the shared panel and only apply saves',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('w',
              course: '课程',
              title: '作业',
              due: DateTime.now().add(const Duration(days: 1))),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);

      await tester.tap(find.byKey(const ValueKey('current-home-sort')));
      await tester.pumpAndSettle();
      expect(find.text('搜索、筛选与排序'), findsOneWidget);
      expect(
          tester
              .widget<RadioGroup<HomeSortOrder>>(
                  find.byType(RadioGroup<HomeSortOrder>))
              .groupValue,
          HomeSortOrder.deadlineAsc);
      await tester.tap(find.byKey(const ValueKey('sort-deadlineDesc')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineAsc);
      expect(find.text('时间近到远'), findsOneWidget);

      await tester.tap(find.text('搜索与筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sort-deadlineDesc')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
      expect(find.text('时间远到近'), findsOneWidget);
      expect(store.syncCalls, 0);
    });

    testWidgets('status owns its row and actions keep 48dp targets',
        (tester) async {
      final store = _ScreenStore()
        ..syncReport = const SyncReport(phase: SyncPhase.partial, issues: [
          SyncIssue(SyncIssueKind.network, '课程读取失败', stage: 'course'),
        ])
        ..replaceAssignmentsForTest([
          _work('w',
              course: '课程',
              title: '作业',
              due: DateTime.now().add(const Duration(days: 1))),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);

      const statusText = '部分课程未更新 · 显示上次记录';
      expect(find.text(statusText), findsOneWidget);
      expect(find.text('上次记录'), findsNothing);
      final statusSemantics = tester.widget<Semantics>(find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == statusText &&
              widget.properties.liveRegion == true));
      expect(statusSemantics, isNotNull);

      final filterInk = find
          .ancestor(of: find.text('搜索与筛选'), matching: find.byType(InkWell))
          .first;
      final sortInk = find
          .ancestor(
              of: find.byKey(const ValueKey('current-home-sort')),
              matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(filterInk).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(sortInk).height, greaterThanOrEqualTo(48));
      final filterTop = tester.getTopLeft(filterInk).dy;
      final sortTop = tester.getTopLeft(sortInk).dy;
      expect((filterTop - sortTop).abs(), lessThan(1));
      expect(tester.getTopLeft(find.text(statusText)).dy, lessThan(filterTop));
      expect(
          tester
              .widget<Semantics>(find.byWidgetPredicate((widget) =>
                  widget is Semantics &&
                  widget.properties.label == '当前排序：时间近到远，打开搜索、筛选与排序'))
              .properties
              .button,
          isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'narrow width and large text stack actions without truncating status',
        (tester) async {
      final store = _ScreenStore()
        ..syncReport = const SyncReport(phase: SyncPhase.failed)
        ..replaceAssignmentsForTest([
          _work('w',
              course: '课程',
              title: '作业',
              due: DateTime.now().add(const Duration(days: 1))),
        ]);
      addTearDown(store.dispose);
      const statusText = '更新失败 · 显示上次记录';
      for (final scenario in [
        (const Size(320, 800), 1.0),
        (const Size(320, 800), 2.0),
        (const Size(375, 812), 1.5),
        (const Size(800, 360), 1.0),
      ]) {
        await _pumpScreen(tester, store, size: scenario.$1, scale: scenario.$2);
        expect(find.text(statusText), findsOneWidget,
            reason: '${scenario.$1} @${scenario.$2}');
        final statusWidget = tester.widget<Text>(find.text(statusText));
        expect(statusWidget.overflow, isNot(TextOverflow.ellipsis));
        expect(statusWidget.softWrap, isNot(false));
        final filterLeft = tester.getTopLeft(find.text('搜索与筛选'));
        final sortLeft =
            tester.getTopLeft(find.byKey(const ValueKey('current-home-sort')));
        final sideBySide = (filterLeft.dy - sortLeft.dy).abs() < 1;
        if (!sideBySide) {
          expect(filterLeft.dy, lessThan(sortLeft.dy));
          expect(filterLeft.dx, sortLeft.dx);
        }
        expect(tester.takeException(), isNull,
            reason: '${scenario.$1} @${scenario.$2}');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('recovery scope keeps its header without home actions',
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

      expect(find.byKey(const ValueKey('assignment-recovery-scope')),
          findsOneWidget);
      expect(find.text('无截止作业'), findsWidgets);
      expect(find.textContaining('共 1 项'), findsOneWidget);
      expect(find.text('搜索与筛选'), findsNothing);
      expect(find.text('已筛选'), findsNothing);
      expect(find.text('时间近到远'), findsNothing);
      expect(find.text('尚未读取作业'), findsOneWidget);
      expect(store.homeFilters, const HomeFilters());
    });

    testWidgets('filter and sort changes neither sync nor invalidate the index',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('w',
              course: '课程',
              title: '作业',
              due: DateTime.now().add(const Duration(days: 1))),
          _exam('e',
              title: '考试',
              start: DateTime.now().add(const Duration(days: 2)),
              lifecycle: 'scheduled'),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      final index = store.homeDisplayIndex;

      await tester.tap(find.byKey(const ValueKey('current-home-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-exam')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sort-deadlineDesc')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();

      expect(store.homeFilters.type, AssignmentTypeFilter.exam);
      expect(store.homeFilters.sortOrder, HomeSortOrder.deadlineDesc);
      expect(identical(store.homeDisplayIndex, index), isTrue);
      expect(store.syncCalls, 0);
      expect(_cardIds(tester), ['cx:exam:4:5:e']);
    });

    testWidgets('minute rebuild does not reparse notice ranges',
        (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _exam('n',
              title: '无年份考试通知',
              notice: true,
              duration: 60,
              requirements: '考试时间：12-01 09:00 至 12-01 11:00'),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store);
      final index = store.homeDisplayIndex;
      final reads = AssignmentQuery.debugNoticeRangeReadCount;
      final indexReads = index.noticeRangeReadCount;

      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(identical(store.homeDisplayIndex, index), isTrue);
      expect(AssignmentQuery.debugNoticeRangeReadCount, reads);
      expect(index.noticeRangeReadCount, indexReads);
      expect(find.text('无年份考试通知'), findsOneWidget);
    });

    testWidgets('dark theme keeps status and actions readable', (tester) async {
      final store = _ScreenStore()
        ..replaceAssignmentsForTest([
          _work('w',
              course: '课程',
              title: '作业',
              due: DateTime.now().add(const Duration(days: 1))),
        ]);
      addTearDown(store.dispose);
      await _pumpScreen(tester, store, theme: ThemeData.dark());
      expect(find.text('搜索与筛选'), findsOneWidget);
      expect(find.byKey(const ValueKey('current-home-sort')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
