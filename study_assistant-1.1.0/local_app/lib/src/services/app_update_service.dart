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
  });

  final String versionName;
  final String releaseUrl;
  final String apkName;
  final String apkDownloadUrl;
  final String releaseNotes;
  final int? apkSize;
}

class AppUpdateService {
  AppUpdateService({Dio? dio})
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

  final Dio _dio;

  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersionName,
    required int currentVersionCode,
  }) async {
    try {
      debugPrint('[UpdateCheck] checkForUpdate called, current=$currentVersionName');
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
      debugPrint('[UpdateCheck] Remote version: $remoteVersion, Current: $currentVersionName');
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
    final response = await _dio.get<List<int>>(
      update.apkDownloadUrl,
      onReceiveProgress: onProgress,
      options: Options(responseType: ResponseType.bytes),
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300 || response.data == null) {
      throw StateError('下载 APK 失败');
    }
    final bytes = response.data!;
    final totalBytes = _asInt(response.headers.value('content-length')) ??
        update.apkSize ??
        bytes.length;
    onProgress?.call(bytes.length, totalBytes);
    await file.writeAsBytes(bytes, flush: true);
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
