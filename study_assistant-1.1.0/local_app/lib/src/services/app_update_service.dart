import 'package:crypto/crypto.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.releaseUrl,
    required this.apkName,
    required this.apkDownloadUrl,
    required this.releaseNotes,
    this.apkSize,
    this.versionCode,
    this.sha256Hash,
    this.applicationId,
  });

  final int? versionCode;
  final String? sha256Hash, applicationId;
  final String versionName;
  final String releaseUrl;
  final String apkName;
  final String apkDownloadUrl;
  final String releaseNotes;
  final int? apkSize;
}

class AppUpdateService {
  AppUpdateService(
      {Dio? dio,
      this.manifestUrl = const String.fromEnvironment('UPDATE_MANIFEST_URL')})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.github.com',
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                validateStatus: (status) => status != null && status < 500,
                headers: const {
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': 'StudyAssistant/1.0',
                },
              ),
            );

  static const owner = 'arrry-07';
  static const repo = 'chaoxing-journal';
  static const repositoryUrl = 'https://github.com/$owner/$repo';
  static const releasesUrl = '$repositoryUrl/releases';
  static const privateRepository = true;

  final Dio _dio;
  final String manifestUrl;
  Future<UpdateCheckResult> checkConfigured(
      {required int currentVersionCode, CancelToken? cancelToken}) async {
    if (manifestUrl.isEmpty) {
      return const UpdateCheckResult(UpdateCheckStatus.unconfigured);
    }
    final uri = Uri.tryParse(manifestUrl);
    if (uri == null || uri.scheme != 'https') {
      return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
    }
    try {
      final r = await _dio.get<dynamic>(manifestUrl, cancelToken: cancelToken);
      if (r.statusCode == 401 || r.statusCode == 403) {
        return const UpdateCheckResult(UpdateCheckStatus.authRequired);
      }
      if (r.statusCode != 200) {
        return const UpdateCheckResult(UpdateCheckStatus.networkError);
      }
      final j = _asMap(r.data);
      if (j == null) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      final code = j['versionCode'],
          name = j['versionName'],
          url = j['apkUrl'],
          hash = j['sha256'],
          app = j['applicationId'];
      if (code is! int ||
          code <= 0 ||
          name is! String ||
          name.isEmpty ||
          url is! String ||
          Uri.tryParse(url)?.scheme != 'https' ||
          hash is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
          app is! String ||
          app.isEmpty) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      if (code <= currentVersionCode) {
        return const UpdateCheckResult(UpdateCheckStatus.upToDate);
      }
      return UpdateCheckResult(UpdateCheckStatus.available,
          update: AppUpdateInfo(
              versionName: name,
              versionCode: code,
              applicationId: app,
              sha256Hash: hash.toLowerCase(),
              releaseUrl: releasesUrl,
              apkName: 'journal-$code.apk',
              apkDownloadUrl: url,
              releaseNotes: j['notes']?.toString() ?? '',
              apkSize: _asInt(j['size'])));
    } on DioException catch (e) {
      return UpdateCheckResult(CancelToken.isCancel(e)
          ? UpdateCheckStatus.cancelled
          : UpdateCheckStatus.networkError);
    } catch (_) {
      return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
    }
  }

  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersionName,
    required int currentVersionCode,
  }) async {
    try {
      debugPrint(
          '[UpdateCheck] checkForUpdate called, current=$currentVersionName');
      final response = await _dio.get<dynamic>(
        '/repos/$owner/$repo/releases/latest',
      );
      final status = response.statusCode ?? 0;
      debugPrint('[UpdateCheck] GitHub API status: $status');
      if (status < 200 || status >= 300) {
        debugPrint('[UpdateCheck] Non-2xx status, returning null');
        return null;
      }
      final data = response.data;
      if (data == null) {
        debugPrint('[UpdateCheck] response.data is null');
        return null;
      }
      final release = _asMap(data);
      if (release == null) {
        debugPrint('[UpdateCheck] release map is null');
        return null;
      }
      final rawTag = (release['tag_name'] ?? release['name'])?.toString();
      if (rawTag == null || rawTag.trim().isEmpty) {
        debugPrint('[UpdateCheck] rawTag is null/empty');
        return null;
      }
      debugPrint('[UpdateCheck] Remote tag: $rawTag');
      final remoteVersion = normalizeVersionName(rawTag);
      debugPrint(
          '[UpdateCheck] Remote version: $remoteVersion, Current: $currentVersionName');
      if (!isRemoteVersionNewer(remoteVersion, currentVersionName)) {
        debugPrint('[UpdateCheck] Remote version not newer');
        return null;
      }
      final asset = _findApkAsset(release['assets']);
      if (asset == null) {
        debugPrint('[UpdateCheck] No APK asset found');
        return null;
      }
      final apkUrl = asset['browser_download_url']?.toString();
      final apkName = asset['name']?.toString();
      if (apkUrl == null ||
          apkUrl.isEmpty ||
          apkName == null ||
          apkName.isEmpty) {
        debugPrint('[UpdateCheck] APK url or name invalid');
        return null;
      }
      debugPrint('[UpdateCheck] Update found! version=$remoteVersion');
      return AppUpdateInfo(
        versionName: remoteVersion,
        releaseUrl: release['html_url']?.toString() ??
            'https://github.com/$owner/$repo/releases/tag/$rawTag',
        apkName: apkName,
        apkDownloadUrl: apkUrl,
        releaseNotes: release['body']?.toString() ?? '',
        apkSize: _asInt(asset['size']),
      );
    } catch (e, stack) {
      debugPrint('[UpdateCheck] Exception: $e');
      debugPrint('[UpdateCheck] Stack: $stack');
      return null;
    }
  }

  Future<File> downloadApk(
    AppUpdateInfo update, {
    String? targetDirectory,
    CancelToken? cancelToken,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final baseDirectory = targetDirectory == null
        ? Directory(
            '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}updates',
          )
        : Directory(targetDirectory);
    await baseDirectory.create(recursive: true);
    final file = File(
      '${baseDirectory.path}${Platform.pathSeparator}${_safeFileName(update.apkName)}',
    );
    final partial = File('${file.path}.part');
    try {
      final response = await _dio.get<ResponseBody>(
        update.apkDownloadUrl,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.stream),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300 || response.data == null) {
        await response.data?.stream.drain<void>();
        throw StateError('下载 APK 失败');
      }
      final expectedSize =
          _asInt(response.headers.value('content-length')) ?? update.apkSize;
      var received = 0;
      final sink = partial.openWrite();
      try {
        await sink.addStream(response.data!.stream.map((chunk) {
          received += chunk.length;
          onProgress?.call(received, expectedSize ?? -1);
          return chunk;
        }));
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0 || (expectedSize != null && received != expectedSize)) {
        throw StateError('安装包下载不完整，请重试');
      }
      if (cancelToken?.isCancelled == true) throw StateError('下载已取消');
      if (update.sha256Hash != null) {
        final handle = await partial.open();
        late List<int> bytes;
        try {
          bytes = await handle.read(4);
        } finally {
          await handle.close();
        }
        if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
          throw StateError('响应不是APK文件');
        }
        final digest = await sha256.bind(partial.openRead()).first;
        if (digest.toString() != update.sha256Hash) {
          throw StateError('安装包校验失败，请重新下载');
        }
      }
      await partial.rename(file.path);
      onProgress?.call(received, expectedSize ?? received);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
    return file;
  }

  static bool isRemoteVersionNewer(String remote, String current) {
    final remoteParts = _versionParts(remote);
    final currentParts = _versionParts(current);
    final length = remoteParts.length > currentParts.length
        ? remoteParts.length
        : currentParts.length;
    for (var index = 0; index < length; index += 1) {
      final remotePart = index < remoteParts.length ? remoteParts[index] : 0;
      final currentPart = index < currentParts.length ? currentParts[index] : 0;
      if (remotePart > currentPart) {
        return true;
      }
      if (remotePart < currentPart) {
        return false;
      }
    }
    return false;
  }

  static String normalizeVersionName(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    final plusIndex = normalized.indexOf('+');
    if (plusIndex >= 0) {
      normalized = normalized.substring(0, plusIndex);
    }
    return normalized;
  }

  static List<int> _versionParts(String value) {
    return normalizeVersionName(value)
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  Map<String, dynamic>? _findApkAsset(dynamic assets) {
    if (assets is! List) {
      return null;
    }
    for (final item in assets) {
      final asset = _asMap(item);
      final name = asset?['name']?.toString().toLowerCase();
      if (asset != null && name != null && name.endsWith('.apk')) {
        return asset;
      }
    }
    return null;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  String _safeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-').trim();
    if (sanitized.isEmpty || !sanitized.toLowerCase().endsWith('.apk')) {
      return 'study-assistant-update.apk';
    }
    return sanitized;
  }
}

enum UpdateCheckStatus {
  upToDate,
  available,
  networkError,
  authRequired,
  invalidManifest,
  unconfigured,
  cancelled
}

class UpdateCheckResult {
  const UpdateCheckResult(this.status, {this.update});
  final UpdateCheckStatus status;
  final AppUpdateInfo? update;
  String get message => switch (status) {
        UpdateCheckStatus.upToDate => '当前已是最新版本',
        UpdateCheckStatus.available => '发现新版本',
        UpdateCheckStatus.networkError => '检查更新失败，请重试',
        UpdateCheckStatus.authRequired => '更新渠道需要授权，请使用浏览器备选',
        UpdateCheckStatus.invalidManifest => '更新清单无效，请联系维护者',
        UpdateCheckStatus.unconfigured => '更新渠道待配置',
        UpdateCheckStatus.cancelled => '已取消检查'
      };
}
