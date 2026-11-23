import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/services/interaction_feedback_service.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/sync_status_screen.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_api_parser.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/models/sync_scope.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/home_sync_presentation.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  const verification = SyncIssue(SyncIssueKind.verificationRequired, '需要验证');
  const missingCourseCredential = SyncIssue(
      SyncIssueKind.schemaChanged, '示例课程 课程页未生成作业读取凭证，可在应用内检查访问',
      stage: 'coursePage');
  const examRedirect =
      SyncIssue(SyncIssueKind.schemaChanged, '考试页面跳转未通过安全检查', stage: 'exam');

  testWidgets('exam read stages display localized pause information',
      (tester) async {
    final report = SyncReport(
      phase: SyncPhase.partial,
      sourceResults: const [
        SyncSourceResult(
            source: 'exam',
            phase: SyncSourcePhase.partial,
            reasonCodes: [
              'examPhoneListFailed',
              'examCourseEntryFailed',
              'examPcListFailed',
              'examCircuitPaused'
            ]),
      ],
    );
    final store = await _storeWithCachedRecords(report);
    await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
    await tester.scrollUntilVisible(find.text('读取来源'), 250);
    await tester.tap(find.text('读取来源'));
    await tester.pumpAndSettle();
    for (final text in [
      '手机考试列表未完整读取',
      '考试补查所需的课程入口未读取',
      'PC 考试列表未完整读取',
      '考试请求连续失败，本轮已暂停该类请求'
    ]) {
      expect(find.textContaining(text), findsOneWidget);
    }
  });

  test('sync summary does not hide detail and exam failures behind one source',
      () {
    const report = SyncReport(
      phase: SyncPhase.partial,
      sourceResults: [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
          detailUnconfirmedCount: 1,
        ),
        SyncSourceResult(
          source: 'exam',
          phase: SyncSourcePhase.partial,
          failedCourses: 1,
        ),
      ],
    );
    expect(report.summary, '部分课业信息未更新');
  });

  test(
      'not-enabled group history does not turn a detail retry into a source failure',
      () {
    const report = SyncReport(
      phase: SyncPhase.partial,
      sourceResults: [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
          detailUnconfirmedCount: 1,
        ),
        SyncSourceResult(
          source: 'groupHistory',
          phase: SyncSourcePhase.notEnabled,
        ),
      ],
    );
    expect(report.summary, '作业列表已更新，部分截止时间待确认');
  });

  test('classroom failure is counted once without a generic multi-source label',
      () {
    const report = SyncReport(
      phase: SyncPhase.partial,
      failedCourses: 1,
      sourceResults: [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
        ),
        SyncSourceResult(
          source: 'classroomActivity:42',
          phase: SyncSourcePhase.partial,
          failedCourses: 1,
        ),
      ],
    );
    expect(report.summary, '作业记录已更新，部分课堂任务未更新');
  });

  test('incomplete exam count deduplicates repeated source rows', () {
    const report = SyncReport(
      phase: SyncPhase.partial,
      sourceResults: [
        SyncSourceResult(
          source: 'exam',
          phase: SyncSourcePhase.partial,
        ),
        SyncSourceResult(
          source: 'exam',
          phase: SyncSourcePhase.failed,
        ),
        SyncSourceResult(
          source: 'examNotice',
          phase: SyncSourcePhase.partial,
        ),
        SyncSourceResult(
          source: 'examAccount',
          phase: SyncSourcePhase.success,
        ),
      ],
    );
    expect(report.incompleteExamSourceCount, 2);
  });

  testWidgets('restored verification report without target asks for a refresh',
      (tester) async {
    await _pumpRestoredReport(tester, [verification]);
    expect(find.text('在应用内检查访问'), findsNothing);
    await tester.ensureVisible(find.text('完成安全验证'));
    await tester.tap(find.text('完成安全验证'));
    await tester.pump();
    expect(find.text('请先刷新作业数据，再完成安全验证'), findsOneWidget);
  });

  testWidgets('restored course credential issue offers an access check',
      (tester) async {
    await _pumpRestoredReport(tester, [missingCourseCredential]);
    expect(find.text('完成安全验证'), findsNothing);
    await tester.ensureVisible(find.text('在应用内检查访问'));
    await tester.tap(find.text('在应用内检查访问'));
    await tester.pump();
    expect(find.text('请先刷新作业数据，再检查访问'), findsOneWidget);
  });

  for (final scenario in [
    (
      name: 'exam redirect failure alone offers neither browser action',
      issues: [examRedirect],
      action: null
    ),
    (
      name: 'generic course page parse failure offers neither browser action',
      issues: [
        const SyncIssue(SyncIssueKind.schemaChanged, '学习通响应无法解析，请稍后重试',
            stage: 'coursePage')
      ],
      action: null
    ),
    (
      name: 'exam redirect failure preserves the access check',
      issues: [examRedirect, missingCourseCredential],
      action: '在应用内检查访问'
    ),
    (
      name: 'exam redirect failure preserves the real verification action',
      issues: [examRedirect, verification],
      action: '完成安全验证'
    ),
    (
      name: 'real verification takes priority over the access check',
      issues: [examRedirect, missingCourseCredential, verification],
      action: '完成安全验证'
    ),
  ]) {
    testWidgets(scenario.name, (tester) async {
      await _pumpRestoredReport(tester, scenario.issues);
      for (final label in ['完成安全验证', '在应用内检查访问']) {
        expect(find.text(label),
            label == scenario.action ? findsOneWidget : findsNothing);
      }
    });
  }

  testWidgets('sync status links to the single background-check setting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncStatusScreen(store: store))),
    );

    expect(find.text('白天后台检查'), findsOneWidget);
    expect(find.text('调整后台检查与提醒'), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-sync-option-15')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-30')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-60')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-custom')), findsNothing);
    expect(find.byKey(const ValueKey('auto-sync-option-off')), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('legacy disabled background check remains visibly disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncStatusScreen(store: store))),
    );

    expect(store.backgroundCheckEnabled, isFalse);
    expect(find.textContaining('已关闭；手动刷新'), findsOneWidget);
  });

  testWidgets('issue query opens grouped details immediately', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    store.syncReport = const SyncReport(
      phase: SyncPhase.partial,
      issues: [
        SyncIssue(
          SyncIssueKind.schemaChanged,
          '作业详情未识别',
          stage: 'detail',
          courseKey: '1:2',
        ),
      ],
    );
    final router = GoRouter(initialLocation: '/sync?expand=issues', routes: [
      GoRoute(
        path: '/sync',
        builder: (_, state) => SyncStatusScreen(
          store: store,
          expandIssues: state.uri.queryParameters['expand'] == 'issues',
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('问题明细（1 组，共 1 条）'), findsOneWidget);
    expect(find.textContaining('作业详情未识别'), findsOneWidget);
    expect(find.textContaining('涉及：课程信息待刷新'), findsOneWidget);

    store.chaoxingClient.courses = const [
      ChaoxingCourseRef(courseId: '1', clazzId: '2', courseName: '无作业课程'),
    ];
    expect(store.courseAssignments, isEmpty);
    await tester.pumpWidget(MaterialApp.router(
      key: const ValueKey('with-fetched-courses'),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('涉及：无作业课程'), findsOneWidget);
    expect(find.textContaining('涉及：课程信息待刷新'), findsNothing);
  });

  for (final scenario in [
    (
      name: 'partial exam source without failed course count',
      source: 'exam',
      phase: SyncSourcePhase.partial,
      failedCourses: 0,
      reasonCodes: const ['schemaChanged'],
    ),
    (
      name: 'failed account exam source',
      source: 'examAccount',
      phase: SyncSourcePhase.failed,
      failedCourses: 1,
      reasonCodes: const <String>[],
    ),
    (
      name: 'partial exam notice source',
      source: 'examNotice',
      phase: SyncSourcePhase.partial,
      failedCourses: 0,
      reasonCodes: const ['parseFailure'],
    ),
  ]) {
    testWidgets('${scenario.name} keeps the last complete records card visible',
        (tester) async {
      final report = SyncReport(
        phase: SyncPhase.partial,
        attemptedAt: DateTime.utc(2026, 11, 19, 4),
        lastDataSuccessAt: DateTime.utc(2026, 11, 19, 3),
        lastFullSuccessAt: DateTime.utc(2026, 11, 18, 3),
        sourceResults: [
          const SyncSourceResult(
            source: 'courseWork',
            phase: SyncSourcePhase.success,
          ),
          SyncSourceResult(
            source: scenario.source,
            phase: scenario.phase,
            failedCourses: scenario.failedCourses,
            reasonCodes: scenario.reasonCodes,
          ),
        ],
      );
      expect(report.failedCourses, 0);
      expect(report.incompleteExamSourceCount, 1);
      expect(report.summary, '作业记录已更新，部分考试信息未更新');

      final store = await _storeWithCachedRecords(report);
      expect(store.lastSyncAt, isNotNull);
      expect(store.hadCacheBeforeLastSync, isTrue);
      expect(
        store.assignments.map((item) => item.title),
        containsAll(['本次新作业', '上次考试']),
      );

      await tester.pumpWidget(
        MaterialApp(home: SyncStatusScreen(store: store)),
      );
      expect(
        find.byKey(const ValueKey('sync-cached-record-status')),
        findsOneWidget,
      );
      expect(find.text('当前保留上次完整同步记录'), findsOneWidget);
    });
  }

  testWidgets('successful exam source never shows the cached records card',
      (tester) async {
    final report = SyncReport(
      phase: SyncPhase.partial,
      attemptedAt: DateTime.utc(2026, 11, 19, 4),
      lastDataSuccessAt: DateTime.utc(2026, 11, 19, 3),
      lastFullSuccessAt: DateTime.utc(2026, 11, 18, 3),
      sourceResults: const [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
        ),
        SyncSourceResult(
          source: 'exam',
          phase: SyncSourcePhase.success,
        ),
      ],
    );
    final store = await _storeWithCachedRecords(report, includeNewWork: false);
    await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
    expect(
      find.byKey(const ValueKey('sync-cached-record-status')),
      findsNothing,
    );
  });

  testWidgets('not-enabled group history never shows the cached records card',
      (tester) async {
    final report = SyncReport(
      phase: SyncPhase.partial,
      attemptedAt: DateTime.utc(2026, 11, 19, 4),
      lastDataSuccessAt: DateTime.utc(2026, 11, 19, 3),
      lastFullSuccessAt: DateTime.utc(2026, 11, 18, 3),
      sourceResults: const [
        SyncSourceResult(
          source: 'courseWork',
          phase: SyncSourcePhase.success,
        ),
        SyncSourceResult(
          source: 'groupHistory',
          phase: SyncSourcePhase.notEnabled,
        ),
      ],
    );
    final store = await _storeWithCachedRecords(report, includeNewWork: false);
    await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
    expect(
      find.byKey(const ValueKey('sync-cached-record-status')),
      findsNothing,
    );
  });

  testWidgets('empty cache never shows the cached records card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final report = SyncReport(
      phase: SyncPhase.partial,
      attemptedAt: DateTime.utc(2026, 11, 19, 4),
      lastDataSuccessAt: DateTime.utc(2026, 11, 19, 3),
      lastFullSuccessAt: DateTime.utc(2026, 11, 18, 3),
      sourceResults: const [
        SyncSourceResult(
          source: 'exam',
          phase: SyncSourcePhase.partial,
          reasonCodes: ['schemaChanged'],
        ),
      ],
    );
    final repo = LocalAssignmentRepository();
    await repo.activateAccount('student');
    await repo.mergeAndSave(const []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_report_v1', jsonEncode(report.toJson()));
    final store = AssignmentStore(
      repository: repo,
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.lastSyncAt, isNotNull);
    expect(store.hadCacheBeforeLastSync, isFalse);
    await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
    expect(
      find.byKey(const ValueKey('sync-cached-record-status')),
      findsNothing,
    );
  });

  testWidgets(
      'normal exam degradation keeps success summary, full sync time and source reasons',
      (tester) async {
    final syncedAt = DateTime.utc(2026, 11, 20, 15, 52);
    final legacyPartialPayload = {
      'phase': 'partial',
      'attemptedAt': syncedAt.toIso8601String(),
      'lastDataSuccessAt': syncedAt.toIso8601String(),
      'lastFullSuccessAt': null,
      'succeededCourses': 40,
      'failedCourses': 0,
      'issues': const [],
      'sourceResults': const [
        {
          'source': 'courseWork',
          'phase': 'success',
          'succeededCourses': 40,
          'failedCourses': 0,
          'recordCount': 39,
          'unconfirmedCount': 0,
          'detailUnconfirmedCount': 0,
          'reasonCodes': <String>[],
        },
        {
          'source': 'exam',
          'phase': 'partial',
          'succeededCourses': 40,
          'failedCourses': 0,
          'recordCount': 8,
          'unconfirmedCount': 8,
          'detailUnconfirmedCount': 0,
          'reasonCodes': ['examPcSupplementUnavailable'],
        },
        {
          'source': 'examAccount',
          'phase': 'partial',
          'succeededCourses': 1,
          'failedCourses': 0,
          'recordCount': 3,
          'unconfirmedCount': 0,
          'detailUnconfirmedCount': 0,
          'reasonCodes': ['accountExamRowSkippedNoId'],
        },
      ],
    };

    final restored = SyncReport.fromJson(legacyPartialPayload);
    expect(restored.phase, SyncPhase.success);
    expect(restored.incompleteExamSourceCount, 0);
    expect(restored.lastFullSuccessAt?.toUtc(), syncedAt);
    expect(restored.summary, '作业记录已更新');

    final homePresentation = HomeSyncPresentation.from(
      restored,
      loading: false,
      hasCache: true,
      now: syncedAt.add(const Duration(seconds: 20)),
    );
    expect(homePresentation.summary, '刚刚更新');
    expect(homePresentation.action, HomeSyncAction.none);

    SharedPreferences.setMockInitialValues({
      'sync_report_v1': jsonEncode(legacyPartialPayload),
    });
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(),
      notificationService: _NoopNotificationService(),
      widgetSnapshotService: _NoopWidgetSnapshotService(),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    expect(store.syncReport.phase, SyncPhase.success);
    expect(store.syncReport.summary, '作业记录已更新');
    expect(store.lastSyncAt, isNotNull);

    await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
    expect(find.text(store.syncSummary), findsOneWidget);
    expect(find.text('尚无完整同步记录'), findsNothing);
    expect(find.textContaining('最近完整同步：'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('sync-cached-record-status')), findsNothing);

    await tester.tap(find.text('读取来源'));
    await tester.pumpAndSettle();
    expect(find.textContaining('读取完成 · 8 条'), findsOneWidget);
    expect(
      find.textContaining('部分课程 PC 考试补充时间未取得，已保留手机端记录'),
      findsOneWidget,
    );
    expect(find.textContaining('部分历史账号考试缺少唯一标识已跳过'), findsOneWidget);
  });

  testWidgets(
      'sync status refresh triggers syncDone only on fresh same-epoch success without operationError',
      (tester) async {
    InteractionFeedback.debugReset();
    addTearDown(InteractionFeedback.debugReset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const channel = MethodChannel('study_assistant/interaction_sound');
      final kinds = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'feedback') {
          kinds.add((call.arguments as Map)['kind'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      late _SyncRefreshStore store;
      var mode = 0;
      store = _SyncRefreshStore(() async {
        switch (mode) {
          case 0:
            store.nextReport = SyncReport(
                phase: SyncPhase.success,
                attemptedAt: DateTime(2026, 11, 22, 10, 0, 1));
            store.nextError = null;
          case 1:
            store.nextReport = SyncReport(
                phase: SyncPhase.failed,
                attemptedAt: DateTime(2026, 11, 22, 10, 0, 2));
            store.nextError = null;
          case 2:
            store.nextReport = SyncReport(
                phase: SyncPhase.success,
                attemptedAt: DateTime(2026, 11, 22, 10, 0, 3));
            store.nextError = '写入失败';
          case 3:
            store.nextEpoch++;
            store.nextReport = SyncReport(
                phase: SyncPhase.success,
                attemptedAt: DateTime(2026, 11, 22, 10, 0, 4));
            store.nextError = null;
        }
      });
      addTearDown(store.dispose);

      await tester
          .pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        kinds.clear();
        mode = i;
        await tester.tap(find.text('刷新作业数据'));
        await tester.pumpAndSettle();
        expect(
          kinds.where((k) => k == 'syncDone').toList(),
          i == 0 ? ['syncDone'] : isEmpty,
          reason: 'mode=$i',
        );
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'displays current-term vs full sync scope summary and triggers syncAllTerms from button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final currentAt = DateTime(2026, 11, 22, 11, 30);
    final fullAt = DateTime(2026, 11, 20, 9, 15);
    var fullScanCalled = false;

    final store = _SyncRefreshStore(() async {})
      ..nextReport = SyncReport(
        phase: SyncPhase.success,
        attemptedAt: currentAt,
        lastDataSuccessAt: currentAt,
        lastCurrentSuccessAt: currentAt,
        lastFullSuccessAt: fullAt,
        syncScope: AssignmentSyncScope.current,
        plannedCourses: 2,
        skippedCourses: 3,
      )
      ..onSyncAllTerms = () async {
        fullScanCalled = true;
      };
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
    await tester.pumpAndSettle();

    expect(find.textContaining('最近本学期同步：'), findsOneWidget);
    expect(find.textContaining('最近完整同步：'), findsOneWidget);
    expect(
      find.textContaining('本次范围：本学期优先 · 已扫描 2 门，跳过往期/归档 3 门'),
      findsOneWidget,
    );

    final allBtn = find.byKey(const ValueKey('sync-all-terms-button'));
    expect(allBtn, findsOneWidget);
    expect(find.text('全量扫描全部学期'), findsOneWidget);
    await tester.ensureVisible(allBtn);
    await tester.tap(allBtn);
    await tester.pumpAndSettle();
    expect(fullScanCalled, isTrue);
  });
}

class _SyncRefreshStore extends AssignmentStore {
  _SyncRefreshStore(this._onSync)
      : super(
          sessionStore: _MemorySessionStore(),
          notificationService: _NoopNotificationService(),
          widgetSnapshotService: _NoopWidgetSnapshotService(),
          manageBackgroundSchedule: false,
        );

  final Future<void> Function() _onSync;
  Future<void> Function()? onSyncAllTerms;
  SyncReport nextReport = const SyncReport(phase: SyncPhase.idle);
  String? nextError;
  int nextEpoch = 0;

  @override
  bool get isAuthenticated => true;

  @override
  int get accountEpoch => nextEpoch;

  @override
  SyncReport get syncReport => nextReport;

  @override
  DateTime? get lastSyncAt => nextReport.lastFullSuccessAt;

  @override
  String? get operationError => nextError;

  @override
  String? get error => nextError;

  @override
  Future<void> syncAssignments({bool complete = false}) => _onSync();

  @override
  Future<void> syncAllTerms() => (onSyncAllTerms ?? _onSync)();
}

Future<void> _pumpRestoredReport(
    WidgetTester tester, List<SyncIssue> issues) async {
  final report = SyncReport(phase: SyncPhase.partial, issues: issues);
  SharedPreferences.setMockInitialValues({
    'sync_report_v1': jsonEncode(report.toJson()),
  });
  final store = AssignmentStore(
    sessionStore: _MemorySessionStore(),
    notificationService: _NoopNotificationService(),
    widgetSnapshotService: _NoopWidgetSnapshotService(),
  );
  addTearDown(store.dispose);
  await store.restoreSession();
  await tester.pumpWidget(MaterialApp(home: SyncStatusScreen(store: store)));
}

Future<AssignmentStore> _storeWithCachedRecords(
  SyncReport report, {
  bool includeNewWork = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = LocalAssignmentRepository();
  await repo.activateAccount('student');
  final oldExam = Assignment(
    id: 'cx:exam:7:11:old',
    source: AssignmentSource.exam,
    courseName: '编译原理',
    title: '上次考试',
    deadlineAt: null,
    requirementsText: '',
    status: 'pending',
    lastSyncedAt: DateTime.utc(2026, 11, 18),
    exam: ExamInfo(
      examId: 'old',
      courseId: '7',
      clazzId: '11',
      startAt: null,
      endAt: null,
      startTrusted: false,
      endTrusted: false,
      lifecycle: 'unknown',
    ),
  );
  final newWork = Assignment(
    id: 'cx:work:7:11:new',
    courseName: '编译原理',
    title: '本次新作业',
    deadlineAt: DateTime.utc(2026, 12, 1),
    requirementsText: '',
    status: 'pending',
    lastSyncedAt: DateTime.utc(2026, 11, 19, 3),
  );
  await repo.mergeAndSave([oldExam, if (includeNewWork) newWork]);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('sync_report_v1', jsonEncode(report.toJson()));
  final store = AssignmentStore(
    repository: repo,
    sessionStore: _MemorySessionStore(),
    notificationService: _NoopNotificationService(),
    widgetSnapshotService: _NoopWidgetSnapshotService(),
  );
  addTearDown(store.dispose);
  await store.restoreSession();
  return store;
}

class _MemorySessionStore extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student';

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _NoopNotificationService extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}
