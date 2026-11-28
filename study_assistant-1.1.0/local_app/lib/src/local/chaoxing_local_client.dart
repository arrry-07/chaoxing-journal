import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/assignment.dart';
import '../models/assignment_sync_progress.dart';
import '../models/course_chapter_progress.dart';
import '../models/course_notice.dart';
import '../models/sync_report.dart';
import '../models/sync_scope.dart';
import 'chaoxing_ai_practice_parser.dart';
import 'chaoxing_api_parser.dart';
import 'chaoxing_assignment_parser.dart';
import 'chaoxing_chapter_parser.dart';
import 'chaoxing_classroom_parser.dart';
import 'chaoxing_exam_parser.dart';
import 'chaoxing_param_helper.dart';

import 'chaoxing_request_policy.dart';

part 'chaoxing_coursework_client.dart';
part 'chaoxing_exam_client.dart';
part 'chaoxing_session_client.dart';
part 'chaoxing_transport_client.dart';

class VerificationTargetUnavailable implements Exception {
  const VerificationTargetUnavailable();
}

class ChaoxingAuthenticationException implements Exception {
  const ChaoxingAuthenticationException([this.httpStatus]);

  final int? httpStatus;

  @override
  String toString() => '学习通登录已失效，请重新登录';
}

class ChaoxingLoginResult {
  const ChaoxingLoginResult({
    required this.success,
    this.message,
    this.displayName,
    this.avatarUrl,
  });

  final bool success;
  final String? message;
  final String? displayName;
  final String? avatarUrl;
}

class ChaoxingLocalClient {
  // The signed work list is the desktop course surface, as in the reference CLI.
  static const courseUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  ChaoxingLocalClient(
      {Dio? dio,
      Future<void> Function(Duration)? wait,
      this.enableClassroomTasks = true,
      this.enableExams = true})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                followRedirects: false,
                validateStatus: (status) => status != null && status < 500,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36 SuperStarStudyHelper/0.1',
                  'Accept':
                      'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'Referer': 'https://i.chaoxing.com/',
                },
              ),
            ),
        _wait = wait ?? _defaultWait;

  final Dio _dio;
  final bool enableClassroomTasks;
  final bool enableExams;
  List<SyncSourceResult> sourceResults = const [];
  List<CourseNotice> _lastFetchedNotices = const [];
  List<CourseNotice> get lastFetchedNotices =>
      List.unmodifiable(_lastFetchedNotices);
  bool _collectCourseNoticesInNextSync = false;
  bool _enableTaskEngineProbeInNextSync = false;
  final Future<void> Function(Duration) _wait;
  CancelToken? _activeRequestToken;
  bool _stopRequested = false;
  static Future<void> _defaultWait(Duration delay) =>
      Future<void>.delayed(delay);

  final _requestStats = <String, _RequestStats>{};
  final _phaseElapsedMs = <String, int>{};
  Map<String, Response<dynamic>>? _syncCourseEntries;
  Set<String>? _syncExamEntryCourses;
  final Set<String> _sessionVueExamCourses = <String>{};
  bool _sessionHasPcExamCredential = false;
  final _openCircuits = <String, SyncIssue>{};
  final _consecutiveTransientFailures = <String, int>{};
  int _syncRetryCount = 0;
  int? _fullSyncElapsedMs;
  bool Function()? shouldStop;
  void Function(AssignmentSyncProgress)? onProgress;

  Map<String, ({int count, int elapsedMs, int httpFailures})>
      get requestTimings => Map.unmodifiable({
            for (final entry in _requestStats.entries)
              entry.key: (
                count: entry.value.count,
                elapsedMs: entry.value.totalHttpMs + entry.value.totalParseMs,
                httpFailures: entry.value.failures,
              ),
          });

  SyncDiagnostics get diagnostics => SyncDiagnostics(
        fullSyncElapsedMs: _fullSyncElapsedMs,
        phaseElapsedMs: Map.unmodifiable(_phaseElapsedMs),
        requests: Map.unmodifiable({
          for (final entry in _requestStats.entries)
            entry.key: SyncRequestDiagnostics(
              count: entry.value.count,
              failures: entry.value.failures,
              parseFailures: entry.value.parseFailures,
              httpSamples: entry.value.httpSamples,
              parseSamples: entry.value.parseSamples,
            ),
        }),
      );

  final List<_SessionCookie> _cookies = [];
  Uri? _verificationTarget;
  Uri? _courseVerificationProbe;
  bool _v3FormalApiConfirmed = false;
  SyncIssueKind? _deadlineReadsBlockedBy;

  int _skippedMalformedVerifyCookies = 0;
  int get skippedMalformedVerifyCookies => _skippedMalformedVerifyCookies;

  int _sessionGeneration = 0;
  bool hasCourseResponse = false;

  bool get needsSessionInitialization =>
      _cookies.every((cookie) => cookie.expired);

  String? lastSyncWarning;
  bool deferProfile = false;
  dynamic _loginPayload;
  bool get canHydrateProfile => _loginPayload != null;
  List<SyncIssue> issues = [];
  int succeededCourses = 0, failedCourses = 0;
  int detailUnconfirmedCount = 0;
  final Set<String> _detailUnconfirmedCourseKeys = <String>{};
  List<ChaoxingCourseRef> courses = [];
  Set<String> trackedActivityIds = {};
  Map<String, Assignment> previousAssignments = {};
  SyncCourseSelector? nextSyncCourseSelector;
  AssignmentSyncScope lastSyncScope = AssignmentSyncScope.all;
  int plannedCourses = 0;
  int skippedCourses = 0;
  Set<String> lastPlannedCourseKeys = const {};
  Set<String> lastFailedCourseKeys = const {};
  final Set<String> _lastExamFailedCourseKeys = <String>{};

  void cancelActiveRequests({bool reportCancelled = true}) =>
      _cancelActiveRequests(reportCancelled: reportCancelled);

  Future<bool> verifyInBrowser({bool courseInspection = false}) =>
      _verifyInBrowser(courseInspection: courseInspection);

  Future<ChaoxingLoginResult> loadProfile() => _loadProfile();

  void clearSession() => _clearSession();

  Future<ChaoxingLoginResult> login({
    required String account,
    required String password,
  }) =>
      _login(account: account, password: password);

  /// Refresh just the selected course; fetching the lightweight course index
  /// supplies its current cpi/signatures without reading every homework list.
  Future<List<Assignment>> fetchAssignmentsForCourse(
          {required String courseId, required String clazzId}) =>
      _fetchAssignmentsForCourse(courseId: courseId, clazzId: clazzId);

  /// Fetches ONLY the single visited non-exam target within its course without
  /// scanning other assignments' detail pages, classroom activities, or exams.
  Future<Assignment?> fetchReturnedWork(Assignment target) =>
      _fetchReturnedWork(target);

  Future<List<Assignment>> fetchAssignmentsWithOptions({
    bool collectCourseNotices = false,
    bool enableTaskEngineProbe = false,
  }) =>
      _fetchAssignmentsWithOptions(
          collectCourseNotices: collectCourseNotices,
          enableTaskEngineProbe: enableTaskEngineProbe);

  Future<List<Assignment>> fetchAssignments() => _fetchAssignments();

  Future<CourseChapterSnapshot> fetchCourseChapters(ChaoxingCourseRef course) =>
      _fetchCourseChapters(course);

  /// Share only a successful terminal credential page within one refresh. The
  /// callers still validate redirects independently; never cache a redirect,
  /// failed/missing credential response, or a page from a replaced session.
  static String _courseEntryCacheKey(Uri uri) {
    final keys = uri.queryParametersAll.keys.toList()..sort();
    return uri.replace(queryParameters: {
      for (final key in keys) key: uri.queryParametersAll[key]!,
    }).toString();
  }
}
