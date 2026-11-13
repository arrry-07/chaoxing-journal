import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';

Assignment _sortRecord(
  String workId, {
  required String courseName,
  required String title,
  DateTime? deadlineAt,
  bool trusted = true,
  bool failed = false,
  String? rawDeadline,
  String status = 'pending',
  String courseId = '1',
  String classId = '2',
}) =>
    Assignment(
      id: 'cx:work:$courseId:$classId:$workId',
      courseName: courseName,
      title: title,
      deadlineAt: deadlineAt,
      deadlineTrusted: trusted,
      deadlineReadFailed: failed,
      deadlineRawText: rawDeadline,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime.utc(2026, 11, 12),
    );

void main() {
  test('sortHome supports all orders without mutating the source list', () {
    final now = DateTime.utc(2026, 11, 12, 2);
    final alpha = _sortRecord(
      'a',
      courseName: ' course b ',
      title: 'alpha',
      deadlineAt: now.add(const Duration(days: 5)),
    );
    final bravo = _sortRecord(
      'b',
      courseName: 'course A',
      title: 'Bravo',
      deadlineAt: now.add(const Duration(days: 1)),
    );
    final cachedFailure = _sortRecord(
      'c',
      courseName: 'course C',
      title: 'charlie',
      deadlineAt: now.subtract(const Duration(days: 1)),
      failed: true,
    );
    final unknownYear = _sortRecord(
      'd',
      courseName: 'course D',
      title: 'delta',
      trusted: false,
      rawDeadline: '11月20日（年份待确认）',
    );
    final noDeadline = _sortRecord(
      'e',
      courseName: 'course E',
      title: 'echo',
    );
    final records = [
      noDeadline,
      cachedFailure,
      bravo,
      unknownYear,
      alpha,
    ];
    final originalOrder = records.toList();

    List<String> ids(HomeSortOrder order) =>
        AssignmentQuery.sortHome(records, order, now: now)
            .map((assignment) => assignment.title)
            .toList();

    expect(ids(HomeSortOrder.grouped),
        ['echo', 'charlie', 'Bravo', 'delta', 'alpha']);
    expect(records, originalOrder);
    expect(
        identical(
            AssignmentQuery.sortHome(records, HomeSortOrder.grouped, now: now),
            records),
        isFalse);
    expect(ids(HomeSortOrder.deadlineAsc),
        ['Bravo', 'alpha', 'echo', 'charlie', 'delta']);
    expect(ids(HomeSortOrder.deadlineDesc),
        ['alpha', 'Bravo', 'echo', 'charlie', 'delta']);
    expect(ids(HomeSortOrder.courseName),
        ['Bravo', 'alpha', 'echo', 'charlie', 'delta']);
    expect(ids(HomeSortOrder.title),
        ['alpha', 'Bravo', 'echo', 'charlie', 'delta']);
  });

  test('sort ties preserve same-title classes with deterministic identity', () {
    final now = DateTime.utc(2026, 11, 12, 2);
    final sameDeadline = now.add(const Duration(days: 2));
    final classNine = _sortRecord(
      'same',
      courseName: '同名课程',
      title: '同名作业',
      deadlineAt: sameDeadline,
      courseId: '1',
      classId: '9',
    );
    final classThree = _sortRecord(
      'same',
      courseName: '同名课程',
      title: '同名作业',
      deadlineAt: sameDeadline,
      courseId: '1',
      classId: '3',
    );
    final earlierTitle = _sortRecord(
      'same',
      courseName: '同名课程',
      title: 'A 作业',
      deadlineAt: sameDeadline,
      courseId: '1',
      classId: '1',
    );
    final idZulu = _sortRecord(
      'id-z',
      courseName: '同名课程',
      title: '同名作业',
      deadlineAt: sameDeadline,
      courseId: '1',
      classId: '2',
    );
    final idAlpha = _sortRecord(
      'id-a',
      courseName: '同名课程',
      title: '同名作业',
      deadlineAt: sameDeadline,
      courseId: '1',
      classId: '2',
    );
    final records = [classNine, idZulu, earlierTitle, classThree, idAlpha];

    final sorted = AssignmentQuery.sortHome(
      records,
      HomeSortOrder.deadlineAsc,
      now: now,
    );
    expect(sorted.map((assignment) => assignment.courseKey),
        ['1:1', '1:2', '1:2', '1:3', '1:9']);
    expect(sorted[1].id, endsWith(':id-a'));
    expect(sorted[2].id, endsWith(':id-z'));

    final grouped = AssignmentQuery.home(records, now, {}).near;
    expect(grouped.map((assignment) => assignment.courseKey),
        ['1:1', '1:2', '1:2', '1:3', '1:9']);
    expect(grouped[1].id, endsWith(':id-a'));
    expect(grouped[2].id, endsWith(':id-z'));
  });

  test('deadline order keeps bucket priority when direction changes', () {
    final now = DateTime.utc(2026, 11, 12, 2);
    final near = _sortRecord(
      'near',
      courseName: '课程',
      title: '近期',
      deadlineAt: now.add(const Duration(days: 1)),
    );
    final far = _sortRecord(
      'far',
      courseName: '课程',
      title: '较远',
      deadlineAt: now.add(const Duration(days: 20)),
    );
    final noDeadline = _sortRecord(
      'none',
      courseName: '课程',
      title: '无截止',
    );
    final pending = _sortRecord(
      'pending',
      courseName: '课程',
      title: '待确认',
      deadlineAt: now.subtract(const Duration(days: 5)),
      trusted: false,
    );
    final overdueOld = _sortRecord(
      'overdue-old',
      courseName: '课程',
      title: '早逾期',
      deadlineAt: now.subtract(const Duration(days: 4)),
    );
    final overdueNew = _sortRecord(
      'overdue-new',
      courseName: '课程',
      title: '晚逾期',
      deadlineAt: now.subtract(const Duration(days: 1)),
    );
    final records = [
      overdueOld,
      pending,
      far,
      noDeadline,
      overdueNew,
      near,
    ];

    List<String> titles(HomeSortOrder order) => AssignmentQuery.sortHome(
          records,
          order,
          now: now,
        ).map((assignment) => assignment.title).toList();

    expect(
      titles(HomeSortOrder.deadlineAsc),
      ['近期', '较远', '无截止', '待确认', '早逾期', '晚逾期'],
    );
    expect(
      titles(HomeSortOrder.deadlineDesc),
      ['较远', '近期', '无截止', '待确认', '晚逾期', '早逾期'],
    );
  });

  test('name order puts actionable work before pending and overdue buckets',
      () {
    final now = DateTime.utc(2026, 11, 12, 2);
    final actionable = _sortRecord(
      'actionable',
      courseName: 'Zulu',
      title: 'Zulu',
      deadlineAt: now.add(const Duration(days: 1)),
    );
    final noDeadline = _sortRecord(
      'none',
      courseName: 'Albatross',
      title: 'Albatross',
    );
    final pending = _sortRecord(
      'pending',
      courseName: 'Alpha',
      title: 'Alpha',
      trusted: false,
    );
    final overdue = _sortRecord(
      'overdue',
      courseName: 'Beta',
      title: 'Beta',
      deadlineAt: now.subtract(const Duration(days: 1)),
    );
    final records = [overdue, pending, actionable, noDeadline];

    List<String> titles(HomeSortOrder order) => AssignmentQuery.sortHome(
          records,
          order,
          now: now,
        ).map((assignment) => assignment.title).toList();

    expect(
      titles(HomeSortOrder.courseName),
      ['Albatross', 'Zulu', 'Alpha', 'Beta'],
    );
    expect(
      titles(HomeSortOrder.title),
      ['Albatross', 'Zulu', 'Alpha', 'Beta'],
    );
  });

  test('name order uses pinyin, case-insensitive English and natural numbers',
      () {
    final now = DateTime.utc(2026, 11, 12, 2);
    final due = now.add(const Duration(days: 1));
    final courseRecords = [
      _sortRecord('1', courseName: '数学', title: '一', deadlineAt: due),
      _sortRecord('2', courseName: 'beta', title: '二', deadlineAt: due),
      _sortRecord('3', courseName: '北京', title: '三', deadlineAt: due),
      _sortRecord('4', courseName: '重庆', title: '四', deadlineAt: due),
      _sortRecord('5', courseName: 'Alpha', title: '五', deadlineAt: due),
    ];
    final titleRecords = [
      _sortRecord('6', courseName: '课程', title: '作业10', deadlineAt: due),
      _sortRecord('7', courseName: '课程', title: '作业2', deadlineAt: due),
      _sortRecord('8', courseName: '课程', title: '英语', deadlineAt: due),
      _sortRecord('9', courseName: '课程', title: 'alpha', deadlineAt: due),
    ];

    expect(
      AssignmentQuery.sortHome(
        courseRecords,
        HomeSortOrder.courseName,
        now: now,
      ).map((assignment) => assignment.courseName),
      ['Alpha', '北京', 'beta', '重庆', '数学'],
    );
    expect(
      AssignmentQuery.sortHome(
        titleRecords,
        HomeSortOrder.title,
        now: now,
      ).map((assignment) => assignment.title),
      ['alpha', '英语', '作业2', '作业10'],
    );
  });

  test('name ties use raw text, course identity and input order', () {
    final now = DateTime.utc(2026, 11, 12, 2);
    final due = now.add(const Duration(days: 1));
    final li = _sortRecord(
      'li',
      courseName: '课程',
      title: '李',
      deadlineAt: due,
    );
    final liHomophone = _sortRecord(
      'homophone',
      courseName: '课程',
      title: '里',
      deadlineAt: due,
    );
    final duplicateA = _sortRecord(
      'duplicate',
      courseName: '课程',
      title: '同名',
      deadlineAt: due,
    );
    final duplicateB = duplicateA.copyWith(requirementsText: 'different');

    expect(
      AssignmentQuery.sortHome(
        [liHomophone, duplicateB, li, duplicateA],
        HomeSortOrder.title,
        now: now,
      ).map((assignment) => assignment.title),
      ['李', '里', '同名', '同名'],
    );
    final stable = AssignmentQuery.sortHome(
      [duplicateB, duplicateA],
      HomeSortOrder.title,
      now: now,
    );
    expect(stable[0].requirementsText, 'different');
    expect(stable[1].requirementsText, '');
  });

  test('formal scope and horizon keep unknown discoverable and history folded',
      () {
    final now = DateTime.utc(2026, 11, 4, 2);
    Assignment a(String id, int days, String status) => Assignment(
        id: id,
        courseName: '同名课',
        title: id,
        deadlineAt: now.add(Duration(days: days)),
        requirementsText: '',
        status: status,
        lastSyncedAt: now);
    final records = [
      a('cx:work:1:2:1', 1, 'pending'),
      a('cx:work:1:3:1', 45, 'returned'),
      a('cx:work:1:2:2', -200, 'pending'),
      a('cx:work:1:2:3', 2, 'unknown'),
      a('cx:activity:1:2:4', 1, 'pending'),
      a('cx:work:1:2:5', 1, 'submitted')
    ];
    final g = AssignmentQuery.home(records, now, {});
    expect(g.near.map((a) => a.id), ['cx:work:1:2:1']);
    expect(g.far.length, 1);
    expect(g.overdue.length, 1);
    expect(g.uncertain.length, 1);
    expect(AssignmentQuery.scope(records, {'1:3'}).length, 1);
    expect(Assignment.fromJson(records[4].toJson()).source,
        AssignmentSource.classroomActivity);
  });
  test('calendar business day is Beijing even with UTC input', () {
    final a = Assignment(
        id: 'cx:work:1:2:3',
        courseName: '课',
        title: '题',
        deadlineAt: DateTime.utc(2026, 11, 4, 17),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.utc(2026));
    expect(
      AssignmentQuery.forDay(
        [a],
        DateTime(2026, 11, 5),
        {},
        now: DateTime.utc(2026, 11, 4, 2),
      ).length,
      1,
    );
  });
  test('calendar excludes retained historical deadline after read failure', () {
    final now = DateTime.utc(2026, 11, 4, 2);
    final failedRead = Assignment(
        id: 'cx:work:1:2:3',
        courseName: '课',
        title: '题',
        deadlineAt: DateTime.utc(2026, 11, 5, 2),
        requirementsText: '',
        status: 'pending',
        deadlineTrusted: true,
        deadlineReadFailed: true,
        lastSyncedAt: now);

    expect(
      AssignmentQuery.forDay(
        [failedRead],
        DateTime(2026, 11, 5),
        {},
        now: now,
      ),
      isEmpty,
    );
    expect(AssignmentQuery.home([failedRead], now, {}).uncertain, [failedRead]);
    expect(AssignmentQuery.home([failedRead], now, {}).near, isEmpty);
  });

  test('queryClassificationDistinguishesNoDeadlineFromRetainedUntrustedDates',
      () {
    final now = DateTime.utc(2026, 11, 4, 2);
    final retained = _sortRecord(
      'retained',
      courseName: '课程',
      title: '保留但不可信',
      deadlineAt: now.add(const Duration(days: 1)),
      trusted: false,
    );
    final readFailed = _sortRecord(
      'read-failed',
      courseName: '课程',
      title: '读取失败保留日期',
      deadlineAt: now.add(const Duration(days: 1)),
      failed: true,
    );
    final trusted = _sortRecord(
      'trusted',
      courseName: '课程',
      title: '可信日期',
      deadlineAt: now.add(const Duration(days: 1)),
    );
    final clear = _sortRecord(
      'clear',
      courseName: '课程',
      title: '明确无截止',
    );
    final failedWithoutDate = _sortRecord(
      'failed-no-date',
      courseName: '课程',
      title: '读取失败且无日期',
      failed: true,
    );
    final rows = [retained, readFailed, trusted, clear, failedWithoutDate];

    List<String> titles(AssignmentDeadlineFilter filter) =>
        AssignmentQuery.filterHome(rows, deadline: filter, now: now)
            .map((assignment) => assignment.title)
            .toList();

    expect(titles(AssignmentDeadlineFilter.noDeadline), ['明确无截止']);
    expect(titles(AssignmentDeadlineFilter.uncertain), [
      '保留但不可信',
      '读取失败保留日期',
      '读取失败且无日期',
    ]);
    expect(
        AssignmentQuery.forDay(
          rows,
          DateTime(2026, 11, 5),
          {},
          now: now,
        ).map((assignment) => assignment.title),
        ['可信日期']);

    final groups = AssignmentQuery.home(rows, now, {});
    expect(groups.uncertain.map((assignment) => assignment.title), [
      '保留但不可信',
      '读取失败保留日期',
      '读取失败且无日期',
    ]);
    expect(groups.noDeadline.map((assignment) => assignment.title), ['明确无截止']);
    expect(groups.near.map((assignment) => assignment.title), ['可信日期']);
  });

  test('search matches title and course without changing source scope', () {
    final now = DateTime.utc(2026, 11, 4, 2);
    Assignment work(String id,
            {required String title,
            required String course,
            String status = 'pending',
            DateTime? due}) =>
        Assignment(
            id: id,
            courseName: course,
            title: title,
            deadlineAt: due ?? now.add(const Duration(days: 1)),
            requirementsText: '',
            status: status,
            lastSyncedAt: now);
    final rows = [
      work('cx:work:1:2:a', title: '高数练习', course: '高等数学'),
      work('cx:work:1:2:b', title: 'English Essay', course: '大学英语'),
      work('cx:activity:1:2:c', title: '高数课堂活动', course: '高等数学'),
      work('cx:work:1:2:d',
          title: '高数已提交', course: '高等数学', status: 'submitted'),
    ];

    expect(
        AssignmentQuery.filterHome(rows,
                query: '英语', deadline: AssignmentDeadlineFilter.all, now: now)
            .map((a) => a.id),
        ['cx:work:1:2:b']);
    expect(
        AssignmentQuery.filterHome(rows,
                query: '高数', deadline: AssignmentDeadlineFilter.all, now: now)
            .map((a) => a.id),
        ['cx:work:1:2:a']);
  });

  test('not expired includes future deadlines and confirmed no deadline', () {
    final now = DateTime.utc(2026, 11, 1, 9);
    Assignment row(String id,
            {DateTime? due,
            String status = 'pending',
            bool trusted = true,
            bool failed = false,
            String courseId = '1'}) =>
        _sortRecord(id,
            courseName: '课程',
            title: id,
            deadlineAt: due,
            status: status,
            trusted: trusted,
            failed: failed,
            courseId: courseId);
    final future = now.add(const Duration(microseconds: 1));
    final rows = [
      row('future', due: future),
      row('other', due: future, courseId: '2'),
      row('past', due: now.subtract(const Duration(microseconds: 1))),
      row('exact', due: now),
      row('none'),
      row('failed', due: future, failed: true),
      row('untrusted', due: future, trusted: false),
      row('unknown', due: future, status: 'unknown'),
      row('done', due: future, status: 'submitted'),
    ];
    List<String> ids(AssignmentDeadlineFilter filter) =>
        AssignmentQuery.filterHome(rows, deadline: filter, now: now.toLocal())
            .map((a) => a.title)
            .toList();
    expect(
      ids(AssignmentDeadlineFilter.notExpired),
      ['future', 'other', 'none'],
    );
    expect(ids(AssignmentDeadlineFilter.overdue), ['past', 'exact']);
    expect(ids(AssignmentDeadlineFilter.noDeadline), ['none']);
    expect(ids(AssignmentDeadlineFilter.uncertain),
        ['failed', 'untrusted', 'unknown']);
    expect(
        AssignmentQuery.filterHome(rows,
                deadline: AssignmentDeadlineFilter.notExpired,
                query: 'future',
                courseKey: '1:2',
                now: now)
            .map((a) => a.title),
        ['future']);
  });
  test('deadline filters distinguish horizons overdue unknown and undated', () {
    final now = DateTime.utc(2026, 11, 4, 2);
    Assignment work(String id,
            {DateTime? due,
            String status = 'pending',
            bool trusted = true,
            bool failed = false}) =>
        Assignment(
            id: 'cx:work:1:2:$id',
            courseName: '课程',
            title: id,
            deadlineAt: due,
            requirementsText: '',
            status: status,
            deadlineTrusted: trusted,
            deadlineReadFailed: failed,
            lastSyncedAt: now);
    final rows = [
      work('today', due: now.add(const Duration(hours: 1))),
      work('week', due: now.add(const Duration(days: 7))),
      work('month', due: now.add(const Duration(days: 30))),
      work('late', due: now.subtract(const Duration(minutes: 1))),
      work('unknown', status: 'unknown', due: now.add(const Duration(days: 1))),
      work('failed',
          due: now.add(const Duration(days: 1)), trusted: false, failed: true),
      work('none'),
    ];
    List<String> ids(AssignmentDeadlineFilter filter) =>
        AssignmentQuery.filterHome(rows, deadline: filter, now: now)
            .map((a) => a.id.split(':').last)
            .toList();

    expect(ids(AssignmentDeadlineFilter.next7Days), ['today', 'week']);
    expect(
        ids(AssignmentDeadlineFilter.next30Days), ['today', 'week', 'month']);
    expect(ids(AssignmentDeadlineFilter.overdue), ['late']);
    expect(ids(AssignmentDeadlineFilter.uncertain), ['unknown', 'failed']);
    expect(ids(AssignmentDeadlineFilter.noDeadline), ['none']);
  });
}
