import 'dart:io';
import 'package:study_assistant_mobile/src/features/help_feedback_screen.dart';
import 'package:study_assistant_mobile/src/features/open_source_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/models/course.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _EvidenceSession extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => null;
  @override
  Future<String?> readChaoxingDisplayName() async => '样例同学';
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _EvidenceNotifications extends LocalNotificationService {
  @override
  Future<void> rescheduleAssignments(List<Assignment> items,
      {List<int>? offsetsMinutes}) async {}
}

class _EvidenceWidget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> items) async {}
}

void main() {
  testWidgets('sample UI evidence at narrow and large font sizes', (t) async {
    await initializeDateFormatting('zh_CN');
    for (final name in ['JournalBody', 'JournalTitle']) {
      final f = FontLoader(name)
        ..addFont(rootBundle.load('assets/type/$name.ttf'));
      await f.load();
    }
    final s = AssignmentStore(
        sessionStore: _EvidenceSession(),
        notificationService: _EvidenceNotifications(),
        widgetSnapshotService: _EvidenceWidget());
    addTearDown(s.dispose);
    SharedPreferences.setMockInitialValues({});
    await s.repository.saveCourses([
      const CourseRef(courseId: '1', clazzId: '2', name: '样例 · 高等数学'),
      const CourseRef(courseId: '3', clazzId: '4', name: '样例 · 大学物理与天文学'),
      const CourseRef(courseId: '5', clazzId: '6', name: '样例 · 工程制图'),
    ]);
    await s.restoreSession();
    final now = DateTime.now();
    s.replaceAssignmentsForTest([
      for (var i = 0; i < 3; i++)
        Assignment(
            id: 'cx:work:1:2:$i',
            courseName: '样例 · 概率论与数理统计',
            title: '样例数据 · 第${i + 1}次课后练习与实验报告',
            deadlineAt: now.add(Duration(hours: 3 + i)),
            requirementsText: '',
            status: i == 2 ? 'unknown' : 'pending',
            lastSyncedAt: now)
    ]);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final boundary = GlobalKey();
    Future<void> capture(
        String name, Widget child, double width, double scale) async {
      t.view.physicalSize = Size(width, 760);
      await t.pumpWidget(MaterialApp(
          theme: StudyAssistantTheme.light,
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 760), textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                  body: RepaintBoundary(
                      key: boundary,
                      child: Material(
                          color: const Color(0xFFF7F5EC),
                          child: Column(children: [
                            const Text('样例数据 · 仅用于布局验收'),
                            Expanded(child: child)
                          ])))))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(
            find.byKey(boundary),
            matchesGoldenFile(Uri.file(
                '${Directory(Directory.current.resolveSymbolicLinksSync()).parent.parent.path}/docs/evidence/2026-11-04/$name.png')));
      }
    }

    for (final scale in [1.0, 2.0]) {
      for (final w in [320.0, 360.0, 432.0]) {
        await capture('nov-home-${w.toInt()}-$scale',
            AssignmentListScreen(store: s), w, scale);
        await capture('nov-calendar-${w.toInt()}-$scale',
            CalendarScreen(store: s), w, scale);
        await capture('nov-profile-${w.toInt()}-$scale',
            ProfileScreen(store: s), w, scale);
        await capture('nov-help-${w.toInt()}-$scale',
            const HelpFeedbackScreen(), w, scale);
        await capture('nov-license-${w.toInt()}-$scale',
            const OpenSourceScreen(), w, scale);
      }
    }
  });
}
