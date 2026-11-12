import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/local/chaoxing_local_client.dart';
import 'package:study_assistant_mobile/src/local/local_assignment_repository.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/models/assignment_sync_progress.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

// 2026-11-07T12:00:00Z, inside the accepted timestamp range.
const _trustedEnd = 1794052800000;

Map<String, dynamic> _course(String id, {String clazzId = '2'}) =>
    {'courseId': id, 'clazzId': clazzId, 'courseName': '课$id'};

Map<String, dynamic> _row(
  int workId, {
  String courseId = '1',
  String clazzId = '2',
  int? endTime,
}) =>
    {
      'title': '题$workId',
      'stuStatus': 0,
      'endTime': endTime ?? _trustedEnd,
      'taskUrl':
          'https://mooc1.chaoxing.com/work/task?workId=$workId&courseId=$courseId&classId=$clazzId',
    };

Response<dynamic> _ok(RequestOptions request, dynamic data) =>
    Response<dynamic>(requestOptions: request, statusCode: 200, data: data);

/// V3 course discovery plus a per-request hook for formal homework pages.
Dio _v3Dio(
  List<Map<String, dynamic>> courses,
  Future<void> Function(
          RequestOptions request, RequestInterceptorHandler handler)
      onWorkPage,
) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
    final path = request.uri.path;
    if (path == '/mycourse/backclazzdata') {
      handler.resolve(_ok(request, {'courses': courses}));
    } else if (path == '/visit/stucoursemiddle') {
      handler.resolve(
          _ok(request, '<script src="/mooc2-ans-vue/js/fanyav3.js"></script>'));
    } else if (path == '/mooc2-ans/coursemanagev3/stu-base-info') {
      handler.resolve(_ok(request, {'status': true, 'navigationList': []}));
    } else if (path == '/mooc-ans/work/api/task') {
      await onWorkPage(request, handler);
    } else {
      throw StateError('unexpected endpoint $path');
    }
  }));
  return dio;
}

Assignment _oldWork(int workId, {String courseId = '1'}) => Assignment(
      id: 'cx:work:$courseId:2:$workId',
      courseName: '课$courseId',
      title: '旧题$workId',
      deadlineAt: DateTime.utc(2024, 1, 2),
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: DateTime.utc(2024),
    );

void main() {
  test('v3FirstPageVisibleWhileSecondPageWaits', () async {
    final secondPageStarted = Completer<void>();
    final secondPageGate = Completer<void>();
    final events = <AssignmentSyncProgress>[];
    final dio = _v3Dio([_course('1')], (request, handler) async {
      final page = request.uri.queryParameters['pageNum'];
      if (page == '1') {
        handler.resolve(_ok(request, {
          'status': true,
          'total': 2,
          'data': [_row(1)],
        }));
        return;
      }
      if (!secondPageStarted.isCompleted) secondPageStarted.complete();
      await secondPageGate.future;
      handler.resolve(_ok(request, {
        'status': true,
        'total': 2,
        'data': [_row(2)],
      }));
    });
    final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
    client.onProgress = events.add;
    var finished = false;
    final fetching = () async {
      try {
        return await client.fetchAssignments();
      } finally {
        finished = true;
      }
    }();

    await secondPageStarted.future;

    expect(finished, isFalse, reason: '第二页未返回前整轮同步不能算完成');
    final preview = events.last;
    expect(preview.stage, AssignmentSyncStage.workLists);
    expect(preview.assignments.map((item) => item.id), ['cx:work:1:2:1']);
    expect(preview.assignments.single.deadlineTrusted, isTrue);
    expect(preview.pendingDetailIds, isEmpty);

    secondPageGate.complete();
    final rows = await fetching;
    expect(rows.map((item) => item.id),
        unorderedEquals(['cx:work:1:2:1', 'cx:work:1:2:2']));
  });

  test('invalidLaterPageRetractsOnlyThatCoursePreview', () async {
    Future<void> expectOnlyCourseOneSurvives(String failure) async {
      final events = <AssignmentSyncProgress>[];
      final dio = _v3Dio(
        [_course('1'), _course('2')],
        (request, handler) async {
          final courseId = request.uri.queryParameters['courseId']!;
          final page = request.uri.queryParameters['pageNum'];
          if (courseId == '2' && page == '2') {
            if (failure == 'readFailure') {
              handler.reject(DioException(
                  requestOptions: request,
                  type: DioExceptionType.connectionTimeout));
              return;
            }
            final data = switch (failure) {
              'duplicate' => {
                  'status': true,
                  'total': 2,
                  'data': [_row(2, courseId: '2')],
                },
              'identityMismatch' => {
                  'status': true,
                  'total': 2,
                  'data': [_row(102, courseId: '99')],
                },
              'totalMismatch' => {
                  'status': true,
                  'total': 1,
                  'data': [_row(2, courseId: '2')],
                },
              _ => throw StateError('unknown failure $failure'),
            };
            handler.resolve(_ok(request, data));
            return;
          }
          final total = courseId == '2' ? 2 : 1;
          handler.resolve(_ok(request, {
            'status': true,
            'total': total,
            'data': [_row(int.parse(courseId), courseId: courseId)],
          }));
        },
      );
      final client = ChaoxingLocalClient(dio: dio, wait: (_) async {});
      client.onProgress = events.add;

      final rows = await client.fetchAssignments();

      expect(rows.map((item) => item.id), ['cx:work:1:2:1']);
      expect(client.succeededCourses, 1);
      expect(client.failedCourses, 1);
      expect(client.lastSyncWarning, contains('1 门待重试'));
      expect(client.issues.any((issue) => issue.courseKey == '2:2'), isTrue,
          reason: '$failure 仍应按部分失败处理');
      expect(
          events.any((event) =>
              event.assignments.any((item) => item.id == 'cx:work:2:2:2')),
          isTrue,
          reason: '$failure 前第一页应已作为预览发布');
      expect(events.last.assignments.map((item) => item.id),
          unorderedEquals(['cx:work:1:2:1']),
          reason: '$failure 只撤回课程 2 的临时行');

      final merged = LocalAssignmentRepository.mergeAssignments(
          [_oldWork(77, courseId: '2')], rows);
      expect(merged.any((item) => item.id == 'cx:work:2:2:77'), isTrue,
          reason: '$failure 后课程 2 应回退到旧正式缓存');
      expect(merged.any((item) => item.id == 'cx:work:2:2:2'), isFalse);
    }

    for (final failure in [
      'duplicate',
      'identityMismatch',
      'totalMismatch',
      'readFailure',
    ]) {
      await expectOnlyCourseOneSurvives(failure);
    }
  });

  test('previewNeverSchedulesOrPersists', () async {
    SharedPreferences.setMockInitialValues({});
    final secondPageStarted = Completer<void>();
    final secondPageGate = Completer<void>();
    final dio = _v3Dio([_course('1')], (request, handler) async {
      final page = request.uri.queryParameters['pageNum'];
      if (page == '1') {
        handler.resolve(_ok(request, {
          'status': true,
          'total': 2,
          'data': [_row(1)],
        }));
        return;
      }
      if (!secondPageStarted.isCompleted) secondPageStarted.complete();
      await secondPageGate.future;
      handler.reject(DioException(
          requestOptions: request, type: DioExceptionType.connectionTimeout));
    });
    final repository = LocalAssignmentRepository();
    final old = _oldWork(99);
    await repository.mergeAndSave([old]);
    final notifications = _RecordingNotificationService();
    final store = AssignmentStore(
      sessionStore: _MemorySessionStore(account: 'student'),
      notificationService: notifications,
      widgetSnapshotService: _NoopWidgetSnapshotService(),
      repository: repository,
      chaoxingClient: ChaoxingLocalClient(dio: dio, wait: (_) async {}),
    );
    addTearDown(store.dispose);
    await store.restoreSession();
    notifications.scheduledIds.clear();

    final syncing = store.syncAssignments();
    await secondPageStarted.future;
    await pumpEventQueue();

    expect(store.homeDisplayAssignments.map((item) => item.id),
        contains('cx:work:1:2:1'),
        reason: '第二页等待时第一页应已显示');
    expect(store.homeSyncProgress, isNotNull);
    expect((await repository.loadJournal()).map((item) => item.id),
        ['cx:work:1:2:99'],
        reason: '预览行不能写入正式仓库');
    expect(notifications.scheduledIds, isNot(contains('cx:work:1:2:1')),
        reason: '预览行不能参与提醒调度');

    secondPageGate.complete();
    await syncing;

    expect(store.error, isNotNull);
    expect(store.homeSyncProgress, isNull);
    expect((await repository.loadJournal()).map((item) => item.id),
        ['cx:work:1:2:99'],
        reason: '整轮失败后仍保留旧正式缓存');
    expect(store.homeDisplayAssignments.map((item) => item.id),
        ['cx:work:1:2:99']);
    expect(notifications.scheduledIds, isNot(contains('cx:work:1:2:1')));
  });
}

class _MemorySessionStore extends SecureSessionStore {
  _MemorySessionStore({this.account});

  final String? account;

  @override
  Future<void> clear() async {}

  @override
  Future<String?> readChaoxingAccount() async => account;

  @override
  Future<String?> readChaoxingDisplayName() async => null;

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;

  @override
  Future<String?> readChaoxingPassword() async => null;
}

class _RecordingNotificationService extends LocalNotificationService {
  final scheduledIds = <String>{};

  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleManual(List<ManualEntry> entries) async {}

  @override
  Future<void> rescheduleSummary(List<Assignment> assignments,
      PersonalWorkspace personal, DateTime? lastSync) async {
    scheduledIds.addAll(assignments.map((item) => item.id));
  }

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {
    scheduledIds.addAll(assignments.map((item) => item.id));
  }
}

class _NoopWidgetSnapshotService extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}
