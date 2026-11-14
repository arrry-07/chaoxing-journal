import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Store extends AssignmentStore {
  _Store()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  @override
  Future<bool> saveHomeFilters(HomeFilters next, int expectedEpoch) async {
    homeFilters = next;
    notifyListeners();
    return true;
  }

  void changed() => notifyListeners();
}

Assignment _work(
  String id, {
  required String title,
  required String course,
  required DateTime? due,
  bool trusted = true,
  String? submitUrl,
}) =>
    Assignment(
      id: 'cx:work:1:2:$id',
      title: title,
      courseName: course,
      deadlineAt: due,
      deadlineTrusted: trusted,
      requirementsText: '',
      status: 'pending',
      submitUrl: submitUrl,
      lastSyncedAt: DateTime.now(),
    );

DateTime _chinaTime(DateTime now, int dayOffset, int hour) {
  final china = now.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(
    china.year,
    china.month,
    china.day + dayOffset,
    hour - 8,
  );
}

String _heading(DateTime instant) {
  final day = instant.toUtc().add(const Duration(hours: 8));
  return '${day.month}月${day.day}日 周${'一二三四五六日'[day.weekday - 1]}';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'all home sort modes keep their order and add trusted date headings',
      (tester) async {
    final now = DateTime.now();
    final dayOne = _chinaTime(now, 1, 10);
    final dayTwo = _chinaTime(now, 2, 9);
    final alpha = _work('alpha', title: 'Alpha 作业', course: '物理', due: dayOne);
    final beta = _work('beta',
        title: 'Beta 作业',
        course: '数学',
        due: dayOne.add(const Duration(hours: 2)));
    final gamma = _work('gamma', title: 'Gamma 作业', course: '数学', due: dayTwo);
    final delta = _work('delta', title: 'Delta 作业', course: '语文', due: null);
    final unknown = _work(
      'unknown',
      title: 'Unknown 作业',
      course: '英语',
      due: dayTwo,
      trusted: false,
    );
    final store = _Store()
      ..replaceAssignmentsForTest([unknown, delta, gamma, beta, alpha]);
    addTearDown(store.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))),
    );

    final expected = {
      HomeSortOrder.grouped: (
        ['Alpha 作业', 'Beta 作业', 'Gamma 作业', 'Delta 作业', 'Unknown 作业'],
        [_heading(dayOne), _heading(dayTwo)],
      ),
      HomeSortOrder.deadlineAsc: (
        ['Alpha 作业', 'Beta 作业', 'Gamma 作业', 'Delta 作业', 'Unknown 作业'],
        [_heading(dayOne), _heading(dayTwo)],
      ),
      HomeSortOrder.deadlineDesc: (
        ['Gamma 作业', 'Beta 作业', 'Alpha 作业', 'Delta 作业', 'Unknown 作业'],
        [_heading(dayTwo), _heading(dayOne)],
      ),
      HomeSortOrder.courseName: (
        ['Beta 作业', 'Gamma 作业', 'Alpha 作业', 'Delta 作业', 'Unknown 作业'],
        [_heading(dayOne), _heading(dayTwo), _heading(dayOne)],
      ),
      HomeSortOrder.title: (
        ['Alpha 作业', 'Beta 作业', 'Delta 作业', 'Gamma 作业', 'Unknown 作业'],
        [_heading(dayOne), _heading(dayTwo)],
      ),
    };

    for (final entry in expected.entries) {
      store.homeFilters = HomeFilters(sortOrder: entry.key);
      store.changed();
      await tester.pump();

      final titles = tester
          .widgetList<AssignmentCard>(find.byType(AssignmentCard))
          .map((card) => card.assignment.title)
          .toList();
      expect(titles, entry.value.$1, reason: entry.key.name);
      final headings = tester
          .widgetList<Text>(find.byWidgetPredicate((widget) =>
              widget is Text &&
              RegExp(r'^\d+月\d+日 周[一二三四五六日]$').hasMatch(widget.data ?? '')))
          .map((text) => text.data)
          .toList();
      expect(headings, entry.value.$2, reason: entry.key.name);
    }
  });

  testWidgets('untrusted and absent dates never receive synthetic headings',
      (tester) async {
    final store = _Store()
      ..replaceAssignmentsForTest([
        _work('no-date', title: '无截止日期', course: '语文', due: null),
        _work(
          'untrusted',
          title: '截止待确认',
          course: '英语',
          due: DateTime.now().add(const Duration(days: 2)),
          trusted: false,
        ),
      ]);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AssignmentListScreen(store: store))),
    );

    expect(
      find.byWidgetPredicate((widget) =>
          widget is Text &&
          RegExp(r'^\d+月\d+日 周[一二三四五六日]$').hasMatch(widget.data ?? '')),
      findsNothing,
    );
    expect(find.text('未设置截止时间'), findsOneWidget);
    expect(find.text('状态或截止待确认'), findsOneWidget);
    expect(find.text('无期限'), findsOneWidget);
    expect(find.text('截止时间待确认'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('home date heading and long title reflow without overlaps',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final now = DateTime.now();
    final due = _chinaTime(now, 1, 14);
    const title = '面向对象程序设计课程综合实验报告与项目复盘总结材料';
    final work = _work(
      'layout',
      title: title,
      course: '计算机课程综合实践与应用专题研讨班',
      due: due,
      submitUrl:
          'https://mooc1.chaoxing.com/work/view?courseid=1&classid=2&workid=layout',
    );

    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        final store = _Store()..replaceAssignmentsForTest([work]);
        addTearDown(store.dispose);
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: AssignmentListScreen(store: store)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width/$scale');
        expect(find.text(_heading(due)), findsOneWidget);

        final action = find.widgetWithText(TextButton, '在学习通内打开作业');
        await tester.scrollUntilVisible(
          action,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull, reason: '$width/$scale');
        expect(
          tester.getRect(find.text(title)).overlaps(tester.getRect(action)),
          isFalse,
          reason: '$width/$scale',
        );
      }
    }
  });
}
