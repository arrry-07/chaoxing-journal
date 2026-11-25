import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/app/journal_motion.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_picker_sheet.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_swipe_tile.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/background_reminder_gateway.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

double _contrastRatio(Color fg, Color bg) {
  double luminance(Color c) => c.computeLuminance();
  final l1 = luminance(fg);
  final l2 = luminance(bg);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));

  group('M4 palette & overdue visual contrast tokens', () {
    test(
        'primaryFill/onPrimaryFill and overdueSky/overdueSkyBg meet >=4.5:1 WCAG contrast',
        () {
      for (final p in [JournalPalette.light, JournalPalette.dark]) {
        expect(_contrastRatio(p.onPrimaryFill, p.primaryFill),
            greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(p.overdueSky, p.overdueSkyBg),
            greaterThanOrEqualTo(4.5));
        expect(
            _contrastRatio(p.overdueInk, p.sheet), greaterThanOrEqualTo(4.5));
      }
      expect(JournalPalette.light.primaryFill, const Color(0xFF3D63DD));
      expect(JournalPalette.dark.primaryFill, const Color(0xFF88A8F8));
      expect(JournalPalette.light.onInvertedSurface, const Color(0xFFFFFFFF));
      expect(JournalPalette.dark.onInvertedSurface, const Color(0xFF1A1917));
    });
  });

  group('M6 v2 audible notification channels & auto migration', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    const permissions = MethodChannel('study_assistant/permissions');

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, null);
    });

    test(
        'all four v2 channels register with high importance, chimeSound, and vibration pattern',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      SharedPreferences.setMockInitialValues({});
      final createdChannels = <Map<String, Object?>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (call) async => 35);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getNotificationAppLaunchDetails':
            return {'notificationLaunchedApp': false};
          case 'getNotificationChannels':
            return <Map<String, Object?>>[];
          case 'pendingNotificationRequests':
          case 'getActiveNotifications':
            return <Map<String, Object?>>[];
          case 'createNotificationChannel':
            createdChannels
                .add(Map<String, Object?>.from(call.arguments as Map));
            return true;
          default:
            return true;
        }
      });

      final service = LocalNotificationService();
      await service.initialize();

      expect(createdChannels.map((c) => c['id']).toList(), [
        'assignment_deadlines_v2',
        'assignment_updates_v2',
        'daily_summary_v2',
        'personal_schedule_v2',
      ]);
      for (final ch in createdChannels) {
        expect(ch['importance'], 4, reason: 'channel ${ch['id']}');
        expect(ch['playSound'], isTrue, reason: 'channel ${ch['id']}');
        expect(ch['sound'], 'journal_chime', reason: 'channel ${ch['id']}');
        expect(ch['enableVibration'], isTrue, reason: 'channel ${ch['id']}');
      }
    });

    test(
        'restoreSession auto-migrates legacy v1 deadline channel once while allowing explicit opt-out afterward',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      SharedPreferences.setMockInitialValues({
        'auto_sync_interval_minutes': 0,
      });
      FlutterSecureStorage.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (call) async => 35);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'getNotificationChannels' => <Map<String, Object?>>[],
          'pendingNotificationRequests' ||
          'getActiveNotifications' =>
            <Map<String, Object?>>[],
          _ => true,
        };
      });

      final repo = LocalAssignmentRepository();
      await repo.activateAccount('legacy-user');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'deadline_notification_channel_v1', 'assignment_deadlines');
      final store = AssignmentStore(
        repository: repo,
        sessionStore: _LegacySession('legacy-user'),
        notificationService: LocalNotificationService(),
        widgetSnapshotService: _DummyWidget(),
        chaoxingClient: ChaoxingLocalClient(),
        manageBackgroundSchedule: false,
      );
      addTearDown(store.dispose);

      await store.restoreSession();
      expect(store.activeDeadlineChannelId,
          LocalNotificationService.assignmentV2Channel);
      expect(await repo.loadDeadlineChannelId('legacy-user'),
          LocalNotificationService.assignmentV2Channel);

      // Subsequent explicit downgrade stays respected because one-time marker is recorded.
      await store
          .saveDeadlineChannelId(LocalNotificationService.assignmentChannel);
      await store.restoreSession();
      expect(store.activeDeadlineChannelId,
          LocalNotificationService.assignmentChannel);
    });

    test(
        'migrateLegacySummaryChannelIfNeeded and retireLegacyUpdatesAndDeadlineChannelsIfNeeded keep strict order',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      SharedPreferences.setMockInitialValues({});
      final log = <String>[];
      final existing = <String>{
        'daily_summary',
        'assignment_updates',
        'assignment_deadlines',
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (call) async => 35);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getNotificationAppLaunchDetails':
            return {'notificationLaunchedApp': false};
          case 'getNotificationChannels':
            return [
              for (final id in existing)
                {
                  'id': id,
                  'name': id,
                  'description': '',
                  'groupId': null,
                  'showBadge': true,
                  'importance': 4,
                  'sound': null,
                  'playSound': false,
                  'enableLights': false,
                  'enableVibration': false,
                  'vibrationPattern': null,
                  'ledColor': 0,
                  'audioAttributesUsage': 5,
                }
            ];
          case 'createNotificationChannel':
            final id = (call.arguments as Map)['id'] as String;
            existing.add(id);
            log.add('create:$id');
            return true;
          case 'zonedSchedule':
            log.add('schedule:${(call.arguments as Map)['payload']}');
            return true;
          case 'deleteNotificationChannel':
            final id = call.arguments as String;
            existing.remove(id);
            log.add('delete:$id');
            return true;
          case 'pendingNotificationRequests':
          case 'getActiveNotifications':
            return <Map<String, Object?>>[];
          default:
            return true;
        }
      });

      final service = LocalNotificationService(
        clock: () => DateTime.utc(2030, 11, 20, 10, 0),
      );
      await service.migrateLegacySummaryChannelIfNeeded(
        const [],
        PersonalWorkspace(summaryEnabled: true),
        DateTime.utc(2030, 11, 20, 9, 0),
      );
      await service.retireLegacyUpdatesAndDeadlineChannelsIfNeeded(
        retireDeadlineV1: true,
      );

      expect(log.indexOf('create:daily_summary_v2'),
          lessThan(log.indexOf('schedule:d:summary')));
      expect(log.indexOf('schedule:d:summary'),
          lessThan(log.indexOf('delete:daily_summary')));
      expect(log.indexOf('create:assignment_updates_v2'),
          lessThan(log.indexOf('delete:assignment_updates')));
      expect(log.indexOf('create:assignment_deadlines_v2'),
          lessThan(log.indexOf('delete:assignment_deadlines')));
    });

    test(
        'null savedDeadlineChannel on non-native path creates v2, reschedules future assignments onto v2, then retires v1 and preserves v1 on reschedule failure',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      final now = DateTime.utc(2030, 11, 20, 4, 0); // 12:00 Beijing

      for (final failReschedule in [false, true]) {
        SharedPreferences.setMockInitialValues({
          'auto_sync_interval_minutes': 0,
        });
        FlutterSecureStorage.setMockInitialValues({});
        final events = <String>[];
        final existing = <String>{'assignment_deadlines'};

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(permissions, (call) async => 35);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getNotificationAppLaunchDetails':
              return {'notificationLaunchedApp': false};
            case 'getNotificationChannels':
              return [
                for (final id in existing)
                  {
                    'id': id,
                    'name': id,
                    'description': '',
                    'groupId': null,
                    'showBadge': true,
                    'importance': 4,
                    'sound': null,
                    'playSound': false,
                    'enableLights': false,
                    'enableVibration': false,
                    'vibrationPattern': null,
                    'ledColor': 0,
                    'audioAttributesUsage': 5,
                  }
              ];
            case 'createNotificationChannel':
              final id = (call.arguments as Map)['id'] as String;
              existing.add(id);
              events.add('create:$id');
              return true;
            case 'zonedSchedule':
              if (failReschedule) {
                throw PlatformException(code: 'schedule_error');
              }
              final args = Map<Object?, Object?>.from(call.arguments as Map);
              final details =
                  Map<Object?, Object?>.from(args['platformSpecifics'] as Map);
              events.add('schedule:${args['payload']}@${details['channelId']}');
              return null;
            case 'deleteNotificationChannel':
              final id = call.arguments as String;
              existing.remove(id);
              events.add('delete:$id');
              return true;
            case 'pendingNotificationRequests':
            case 'getActiveNotifications':
              return <Map<String, Object?>>[];
            case 'areNotificationsEnabled':
            case 'canScheduleExactNotifications':
              return true;
            default:
              return true;
          }
        });

        final repo = LocalAssignmentRepository();
        await repo.activateAccount('null-saved-user');
        await repo.mergeAndSave([
          Assignment(
            id: 'cx:work:1:1:w1',
            courseName: '高等数学',
            title: '高数作业1',
            deadlineAt: now.add(const Duration(days: 2)),
            deadlineTrusted: true,
            requirementsText: '',
            status: 'pending',
            lastSyncedAt: now,
          ),
        ]);
        // savedDeadlineChannel remains null in SharedPreferences.
        expect(await repo.loadDeadlineChannelId('null-saved-user'), isNull);

        final store = AssignmentStore(
          repository: repo,
          sessionStore: _LegacySession('null-saved-user'),
          notificationService: LocalNotificationService(clock: () => now),
          widgetSnapshotService: _DummyWidget(),
          chaoxingClient: ChaoxingLocalClient(),
          nativeReminderDeliveryEnabled: false,
          manageBackgroundSchedule: true,
          clock: () => now,
        );
        addTearDown(store.dispose);

        await store.restoreSession();

        if (!failReschedule) {
          expect(
            events,
            containsAllInOrder([
              'create:assignment_deadlines_v2',
              'schedule:a:studyassistant:///assignments/cx%3Awork%3A1%3A1%3Aw1@assignment_deadlines_v2',
              'delete:assignment_deadlines',
            ]),
          );
          expect(existing.contains('assignment_deadlines'), isFalse);
        } else {
          expect(events, contains('create:assignment_deadlines_v2'));
          expect(
            events.contains('delete:assignment_deadlines'),
            isFalse,
            reason: 'v1 channel must be preserved when rescheduling fails',
          );
          expect(existing.contains('assignment_deadlines'), isTrue);
        }
      }
    });

    test(
        'unauthenticated sendTestDeadlineNotification targets assignment_deadlines_v2',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
      FlutterSecureStorage.setMockInitialValues({});
      final shownChannels = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (call) async => 35);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'show') {
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          final details =
              Map<Object?, Object?>.from(args['platformSpecifics'] as Map);
          shownChannels.add(details['channelId'] as String);
          return true;
        }
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'getNotificationChannels' => [
              {
                'id': LocalNotificationService.assignmentV2Channel,
                'name': '作业截止提醒',
                'description': '',
                'groupId': null,
                'showBadge': true,
                'importance': 4,
                'sound': 'journal_chime',
                'playSound': true,
                'enableLights': false,
                'enableVibration': true,
                'vibrationPattern': null,
                'ledColor': 0,
                'audioAttributesUsage': 5,
              }
            ],
          'pendingNotificationRequests' || 'getActiveNotifications' => [],
          'areNotificationsEnabled' || 'canScheduleExactNotifications' => true,
          _ => true,
        };
      });

      final store = AssignmentStore(
        sessionStore: _NullSession(),
        notificationService: LocalNotificationService(
          clock: () => DateTime(2030, 11, 20, 10, 0),
        ),
        widgetSnapshotService: _DummyWidget(),
        chaoxingClient: ChaoxingLocalClient(),
        nativeReminderDeliveryEnabled: false,
        manageBackgroundSchedule: false,
        clock: () => DateTime(2030, 11, 20, 10, 0),
      );
      addTearDown(store.dispose);
      await store.restoreSession();

      final outcome = await store.sendTestDeadlineNotification();
      expect(outcome.status, TestDeadlineNotificationStatus.posted);
      expect(outcome.channelId, LocalNotificationService.assignmentV2Channel);
      expect(shownChannels, [LocalNotificationService.assignmentV2Channel]);
    });

    test(
        'showTestManualNotification cancels duplicate pending timer and cancelPrivateSchedules cancels pending timer',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
      SharedPreferences.setMockInitialValues({});
      var showCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (call) async => 35);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'show') {
          showCount++;
          return true;
        }
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false
            },
          'getNotificationChannels' => [
              {
                'id': LocalNotificationService.manualV2Channel,
                'name': '待办与考试提醒',
                'description': '',
                'groupId': null,
                'showBadge': true,
                'importance': 4,
                'sound': 'journal_chime',
                'playSound': true,
                'enableLights': false,
                'enableVibration': true,
                'vibrationPattern': null,
                'ledColor': 0,
                'audioAttributesUsage': 5,
              }
            ],
          'pendingNotificationRequests' || 'getActiveNotifications' => [],
          'areNotificationsEnabled' || 'canScheduleExactNotifications' => true,
          _ => true,
        };
      });

      final service = LocalNotificationService();
      expect(
        await service.showTestManualNotification(
          delay: const Duration(milliseconds: 80),
        ),
        isTrue,
      );
      expect(
        await service.showTestManualNotification(
          delay: const Duration(milliseconds: 80),
        ),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(showCount, 1, reason: 'rapid second call must cancel first timer');

      showCount = 0;
      expect(
        await service.showTestManualNotification(
          delay: const Duration(milliseconds: 80),
        ),
        isTrue,
      );
      await service.cancelPrivateSchedules();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(
        showCount,
        0,
        reason: 'cancelPrivateSchedules must cancel pending manual test timer',
      );
    });
  });

  group('M3 JournalPickerSheet fixed height & 320dp@2x keyboard safety', () {
    testWidgets(
        'fixed height sheet keeps zero outer height delta across filter tabs and zero overflow at 320dp@2x with and without keyboard',
        (tester) async {
      final options = [
        const JournalPickerOption<String>(value: '', label: '全部课程'),
        for (var i = 0; i < 12; i++)
          JournalPickerOption<String>(
            value: 'all-$i',
            label: '全部课程示例 $i',
            subtitle: '教师 $i',
          ),
        const JournalPickerOption<String>(
          value: 'cur-1',
          label: '本学期课程一',
          subtitle: '张老师',
        ),
      ];
      const filterOptions = [
        JournalPickerFilterOption(id: 'allTerms', label: '全部学期'),
        JournalPickerFilterOption(id: 'currentTerm', label: '本学期'),
      ];

      // 1) Multi-course tab -> single-course tab keeps exact same sheet height (delta == 0).
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showJournalPickerSheet<String>(
                    context,
                    title: '课程筛选',
                    selectedValue: '',
                    searchable: true,
                    filterOptions: filterOptions,
                    initialFilterId: 'allTerms',
                    filterPredicate: (opt, filterId) {
                      if (opt.value.isEmpty) return true;
                      if (filterId == 'currentTerm') {
                        return opt.value == 'cur-1';
                      }
                      return true;
                    },
                    filterNoticeBuilder: (filterId, filtered) =>
                        filterId == 'currentTerm'
                            ? '本学期暂未识别出课程，可切换到「本学年」或「全部学期」查看'
                            : null,
                    options: options,
                  );
                },
                child: const Text('打开筛选'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开筛选'));
      await tester.pumpAndSettle();

      Finder sheetSurface() => find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).borderRadius ==
                    const BorderRadius.vertical(top: Radius.circular(24)),
          );

      final beforeHeight = tester.getSize(sheetSurface()).height;
      await tester.tap(find.byKey(const ValueKey('picker-filter-currentTerm')));
      await tester.pumpAndSettle();
      final afterHeight = tester.getSize(sheetSurface()).height;
      expect((afterHeight - beforeHeight).abs(), 0.0);

      // Dismiss sheet before next viewport check.
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      // 2) 320dp @ 2x without and with keyboard (including tight screen).
      for (final scenario in const [
        (size: Size(320, 640), viewInsets: EdgeInsets.zero),
        (size: Size(320, 640), viewInsets: EdgeInsets.only(bottom: 260)),
        (size: Size(320, 568), viewInsets: EdgeInsets.only(bottom: 310)),
      ]) {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: scenario.size,
              padding: const EdgeInsets.only(top: 24, bottom: 20),
              viewInsets: scenario.viewInsets,
              textScaler: const TextScaler.linear(2.0),
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showJournalPickerSheet<String>(
                        context,
                        title: '课程筛选',
                        selectedValue: '',
                        searchable: true,
                        filterOptions: filterOptions,
                        initialFilterId: 'currentTerm',
                        filterPredicate: (opt, filterId) =>
                            opt.value.isEmpty || opt.value == 'cur-1',
                        filterNoticeBuilder: (_, __) =>
                            '本学期暂未识别出课程，可切换到「本学年」或「全部学期」查看',
                        options: options,
                      );
                    },
                    child: const Text('打开窄屏筛选'),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('打开窄屏筛选'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'size=${scenario.size} insets=${scenario.viewInsets}',
        );
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('M8 motion tokens & reduced-motion contract', () {
    test('JournalMotion curves and theme transitions/splash match M8 spec', () {
      expect(JournalMotion.easeOut, const Cubic(0.23, 1.0, 0.32, 1.0));
      expect(JournalMotion.easeDrawer, const Cubic(0.32, 0.72, 0.0, 1.0));

      for (final theme in [
        StudyAssistantTheme.light,
        StudyAssistantTheme.dark
      ]) {
        expect(theme.splashFactory, NoSplash.splashFactory);
        expect(theme.splashColor, Colors.transparent);
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.android],
          isA<PredictiveBackPageTransitionsBuilder>(),
        );
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.iOS],
          isA<CupertinoPageTransitionsBuilder>(),
        );
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.windows],
          isA<FadeForwardsPageTransitionsBuilder>(),
        );
      }
    });

    testWidgets('JournalMotion respects MediaQuery.disableAnimations',
        (tester) async {
      late Duration dEnabled;
      late Duration dReduced;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(builder: (context) {
            dEnabled = JournalMotion.duration(
              context,
              const Duration(milliseconds: 180),
            );
            return const SizedBox.shrink();
          }),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(builder: (context) {
            dReduced = JournalMotion.duration(
              context,
              const Duration(milliseconds: 180),
            );
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(dEnabled, const Duration(milliseconds: 180));
      expect(dReduced, Duration.zero);
    });

    testWidgets(
        'JournalSwipeTile AnimatedScale pops across threshold and stays static under reduced motion',
        (tester) async {
      for (final reduced in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: JournalSwipeTile(
              key: ValueKey('swipe-$reduced'),
              rightAction: JournalSwipeAction(
                label: '加入计划',
                icon: Icons.wb_sunny_outlined,
                color: Journal.slate,
                backgroundColor: Journal.sage,
                onTrigger: () {},
              ),
              child: const SizedBox(
                width: double.infinity,
                height: 56,
                child: Center(child: Text('滑动卡片')),
              ),
            ),
          ),
        ));

        final gesture =
            await tester.startGesture(tester.getCenter(find.text('滑动卡片')));
        // Cross drag slop first, then move within (1, 72) below threshold.
        await gesture.moveBy(const Offset(20, 0));
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        final preScale =
            tester.widget<AnimatedScale>(find.byType(AnimatedScale));
        if (reduced) {
          expect(preScale.scale, 1.0);
          expect(preScale.duration, Duration.zero);
        } else {
          expect(preScale.scale, lessThan(1.0));
          expect(preScale.duration, const Duration(milliseconds: 90));
        }

        // Cross threshold (> 72dp).
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump();
        final postScale =
            tester.widget<AnimatedScale>(find.byType(AnimatedScale));
        if (reduced) {
          expect(postScale.scale, 1.0);
          expect(postScale.duration, Duration.zero);
        } else {
          expect(postScale.scale, 1.20);
          expect(postScale.duration, const Duration(milliseconds: 160));
        }

        await gesture.up();
        await tester.pumpAndSettle();
      }
    });

    testWidgets(
        'ManualAgendaScreen completed section uses AnimatedSize + AnimatedRotation and zeroes durations when disableAnimations is true',
        (tester) async {
      final now = DateTime.utc(2026, 11, 20, 4);
      for (final reduced in [false, true]) {
        SharedPreferences.setMockInitialValues({
          'auto_sync_interval_minutes': 0,
        });
        FlutterSecureStorage.setMockInitialValues({});
        final repo = LocalAssignmentRepository();
        await repo.activateAccount('m8-agenda');
        final store = AssignmentStore(
          repository: repo,
          sessionStore: _LegacySession('m8-agenda'),
          notificationService: _NoopAgendaNotif(),
          widgetSnapshotService: _DummyWidget(),
          chaoxingClient: ChaoxingLocalClient(),
          manageBackgroundSchedule: false,
          clock: () => now,
        );
        addTearDown(store.dispose);
        await store.restoreSession();
        await store.saveNotebook(
          (n) => n.withEntries([
            ManualEntry(
              id: 'm-done',
              title: '已完成测试待办',
              kind: ManualEntry.kindTodo,
              done: true,
              at: now.add(const Duration(hours: 2)),
            ),
          ]),
          store.accountEpoch,
        );

        await tester.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: ManualAgendaScreen(
            key: ValueKey('agenda-$reduced'),
            store: store,
            clock: () => now,
          ),
        ));
        await tester.pumpAndSettle();

        final rotationBefore =
            tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
        expect(rotationBefore.turns, 0.0);
        expect(
          rotationBefore.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 200),
        );
        if (reduced) {
          expect(find.byType(AnimatedSize), findsNothing);
        } else {
          final sizeBefore =
              tester.widget<AnimatedSize>(find.byType(AnimatedSize));
          expect(sizeBefore.curve, JournalMotion.easeDrawer);
          expect(sizeBefore.duration, const Duration(milliseconds: 220));
        }

        await tester.tap(find.byKey(const ValueKey('agenda-completed-toggle')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final rotationAfter =
            tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
        expect(rotationAfter.turns, 0.5);
        expect(find.text('已完成测试待办'), findsOneWidget);
      }
    });
  });
}

class _NullSession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => null;
  @override
  Future<String?> readChaoxingPassword() async => null;
}

class _NoopAgendaNotif extends LocalNotificationService {
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
  @override
  Future<void> migrateLegacyManualChannelIfNeeded(
      List<ManualEntry> entries) async {}
  @override
  Future<void> migrateLegacySummaryChannelIfNeeded(List<Assignment> assignments,
      PersonalWorkspace personal, DateTime? lastSync) async {}
  @override
  Future<void> retireLegacyUpdatesAndDeadlineChannelsIfNeeded({
    required bool retireDeadlineV1,
    Future<bool> Function()? beforeRetireDeadlineV1,
  }) async {}
}

class _LegacySession extends SecureSessionStore {
  _LegacySession(this.account);
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

class _DummyWidget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}
