import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/help_feedback_screen.dart';
import 'package:study_assistant_mobile/src/features/open_source_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/update_dialog.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/sync_report.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/app_update_service.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  AssignmentStore store() => AssignmentStore(
      sessionStore: SecureSessionStore(),
      notificationService: LocalNotificationService(),
      widgetSnapshotService: WidgetSnapshotService());
  testWidgets('failed first sync never claims cached or empty success',
      (t) async {
    final s = store()..syncReport = const SyncReport(phase: SyncPhase.failed);
    addTearDown(s.dispose);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    expect(find.text('本次尚未取得作业，请点击右上角刷新继续。'), findsOneWidget);
    expect(find.text('显示上次记录'), findsNothing);
    expect(find.text('未来30天暂无确认待交作业。'), findsNothing);
    s.replaceAssignmentsForTest([
      Assignment(
          id: 'cx:activity:1:2:3',
          courseName: '历史课',
          title: '历史题',
          deadlineAt: null,
          requirementsText: '',
          status: 'unknown',
          lastSyncedAt: DateTime.now())
    ]);
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: AssignmentListScreen(store: s))));
    expect(find.text('查看全部本地记录'), findsOneWidget);
  });
  testWidgets('help starts with questions and opens standalone detail',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: HelpFeedbackScreen()));
    expect(find.byType(TextField), findsNothing);
    expect(find.text(HelpFeedbackScreen.feedbackTemplate), findsNothing);
    await t.tap(find.text('同步失败怎么办？'));
    await t.pumpAndSettle();
    expect(find.textContaining('无需安装官方 App'), findsOneWidget);
  });
  testWidgets('license introduction precedes full original declarations',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: OpenSourceScreen()));
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.textContaining('版权与许可声明'), findsOneWidget);
    expect(find.text('完整依赖与原始许可'), findsOneWidget);
  });
  testWidgets('latest version has an explicit result and a release link',
      (t) async {
    await t.pumpWidget(
        MaterialApp(home: UpdateDialog(service: _LatestUpdateService())));
    await t.pumpAndSettle();
    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(find.text('查看 GitHub 发行版'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('重新检查'), findsNothing);
    expect(find.text('下载并安装'), findsNothing);
  });
}

class _LatestUpdateService extends AppUpdateService {
  @override
  Future<UpdateCheckResult> checkConfigured(
          {required int currentVersionCode, CancelToken? cancelToken}) async =>
      const UpdateCheckResult(UpdateCheckStatus.upToDate);
}
