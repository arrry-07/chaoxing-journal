import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/reminder_history.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/daily_summary.dart';
import 'package:study_assistant_mobile/src/services/reminder_explanation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('study_assistant/background_reminders');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('history control and page are parsed strictly', () async {
    var listCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getReminderHistoryControl':
          return {
            'historyGeneration': 4,
            'recordingEnabled': true,
            'ownerMatches': true,
            'purgePending': false,
            'purgeToken': null,
          };
        case 'listReminderHistory':
          listCalls++;
          expect(
            (call.arguments as Map)['context'],
            {
              'accountHash': 'hash',
              'sessionEpoch': 2,
              'historyGeneration': 4,
              'operationSequence': 0,
            },
          );
          return {
            'items': [
              {
                'id': 9,
                'observationId': '4:7:0',
                'operationSequence': 7,
                'subjectKind': 'assignment',
                'subjectId': 'cx:work:1:2:3',
                'logicalKey': 'event-1',
                'category': 'deadline',
                'stage': 'scheduled',
                'reasonCode': null,
                'observedAt': 1000,
                'scheduledAt': 2000,
                'notificationId': 11,
                'batchKey': null,
              },
            ],
            'snapshotMaxId': 9,
            'nextBeforeId': null,
            'checkedAt': 3000,
            'historyGeneration': 4,
          };
        default:
          fail('unexpected ${call.method}');
      }
    });
    const gateway = BackgroundReminderGateway();
    final control = await gateway.getReminderHistoryControl(
      accountHash: 'hash',
      sessionEpoch: 2,
    );
    expect(control.historyGeneration, 4);
    expect(control.recordingEnabled, isTrue);
    expect(control.ownerMatches, isTrue);
    final page = await gateway.listReminderHistory(
      context: const ReminderObservationContext(
        accountHash: 'hash',
        sessionEpoch: 2,
        historyGeneration: 4,
        operationSequence: 0,
      ),
    );
    expect(listCalls, 1);
    expect(page.items.single.category, 'deadline');
    expect(page.items.single.scheduledAt,
        DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true).toLocal());
    expect(page.checkedAt,
        DateTime.fromMillisecondsSinceEpoch(3000, isUtc: true).toLocal());
  });

  test('history platform errors keep their reason code', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'stale_history_generation',
        message: '提醒历史代次已变化',
      );
    });
    const gateway = BackgroundReminderGateway();
    await expectLater(
      gateway.getReminderHistoryControl(),
      throwsA(
        isA<ReminderHistoryException>().having(
          (error) => error.code,
          'code',
          'stale_history_generation',
        ),
      ),
    );
  });

  test('append rejects an unknown native result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'mystery');
    const gateway = BackgroundReminderGateway();
    await expectLater(
      gateway.appendReminderObservation(
        context: const ReminderObservationContext(
          accountHash: 'hash',
          sessionEpoch: 1,
          historyGeneration: 1,
          operationSequence: 2,
        ),
        observation: const ReminderObservation(
          subjectKind: 'assignment',
          logicalKey: 'event',
          category: 'deadline',
          stage: 'scheduled',
        ),
      ),
      throwsA(isA<ReminderHistoryException>()),
    );
  });

  group('reminder explanation', () {
    final now = DateTime(2026, 11, 18, 12);

    Assignment assignment({
      String id = 'cx:work:1:2:3',
      String status = 'pending',
      DateTime? deadline,
      bool trusted = true,
      bool readFailed = false,
    }) =>
        Assignment(
          id: id,
          courseName: '课程',
          title: '作业',
          deadlineAt: deadline ?? now.add(const Duration(days: 2)),
          requirementsText: '',
          status: status,
          lastSyncedAt: now,
          deadlineTrusted: trusted,
          deadlineReadFailed: readFailed,
        );

    ReminderPlanState plan({
      bool baseline = true,
      Set<String> known = const {},
      Set<String> sent = const {},
    }) =>
        ReminderPlanState(
          accountHash: 'hash',
          sessionEpoch: 1,
          baselineCompleted: baseline,
          knownAssignmentIds: known,
          sentNewAssignmentIds: sent,
          lastAttemptAt: null,
          lastFullSuccessAt: null,
          pendingUpdate: false,
          mutationVersion: 1,
        );

    ReminderExplanation explain(
      Assignment item, {
      ReminderPlanState? planState,
      bool hidden = false,
      ReminderSubjectEvidence? evidence,
      ReminderHealth? health,
      PluginScheduleEvidenceSnapshot? plugin,
    }) =>
        ReminderExplanationService.forAssignment(
          primary: item,
          sources: [item],
          groupHidden: hidden,
          hiddenAssignmentIds: hidden ? {item.id} : const {},
          unfollowedCourseKeys: const {},
          plan: planState ?? plan(),
          offsets: const [30],
          newReminderEnabled: true,
          now: now,
          evidence: evidence,
          health: health,
          pluginEvidence: plugin,
          queryWarnings: const [],
        );

    test('eligible assignment is unconfirmed without system evidence', () {
      final result = explain(
        assignment(),
        health: const ReminderHealth(
          notifications: true,
          assignmentChannel: ReminderChannelHealth(
            ReminderChannelStatus.enabled,
          ),
        ),
      );
      final deadline =
          result.categories.firstWhere((item) => item.category == 'deadline');
      final added = result.categories
          .firstWhere((item) => item.category == 'newAssignment');
      expect(deadline.status, ReminderExplanationStatus.unconfirmed);
      expect(
          deadline.nextScheduledAt,
          now
              .add(const Duration(days: 2))
              .subtract(const Duration(minutes: 30)));
      expect(added.status, ReminderExplanationStatus.unconfirmed);
      expect(result.queryWarnings, isEmpty);
    });

    test('system permission off defers an otherwise eligible reminder', () {
      final result = explain(
        assignment(),
        health: const ReminderHealth(
          notifications: false,
          assignmentChannel: ReminderChannelHealth(
            ReminderChannelStatus.enabled,
          ),
        ),
      );
      final deadline =
          result.categories.firstWhere((item) => item.category == 'deadline');
      expect(deadline.status, ReminderExplanationStatus.deferred);
      expect(deadline.reasonCodes, contains('notificationPermissionOff'));
    });

    test('hidden group is ineligible', () {
      final result = explain(assignment(), hidden: true);
      expect(
        result.categories.map((item) => item.status),
        everyElement(ReminderExplanationStatus.ineligible),
      );
      expect(
        result.categories.expand((item) => item.reasonCodes),
        contains('hidden'),
      );
    });

    test('matching plugin evidence makes the reminder planned', () {
      final at = now.add(const Duration(hours: 2));
      final evidence = ReminderSubjectEvidence(
        checkedAt: now,
        nativeEvents: const [],
        pluginEvidence: [
          ReminderPluginSubjectEvidence(
            subjectKind: 'assignment',
            subjectId: 'cx:work:1:2:3',
            logicalKey: 'event',
            category: 'deadline',
            state: 'confirmedScheduled',
            scheduledAt: at,
            notificationId: 42,
            expectedPayload: 'a:payload',
            evidenceAt: now,
          ),
        ],
        queryWarnings: const [],
        historyGeneration: 1,
      );
      final result = explain(
        assignment(),
        health: const ReminderHealth(
          notifications: true,
          assignmentChannel: ReminderChannelHealth(
            ReminderChannelStatus.enabled,
          ),
        ),
        evidence: evidence,
        plugin: PluginScheduleEvidenceSnapshot(
          items: const [
            PluginScheduleEvidence(
              id: 42,
              payload: 'a:payload',
              channelId: 'assignment_deadlines',
              pending: true,
              active: false,
            ),
          ],
          error: null,
          checkedAt: now,
        ),
      );
      final deadline =
          result.categories.firstWhere((item) => item.category == 'deadline');
      expect(deadline.status, ReminderExplanationStatus.planned);
      expect(deadline.nextScheduledAt, at);
    });

    test('manual reminder after its window is deferred', () {
      final entry = ManualEntry(
        id: 'manual-1',
        title: '复习',
        kind: 'todo',
        at: now.add(const Duration(minutes: 10)),
        remind: true,
        done: false,
      );
      final result = ReminderExplanationService.forManual(
        entry: entry,
        entryId: entry.id,
        now: now,
        evidence: null,
        health: null,
        pluginEvidence: null,
        queryWarnings: const [],
      );
      expect(result.categories.single.status,
          ReminderExplanationStatus.ineligible);
      expect(
          result.categories.single.reasonCodes, contains('offsetWindowPassed'));
    });

    test('removed manual entry uses a generic name', () {
      final result = ReminderExplanationService.forManual(
        entry: null,
        entryId: 'gone',
        now: now,
        evidence: null,
        health: null,
        pluginEvidence: null,
        queryWarnings: const [],
      );
      expect(result.displayName, '已移除的个人安排');
      expect(result.categories.single.reasonCodes, contains('removed'));
    });

    test('unmatched plugin evidence is unconfirmed instead of planned', () {
      final at = now.add(const Duration(hours: 2));
      final evidence = ReminderSubjectEvidence(
        checkedAt: now,
        nativeEvents: const [],
        pluginEvidence: [
          ReminderPluginSubjectEvidence(
            subjectKind: 'manual',
            subjectId: 'manual-1',
            logicalKey: 'manual:1',
            category: 'personal',
            state: 'confirmedScheduled',
            scheduledAt: at,
            notificationId: 99,
            expectedPayload: 'p:manual-1',
            evidenceAt: now,
          ),
        ],
        queryWarnings: const [],
        historyGeneration: 1,
      );
      final result = ReminderExplanationService.forManual(
        entry: ManualEntry(
          id: 'manual-1',
          title: '待办',
          kind: 'todo',
          at: at.add(const Duration(minutes: 30)),
          remind: true,
          done: false,
        ),
        entryId: 'manual-1',
        now: now,
        evidence: evidence,
        health: const ReminderHealth(
          notifications: true,
          manualChannel: ReminderChannelHealth(ReminderChannelStatus.enabled),
        ),
        pluginEvidence: PluginScheduleEvidenceSnapshot(
          items: const [],
          error: null,
          checkedAt: now,
        ),
        queryWarnings: const [],
      );
      final category = result.categories.single;
      expect(category.status, ReminderExplanationStatus.unconfirmed);
      expect(category.reasonCodes, contains('scheduleUnconfirmed'));
    });

    test('native pending deadline evidence confirms reminder', () {
      final at = now.add(const Duration(hours: 3));
      final evidence = ReminderSubjectEvidence(
        checkedAt: now,
        nativeEvents: [
          ReminderNativeSubjectEvidence(
            subjectKind: 'assignment',
            subjectId: 'cx:work:1:2:3',
            eventId: 'evt-1',
            category: 'deadline',
            logicalKey: 'evt-1',
            state: 'pending',
            scheduledAt: at,
            notificationId: 12,
            evidenceAt: now,
          ),
        ],
        pluginEvidence: const [],
        queryWarnings: const [],
        historyGeneration: 1,
      );
      final result = explain(
        assignment(),
        health: const ReminderHealth(
          notifications: true,
          assignmentChannel:
              ReminderChannelHealth(ReminderChannelStatus.enabled),
        ),
        evidence: evidence,
      );
      final deadline =
          result.categories.firstWhere((item) => item.category == 'deadline');
      expect(deadline.status, ReminderExplanationStatus.planned);
      expect(deadline.nextScheduledAt, at);
    });

    test('native deadline with missing alarm reports scheduleUnconfirmed', () {
      final at = now.add(const Duration(hours: 3));
      final evidence = ReminderSubjectEvidence(
        checkedAt: now,
        nativeEvents: [
          ReminderNativeSubjectEvidence(
            subjectKind: 'assignment',
            subjectId: 'cx:work:1:2:3',
            eventId: 'evt-missing-alarm',
            category: 'deadline',
            logicalKey: 'evt-missing-alarm',
            state: 'pending',
            scheduledAt: at,
            notificationId: 12,
            evidenceAt: now,
            alarmScheduled: false,
          ),
        ],
        pluginEvidence: const [],
        queryWarnings: const [],
        historyGeneration: 1,
      );
      final result = explain(
        assignment(),
        health: const ReminderHealth(
          notifications: true,
          assignmentChannel:
              ReminderChannelHealth(ReminderChannelStatus.enabled),
        ),
        evidence: evidence,
      );
      final deadline =
          result.categories.firstWhere((item) => item.category == 'deadline');
      expect(deadline.status, ReminderExplanationStatus.unconfirmed);
      expect(deadline.reasonCodes, contains('scheduleUnconfirmed'));
    });

    test('pending native newAssignment is not masked by alreadyKnown', () {
      final evidence = ReminderSubjectEvidence(
        checkedAt: now,
        nativeEvents: [
          ReminderNativeSubjectEvidence(
            subjectKind: 'assignment',
            subjectId: 'cx:work:1:2:3',
            eventId: 'evt-new-1',
            category: 'newAssignment',
            logicalKey: 'evt-new-1',
            state: 'pending',
            scheduledAt: now,
            notificationId: 13,
            evidenceAt: now,
          ),
        ],
        pluginEvidence: const [],
        queryWarnings: const [],
        historyGeneration: 1,
      );
      final result = explain(
        assignment(),
        planState: plan(known: const {'cx:work:1:2:3'}),
        health: const ReminderHealth(
          notifications: true,
          assignmentChannel:
              ReminderChannelHealth(ReminderChannelStatus.enabled),
        ),
        evidence: evidence,
      );
      final added = result.categories
          .firstWhere((item) => item.category == 'newAssignment');
      expect(added.reasonCodes, isNot(contains('alreadyKnown')));
      expect(added.status, ReminderExplanationStatus.planned);
    });

    test('assignment without deadline does not emit anchorPassed', () {
      final noDeadline = Assignment(
        id: 'cx:work:1:2:no-dl',
        courseName: '课程',
        title: '无截止作业',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
        deadlineTrusted: true,
      );
      final result = explain(noDeadline);
      final deadline =
          result.categories.firstWhere((item) => item.category == 'deadline');
      expect(deadline.status, ReminderExplanationStatus.ineligible);
      expect(deadline.reasonCodes, contains('noDeadline'));
      expect(deadline.reasonCodes, isNot(contains('anchorPassed')));
    });

    test('H5: newAssignment respects per-source baselinedSources', () {
      final exam = Assignment(
        id: 'cx:exam:1:2:100',
        courseName: '高等数学',
        title: '期中考试',
        deadlineAt: now.add(const Duration(days: 2)),
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
        deadlineTrusted: true,
        exam: ExamInfo(
          courseId: '1',
          clazzId: '2',
          examId: '100',
          startAt: now.add(const Duration(days: 2)),
          startTrusted: true,
          lifecycle: 'scheduled',
        ),
        submitUrl: 'https://example.com/exam/100',
      );
      final result = explain(
        exam,
        planState: ReminderPlanState(
          accountHash: 'hash',
          sessionEpoch: 1,
          baselineCompleted: true,
          baselinedSources: const {'courseWork'},
          knownAssignmentIds: {exam.id},
          sentNewAssignmentIds: const {},
          lastAttemptAt: null,
          lastFullSuccessAt: null,
          pendingUpdate: false,
          mutationVersion: 1,
        ),
      );
      final added = result.categories
          .firstWhere((item) => item.category == 'newAssignment');
      expect(added.status, ReminderExplanationStatus.ineligible);
      expect(added.reasonCodes, contains('baselinePending'));
      expect(added.reasonCodes, isNot(contains('alreadyKnown')));
    });

    test(
        'H5: _nextPlanned shifts pre-08:00 trigger to 08:00 and drops >= deadline',
        () {
      final atTen = DateTime(2026, 11, 19, 10, 0);
      final earlyItem = assignment(deadline: atTen);
      final earlyExplain = ReminderExplanationService.forAssignment(
        primary: earlyItem,
        sources: [earlyItem],
        groupHidden: false,
        hiddenAssignmentIds: const {},
        unfollowedCourseKeys: const {},
        plan: plan(),
        offsets: const [240], // 06:00 -> shifted to 08:00 < 10:00
        newReminderEnabled: true,
        now: DateTime(2026, 11, 19, 2, 0),
        evidence: null,
        health: const ReminderHealth(
          notifications: true,
          assignmentChannel: ReminderChannelHealth(
            ReminderChannelStatus.enabled,
          ),
        ),
        pluginEvidence: null,
        queryWarnings: const [],
      );
      final validDeadline = earlyExplain.categories
          .firstWhere((item) => item.category == 'deadline');
      expect(validDeadline.nextScheduledAt, DateTime(2026, 11, 19, 8, 0));

      final utcItem = assignment(deadline: atTen.toUtc());
      final utcExplain = ReminderExplanationService.forAssignment(
        primary: utcItem,
        sources: [utcItem],
        groupHidden: false,
        hiddenAssignmentIds: const {},
        unfollowedCourseKeys: const {},
        plan: plan(),
        offsets: const [240],
        newReminderEnabled: true,
        now: DateTime(2026, 11, 19, 2),
        evidence: null,
        health: const ReminderHealth(
          notifications: true,
          assignmentChannel: ReminderChannelHealth(
            ReminderChannelStatus.enabled,
          ),
        ),
        pluginEvidence: null,
        queryWarnings: const [],
      );
      expect(
        utcExplain.categories
            .singleWhere((item) => item.category == 'deadline')
            .nextScheduledAt,
        DateTime(2026, 11, 19, 8),
      );

      final atSevenThirty = DateTime(2026, 11, 19, 7, 30);
      final invalidItem = assignment(deadline: atSevenThirty);
      final expiredShiftExplain = ReminderExplanationService.forAssignment(
        primary: invalidItem,
        sources: [invalidItem],
        groupHidden: false,
        hiddenAssignmentIds: const {},
        unfollowedCourseKeys: const {},
        plan: plan(),
        offsets: const [60], // 06:30 -> shifted to 08:00 >= 07:30 -> dropped
        newReminderEnabled: true,
        now: DateTime(2026, 11, 19, 2, 0),
        evidence: null,
        health: const ReminderHealth(
          notifications: true,
          assignmentChannel: ReminderChannelHealth(
            ReminderChannelStatus.enabled,
          ),
        ),
        pluginEvidence: null,
        queryWarnings: const [],
      );
      final droppedDeadline = expiredShiftExplain.categories
          .firstWhere((item) => item.category == 'deadline');
      expect(droppedDeadline.status, ReminderExplanationStatus.ineligible);
      expect(droppedDeadline.reasonCodes, contains('offsetWindowPassed'));
      expect(droppedDeadline.nextScheduledAt, isNull);
    });

    test(
        'H5: pre-08:00 newAssignment shows 08:00 and omits notification settings CTA',
        () {
      final preWindowNow = DateTime(2026, 11, 19, 2, 0);
      final futureItem = assignment(deadline: DateTime(2026, 11, 20, 12, 0));
      final evidence = ReminderSubjectEvidence(
        checkedAt: preWindowNow,
        nativeEvents: [
          ReminderNativeSubjectEvidence(
            subjectKind: 'assignment',
            subjectId: futureItem.id,
            eventId: 'e-new',
            logicalKey: 'e-new',
            category: 'newAssignment',
            state: 'pending',
            scheduledAt: preWindowNow,
            notificationId: 77,
            evidenceAt: preWindowNow,
            alarmScheduled: true,
          ),
        ],
        pluginEvidence: const [],
        queryWarnings: const [],
        historyGeneration: 1,
      );
      final result = ReminderExplanationService.forAssignment(
        primary: futureItem,
        sources: [futureItem],
        groupHidden: false,
        hiddenAssignmentIds: const {},
        unfollowedCourseKeys: const {},
        plan: plan(),
        offsets: const [30],
        newReminderEnabled: true,
        now: preWindowNow,
        evidence: evidence,
        health: const ReminderHealth(
          notifications: true,
          assignmentUpdatesChannel: ReminderChannelHealth(
            ReminderChannelStatus.enabled,
          ),
        ),
        pluginEvidence: null,
        queryWarnings: const [],
      );
      final added = result.categories
          .firstWhere((item) => item.category == 'newAssignment');
      expect(added.status, ReminderExplanationStatus.deferred);
      expect(added.reasonCodes, contains('outsideWindow'));
      expect(added.nextScheduledAt, DateTime(2026, 11, 19, 8, 0));
      expect(added.actionLabel, isNull);
    });

    test('H5: untrusted deadline with null date does not emit noDeadline', () {
      final unknown = Assignment(
        id: 'cx:work:1:2:unknown-dl',
        courseName: '课程',
        title: '截止未知',
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: now,
        deadlineTrusted: false,
      );
      final result = explain(unknown);
      final deadline =
          result.categories.firstWhere((item) => item.category == 'deadline');
      expect(deadline.reasonCodes, contains('deadlineUnknown'));
      expect(deadline.reasonCodes, isNot(contains('noDeadline')));
    });
  });
}
