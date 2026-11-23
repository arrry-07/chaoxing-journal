import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/home_manual_timeline.dart';
import 'package:study_assistant_mobile/src/services/home_sync_presentation.dart';

Assignment _assignment(
  String id, {
  String course = '高等数学',
  String title = '作业',
  DateTime? due,
  bool trusted = true,
  bool readFailed = false,
  String status = 'pending',
  String? availableFromText,
  String? availableFrom,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      courseName: course,
      title: title,
      deadlineAt: due,
      deadlineTrusted: trusted,
      deadlineReadFailed: readFailed,
      requirementsText: '',
      status: status,
      lastSyncedAt: DateTime(2026, 11, 23, 9),
      availableFromText: availableFromText,
      availableFromAt:
          availableFrom == null ? null : DateTime.parse(availableFrom),
    );

ManualEntry _entry(
  String id, {
  String title = '待办',
  String kind = 'todo',
  String course = '',
  String location = '',
  DateTime? at,
  bool done = false,
  bool remind = false,
}) =>
    ManualEntry(
      id: id,
      title: title,
      kind: kind,
      course: course,
      location: location,
      at: at,
      done: done,
      remind: remind,
    );

void main() {
  final now = DateTime(2026, 11, 23, 10);

  test('manual bucket distinguishes completed, undated, future and overdue',
      () {
    expect(
      HomeManualTimeline.manualBucketAt(
        _entry('done', at: now.add(const Duration(hours: 1)), done: true),
        now,
      ),
      AssignmentDeadlineBucket.completed,
    );
    expect(
      HomeManualTimeline.manualBucketAt(_entry('none'), now),
      AssignmentDeadlineBucket.confirmedNoDeadline,
    );
    expect(
      HomeManualTimeline.manualBucketAt(
        _entry('future', at: now.add(const Duration(hours: 1))),
        now,
      ),
      AssignmentDeadlineBucket.notExpiredWithDeadline,
    );
    expect(
      HomeManualTimeline.manualBucketAt(
        _entry('past', at: now.subtract(const Duration(minutes: 1))),
        now,
      ),
      AssignmentDeadlineBucket.overdue,
    );
  });

  test('manual filters cover done, type, course, query and deadline choices',
      () {
    final entries = [
      _entry(
        'todo',
        title: '复习极限',
        course: '高等数学',
        location: 'A101',
        at: now.add(const Duration(hours: 2)),
      ),
      _entry(
        'exam',
        title: '英语听力',
        kind: 'exam',
        course: '大学英语',
        at: now.add(const Duration(days: 2)),
      ),
      _entry(
        'overdue',
        title: '交实验报告',
        course: '大学物理',
        at: now.subtract(const Duration(hours: 1)),
      ),
      _entry('none', title: '无日期待办', course: '高等数学'),
      _entry(
        'done',
        title: '已完成',
        course: '高等数学',
        at: now.add(const Duration(hours: 3)),
        done: true,
      ),
    ];

    List<String> ids({
      String query = '',
      String? course,
      AssignmentDeadlineFilter deadline = AssignmentDeadlineFilter.all,
      AssignmentTypeFilter type = AssignmentTypeFilter.all,
    }) =>
        [
          for (final entry in HomeManualTimeline.filterManualEntries(
            entries,
            query: query,
            selectedCourseName: course,
            deadline: deadline,
            type: type,
            now: now,
          ))
            entry.id,
        ];

    expect(ids(), ['todo', 'exam', 'overdue', 'none']);
    expect(
        ids(type: AssignmentTypeFilter.homework), ['todo', 'overdue', 'none']);
    expect(ids(type: AssignmentTypeFilter.task), ['todo', 'overdue', 'none']);
    expect(ids(type: AssignmentTypeFilter.exam), ['exam']);
    expect(ids(type: AssignmentTypeFilter.examNotice), ['exam']);
    expect(ids(course: ' 高等数学 '), ['todo', 'none']);
    expect(ids(query: 'A101'), ['todo']);
    expect(ids(query: '英语'), ['exam']);
    expect(ids(deadline: AssignmentDeadlineFilter.next7Days), ['todo', 'exam']);
    expect(
        ids(deadline: AssignmentDeadlineFilter.next30Days), ['todo', 'exam']);
    expect(ids(deadline: AssignmentDeadlineFilter.overdue), ['overdue']);
    expect(ids(deadline: AssignmentDeadlineFilter.noDeadline), ['none']);
    expect(
      ids(deadline: AssignmentDeadlineFilter.notExpired),
      ['todo', 'exam', 'none'],
    );
    expect(ids(deadline: AssignmentDeadlineFilter.uncertain), isEmpty);
  });

  test('mixed timeline keeps overdue last in both directions and layers dates',
      () {
    final assignments = [
      _assignment(
        'a-overdue',
        title: '学习通逾期',
        due: now.subtract(const Duration(hours: 1)),
      ),
      _assignment(
        'a-today',
        title: '学习通今日',
        due: now.add(const Duration(hours: 2)),
      ),
      _assignment(
        'a-far',
        title: '学习通远期',
        due: now.add(const Duration(days: 10)),
      ),
      _assignment('a-none', title: '学习通无截止'),
      _assignment(
        'a-uncertain',
        title: '学习通待确认',
        trusted: false,
        readFailed: true,
      ),
      _assignment(
        'a-start',
        title: '学习通有开始锚点',
        trusted: false,
        readFailed: true,
        availableFromText: '进行中',
        availableFrom: '2026-11-20T09:00:00+08:00',
      ),
    ];
    final manual = [
      _entry(
        'm-overdue',
        title: '手动逾期',
        at: now.subtract(const Duration(days: 1)),
      ),
      _entry(
        'm-today',
        title: '手动今日',
        at: now.add(const Duration(hours: 1)),
      ),
      _entry(
        'm-far',
        title: '手动远期',
        at: now.add(const Duration(days: 8)),
      ),
      _entry('m-none', title: '手动无截止'),
      _entry(
        'm-done',
        title: '手动完成',
        at: now.add(const Duration(hours: 4)),
        done: true,
      ),
    ];

    List<String> titles(HomeSortOrder order) => [
          for (final item in HomeManualTimeline.mergeAndSort(
            assignments: assignments,
            manualEntries:
                manual.where((entry) => !entry.done).toList(growable: false),
            order: order,
            now: now,
          ))
            item.title,
        ];

    final asc = titles(HomeSortOrder.deadlineAsc);
    expect(asc.take(2), ['手动今日', '学习通今日']);
    expect(asc.sublist(asc.length - 2), ['学习通逾期', '手动逾期']);
    expect(
      asc.indexOf('学习通无截止'),
      lessThan(asc.indexOf('学习通远期')),
    );
    expect(asc.indexOf('学习通有开始锚点'), lessThan(asc.indexOf('学习通远期')));
    expect(asc.indexOf('学习通远期'), lessThan(asc.indexOf('学习通待确认')));
    expect(asc.indexOf('学习通远期'), lessThan(asc.indexOf('手动无截止')));

    final desc = titles(HomeSortOrder.deadlineDesc);
    expect(desc.sublist(desc.length - 2), ['手动逾期', '学习通逾期']);
    expect(
      desc.indexOf('学习通远期'),
      lessThan(desc.indexOf('学习通无截止')),
    );
  });

  test('course ordering applies natural course name then time', () {
    final items = HomeManualTimeline.mergeAndSort(
      assignments: [
        _assignment(
          'english',
          course: '英语',
          title: '英语作业一',
          due: now.add(const Duration(hours: 3)),
        ),
        _assignment(
          'math',
          course: '高数',
          title: '高数作业一',
          due: now.add(const Duration(hours: 5)),
        ),
      ],
      manualEntries: [
        _entry(
          'manual-english',
          title: '英语手动待办',
          course: '英语',
          at: now.add(const Duration(hours: 1)),
        ),
      ],
      order: HomeSortOrder.courseName,
      now: now,
    );
    expect(
      [for (final item in items) item.displayCourse],
      ['高数', '英语', '英语'],
    );
    expect(items[1].title, '英语手动待办');
    expect(items[2].title, '英语作业一');
  });

  test('home due summary counts manual todos without touching completion', () {
    final summary = HomeDueSummary.from(
      const [],
      now: now,
      manualEntries: [
        _entry('today', at: now.add(const Duration(hours: 2))),
        _entry('two-days', at: now.add(const Duration(days: 2))),
        _entry('three-days', at: now.add(const Duration(days: 3))),
        _entry('overdue', at: now.subtract(const Duration(hours: 1))),
        _entry('exam', kind: 'exam', at: now.add(const Duration(hours: 4))),
        _entry('done', at: now.add(const Duration(hours: 5)), done: true),
      ],
    );
    expect(summary.dueToday, 1);
    expect(summary.dueIn3Days, 2);
    expect(summary.completedToday, 0);
  });
}
