import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/help_feedback_screen.dart';
import 'package:study_assistant_mobile/src/features/local_records_screen.dart';
import 'package:study_assistant_mobile/src/features/course_list_screen.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Session extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => null;
  @override
  Future<String?> readChaoxingDisplayName() async => null;
  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

class _Notification extends LocalNotificationService {
  @override
  Future<void> rescheduleAssignments(List<Assignment> a,
      {List<int>? offsetsMinutes}) async {}
}

class _Widget extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> a) async {}
}

void main() {
  testWidgets(
      'help contains offline guidance and a credential-free feedback template',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: HelpFeedbackScreen()));
    expect(find.text('帮助中心'), findsOneWidget);
    expect(HelpFeedbackScreen.feedbackTemplate, contains('复现步骤'));
    expect(HelpFeedbackScreen.feedbackTemplate, contains('问题：'));
    expect(find.text('反馈成功'), findsNothing);
  });
  testWidgets('records keep other sources separate and restore hidden work',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = AssignmentStore(
        sessionStore: _Session(),
        notificationService: _Notification(),
        widgetSnapshotService: _Widget());
    addTearDown(s.dispose);
    Assignment a(String id, String title) => Assignment(
        id: id,
        courseName: '课',
        title: title,
        deadlineAt: null,
        requirementsText: '',
        status: 'pending',
        lastSyncedAt: DateTime.now());
    await s.repository.mergeAndSave(
        [a('cx:work:1:2:3', '正式样例'), a('cx:activity:1:2:4', '活动样例')]);
    await s.refreshAssignments();
    await t.pumpWidget(MaterialApp(home: LocalRecordsScreen(store: s)));
    expect(find.text('正式样例'), findsOneWidget);
    expect(find.text('活动样例'), findsNothing);
    await t.tap(find.text('历史与其他来源'));
    await t.pumpAndSettle();
    expect(find.text('活动样例'), findsOneWidget);
    expect(find.text('正式样例'), findsNothing);
    await s.updateCompletion('cx:work:1:2:3', true);
    await t.tap(find.text('已隐藏'));
    await t.pumpAndSettle();
    await t.tap(find.text('恢复'));
    await t.pumpAndSettle();
    expect(s.hiddenAssignments, isEmpty);
    expect((await s.repository.loadJournal()).length, 2);
  });
  testWidgets('same-name classes remain separate and follow choice persists',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'course_refs': jsonEncode([
        for (final c in ['2', '3'])
          {'courseId': '1', 'clazzId': c, 'name': '概率论与数理统计'}
      ])
    });
    final s = AssignmentStore(
        sessionStore: _Session(),
        notificationService: _Notification(),
        widgetSnapshotService: _Widget());
    addTearDown(s.dispose);
    await s.restoreSession();
    await t.pumpWidget(MaterialApp(home: CourseListScreen(store: s)));
    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(find.text('班级 2'), findsOneWidget);
    expect(find.text('班级 3'), findsOneWidget);
    await t.tap(find.byType(SwitchListTile).first);
    await t.pumpAndSettle();
    expect(s.follows('1:2'), isFalse);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('unfollowed_courses'),
        ['1:2']);
  });
}
