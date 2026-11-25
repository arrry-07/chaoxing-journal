import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/app/journal_motion.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
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
  });

  group('M8 motion tokens & reduced-motion contract', () {
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
  });
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
