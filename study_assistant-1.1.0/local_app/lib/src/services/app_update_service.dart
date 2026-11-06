import 'package:crypto/crypto.dart';
import '../app/app_version.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'parallel_apk_transfer.dart';

import 'package:dio/dio.dart';
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
      this.maxDownloadBytes = 256 * 1024 * 1024,
      this.parallelDownloads = false,
      this.totalDownloadTimeout = const Duration(minutes: 5),
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

  final Dio _dio;
  final int maxDownloadBytes;
  bool parallelDownloads;
  final Duration totalDownloadTimeout;
  final String manifestUrl;
  Future<UpdateCheckResult> checkConfigured(
      {required int currentVersionCode, CancelToken? cancelToken}) async {
    if (manifestUrl.isEmpty) {
      return _checkGitHub(
          currentVersionName: AppVersion.name,
          currentVersionCode: currentVersionCode,
          cancelToken: cancelToken);
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

  /// Legacy nullable API; application UI uses the explicit result from checkConfigured.
  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersionName,
    required int currentVersionCode,
  }) async =>
      (await _checkGitHub(
              currentVersionName: currentVersionName,
              currentVersionCode: currentVersionCode))
          .update;

  Future<UpdateCheckResult> _checkGitHub({
    required String currentVersionName,
    required int currentVersionCode,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
        cancelToken: cancelToken,
      );
      final status = response.statusCode;
      if (status == 429 ||
          (status == 403 &&
              (response.headers.value('x-ratelimit-remaining') == '0' ||
                  response.headers.value('retry-after') != null))) {
        return const UpdateCheckResult(UpdateCheckStatus.rateLimited);
      }
      if (status == 401 || status == 403) {
        return const UpdateCheckResult(UpdateCheckStatus.authRequired);
      }
      if (status == 404) {
        return const UpdateCheckResult(UpdateCheckStatus.noRelease);
      }
      if (status != 200) {
        return const UpdateCheckResult(UpdateCheckStatus.networkError);
      }
      final release = _asMap(response.data);
      final tag = release?['tag_name']?.toString() ?? '';
      final match =
          RegExp(r'^[vV]?(\d+\.\d+\.\d+)(?:\+(\d+))?$').firstMatch(tag);
      if (release == null ||
          match == null ||
          release['draft'] == true ||
          release['prerelease'] == true) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      final remoteVersion = match.group(1)!;
      final remoteCode = int.tryParse(match.group(2) ?? '');
      final sameVersion =
          normalizeVersionName(currentVersionName) == remoteVersion;
      if (!isRemoteVersionNewer(remoteVersion, currentVersionName) &&
          !(sameVersion &&
              remoteCode != null &&
              remoteCode > currentVersionCode)) {
        return const UpdateCheckResult(UpdateCheckStatus.upToDate);
      }
      if (remoteCode != null && remoteCode <= currentVersionCode) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      final assets = release['assets'];
      final apks = assets is List
          ? assets
              .map(_asMap)
              .whereType<Map<String, dynamic>>()
              .where((a) =>
                  a['name'] is String && (a['name'] as String).endsWith('.apk'))
              .toList()
          : <Map<String, dynamic>>[];
      final preferred = apks
          .where((a) => a['name'] == 'chaoxing-journal-$remoteVersion.apk')
          .toList();
      final asset = preferred.length == 1
          ? preferred.single
          : (apks.length == 1 ? apks.single : null);
      if (asset == null) {
        return const UpdateCheckResult(UpdateCheckStatus.packageUnavailable);
      }
      final url = asset['browser_download_url']?.toString() ?? '';
      final digest = asset['digest']?.toString() ?? '';
      final size = _asInt(asset['size']);
      final uri = Uri.tryParse(url);
      // Only a release asset in this repository is eligible for in-app installation.
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          !uri.path.startsWith('/$owner/$repo/releases/download/') ||
          !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
          size == null ||
          size <= 0) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      return UpdateCheckResult(UpdateCheckStatus.available,
          update: AppUpdateInfo(
            versionName: remoteVersion,
            versionCode: remoteCode,
            releaseUrl: '$releasesUrl/tag/${Uri.encodeComponent(tag)}',
            apkName: asset['name'] as String,
            apkDownloadUrl: url,
            releaseNotes: release['body']?.toString() ?? '',
            apkSize: size,
            sha256Hash: digest.substring(7).toLowerCase(),
          ));
    } on DioException catch (e) {
      return UpdateCheckResult(CancelToken.isCancel(e)
          ? UpdateCheckStatus.cancelled
          : UpdateCheckStatus.networkError);
    } catch (_) {
      return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
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
    // Every attempt owns its temporary directory; cancellation cannot delete a
    // newer attempt's partial file or an already verified APK.
    final working = await baseDirectory.createTemp('.apk-download-');
    final partial =
        File('${working.path}${Platform.pathSeparator}download.part');
    final transfer = CancelToken();
    var active = true;
    if (cancelToken?.isCancelled == true) transfer.cancel('下载已取消');
    cancelToken?.whenCancel.then((error) {
      if (active) transfer.cancel(error.message);
    });
    final deadline = Timer(totalDownloadTimeout, () {
      transfer.cancel('下载总时限已到，请重试');
    });
    Future<T> guarded<T>(Future<T> work) => Future.any([
          work,
          transfer.whenCancel.then<T>((error) => throw error),
        ]);
    void checkCancelled() {
      if (transfer.isCancelled) throw transfer.cancelError!;
    }

    StreamIterator<List<int>>? chunks;
    Stream<List<int>>? responseStream;
    var streamStarted = false;
    RandomAccessFile? output;
    try {
      checkCancelled();
      final declared = update.apkSize;
      if (maxDownloadBytes <= 0 ||
          (declared != null &&
              (declared <= 0 || declared > maxDownloadBytes))) {
        throw StateError('安装包大小超出允许范围');
      }
      Response<ResponseBody>? response;
      final parallel = parallelDownloads &&
          declared != null &&
          declared >= ParallelApkTransfer.minimumSize &&
          update.sha256Hash != null;
      if (parallel) {
        response = await ParallelApkTransfer.download(
            dio: _dio,
            url: update.apkDownloadUrl,
            size: declared,
            destination: partial,
            working: working,
            token: transfer,
            onProgress: onProgress);
      }
      var received = 0;
      int? expectedSize = declared;
      if (!parallel || response != null) {
        final fullResponse = response ??
            await guarded<Response<ResponseBody>>(_dio.get<ResponseBody>(
              update.apkDownloadUrl,
              cancelToken: transfer,
              options: Options(responseType: ResponseType.stream, headers: {
                'Accept': 'application/octet-stream',
                'Accept-Encoding': 'identity'
              }),
            ));
        final body = fullResponse.data;
        if (body != null) {
          responseStream = body.stream;
          chunks = StreamIterator<List<int>>(responseStream);
        }
        final status = fullResponse.statusCode ?? 0;
        if (status != 200 || chunks == null) {
          throw StateError('下载 APK 失败');
        }
        final header = fullResponse.headers.value('content-length');
        final headerSize = header == null ? null : int.tryParse(header);
        if ((header != null && (headerSize == null || headerSize <= 0)) ||
            (headerSize != null && headerSize > maxDownloadBytes) ||
            (headerSize != null &&
                declared != null &&
                headerSize != declared)) {
          throw StateError('安装包响应长度异常');
        }
        expectedSize = declared ?? headerSize;
        output = await partial.open(mode: FileMode.write);
        final buffer = BytesBuilder(copy: false);
        streamStarted = true;
        while (await guarded(chunks.moveNext())) {
          checkCancelled();
          final chunk = chunks.current;
          final nextSize = received + chunk.length;
          if (nextSize > maxDownloadBytes ||
              (expectedSize != null && nextSize > expectedSize)) {
            throw StateError('安装包响应超出允许大小');
          }
          buffer.add(chunk);
          if (buffer.length >= ParallelApkTransfer.bufferSize) {
            await output.writeFrom(buffer.takeBytes());
          }
          received = nextSize;
          onProgress?.call(received, expectedSize ?? -1);
        }
        if (buffer.isNotEmpty) await output.writeFrom(buffer.takeBytes());
        await output.close();
        output = null;
      } else {
        received = await partial.length();
      }
      if (received == 0 || (expectedSize != null && received != expectedSize)) {
        throw StateError('安装包下载不完整，请重试');
      }
      checkCancelled();
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
        checkCancelled();
        if (digest.toString() != update.sha256Hash) {
          throw StateError('安装包校验失败，请重新下载');
        }
      }
      checkCancelled();
      await partial.rename(file.path);
      // Renaming is the publication point: late cancellation must not remove
      // this verified file or turn another attempt's completed file into a part.
      onProgress?.call(received, expectedSize ?? received);
    } finally {
      active = false;
      deadline.cancel();
      transfer.cancel('下载已结束');
      // StreamIterator subscribes lazily: header/status rejection must close an
      // unstarted response as well, instead of leaving its socket/body alive.
      try {
        if (streamStarted) {
          await chunks?.cancel();
        } else {
          await responseStream?.listen((_) {}, onError: (Object _) {}).cancel();
        }
      } finally {
        try {
          await output?.close();
        } finally {
          if (await working.exists()) await working.delete(recursive: true);
        }
      }
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
  cancelled,
  noRelease,
  rateLimited,
  packageUnavailable
}

class UpdateCheckResult {
  const UpdateCheckResult(this.status, {this.update});
  final UpdateCheckStatus status;
  final AppUpdateInfo? update;
  String get message => switch (status) {
        UpdateCheckStatus.upToDate => '当前已是最新版本',
        UpdateCheckStatus.available => '发现新版本',
        UpdateCheckStatus.networkError => '检查更新失败，请重试',
        UpdateCheckStatus.authRequired => '暂时无法访问更新渠道，请稍后重试或查看发行版',
        UpdateCheckStatus.invalidManifest => '更新清单无效，请联系维护者',
        UpdateCheckStatus.unconfigured => '更新渠道待配置',
        UpdateCheckStatus.cancelled => '已取消检查',
        UpdateCheckStatus.noRelease => '仓库尚未发布正式版本',
        UpdateCheckStatus.rateLimited => '检查过于频繁，请稍后重试',
        UpdateCheckStatus.packageUnavailable => '新版安装包尚未就绪，请稍后重试'
      };
}
