import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_version.dart';
import 'app_update_service.dart';
import 'external_link_service.dart';

enum UpdatePhase {
  idle,
  checking,
  checked,
  available,
  downloading,
  verifying,
  ready,
  installing,
  failed,
  cancelled
}

/// The application owns this task; a dialog only observes it.
class AppUpdateController extends ChangeNotifier {
  AppUpdateController({AppUpdateService? service, ExternalLinkService? links})
      : service = service ?? AppUpdateService(),
        links = links ?? ExternalLinkService();

  final AppUpdateService service;
  final ExternalLinkService links;
  UpdatePhase phase = UpdatePhase.idle;
  UpdateCheckResult? result;
  String message = '正在检查更新…';
  String? downloadedPath;
  int receivedBytes = 0;
  int totalBytes = -1;
  double bytesPerSecond = 0;
  bool dialogIsOpen = false;
  bool hasShownDialog = false;
  String get transferSummary {
    final received = (receivedBytes / 1048576).toStringAsFixed(1);
    final total =
        totalBytes > 0 ? ' / ${(totalBytes / 1048576).toStringAsFixed(1)}' : '';
    final speed = bytesPerSecond > 0
        ? ' · ${(bytesPerSecond / 1048576).toStringAsFixed(2)} MB/s'
        : '';
    return '$received$total MB$speed';
  }

  CancelToken? _cancel;
  bool _disposed = false;
  bool _startupChecked = false;
  Future<void>? _startupRequest;
  bool _manualDuringStartup = false;
  static const _ignoredVersionKey = 'update.ignoredVersion';
  String get _candidateKey =>
      '${update?.versionName}+${update?.versionCode ?? 0}';

  /// Only cold starts check automatically. Manual checks deliberately bypass
  /// the ignored release, so the user can change their mind from Settings.
  Future<bool> checkOnStartup() async {
    if (_startupChecked || _disposed) return false;
    _startupChecked = true;
    // A manual check/download already owns the task; startup must not replace it.
    if (phase != UpdatePhase.idle) return false;
    _manualDuringStartup = false;
    final request = check(startup: true);
    _startupRequest = request;
    try {
      await request;
    } finally {
      _startupRequest = null;
    }
    if (_manualDuringStartup) return false;
    if (_disposed || update == null || phase != UpdatePhase.available) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return !_disposed &&
          !hasShownDialog &&
          prefs.getString(_ignoredVersionKey) != _candidateKey;
    } catch (_) {
      // A preference read failure must not prevent discovery of a new release.
      return !_disposed && !hasShownDialog;
    }
  }

  Future<bool> ignoreCurrentVersion() async {
    if (_disposed || update == null || busy) return false;
    final key = _candidateKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await prefs.setString(_ignoredVersionKey, key)) return true;
    } catch (_) {
      // Keep the prompt open so the user knows the preference was not saved.
    }
    if (!_disposed) {
      message = '未能保存忽略设置，请重试或直接关闭';
      _emit();
    }
    return false;
  }

  AppUpdateInfo? get update => result?.update;
  bool get busy => {
        UpdatePhase.checking,
        UpdatePhase.downloading,
        UpdatePhase.verifying,
        UpdatePhase.installing
      }.contains(phase);
  bool get downloading =>
      phase == UpdatePhase.downloading || phase == UpdatePhase.verifying;
  double? get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0, 1) : null;
  bool get showBanner =>
      downloading ||
      phase == UpdatePhase.ready ||
      (phase == UpdatePhase.failed && update != null);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check({bool startup = false}) async {
    // A manual request must not inherit latest-only results from an in-flight
    // startup request. Wait for it, then perform the manual list check.
    final pendingStartup = _startupRequest;
    if (!startup && pendingStartup != null) {
      _manualDuringStartup = true;
      await pendingStartup;
    }
    if (_disposed || busy || downloadedPath != null) return;
    phase = UpdatePhase.checking;
    message = '正在检查最新版本…';
    result = null;
    _cancel = CancelToken();
    _emit();
    try {
      var checked = await (startup
          ? service.checkForStartup(
              currentVersionCode: AppVersion.code, cancelToken: _cancel)
          : service.checkConfigured(
              currentVersionCode: AppVersion.code, cancelToken: _cancel));
      if (startup &&
          checked.update != null &&
          !AppUpdateService.isNewIteration(
              checked.update!.versionName, AppVersion.name)) {
        checked = const UpdateCheckResult(UpdateCheckStatus.upToDate);
      }
      if (_disposed) return;
      result = checked;
      phase = checked.status == UpdateCheckStatus.available
          ? UpdatePhase.available
          : UpdatePhase.checked;
      message = checked.message;
    } catch (_) {
      if (_disposed) return;
      phase = UpdatePhase.checked;
      result = const UpdateCheckResult(UpdateCheckStatus.networkError);
      message = result!.message;
    }
    _emit();
  }

  Future<void> download() async {
    final candidate = update;
    if (_disposed || busy || candidate == null || downloadedPath != null) {
      return;
    }
    phase = UpdatePhase.downloading;
    receivedBytes = 0;
    bytesPerSecond = 0;
    totalBytes = candidate.apkSize ?? -1;
    message = '正在下载更新包';
    _cancel = CancelToken();
    final watch = Stopwatch()..start();
    var lastNotification = -100;
    var speedAt = 0, speedBytes = 0;
    _emit();
    File? file;
    try {
      file = await service.downloadApk(candidate, cancelToken: _cancel,
          onProgress: (received, total) {
        if (_disposed || _cancel!.isCancelled) return;
        receivedBytes = received;
        totalBytes = total;
        final elapsed = watch.elapsedMilliseconds;
        if (elapsed - speedAt >= 500) {
          bytesPerSecond = (received - speedBytes) * 1000 / (elapsed - speedAt);
          speedAt = elapsed;
          speedBytes = received;
        }
        if (watch.elapsedMilliseconds - lastNotification >= 100 ||
            received == total) {
          lastNotification = watch.elapsedMilliseconds;
          _emit();
        }
      });
      if (_disposed || _cancel!.isCancelled) {
        if (await file.exists()) await file.delete();
        if (!_disposed) {
          phase = UpdatePhase.cancelled;
          message = '已取消下载，可重新开始';
          _emit();
        }
        return;
      }
      phase = UpdatePhase.verifying;
      message = '正在校验安装包身份…';
      _emit();
      await _inspect(file.path, candidate);
      if (_disposed) return;
      downloadedPath = file.path;
      phase = UpdatePhase.ready;
      message = '更新包已就绪，可以安装';
    } catch (e) {
      if (file != null && await file.exists()) await file.delete();
      if (_disposed) return;
      final cancelled = _cancel?.isCancelled == true;
      phase = cancelled ? UpdatePhase.cancelled : UpdatePhase.failed;
      message = cancelled ? '已取消下载，可重新开始' : _error(e, '下载失败，请重试');
    }
    _emit();
  }

  Future<void> _inspect(String path, AppUpdateInfo candidate) async {
    final info = await links.inspectApk(path);
    if (info['compatible'] != true) {
      throw StateError(info['reason']?.toString() ?? '安装包无法覆盖当前应用');
    }
    if ((candidate.applicationId != null &&
            info['applicationId'] != candidate.applicationId) ||
        (candidate.versionCode != null &&
            info['versionCode'] != candidate.versionCode) ||
        (info['versionName'] != null &&
            info['versionName'] != candidate.versionName)) {
      throw StateError('安装包身份与发布版本不符');
    }
  }

  Future<void> install() async {
    final path = downloadedPath;
    if (_disposed || busy || path == null || update == null) return;
    phase = UpdatePhase.installing;
    message = '正在打开系统安装器…';
    _emit();
    try {
      await _inspect(path, update!);
    } catch (e) {
      if (_disposed) return;
      downloadedPath = null;
      phase = UpdatePhase.failed;
      message = '${_error(e, '安装包已失效')}，请重新下载';
      try {
        final stale = File(path);
        if (await stale.exists()) await stale.delete();
      } on FileSystemException {
        // A reclaimed or locked cache file must not block a fresh download.
      }
      _emit();
      return;
    }
    try {
      if (_disposed) return;
      final opened = await links.installApk(path);
      if (_disposed) return;
      message = opened ? '已打开系统安装器，请确认安装；取消后仍可重试' : '请允许安装此来源的应用，返回后点击“安装更新”重试';
    } catch (e) {
      if (_disposed) return;
      message = _error(e, '无法打开安装器，请重试');
    }
    phase = UpdatePhase.ready;
    _emit();
  }

  void cancelDownload() {
    // Once verification starts, allow it to finish rather than race a new download.
    if (phase == UpdatePhase.downloading) _cancel?.cancel('user cancelled');
  }

  void hideBanner() {
    if (!busy) {
      phase = UpdatePhase.available;
      _emit();
    }
  }

  String _error(Object e, String fallback) => switch (e) {
        StateError() => e.message.toString(),
        DioException(type: DioExceptionType.connectionTimeout) =>
          '连接更新服务器超时，请检查网络后重试',
        DioException(type: DioExceptionType.receiveTimeout) => '下载响应超时，请稍后重试',
        _ => fallback,
      };

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel('app disposed');
    super.dispose();
  }
}
