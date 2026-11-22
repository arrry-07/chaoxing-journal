import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/app/transient_feedback.dart';
import 'package:study_assistant_mobile/src/features/assignment_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/features/widgets/coursework_status_pill.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_floating_nav_bar.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
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
    expect(find.byType(JournalFloatingNavBar), findsNothing);
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
    expect(openRect.height, greaterThanOrEqualTo(46));
    expect(open.hitTestable(), findsOneWidget);
    final openButton = tester.widget<FilledButton>(open);
    expect(
      openButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      const Color(0xFF34322F),
    );
    expect(
      openButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
      const Color(0xFFFFF7EC),
    );
    final openWeb = find.byKey(const ValueKey('assignment-detail-open-web'));
    await reveal(openWeb);
    expect(openWeb.hitTestable(), findsOneWidget);
    expect(tester.widget<TextButton>(openWeb), isA<TextButton>());
    expect(tester.getSize(openWeb).height, greaterThanOrEqualTo(48));

    final last = find.byKey(const ValueKey('assignment-detail-hide'));
    await reveal(last);
    expect(last.hitTestable(), findsOneWidget);
    final hideTextButton = tester.widget<TextButton>(
      find.descendant(of: last, matching: find.byType(TextButton)),
    );
    expect(
      hideTextButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
      Journal.ink,
    );
    expect(tester.takeException(), isNull);

    final back = find.byKey(const ValueKey('assignment-detail-back'));
    await reveal(back, delta: -240);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentListScreen), findsOneWidget);
    expect(find.byType(JournalFloatingNavBar), findsOneWidget);
    expect(
      tester.getRect(find.byType(JournalFloatingNavBar)).bottom,
      lessThanOrEqualTo(safeBottom),
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
      availableFromAt: DateTime.utc(2026, 11, 17, 16, 30),
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

    final time = find.byKey(const ValueKey('assignment-detail-time'));
    expect(
        find.descendant(of: time, matching: find.text('时间安排')), findsOneWidget);
    expect(
        find.descendant(of: time, matching: find.text('北京时间')), findsOneWidget);
    expect(find.textContaining('（北京时间）'), findsNothing);
    expect(
        find.descendant(of: time, matching: find.text('开始')), findsOneWidget);
    expect(
      find.descendant(of: time, matching: find.text('2026年11月18日 00:30')),
      findsOneWidget,
    );
    expect(
        find.descendant(of: time, matching: find.text('截止')), findsOneWidget);
    expect(
      find.descendant(of: time, matching: find.text('2026年11月19日 12:00')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('assignment-detail-pin')), findsNothing);

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
        find.text('提醒状态'),
        240,
        scrollable: scroll,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('个人清单与备注')).dy,
        lessThan(tester.getTopLeft(find.text('安排每日计划')).dy),
      );
      expect(
        tester.getTopLeft(find.text('安排每日计划')).dy,
        lessThan(tester.getTopLeft(find.text('提醒状态')).dy),
      );
    }

    await render(const Size(360, 800), 1);
    await render(const Size(393, 852), 1.3);
    await render(const Size(320, 640), 2);
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
      availableFromText: ' 11月18日（原文） ',
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
          final time = find.byKey(const ValueKey('assignment-detail-time'));
          await reveal(time);
          expect(find.descendant(of: time, matching: find.text('时间安排')),
              findsOneWidget);
          expect(find.descendant(of: time, matching: find.text('北京时间')),
              findsOneWidget);
          expect(find.textContaining('（北京时间）'), findsNothing);
          expect(find.descendant(of: time, matching: find.text('开始')),
              findsOneWidget);
          expect(find.descendant(of: time, matching: find.text('11月18日（原文）')),
              findsOneWidget);
          expect(
            find.descendant(of: time, matching: find.text('历史截止（未核实）')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: time, matching: find.text('2026年11月24日 12:00')),
            findsOneWidget,
          );
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

  testWidgets(
      'detail pin moves one filtered home row and is pruned on submission and hiding',
      (tester) async {
    const account = 'pin-test-student';
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'chaoxingAccount': account});
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1500);
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    Assignment work(String id, String title, DateTime? deadline) => Assignment(
          id: 'cx:work:1:2:$id',
          courseName: '合成课程',
          title: title,
          deadlineAt: deadline,
          requirementsText: '',
          status: 'pending',
          lastSyncedAt: now,
        );
    final near = work('31', '较早截止作业', now.add(const Duration(days: 1)));
    final later = work('32', '稍后截止作业', now.add(const Duration(days: 5)));
    final hide = work('33', '无截止待隐藏作业', null);
    final overdue =
        work('34', '未置顶逾期作业', now.subtract(const Duration(microseconds: 1)));
    final lease = _PinTestLease();
    final repository =
        _PinWriteFailureRepository(backgroundReminderGateway: lease);
    final store = _PinTestStore(repository: repository);
    addTearDown(store.dispose);
    await tester.runAsync(() async {
      await repository.activateAccount(account);
      await repository.mergeAndSave(
        [near, later, hide, overdue],
        completeSync: false,
      );
      await store.restoreSession();
    });
    expect(store.isAuthenticated, isTrue);

    final router = _router(store, clock: () => now);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      theme: StudyAssistantTheme.light,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    final pin = find.byKey(const ValueKey('assignment-detail-pin'));
    final back = find.byKey(const ValueKey('assignment-detail-back'));
    final pinHeading = find.text('置顶');
    List<String> homeIds() => tester
        .widgetList<AssignmentCard>(find.byType(AssignmentCard))
        .map((card) => card.assignment.id)
        .toList();
    Future<void> tap(Finder target) async {
      await tester.runAsync(() async {
        store.pendingMutation = null;
        await tester.tap(target.hitTestable());
        await store.pendingMutation;
      });
      await tester.pumpAndSettle();
    }

    expect(homeIds(), [near.id, later.id, hide.id, overdue.id]);
    await tap(find.text(later.title));
    expect(find.descendant(of: pin, matching: find.text('置顶')), findsOneWidget);

    repository.failPinWrites = true;
    await tap(pin);
    expect(find.text('置顶失败，请稍后重试。'), findsOneWidget);
    expect(store.isPinned(later), isFalse);
    repository.failPinWrites = false;
    repository.crossEngineLockEnabled = true;
    lease.failNextRelease = true;
    await tap(pin);
    expect(lease.failNextRelease, isFalse);
    expect(store.isPinned(later), isTrue);
    expect(store.error, contains('置顶状态已保存'));
    expect(find.text('置顶失败，请稍后重试。'), findsNothing);
    expect(
        find.descendant(of: pin, matching: find.text('已置顶')), findsOneWidget);
    await tap(back);

    expect(pinHeading, findsOneWidget);
    expect(homeIds(), [later.id, near.id, hide.id, overdue.id]);
    expect(find.text(later.title), findsOneWidget);
    final card = find.byKey(ValueKey('assignment-${later.id}'));
    final deadline = later.deadlineAt!.toUtc().add(const Duration(hours: 8));
    final currentYear = now.toUtc().add(const Duration(hours: 8)).year;
    final format = DateFormat(
        deadline.year == currentYear ? 'M月d日 HH:mm' : 'yyyy年M月d日 HH:mm');
    expect(
        find.descendant(
            of: card, matching: find.text('截止 ${format.format(deadline)}')),
        findsOneWidget);
    expect(tester.getTopLeft(pinHeading).dy,
        lessThan(tester.getTopLeft(find.text(later.title)).dy));
    expect(await tester.runAsync(() => repository.loadPinnedIds(account)),
        {later.courseTaskKey});

    expect(
      await tester.runAsync(() => store.saveHomeFilters(
            HomeFilters(query: near.title),
            store.accountEpoch,
          )),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(homeIds(), [near.id]);
    expect(pinHeading, findsNothing);
    expect(
      await tester.runAsync(
          () => store.saveHomeFilters(const HomeFilters(), store.accountEpoch)),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(homeIds(), [later.id, near.id, hide.id, overdue.id]);

    await tap(find.text(later.title));
    await tap(pin);
    expect(find.descendant(of: pin, matching: find.text('置顶')), findsOneWidget);
    await tap(back);
    expect(pinHeading, findsNothing);
    expect(homeIds(), [near.id, later.id, hide.id, overdue.id]);

    await tap(find.text(later.title));
    await tap(pin);
    await tester.runAsync(() async {
      await repository.mergeAndSave(
        [later.copyWith(status: 'submitted')],
        completeSync: false,
      );
      await store.refreshAssignments();
    });
    await tester.pumpAndSettle();
    expect(find.text('已提交'), findsOneWidget);
    expect(pin, findsNothing);
    expect(store.isPinned(later), isFalse);
    expect(await tester.runAsync(() => repository.loadPinnedIds(account)),
        isEmpty);
    await tap(back);
    expect(homeIds(), [near.id, hide.id, overdue.id]);
    expect(pinHeading, findsNothing);

    await tap(find.text(hide.title));
    await tap(pin);
    await tap(back);
    expect(homeIds(), [hide.id, near.id, overdue.id]);

    router.go('/assignments?scope=noDeadline');
    await tester.pumpAndSettle();
    expect(homeIds(), [hide.id]);
    expect(pinHeading, findsNothing);
    await tap(find.text(hide.title));
    expect(pin, findsNothing);
    await tap(back);
    expect(find.byKey(const ValueKey('assignment-recovery-scope')),
        findsOneWidget);

    router.go('/assignments');
    await tester.pumpAndSettle();
    await tap(find.text(hide.title));
    expect(
        find.descendant(of: pin, matching: find.text('已置顶')), findsOneWidget);
    await tap(find.byKey(const ValueKey('assignment-detail-hide')));
    expect(homeIds(), [near.id, overdue.id]);
    expect(pinHeading, findsNothing);
    expect(store.isPinned(hide), isFalse);
    expect(await tester.runAsync(() => repository.loadPinnedIds(account)),
        isEmpty);

    router.go('/assignments/${Uri.encodeComponent(hide.id)}');
    await tester.pumpAndSettle();
    expect(find.text('恢复到课业清单'), findsOneWidget);
    expect(pin, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'exam notice detail suppresses redundant course eyebrow, orphan timezone line and duplicated notice lines',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    final start = DateTime.utc(2026, 7, 14, 0, 0);
    final end = DateTime.utc(2026, 7, 14, 0, 50);
    const title = '2025-2026-2 《中国近现代史纲要》期末考试';
    const rawNotice = '试卷名称：2025-2026-2 《中国近现代史纲要》期末考试\n'
        '考试时间：2026-07-14 08:00 至 2026-07-14 08:50\n'
        '答题时长：50分钟\n'
        '提示：1、考试过程中如果出现页面卡死、题目空白情况，请尝试切换网络或退出重新进入考试。';
    final notice = Assignment(
      id: 'cx:examNotice:inbox:901',
      source: AssignmentSource.exam,
      courseName: '考试通知',
      title: title,
      deadlineAt: null,
      requirementsText: rawNotice,
      status: 'unknown',
      submitUrl: 'https://notice.chaoxing.com/pc/notice/myNotice',
      lastSyncedAt: DateTime.utc(2026, 7, 14, 2),
      exam: ExamInfo(
        examId: '901',
        courseId: '1',
        clazzId: '2',
        noticeOnly: true,
        startAt: start,
        endAt: end,
        startTrusted: true,
        endTrusted: true,
        durationMinutes: 50,
        location: '',
        lifecycle: 'ended',
      ),
    );
    final store = _RefinementStore()..replaceAssignmentsForTest([notice]);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(
        body: AssignmentDetailScreen(
          store: store,
          assignmentId: notice.id,
          clock: () => DateTime.utc(2026, 7, 14, 2),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('assignment-detail-course')), findsNothing);
    expect(find.text(title), findsOneWidget);
    expect(find.text('考试通知 · 已结束'), findsOneWidget);

    expect(find.text('考试安排'), findsOneWidget);
    expect(find.text('北京时间'), findsOneWidget);
    expect(find.text('（北京时间）'), findsNothing);
    expect(find.text('开考 2026年7月14日 08:00'), findsOneWidget);
    expect(find.text('结束 2026年7月14日 08:50'), findsOneWidget);
    expect(find.text('时长 50 分钟'), findsOneWidget);

    expect(find.text('部分信息尚未核实'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);

    expect(find.text('考试提示'), findsOneWidget);
    expect(
      find.text('1、考试过程中如果出现页面卡死、题目空白情况，请尝试切换网络或退出重新进入考试。'),
      findsOneWidget,
    );
    expect(
      find.textContaining('试卷名称：2025-2026-2 《中国近现代史纲要》期末考试'),
      findsNothing,
    );
    expect(find.textContaining('答题时长：50分钟'), findsNothing);

    final rawToggle = find.text('查看通知原文');
    await tester.ensureVisible(rawToggle);
    await tester.tap(rawToggle);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('考试时间：2026-07-14 08:00 至 2026-07-14 08:50'),
      findsOneWidget,
    );

    final untrusted = AssignmentDetailScreen.formatRequirementsForDisplay(
      notice.copyWith(
        exam: ExamInfo(
          examId: notice.exam!.examId,
          courseId: notice.exam!.courseId,
          clazzId: notice.exam!.clazzId,
          noticeOnly: true,
          startAt: start,
          endAt: end,
          startTrusted: false,
          endTrusted: false,
          durationMinutes: 50,
          lifecycle: 'ended',
        ),
      ),
      displayTitle: title,
      displayCourse: '考试通知',
      hasTrustedFullExamRange: false,
    );
    expect(
        untrusted.body, contains('考试时间：2026-07-14 08:00 至 2026-07-14 08:50'));

    final metadataOnly = AssignmentDetailScreen.formatRequirementsForDisplay(
      notice.copyWith(
        requirementsText:
            '试卷名称：$title\n考试时间：2026-07-14 08:00 至 2026-07-14 08:50\n答题时长：50分钟',
      ),
      displayTitle: title,
      displayCourse: '考试通知',
      hasTrustedFullExamRange: true,
    );
    expect(metadataOnly.body, isEmpty);
    expect(metadataOnly.trimmedRedundantLines, isTrue);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'normal detail stacks time label/value at 360dp 1.0/1.5x and styles actions for light/dark',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.reset);
    final now = DateTime.utc(2026, 11, 18, 4);
    final openItem = Assignment(
      id: 'cx:work:1:2:11',
      courseName: '软件工程实践',
      title: '阶段一常规作业排版验证',
      availableFromAt: DateTime.utc(2026, 11, 17, 16, 30),
      deadlineAt: now.add(const Duration(days: 1)),
      requirementsText: '按模板完成阶段分析说明。',
      status: 'pending',
      submitUrl:
          'https://mooc1.chaoxing.com/work/task?courseId=1&classId=2&workId=11&enc=sample',
      lastSyncedAt: now,
    );
    final disabledItem = Assignment(
      id: 'cx:work:1:2:1a-disabled',
      courseName: '软件工程实践',
      title: '无链接作业禁用状态验证',
      deadlineAt: null,
      requirementsText: '',
      status: 'pending',
      submitUrl: null,
      lastSyncedAt: now,
    );
    final store = _RefinementStore()
      ..replaceAssignmentsForTest([openItem, disabledItem]);
    addTearDown(store.dispose);

    for (final mode in [
      (dark: false, theme: StudyAssistantTheme.light),
      (dark: true, theme: StudyAssistantTheme.dark),
    ]) {
      for (final scale in [1.0, 1.5]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpWidget(MaterialApp(
          theme: mode.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: AssignmentDetailScreen(
              key: ValueKey('1a-${mode.dark}-$scale'),
              store: store,
              assignmentId: openItem.id,
              clock: () => now,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'dark=${mode.dark} scale=$scale');

        final time = find.byKey(const ValueKey('assignment-detail-time'));
        expect(find.descendant(of: time, matching: find.text('北京时间')),
            findsOneWidget);
        expect(find.textContaining('（北京时间）'), findsNothing);
        expect(
          tester.getTopLeft(find.text('开始')).dy,
          lessThan(tester.getTopLeft(find.text('2026年11月18日 00:30')).dy),
        );
        expect(
          tester.getTopLeft(find.text('截止')).dy,
          lessThan(tester.getTopLeft(find.text('2026年11月19日 12:00')).dy),
        );

        final open = find.byKey(const ValueKey('assignment-detail-open'));
        final scroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(open, 200, scrollable: scroll);
        await tester.pumpAndSettle();
        final openButton = tester.widget<FilledButton>(open);
        expect(openButton.onPressed, isNotNull);
        expect(
          openButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
          mode.dark ? JournalPalette.dark.primaryFill : const Color(0xFF34322F),
        );
        expect(
          openButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
          mode.dark
              ? JournalPalette.dark.onPrimaryFill
              : const Color(0xFFFFF7EC),
        );
        expect(tester.getSize(open).height, greaterThanOrEqualTo(46));

        final web = find.byKey(const ValueKey('assignment-detail-open-web'));
        await tester.scrollUntilVisible(web, 120, scrollable: scroll);
        await tester.pumpAndSettle();
        final webButton = tester.widget<TextButton>(web);
        expect(webButton.onPressed, isNotNull);
        expect(
          find.descendant(
            of: web,
            matching: find.byIcon(Icons.open_in_browser_rounded),
          ),
          findsOneWidget,
        );
        final webRect = tester.getRect(web);
        expect((webRect.center.dx - 180).abs(), lessThanOrEqualTo(2.0));
      }
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpWidget(MaterialApp(
      theme: StudyAssistantTheme.light,
      home: Scaffold(
        body: AssignmentDetailScreen(
          key: const ValueKey('1a-disabled'),
          store: store,
          assignmentId: disabledItem.id,
          clock: () => now,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final timeDisabled = find.byKey(const ValueKey('assignment-detail-time'));
    expect(find.descendant(of: timeDisabled, matching: find.text('北京时间')),
        findsNothing);
    expect(find.descendant(of: timeDisabled, matching: find.text('无截止日期')),
        findsOneWidget);
    final openDisabled = find.byKey(const ValueKey('assignment-detail-open'));
    await tester.scrollUntilVisible(openDisabled, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(openDisabled).onPressed, isNull);
    final webDisabled =
        find.byKey(const ValueKey('assignment-detail-open-web'));
    expect(tester.widget<TextButton>(webDisabled).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
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

class _PinTestStore extends _RefinementStore {
  _PinTestStore({required super.repository});

  Future<bool>? pendingMutation;

  @override
  Future<bool> togglePin(Assignment assignment) =>
      pendingMutation = super.togglePin(assignment);

  @override
  Future<bool> setAssignmentsHidden(
          Iterable<String> assignmentIds, bool hidden) =>
      pendingMutation = super.setAssignmentsHidden(assignmentIds, hidden);
}

class _PinTestLease extends BackgroundReminderGateway {
  bool failNextRelease = false;

  @override
  Future<bool> acquireWriteLease(String owner) async => true;

  @override
  Future<void> releaseWriteLease(String owner) async {
    if (!failNextRelease) return;
    failNextRelease = false;
    throw StateError('simulated write lease release failure');
  }
}

class _PinWriteFailureRepository extends LocalAssignmentRepository {
  _PinWriteFailureRepository({super.backgroundReminderGateway});

  bool failPinWrites = false;

  @override
  Future<void> savePinnedIds(Set<String> ids, String account) async {
    if (failPinWrites) throw StateError('simulated pin write failure');
    await super.savePinnedIds(ids, account);
  }
}

class _RefinementStore extends AssignmentStore {
  _RefinementStore({super.repository})
      : super(
          sessionStore: SecureSessionStore(),
          notificationService: LocalNotificationService(),
          widgetSnapshotService: WidgetSnapshotService(),
        );

  @override
  Future<bool> runDueAutoSync({DateTime? now}) async => false;
}
