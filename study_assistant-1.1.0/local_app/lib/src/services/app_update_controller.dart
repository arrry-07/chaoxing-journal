import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
  CancelToken? _cancel;
  bool _disposed = false;

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

  Future<void> check() async {
    if (_disposed || busy || downloadedPath != null) return;
    phase = UpdatePhase.checking;
    message = '正在检查 GitHub 最新版本…';
    result = null;
    _cancel = CancelToken();
    _emit();
    try {
      final checked = await service.checkConfigured(
          currentVersionCode: AppVersion.code, cancelToken: _cancel);
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
    totalBytes = candidate.apkSize ?? -1;
    message = '正在下载更新包';
    _cancel = CancelToken();
    final watch = Stopwatch()..start();
    var lastNotification = -100;
    _emit();
    File? file;
    try {
      file = await service.downloadApk(candidate, cancelToken: _cancel,
          onProgress: (received, total) {
        if (_disposed || _cancel!.isCancelled) return;
        receivedBytes = received;
        totalBytes = total;
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

  String _error(Object e, String fallback) =>
      e is StateError ? e.message.toString() : fallback;

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel('app disposed');
    super.dispose();
  }
}
