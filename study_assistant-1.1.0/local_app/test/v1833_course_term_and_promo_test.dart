import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:study_assistant_mobile/src/models/course_term_preferences.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/models/sync_scope.dart';
import 'package:study_assistant_mobile/src/services/assignment_query.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/course_term_catalog.dart';
import 'package:study_assistant_mobile/src/services/home_course_filter.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M1 course name term inference, pinyin sort & academic year', () {
    test(
        'AcademicTerm.tryParseCourseName parses anchored patterns and rejects traps',
        () {
      expect(
        AcademicTerm.tryParseCourseName('高等数学（2026-2027-1）'),
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseCourseName('线性代数 2026-2027第二学期'),
        const AcademicTerm(2026, AcademicSemester.spring),
      );
      expect(
        AcademicTerm.tryParseCourseName('信号与系统 2026秋'),
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseCourseName('Python程序设计（2026年09月开课）'),
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseCourseName('人工智能导论202609'),
        const AcademicTerm(2026, AcademicSemester.fall),
      );
      expect(
        AcademicTerm.tryParseCourseName('概率论与数理统计 2026.03.05'),
        const AcademicTerm(2025, AcademicSemester.spring),
      );

      // Anti-trap regressions
      expect(AcademicTerm.tryParseCourseName('软件工程 2024级'), isNull);
      expect(AcademicTerm.tryParseCourseName('2025届毕业设计'), isNull);
      expect(AcademicTerm.tryParseCourseName('Python v2026.03 实训'), isNull);
      expect(AcademicTerm.tryParseCourseName('深度学习 2026'), isNull);
      expect(AcademicTerm.tryParseCourseName('课程 2026-13-01'), isNull);
      expect(AcademicTerm.tryParseCourseName('课程 2026-02-29'), isNull);
      expect(AcademicTerm.tryParseCourseName('课程 2025秋 2026春'), isNull);
      expect(
        AcademicTerm.tryParseCourseName('课程 2025-2026春'),
        const AcademicTerm(2025, AcademicSemester.spring),
      );
    });

    test(
        'courseName sits strictly below manual/folder and above activity/ungrouped',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const fromCourseName = CourseRef(
        courseId: '1',
        clazzId: '1',
        name: '高等数学（2026秋）',
      );
      const folderOverridesName = CourseRef(
        courseId: '2',
        clazzId: '2',
        name: '大学物理（2025秋）',
        folderName: '2026年秋',
      );
      final catalog = CourseTermCatalog.build(
        courses: const [fromCourseName, folderOverridesName],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      final e1 = catalog.entryFor(fromCourseName.key)!;
      expect(e1.source, CourseTermSource.courseName);
      expect(e1.term, const AcademicTerm(2026, AcademicSemester.fall));

      final e2 = catalog.entryFor(folderOverridesName.key)!;
      expect(e2.source, CourseTermSource.folder);
      expect(e2.term, const AcademicTerm(2026, AcademicSemester.fall));
    });

    test(
        'currentAcademicYear matches 2-semester academic year and excludes silent ungrouped',
        () {
      final now =
          DateTime.utc(2026, 11, 20, 4); // 2026-fall (academicYear=2026)
      const fall2026 = CourseRef(
        courseId: '1',
        clazzId: '1',
        name: '秋课',
        folderName: '2026年秋',
      );
      const spring2027 = CourseRef(
        courseId: '2',
        clazzId: '2',
        name: '同届春课',
        folderName: '2027年春',
      );
      const past2026Spring = CourseRef(
        courseId: '3',
        clazzId: '3',
        name: '上学年春课',
        folderName: '2026年春',
      );
      const silentUngrouped = CourseRef(
        courseId: '4',
        clazzId: '4',
        name: '空白课',
      );
      final catalog = CourseTermCatalog.build(
        courses: const [fall2026, spring2027, past2026Spring, silentUngrouped],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: now,
      );

      expect(CourseTermScope.currentAcademicYear.label, '本学年');
      expect(
          catalog.matchesCoursePickerScope(
              fall2026.key, CourseTermScope.currentAcademicYear),
          isTrue);
      expect(
          catalog.matchesCoursePickerScope(
              spring2027.key, CourseTermScope.currentAcademicYear),
          isTrue);
      expect(
          catalog.matchesCoursePickerScope(
              past2026Spring.key, CourseTermScope.currentAcademicYear),
          isFalse);
      expect(
          catalog.matchesCoursePickerScope(
              past2026Spring.key, CourseTermScope.pastTerms),
          isTrue);
      expect(
          catalog.matchesCoursePickerScope(
              silentUngrouped.key, CourseTermScope.currentAcademicYear),
          isFalse);
      expect(
          catalog.matchesHomeCoursePicker(
              silentUngrouped.key, 'currentAcademicYear',
              hasVisibleItems: true),
          isTrue);
      expect(
          catalog.matchesCoursePickerScope(
              silentUngrouped.key, CourseTermScope.allTerms),
          isTrue);
    });

    test(
        'pinyin natural sort orders home course options cleanly and sinks ungrouped on tie',
        () {
      expect(compareNaturalPinyin('数据结构2', '数据结构10'), lessThan(0));
      expect(compareNaturalPinyin('编译原理', '高等数学'), lessThan(0));

      const courseA = CourseRef(
        courseId: '10',
        clazzId: '1',
        name: '高等数学',
        folderName: '2026年秋',
      );
      const courseB = CourseRef(
        courseId: '11',
        clazzId: '2',
        name: '编译原理',
        folderName: '2026年秋',
      );
      const blankCourse = CourseRef(
        courseId: '12',
        clazzId: '3',
        name: '操作系统',
      );
      final catalog = CourseTermCatalog.build(
        courses: const [courseA, courseB, blankCourse],
        assignments: const [],
        notices: const [],
        preferences: const CourseTermPreferences.empty(),
        now: DateTime.utc(2026, 11, 20, 4),
      );
      final options = buildHomeCourseFilterOptions(
        assignments: const [],
        catalog: const [courseA, courseB, blankCourse],
        records: const [],
        termCatalog: catalog,
        includeIdleCourses: true,
      );
      expect(options.map((o) => o.name).toList(), ['编译原理', '操作系统', '高等数学']);

      final sorted = sortHomeCourseOptionsByCount(options, const {});
      // Both ungrouped (count == 0) sink after grouped courses (编译原理, 高等数学).
      expect(sorted.map((o) => o.name).toList(), ['编译原理', '高等数学', '操作系统']);
    });
  });

  group('M2 official promo auto-block, manual block & restore', () {
    test(
        'isOfficialPromoCourse blocks official promo titles without false positives',
        () {
      expect(CourseTermCatalog.isOfficialPromoCourse('学习通新手引导'), isTrue);
      expect(CourseTermCatalog.isOfficialPromoCourse('超星平台操作培训教程'), isTrue);
      expect(CourseTermCatalog.isOfficialPromoCourse('开学第一课（官方体验课）'), isTrue);

      for (final safeTitle in const [
        '程序设计竞赛',
        '电子设计竞赛实训',
        '创新创业竞赛指导',
        '大学计算机基础',
        '数据结构',
        '英语演讲比赛指导',
      ]) {
        expect(CourseTermCatalog.isOfficialPromoCourse(safeTitle), isFalse,
            reason: safeTitle);
      }
    });

    test(
        'blocked courses are excluded from current & all sync scopes unless targeted',
        () {
      final now = DateTime.utc(2026, 11, 20, 4);
      const promoCourse = CourseRef(
        courseId: '900',
        clazzId: '90',
        name: '学习通官方体验课',
        folderName: '2026年秋',
      );
      const manualBlockedCourse = CourseRef(
        courseId: '901',
        clazzId: '91',
        name: '概率论与数理统计',
        folderName: '2026年秋',
      );
      const normalCourse = CourseRef(
        courseId: '902',
        clazzId: '92',
        name: '数据结构',
        folderName: '2026年秋',
      );
      final prefs = CourseTermPreferences()
          .withBlockMode(manualBlockedCourse.key, CourseBlockMode.blocked);
      final catalog = CourseTermCatalog.build(
        courses: const [promoCourse, manualBlockedCourse, normalCourse],
        assignments: const [],
        notices: const [],
        preferences: prefs,
        now: now,
      );

      expect(catalog.isBlocked(promoCourse.key), isTrue);
      expect(catalog.isBlocked(manualBlockedCourse.key), isTrue);
      expect(catalog.autoBlockedPromoEntries.map((e) => e.courseKey),
          [promoCourse.key]);
      expect(catalog.manuallyBlockedEntries.map((e) => e.courseKey),
          [manualBlockedCourse.key]);
      expect(catalog.isActiveOrRecalled(promoCourse.key), isFalse);
      expect(catalog.matchesHomeCoursePicker(promoCourse.key, 'allTerms'),
          isFalse);

      final rawCatalog = [
        for (final c in [promoCourse, manualBlockedCourse, normalCourse])
          ChaoxingCourseRef(
            courseId: c.courseId,
            clazzId: c.clazzId,
            courseName: c.name,
            folderName: c.folderName,
          ),
      ];

      final selCurrent = SyncScopeSelection.select(
        catalog: rawCatalog,
        scope: AssignmentSyncScope.current,
        termCatalog: catalog,
      );
      expect(
          selCurrent.targetCourses
              .map((c) => '${c.courseId}:${c.clazzId}')
              .toList(),
          [normalCourse.key]);
      expect(selCurrent.skippedCourseKeys,
          containsAll([promoCourse.key, manualBlockedCourse.key]));

      final selAll = SyncScopeSelection.select(
        catalog: rawCatalog,
        scope: AssignmentSyncScope.all,
        termCatalog: catalog,
      );
      expect(
          selAll.targetCourses
              .map((c) => '${c.courseId}:${c.clazzId}')
              .toList(),
          [normalCourse.key]);
      expect(selAll.skippedCourseKeys,
          containsAll([promoCourse.key, manualBlockedCourse.key]));

      final selTargeted = SyncScopeSelection.select(
        catalog: rawCatalog,
        scope: AssignmentSyncScope.targeted,
        termCatalog: catalog,
        targetedCourseKeys: {manualBlockedCourse.key},
      );
      expect(
          selTargeted.targetCourses
              .map((c) => '${c.courseId}:${c.clazzId}')
              .toList(),
          [manualBlockedCourse.key]);
    });

    testWidgets(
        'CourseListScreen manual block, auto-promo collapse/restore at 320w@2x across themes',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      const promoCourse = CourseRef(
        courseId: '800',
        clazzId: '80',
        name: '学习通新生引导课',
        folderName: '2026年秋',
      );
      const normalCourse = CourseRef(
        courseId: '801',
        clazzId: '81',
        name: '数据结构',
        folderName: '2026年秋',
      );

      for (final dark in [false, true]) {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final repo = LocalAssignmentRepository();
        await repo.activateAccount('block-ui');
        await repo.saveCourses(const [promoCourse, normalCourse],
            account: 'block-ui');
        final store = AssignmentStore(
          repository: repo,
          sessionStore: _StubSession('block-ui'),
          notificationService: _NoopNotif(),
          widgetSnapshotService: _NoopWidget(),
          chaoxingClient: _NoopClient(),
          manageBackgroundSchedule: false,
          clock: () => now,
        );
        addTearDown(store.dispose);
        await store.restoreSession();

        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(MaterialApp(
          theme: dark ? StudyAssistantTheme.dark : StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: CourseListScreen(
            key: ValueKey('course-list-$dark'),
            store: store,
            clock: () => now,
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('数据结构'), findsOneWidget);
        // Official promo course is collapsed by default
        expect(find.text('学习通新生引导课'), findsNothing);
        final promoToggle =
            find.byKey(const ValueKey('course-auto-promo-toggle'));
        await tester.scrollUntilVisible(promoToggle, 120);
        await tester.tap(promoToggle);
        await tester.pumpAndSettle();
        expect(find.text('学习通新生引导课'), findsOneWidget);

        // Restore official promo course -> becomes CourseBlockMode.allowed
        final restoreBtn =
            find.byKey(ValueKey('course-restore-promo-${promoCourse.key}'));
        await tester.scrollUntilVisible(restoreBtn, 120);
        await tester.tap(restoreBtn);
        await tester.pumpAndSettle();
        expect(
          store.courseTermPreferences.entryFor(promoCourse.key)!.blockMode,
          CourseBlockMode.allowed,
        );
        expect(tester.takeException(), isNull, reason: 'dark=$dark');
      }
    });
  });
}

class _StubSession extends SecureSessionStore {
  _StubSession(this.account);
  final String account;

  @override
  Future<String?> readChaoxingAccount() async => account;
  @override
  Future<String?> readChaoxingPassword() async => 'pw';
  @override
  Future<String?> readChaoxingDisplayName() async => '同学';
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotif extends LocalNotificationService {
  @override
  Future<bool> isLegacyAssignmentMigrationComplete() async => true;
  @override
  Future<void> removeLegacyAssignmentSchedules() async {}
  @override
  Future<void> cancelPrivateSchedules() async {}
  @override
  Future<void> rescheduleManual(List<ManualEntry> items) async {}
  @override
  Future<void> rescheduleSummary(List<Assignment> items,
      PersonalWorkspace personal, DateTime? lastSync) async {}
  @override
  Future<void> rescheduleAssignments(List<Assignment> assignments,
      {List<int>? offsetsMinutes}) async {}
}

class _NoopWidget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _NoopClient extends ChaoxingLocalClient {}
