import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/assignment_card.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/display_preferences.dart';
import 'package:study_assistant_mobile/src/models/home_filters.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

import 'review_core_remediation_test.dart' as f;

class _CountingNotifications extends LocalNotificationService {
  int assignmentReschedules = 0;
  int summaryReschedules = 0;
  int manualReschedules = 0;

  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    assignmentReschedules++;
  }

  @override
  Future<void> rescheduleSummary(
    List<Assignment> assignments,
    PersonalWorkspace personal,
    DateTime? lastSync,
  ) async {
    summaryReschedules++;
  }

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {
    manualReschedules++;
  }

  void resetCounts() {
    assignmentReschedules = 0;
    summaryReschedules = 0;
    manualReschedules = 0;
  }
}

class _CountingWidgets extends WidgetSnapshotService {
  int saves = 0;

  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {
    saves++;
  }

  @override
  Future<void> saveAssignmentsForContext(
    List<Assignment> assignments, {
    bool authenticated = true,
    WidgetRange range = WidgetRange.week,
  }) async {
    saves++;
  }

  void resetCounts() {
    saves = 0;
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 22, 10, 0);

  group('P0-04: Home scroll rebuild isolation & lazy preview', () {
    testWidgets(
        'scrolling within first 80px does not trigger AssignmentListScreen body setState or rebuild cards',
        (tester) async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final store = f.makeStore(f.Session());
      addTearDown(store.dispose);
      await store.restoreSession();
      final items = [
        for (var i = 0; i < 20; i++)
          Assignment(
            id: 'cx:work:1:2:$i',
            courseName: '计算机网络',
            title: '实验作业 $i',
            deadlineAt: now.add(Duration(days: i + 1)),
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
          ),
      ];
      await store.repository.mergeAndSave(items);
      await store.refreshAssignments();

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: AssignmentListScreen(store: store, clock: () => now),
        ),
      ));
      await tester.pumpAndSettle();

      final initialCardElements =
          find.byType(AssignmentCard).evaluate().toList(growable: false);
      expect(initialCardElements, isNotEmpty);

      // Drag 50px inside the 0..80px header transition zone.
      final firstCardElement = initialCardElements.first;
      final firstCardWidgetBefore = firstCardElement.widget;

      await tester.drag(find.byType(ListView), const Offset(0, -50));
      await tester.pump();

      // Card widget instance must NOT have been rebuilt by a full-screen setState.
      expect(identical(firstCardElement.widget, firstCardWidgetBefore), isTrue);
    });
  });

  group('P0-05: Granular rescheduling & authListenable isolation', () {
    test(
        'savePersonal plan/note edits do not trigger assignment, manual, or widget reschedules',
        () async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final notifications = _CountingNotifications();
      final widgets = _CountingWidgets();
      final store = AssignmentStore(
        sessionStore: f.Session(),
        notificationService: notifications,
        widgetSnapshotService: widgets,
        chaoxingClient: f.Client(),
      );
      addTearDown(store.dispose);
      await store.restoreSession();
      notifications.resetCounts();
      widgets.resetCounts();

      // 1. Adding to Today Plan with summaryEnabled=false triggers ZERO reschedules.
      final okPlan = await store.savePersonal(
        (cur) => PersonalWorkspace(
          work: cur.work,
          plans: [
            ...cur.plans,
            const DailyPlanItem('cx:work:1:2:1', '2026-11-22', 30),
          ],
          summaryEnabled: false,
          summaryHour: cur.summaryHour,
          summaryMinute: cur.summaryMinute,
        ),
        store.accountEpoch,
      );
      expect(okPlan, isTrue);
      expect(notifications.assignmentReschedules, 0);
      expect(notifications.summaryReschedules, 0);
      expect(notifications.manualReschedules, 0);
      expect(widgets.saves, 0);

      // 2. Enabling daily summary reschedules ONLY summary.
      final okEnableSummary = await store.savePersonal(
        (cur) => PersonalWorkspace(
          work: cur.work,
          plans: cur.plans,
          summaryEnabled: true,
          summaryHour: 21,
          summaryMinute: 0,
        ),
        store.accountEpoch,
      );
      expect(okEnableSummary, isTrue);
      expect(notifications.assignmentReschedules, 0);
      expect(notifications.summaryReschedules, 1);
      expect(notifications.manualReschedules, 0);
      expect(widgets.saves, 0);

      // 3. Editing personal note while summaryEnabled=true triggers ZERO reschedules.
      notifications.resetCounts();
      final okNote = await store.savePersonal(
        (cur) => PersonalWorkspace(
          work: {
            ...cur.work,
            'cx:work:1:2:1': const PersonalWork(note: '重点复习第三章'),
          },
          plans: cur.plans,
          summaryEnabled: cur.summaryEnabled,
          summaryHour: cur.summaryHour,
          summaryMinute: cur.summaryMinute,
        ),
        store.accountEpoch,
      );
      expect(okNote, isTrue);
      expect(notifications.assignmentReschedules, 0);
      expect(notifications.summaryReschedules, 0);
      expect(notifications.manualReschedules, 0);
      expect(widgets.saves, 0);

      // 4. Adding a Today Plan while summaryEnabled=true reschedules ONLY summary.
      final okPlanWithSummary = await store.savePersonal(
        (cur) => PersonalWorkspace(
          work: cur.work,
          plans: [
            ...cur.plans,
            const DailyPlanItem('cx:work:1:2:2', '2026-11-22', 45),
          ],
          summaryEnabled: cur.summaryEnabled,
          summaryHour: cur.summaryHour,
          summaryMinute: cur.summaryMinute,
        ),
        store.accountEpoch,
      );
      expect(okPlanWithSummary, isTrue);
      expect(notifications.assignmentReschedules, 0);
      expect(notifications.summaryReschedules, 1);
      expect(notifications.manualReschedules, 0);
      expect(widgets.saves, 0);

      // 5. Saving notebook reschedules ONLY manual reminders.
      notifications.resetCounts();
      final okNotebook = await store.saveNotebook(
        (cur) => StudyNotebook(
          entries: [
            ...cur.entries,
            ManualEntry(
              id: 'm1',
              kind: 'todo',
              title: '打印实验报告',
              at: now.add(const Duration(days: 1)),
              remind: true,
              minutes: 30,
            ),
          ],
        ),
        store.accountEpoch,
      );
      expect(okNotebook, isTrue);
      expect(notifications.assignmentReschedules, 0);
      expect(notifications.summaryReschedules, 0);
      expect(notifications.manualReschedules, 1);
      expect(widgets.saves, 0);
    });

    test(
        'saveHomeFilters does not toggle isLoading and authListenable ignores non-auth updates',
        () async {
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      final store = f.makeStore(f.Session());
      addTearDown(store.dispose);
      await store.restoreSession();

      var authEvents = 0;
      var sawLoadingDuringFilterSave = false;
      store.authListenable.addListener(() => authEvents++);
      void loadingObserver() {
        if (store.isLoading) sawLoadingDuringFilterSave = true;
      }

      store.addListener(loadingObserver);
      addTearDown(() => store.removeListener(loadingObserver));

      await store.saveHomeFilters(
        const HomeFilters(query: '物理'),
        store.accountEpoch,
      );
      await store.saveDisplay(
        store.display.copyWith(compact: !store.display.compact),
      );

      expect(sawLoadingDuringFilterSave, isFalse);
      expect(authEvents, 0);

      // Logout MUST notify authListenable so GoRouter redirects to /login.
      await store.logout();
      expect(authEvents, greaterThan(0));
    });
  });
}
