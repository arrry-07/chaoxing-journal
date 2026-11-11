// Recording only. Not a public release entry point.
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' as app;
import 'src/local/chaoxing_local_client.dart';
import 'src/local/chaoxing_api_parser.dart';
import 'src/models/assignment.dart';
import 'src/models/personal_workspace.dart';
import 'src/services/assignment_store.dart';
import 'src/services/app_update_controller.dart';
import 'src/services/secure_session_store.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/widget_snapshot_service.dart';

class NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Recording build: network disabled');
}

class DemoUpdates extends AppUpdateController {
  @override
  Future<bool> checkOnStartup() async => false;
  @override
  Future<void> check({bool startup = false}) async {
    throw StateError('Recording: updates disabled');
  }
}

class DemoClient extends ChaoxingLocalClient {
  DemoClient()
    : super(
        dio: Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) => h.reject(
                DioException(requestOptions: o, message: 'No network'),
              ),
            ),
          ),
      );
  @override
  bool get needsSessionInitialization => false;
  @override
  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) async => const ChaoxingLoginResult(success: true, displayName: '小禾');
  @override
  Future<ChaoxingLoginResult> loadProfile() async =>
      const ChaoxingLoginResult(success: true, displayName: '小禾');
  static const names = ['高等数学', '大学英语', '程序设计', '大学物理'];
  static const titles = [
    '导数与微分练习',
    '英语阅读与表达',
    '循环结构实践',
    '力学实验报告',
    '积分应用练习',
    '单元词汇复习',
    '数组与函数',
    '动量守恒练习',
    '期中复习清单',
    '听力练习',
    '程序设计小测',
    '实验预习',
  ];
  final anchor = DateTime.now();
  List<Assignment> sample() => List.generate(12, (i) {
    final c = i % 4;
    final day = DateTime(
      anchor.year,
      anchor.month,
      anchor.day + 1 + i ~/ 4,
      22,
    );
    return Assignment(
      id: 'cx:work:${100 + c}:200:${300 + i}',
      courseName: names[c],
      title: titles[i],
      deadlineAt: i == 8
          ? null
          : (i == 7 ? day.subtract(const Duration(days: 7)) : day),
      requirementsText: '完成本节练习，整理思路并核对结果。演示内容均为合成样例。',
      status: i >= 9 ? 'submitted' : 'pending',
      lastSyncedAt: DateTime.now(),
      deadlineTrusted: i != 8,
      deadlineReadFailed: i == 8,
      completedAt: i >= 9 ? anchor : null,
    );
  });
  @override
  Future<List<Assignment>> fetchAssignments() async {
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    courses = List.generate(
      4,
      (i) => ChaoxingCourseRef(
        courseId: (100 + i).toString(),
        clazzId: '200',
        courseName: names[i],
      ),
    );
    hasCourseResponse = true;
    succeededCourses = 4;
    failedCourses = 0;
    issues = [];
    lastSyncWarning = null;
    return sample();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetwork();
  await initializeDateFormatting('zh_CN');
  final session = SecureSessionStore();
  await session.saveChaoxingAccount(
    account: 'demo-xiaohe',
    password: 'synthetic-only',
    displayName: '小禾',
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('auto_sync_interval_minutes', 0);
  final notifications = LocalNotificationService();
  await notifications.initializeSafely();
  final store = AssignmentStore(
    sessionStore: session,
    notificationService: notifications,
    widgetSnapshotService: WidgetSnapshotService(),
    chaoxingClient: DemoClient(),
  );
  await store.restoreSession();
  await store.syncAssignments();
  if (store.personal.work.isEmpty) {
    await store.savePersonal(
      (p) => PersonalWorkspace(
        work: {
          'cx:work:100:200:300': const PersonalWork(
            note: '先整理课堂笔记，再完成练习。',
            steps: [
              PersonalStep('复习课堂例题', done: true),
              PersonalStep('完成课后练习'),
              PersonalStep('核对答案并整理错题'),
            ],
          ),
        },
      ),
      store.accountEpoch,
    );
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    app.StudyAssistantApp(
      assignmentStore: store,
      notificationService: notifications,
      updateController: DemoUpdates(),
    ),
  );
}
