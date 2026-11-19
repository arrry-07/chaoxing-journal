import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/transient_feedback.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/coursework_status_pill.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));

  testWidgets(
      'real detail route remains readable and operable at 320x640 with 2x text and a bottom inset',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.padding =
        const FakeViewPadding(top: 48, left: 0, right: 0, bottom: 48);
    addTearDown(tester.view.reset);

    final now = DateTime.utc(2026, 11, 18, 4);
    const course = '毛泽东思想和中国特色社会主义理论体系概论（2026年秋季学期联合教学班）';
    const title = '专题社会实践调研报告与小组展示材料归档提交（含访谈记录、现场照片和反思说明）';
    final records = _examRecords(now, course: course, title: title);
    final store = _RefinementStore()..replaceAssignmentsForTest(records);
    addTearDown(store.dispose);
    final router = _router(
      store,
      clock: () => now,
      initialLocation: '/assignments/${Uri.encodeComponent(records.first.id)}',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
    ));
    await tester.pumpAndSettle();

    final detail = find.byType(AssignmentDetailScreen);
    expect(detail, findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.descendant(
        of: detail,
        matching: find.byKey(const ValueKey('assignment-detail-sheet')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text(course)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text(title)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detail,
        matching: find.byKey(const ValueKey('assignment-detail-status')),
      ),
      findsOneWidget,
    );

    final detailList = find.descendant(
      of: detail,
      matching: find.byType(ListView),
    );
    final detailScroll = find.descendant(
      of: detail,
      matching: find.byType(Scrollable),
    );
    Future<void> reveal(Finder finder, {double delta = 240}) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          delta,
          scrollable: detailScroll.first,
        );
      } else {
        await Scrollable.ensureVisible(
          tester.element(finder),
          alignment: 0.5,
        );
      }
      await tester.pumpAndSettle();
    }

    final appPadding =
        MediaQuery.paddingOf(tester.element(find.byType(AppShell)));
    final safeBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
            appPadding.bottom;
    expect(tester.getRect(detailList).bottom, closeTo(safeBottom, 0.5));

    final time = find.byKey(const ValueKey('assignment-detail-time'));
    await reveal(time);
    final timeRect = tester.getRect(time);
    expect(timeRect.top, greaterThanOrEqualTo(appPadding.top));
    expect(timeRect.bottom, lessThanOrEqualTo(safeBottom));
    expect(find.byType(CourseworkStatusPill), findsWidgets);

    final sources = find.byKey(const ValueKey('assignment-source-records'));
    await reveal(sources);
    await tester.tap(sources);
    await tester.pumpAndSettle();
    expect(find.text('正式考试 · 未开始'), findsOneWidget);

    final firstSource = find.text('查看').first;
    await reveal(firstSource);
    await tester.tap(firstSource);
    await tester.pumpAndSettle();
    expect(find.text('原始来源详情'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    final open = find.byKey(const ValueKey('assignment-detail-open'));
    await reveal(open);
    final openRect = tester.getRect(open);
    expect(openRect.top, greaterThanOrEqualTo(appPadding.top));
    expect(openRect.bottom, lessThanOrEqualTo(safeBottom));
    expect(open.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assignment-detail-open-web')).hitTestable(),
      findsOneWidget,
    );

    final last = find.byKey(const ValueKey('assignment-detail-hide'));
    await reveal(last);
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    final back = find.byKey(const ValueKey('assignment-detail-back'));
    await reveal(back, delta: -240);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentListScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.getRect(find.byType(NavigationBar)).bottom,
      closeTo(safeBottom, 0.5),
    );
  });

  testWidgets('return-check banner stays above the injected system inset',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.padding =
        const FakeViewPadding(top: 48, left: 0, right: 0, bottom: 48);
    addTearDown(tester.view.reset);

    final now = DateTime.utc(2026, 11, 18, 4);
    final item = Assignment(
      id: 'cx:work:1:2:9',
      courseName: '工程制图基础',
      title: '组合体三视图测绘练习',
      deadlineAt: now.add(const Duration(days: 1)),
      requirementsText: '按课堂要求提交测绘过程与最终视图。',
      status: 'pending',
      submitUrl:
          'https://mooc1.chaoxing.com/work/task?courseId=1&classId=2&workId=9&enc=sample',
      lastSyncedAt: now,
    );
    final store = _RefinementStore()..replaceAssignmentsForTest([item]);
    addTearDown(store.dispose);
    final router = _router(
      store,
      clock: () => now,
      initialLocation: '/assignments/${Uri.encodeComponent(item.id)}',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1)),
        child: child!,
      ),
    ));
    await tester.pumpAndSettle();

    store.returnCheckMessage = '正在核对刚才作业的提交状态…';
    store.notifyListeners();
    await tester.pump();
    final banner = find.text('正在核对刚才作业的提交状态…');
    expect(banner, findsOneWidget);
    expect(banner.hitTestable(), findsOneWidget);
    final appPadding =
        MediaQuery.paddingOf(tester.element(find.byType(AppShell)));
    final bannerRect = tester.getRect(find.byType(TimedReturnCheck));
    final safeBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
            appPadding.bottom;
    expect(bannerRect.bottom, closeTo(safeBottom, 0.5));

    final detailList = find.descendant(
      of: find.byType(AssignmentDetailScreen),
      matching: find.byType(ListView),
    );
    expect(
        tester.getRect(detailList).bottom, lessThanOrEqualTo(bannerRect.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'detail tool pairs switch layout at the specified width and text scale',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.reset);
    final now = DateTime.utc(2026, 11, 18, 4);
    final item = Assignment(
      id: 'cx:work:1:2:10',
      courseName: '大学物理',
      title: '短作业',
      deadlineAt: now.add(const Duration(days: 2)),
      requirementsText: '',
      status: 'pending',
      submitUrl:
          'https://mooc1.chaoxing.com/work/task?courseId=1&classId=2&workId=10&enc=sample',
      lastSyncedAt: now,
    );
    final store = _RefinementStore()..replaceAssignmentsForTest([item]);
    addTearDown(store.dispose);

    Future<void> render(Size size, double scale) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: AssignmentDetailScreen(
            store: store,
            assignmentId: item.id,
            clock: () => now,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byType(AssignmentDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('安排每日计划'),
        240,
        scrollable: scroll,
      );
      expect(tester.takeException(), isNull);
    }

    await render(const Size(360, 800), 1);
    expect(
      tester.getTopLeft(find.text('安排每日计划')).dy,
      tester.getTopLeft(find.text('提醒状态')).dy,
    );

    await render(const Size(393, 852), 1.3);
    expect(
      tester.getTopLeft(find.text('安排每日计划')).dy,
      tester.getTopLeft(find.text('提醒状态')).dy,
    );

    await render(const Size(320, 640), 2);
    expect(
      tester.getTopLeft(find.text('安排每日计划')).dy,
      lessThan(tester.getTopLeft(find.text('提醒状态')).dy),
    );
  });

  testWidgets(
      'short, long-requirement, unconfirmed and exam details stay operable across the visual matrix',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.reset);
    final now = DateTime.utc(2026, 11, 18, 4);
    final short = Assignment(
      id: 'cx:work:1:2:21',
      courseName: '工程制图基础',
      title: '短作业',
      deadlineAt: now.add(const Duration(days: 2)),
      requirementsText: '',
      status: 'pending',
      submitUrl:
          'https://mooc1.chaoxing.com/work/task?courseId=1&classId=2&workId=21&enc=sample',
      lastSyncedAt: now,
    );
    final long = Assignment(
      id: 'cx:work:1:2:22',
      courseName: '毛泽东思想和中国特色社会主义理论体系概论',
      title: '专题社会实践调研报告与小组展示材料归档提交',
      deadlineAt: now.add(const Duration(days: 4)),
      requirementsText: [
        '请围绕本学期实践主题完成调研报告，正文不少于三千字，并附访谈记录与现场照片。',
        '小组展示材料需包含调研背景、问题分析、访谈证据、结论建议和参考资料。',
        '文件名统一为“班级-组号-主题”，提交前请核对封面、目录、页码和组员分工。',
        '如引用网络资料，请标注来源；访谈对象信息须做匿名化处理。',
      ].join('\n\n'),
      status: 'pending',
      submitUrl:
          'https://mooc1.chaoxing.com/work/task?courseId=1&classId=2&workId=22&enc=sample',
      lastSyncedAt: now,
    );
    final unconfirmed = Assignment(
      id: 'cx:work:1:2:23',
      courseName: '大学物理',
      title: '待确认截止的章节练习',
      deadlineAt: now.add(const Duration(days: 6)),
      deadlineTrusted: false,
      deadlineRawText: '11月24日 23:59（年份待确认）',
      requirementsText: '',
      status: 'pending',
      submitUrl:
          'https://mooc1.chaoxing.com/work/task?courseId=1&classId=2&workId=23&enc=sample',
      lastSyncedAt: now,
    );
    final exam = _examRecords(
      now,
      course: '高等数学',
      title: '高等数学期末考试',
    ).first;
    final store = _RefinementStore()
      ..replaceAssignmentsForTest([short, long, unconfirmed, exam]);
    addTearDown(store.dispose);

    final scenarios = <String, Assignment>{
      'short': short,
      'long': long,
      'unconfirmed': unconfirmed,
      'exam': exam,
    };
    for (final size in [
      const Size(360, 800),
      const Size(393, 852),
      const Size(320, 640),
    ]) {
      final scale = size.width == 360
          ? 1.0
          : size.width == 393
              ? 1.3
              : 2.0;
      for (final entry in scenarios.entries) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: AssignmentDetailScreen(
              key: ValueKey('${entry.key}-${size.width}-$scale'),
              store: store,
              assignmentId: entry.value.id,
              clock: () => now,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '${entry.key} ${size.width}x${size.height} @$scale');

        Future<void> reveal(Finder finder) async {
          final scroll = find
              .descendant(
                of: find.byType(AssignmentDetailScreen),
                matching: find.byType(Scrollable),
              )
              .first;
          if (finder.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              finder,
              240,
              scrollable: scroll,
            );
          } else {
            await Scrollable.ensureVisible(
              tester.element(finder),
              alignment: 0.5,
            );
          }
          await tester.pumpAndSettle();
        }

        if (entry.key == 'short' && size.width == 360) {
          expect(
            find.byKey(const ValueKey('assignment-detail-open')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find
                .byKey(const ValueKey('assignment-detail-open-web'))
                .hitTestable(),
            findsOneWidget,
          );
        }
        if (entry.key == 'long') {
          final requirements =
              find.byKey(const ValueKey('assignment-detail-requirements'));
          await reveal(requirements);
          expect(requirements, findsOneWidget);
        }
        if (entry.key == 'unconfirmed') {
          final verification =
              find.byKey(const ValueKey('assignment-detail-verification'));
          await reveal(verification);
          expect(find.text('历史截止时间待确认，不参与日历和提醒'), findsOneWidget);
        }
        if (entry.key == 'exam') {
          final time = find.byKey(const ValueKey('assignment-detail-time'));
          await reveal(time);
          expect(find.textContaining('地点 云塘校区综合教学楼A-301'), findsOneWidget);
        }

        final open = find.byKey(const ValueKey('assignment-detail-open'));
        await reveal(open);
        expect(open.hitTestable(), findsOneWidget);
        final hide = find.byKey(const ValueKey('assignment-detail-hide'));
        await reveal(hide);
        expect(hide.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason:
                '${entry.key} ${size.width}x${size.height} @$scale actions');
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}

GoRouter _router(
  AssignmentStore store, {
  required DateTime Function() clock,
  String initialLocation = '/assignments',
}) =>
    GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (_, __, child) =>
              AppShell(assignmentStore: store, child: child),
          routes: [
            GoRoute(
              path: '/assignments',
              builder: (_, __) => AssignmentListScreen(store: store),
            ),
            GoRoute(
              path: '/assignments/:id',
              builder: (_, state) => AssignmentDetailScreen(
                store: store,
                assignmentId: state.pathParameters['id']!,
                clock: clock,
              ),
            ),
          ],
        ),
      ],
    );

List<Assignment> _examRecords(
  DateTime now, {
  required String course,
  required String title,
}) {
  final start = now.add(const Duration(days: 3));
  final end = start.add(const Duration(hours: 2));
  final examUrl = Uri.https(
    'mooc1-api.chaoxing.com',
    '/phone/moocAnalysis/examList',
    {'courseId': '1', 'classId': '2'},
  ).toString();
  final noticeUrl = 'https://notice.chaoxing.com/pc/notice/myNotice';
  return [
    Assignment(
      id: 'cx:exam:1:2:3',
      courseName: course,
      title: title,
      deadlineAt: null,
      requirementsText: '携带学生证，提前十五分钟到达考场。',
      status: 'pending',
      submitUrl: examUrl,
      lastSyncedAt: now,
      exam: ExamInfo(
        examId: '3',
        courseId: '1',
        clazzId: '2',
        startAt: start,
        endAt: end,
        startTrusted: true,
        endTrusted: true,
        durationMinutes: 120,
        location: '云塘校区综合教学楼A-301',
        lifecycle: 'scheduled',
      ),
    ),
    for (var id = 801; id <= 802; id++)
      Assignment(
        id: 'cx:examNotice:inbox:$id',
        courseName: course,
        title: '考试通知 $id',
        deadlineAt: null,
        requirementsText: '',
        status: 'unknown',
        submitUrl: noticeUrl,
        lastSyncedAt: now,
        exam: ExamInfo(
          examId: '$id',
          relatedExamId: '3',
          courseId: '1',
          clazzId: '2',
          lifecycle: 'unknown',
          noticeOnly: true,
        ),
      ),
  ];
}

class _RefinementStore extends AssignmentStore {
  _RefinementStore()
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}
