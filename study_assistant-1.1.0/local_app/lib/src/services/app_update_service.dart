import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../app/app_version.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'parallel_apk_transfer.dart';
import 'apk_download_transport.dart';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

const _giteeStableManifestUrl =
    'https://raw.giteeusercontent.com/arrry-07/chaoxing-journal-updates/raw/master/update-stable.json';
const _giteeManualManifestUrl =
    'https://raw.giteeusercontent.com/arrry-07/chaoxing-journal-updates/raw/master/update-manual.json';
const _configuredLegacyManifestUrl =
    String.fromEnvironment('UPDATE_MANIFEST_URL');
const _configuredStableManifestUrl = String.fromEnvironment(
  'UPDATE_STABLE_MANIFEST_URL',
);
const _configuredManualManifestUrl = String.fromEnvironment(
  'UPDATE_MANUAL_MANIFEST_URL',
);

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
    this.backupApkUrls = const [],
  });

  final int? versionCode;
  final String? sha256Hash, applicationId;
  final String versionName;
  final String releaseUrl;
  final String apkName;
  final String apkDownloadUrl;
  final String releaseNotes;
  final int? apkSize;
  final List<String> backupApkUrls;

  List<String> get downloadUrls {
    final seen = <String>{};
    return [
      apkDownloadUrl,
      ...backupApkUrls,
    ].where(seen.add).toList(growable: false);
  }
}

class AppUpdateService {
  AppUpdateService(
      {Dio? dio,
      this.maxDownloadBytes = 256 * 1024 * 1024,
      this.parallelDownloads = false,
      this.totalDownloadTimeout = const Duration(minutes: 5),
      this.staleDownloadAge = const Duration(hours: 24),
      this.now = DateTime.now,
      this.manifestUrl = const String.fromEnvironment('UPDATE_MANIFEST_URL'),
      this.stableManifestUrl =
          const String.fromEnvironment('UPDATE_STABLE_MANIFEST_URL'),
      this.manualManifestUrl =
          const String.fromEnvironment('UPDATE_MANUAL_MANIFEST_URL'),
      this.officialDualSource = false,
      this.githubFallbackEnabled = true})
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

  factory AppUpdateService.withGiteeDefaults({
    Dio? dio,
    String legacyManifestUrl = _configuredLegacyManifestUrl,
    String stableManifestUrl = _configuredStableManifestUrl,
    String manualManifestUrl = _configuredManualManifestUrl,
  }) {
    if (legacyManifestUrl.isNotEmpty) {
      return AppUpdateService(dio: dio, manifestUrl: legacyManifestUrl);
    }
    final hasCustomManifest =
        stableManifestUrl.isNotEmpty || manualManifestUrl.isNotEmpty;
    return AppUpdateService(
      dio: dio,
      stableManifestUrl:
          hasCustomManifest ? stableManifestUrl : _giteeStableManifestUrl,
      manualManifestUrl:
          hasCustomManifest ? manualManifestUrl : _giteeManualManifestUrl,
      officialDualSource: !hasCustomManifest,
    );
  }

  static const owner = 'arrry-07';
  static const repo = 'chaoxing-journal';
  static const repositoryUrl = 'https://github.com/$owner/$repo';
  static const releasesUrl = '$repositoryUrl/releases';
  static const applicationId = 'com.example.studyassistant.journal';
  static const giteeStableManifestUrl = _giteeStableManifestUrl;
  static const giteeManualManifestUrl = _giteeManualManifestUrl;
  static final _releaseVersionPattern = RegExp(r'^\d+\.\d+\.\d+$');

  final Dio _dio;
  final int maxDownloadBytes;
  bool parallelDownloads;
  final Duration totalDownloadTimeout;
  final Duration staleDownloadAge;
  final DateTime Function() now;
  final String manifestUrl;
  final String stableManifestUrl;
  final String manualManifestUrl;
  final bool officialDualSource;
  final bool githubFallbackEnabled;
  static const _downloadDirectoryPrefix = '.apk-download-';
  static const _downloadOwnerFile = 'owner.marker';
  static const _downloadOwnerValue = 'chaoxing-journal-apk-download-v1';
  static const _maxManifestBytes = 64 * 1024;
  static final Set<String> _activeDownloadDirectories = {};

  Future<UpdateCheckResult> checkConfigured(
          {required int currentVersionCode, CancelToken? cancelToken}) =>
      checkForManualUpdate(
          currentVersionName: AppVersion.name,
          currentVersionCode: currentVersionCode,
          cancelToken: cancelToken);

  Future<UpdateCheckResult> checkForManualUpdate({
    required String currentVersionName,
    required int currentVersionCode,
    CancelToken? cancelToken,
  }) async {
    await cleanupStaleDownloads();
    final url = manualManifestUrl.isNotEmpty ? manualManifestUrl : manifestUrl;
    if (url.isNotEmpty) {
      if (officialDualSource &&
          githubFallbackEnabled &&
          _isOfficialGiteeManifest(url)) {
        return _checkDualOfficialSources(
          manifestUrl: url,
          currentVersionName: currentVersionName,
          currentVersionCode: currentVersionCode,
          cancelToken: cancelToken,
        );
      }
      return _checkManifestWithFallback(
        manifestUrl: url,
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
        startupOnly: false,
        githubListReleases: true,
        cancelToken: cancelToken,
      );
    }
    return _checkGitHub(
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
        cancelToken: cancelToken,
        listReleases: true);
  }

  /// Discover every newer public release on cold start, including patches.
  /// The controller still honours ignored versions and never auto-downloads.
  Future<UpdateCheckResult> checkForStartup(
      {required int currentVersionCode, CancelToken? cancelToken}) async {
    if (manualManifestUrl.isEmpty &&
        manifestUrl.isEmpty &&
        stableManifestUrl.isNotEmpty) {
      await cleanupStaleDownloads();
      return _checkManifestWithFallback(
          manifestUrl: stableManifestUrl,
          currentVersionName: AppVersion.name,
          currentVersionCode: currentVersionCode,
          startupOnly: false,
          githubListReleases: false,
          cancelToken: cancelToken);
    }
    return checkForManualUpdate(
      currentVersionName: AppVersion.name,
      currentVersionCode: currentVersionCode,
      cancelToken: cancelToken,
    );
  }

  Future<UpdateCheckResult> _checkDualOfficialSources({
    required String manifestUrl,
    required String currentVersionName,
    required int currentVersionCode,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      return const UpdateCheckResult(UpdateCheckStatus.cancelled);
    }
    final results = await Future.wait([
      _checkManifest(
        manifestUrl: manifestUrl,
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
        startupOnly: false,
        cancelToken: cancelToken,
      ),
      _checkGitHub(
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
        cancelToken: cancelToken,
        listReleases: true,
      ),
    ]);
    return _mergeOfficialResults(results[0], results[1]);
  }

  UpdateCheckResult _mergeOfficialResults(
    UpdateCheckResult gitee,
    UpdateCheckResult github,
  ) {
    if (gitee.status == UpdateCheckStatus.cancelled ||
        github.status == UpdateCheckStatus.cancelled) {
      return const UpdateCheckResult(UpdateCheckStatus.cancelled);
    }
    final giteeUpdate = gitee.update;
    final githubUpdate = github.update;
    if (giteeUpdate != null && githubUpdate != null) {
      final comparison = _compareUpdateVersions(giteeUpdate, githubUpdate);
      if (comparison > 0) {
        return UpdateCheckResult(UpdateCheckStatus.available,
            update: giteeUpdate);
      }
      if (comparison < 0) {
        return UpdateCheckResult(UpdateCheckStatus.available,
            update: githubUpdate);
      }
      return UpdateCheckResult(
        UpdateCheckStatus.available,
        update: _mergeSameVersion(giteeUpdate, githubUpdate),
      );
    }
    if (giteeUpdate != null) {
      return UpdateCheckResult(UpdateCheckStatus.available,
          update: giteeUpdate);
    }
    if (githubUpdate != null) {
      return UpdateCheckResult(UpdateCheckStatus.available,
          update: githubUpdate);
    }
    if (gitee.status == UpdateCheckStatus.upToDate ||
        github.status == UpdateCheckStatus.upToDate) {
      return const UpdateCheckResult(UpdateCheckStatus.upToDate);
    }
    for (final status in const [
      UpdateCheckStatus.rateLimited,
      UpdateCheckStatus.authRequired,
      UpdateCheckStatus.packageUnavailable,
      UpdateCheckStatus.noRelease,
      UpdateCheckStatus.invalidManifest,
    ]) {
      if (gitee.status == status || github.status == status) {
        return UpdateCheckResult(status);
      }
    }
    if (gitee.status == UpdateCheckStatus.networkError &&
        github.status != UpdateCheckStatus.networkError) {
      return UpdateCheckResult(github.status);
    }
    return UpdateCheckResult(gitee.status);
  }

  int _compareUpdateVersions(AppUpdateInfo first, AppUpdateInfo second) {
    if (first.versionName == second.versionName) return 0;
    if (isRemoteVersionNewer(first.versionName, second.versionName)) return 1;
    if (isRemoteVersionNewer(second.versionName, first.versionName)) return -1;
    return 0;
  }

  AppUpdateInfo _mergeSameVersion(
    AppUpdateInfo gitee,
    AppUpdateInfo github,
  ) {
    final sameContent = gitee.apkSize == github.apkSize &&
        gitee.sha256Hash?.toLowerCase() == github.sha256Hash?.toLowerCase();
    if (!sameContent) {
      // Conflicting Gitee metadata must never redirect a verified GitHub
      // release to different bytes.
      return github;
    }
    final versionCode = github.versionCode ?? gitee.versionCode;
    return AppUpdateInfo(
      versionName: github.versionName,
      versionCode: versionCode,
      applicationId: github.applicationId ?? gitee.applicationId,
      sha256Hash: github.sha256Hash ?? gitee.sha256Hash,
      releaseUrl: github.releaseUrl,
      apkName: github.apkName,
      apkDownloadUrl: gitee.apkDownloadUrl,
      backupApkUrls: [
        github.apkDownloadUrl,
        ...github.backupApkUrls,
        ...gitee.backupApkUrls,
      ],
      releaseNotes: github.releaseNotes,
      apkSize: github.apkSize ?? gitee.apkSize,
    );
  }

  Future<UpdateCheckResult> _checkManifestWithFallback({
    required String manifestUrl,
    required String currentVersionName,
    required int currentVersionCode,
    required bool startupOnly,
    required bool githubListReleases,
    CancelToken? cancelToken,
  }) async {
    final primary = await _checkManifest(
      manifestUrl: manifestUrl,
      currentVersionName: currentVersionName,
      currentVersionCode: currentVersionCode,
      startupOnly: startupOnly,
      cancelToken: cancelToken,
    );
    if (!githubFallbackEnabled ||
        cancelToken?.isCancelled == true ||
        !_isOfficialGiteeManifest(manifestUrl) ||
        primary.status == UpdateCheckStatus.available ||
        primary.status == UpdateCheckStatus.upToDate ||
        primary.status == UpdateCheckStatus.cancelled) {
      return primary;
    }
    final fallback = await _checkGitHub(
      currentVersionName: currentVersionName,
      currentVersionCode: currentVersionCode,
      cancelToken: cancelToken,
      listReleases: githubListReleases,
    );
    if (fallback.status == UpdateCheckStatus.available ||
        fallback.status == UpdateCheckStatus.upToDate) {
      return fallback;
    }
    return primary;
  }

  bool _isOfficialGiteeManifest(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'raw.giteeusercontent.com' &&
        uri.userInfo.isEmpty &&
        uri.path.startsWith('/arrry-07/chaoxing-journal-updates/raw/master/');
  }

  Future<UpdateCheckResult> _checkManifest({
    required String manifestUrl,
    required String currentVersionName,
    required int currentVersionCode,
    required bool startupOnly,
    CancelToken? cancelToken,
  }) async {
    if (!_isSecureUrl(manifestUrl)) {
      return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
    }
    try {
      // Read the manifest as text so COS metadata differences and a UTF-8 BOM
      // cannot make Dio's automatic JSON transformer reject a valid document.
      final r = await _dio.get<dynamic>(
        manifestUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );
      if (r.statusCode == 401 || r.statusCode == 403) {
        return const UpdateCheckResult(UpdateCheckStatus.authRequired);
      }
      if (r.statusCode != 200) {
        return const UpdateCheckResult(UpdateCheckStatus.networkError);
      }
      final manifestText = await _readManifestText(r.data, cancelToken);
      final j = manifestText == null ? null : _asMap(manifestText);
      if (j == null) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      final code = j['versionCode'],
          name = j['versionName'],
          url = j['apkUrl'],
          hash = j['sha256'],
          app = j['applicationId'],
          size = j['size'];
      final backupUrls = _parseBackupApkUrls(j, primaryUrl: url);
      if (code is! int ||
          code <= 0 ||
          code > 0x7fffffff ||
          name is! String ||
          !_releaseVersionPattern.hasMatch(name) ||
          url is! String ||
          !_isSecureUrl(url) ||
          hash is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
          app is! String ||
          app != applicationId ||
          size is! int ||
          size <= 0 ||
          size > maxDownloadBytes ||
          backupUrls == null) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      if (code <= currentVersionCode) {
        return const UpdateCheckResult(UpdateCheckStatus.upToDate);
      }
      final normalizedCurrent = normalizeVersionName(currentVersionName);
      if (!_releaseVersionPattern.hasMatch(normalizedCurrent)) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      final sameDisplayVersion = name == normalizedCurrent;
      if (!sameDisplayVersion &&
          !isRemoteVersionNewer(name, normalizedCurrent)) {
        return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
      }
      if (startupOnly && !isNewIteration(name, normalizedCurrent)) {
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
              backupApkUrls: backupUrls,
              releaseNotes: j['notes']?.toString() ?? '',
              apkSize: size));
    } on DioException catch (e) {
      return UpdateCheckResult(CancelToken.isCancel(e)
          ? UpdateCheckStatus.cancelled
          : UpdateCheckStatus.networkError);
    } catch (_) {
      return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
    }
  }

  static bool isNewIteration(String remote, String current) {
    final pattern = RegExp(r'^\d+\.\d+\.\d+$');
    if (!pattern.hasMatch(normalizeVersionName(remote)) ||
        !pattern.hasMatch(normalizeVersionName(current))) {
      return false;
    }
    final next = _versionParts(remote), installed = _versionParts(current);
    return next[0] > installed[0] ||
        (next[0] == installed[0] && next[1] > installed[1]);
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
    bool listReleases = false,
  }) async {
    try {
      final releases = <Map<String, dynamic>>[];
      var page = 1;
      late Response<dynamic> response;
      while (true) {
        response = await _dio.get<dynamic>(
          'https://api.github.com/repos/$owner/$repo/releases${listReleases ? '' : '/latest'}',
          queryParameters:
              listReleases ? {'per_page': 100, 'page': page} : null,
          cancelToken: cancelToken,
        );
        if (!listReleases || response.statusCode != 200) break;
        final data = response.data;
        if (data is! List || data.any((item) => _asMap(item) == null)) {
          return const UpdateCheckResult(UpdateCheckStatus.invalidManifest);
        }
        releases.addAll(data.map((item) => _asMap(item)!));
        final more = data.length == 100 ||
            (response.headers.value('link')?.contains('rel="next"') ?? false);
        if (!more) break;
        page++;
      }
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
      Map<String, dynamic>? release;
      if (listReleases) {
        final stable = releases
            .where((r) => r['draft'] != true && r['prerelease'] != true)
            .toList();
        if (stable.isEmpty) {
          return const UpdateCheckResult(UpdateCheckStatus.noRelease);
        }
        final pattern = RegExp(r'^[vV]?(\d+\.\d+\.\d+)(?:\+(\d+))?$');
        for (final item in stable) {
          final name = pattern.firstMatch(item['tag_name']?.toString() ?? '');
          if (name == null) continue;
          if (release == null) {
            release = item;
            continue;
          }
          final prior = pattern.firstMatch(release['tag_name'].toString())!;
          if (isRemoteVersionNewer(name.group(1)!, prior.group(1)!) ||
              (name.group(1) == prior.group(1) &&
                  (int.tryParse(name.group(2) ?? '') ?? 0) >
                      (int.tryParse(prior.group(2) ?? '') ?? 0))) {
            release = item;
          }
        }
      } else {
        release = _asMap(response.data);
      }
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
    final sources = update.downloadUrls;
    final budget = Stopwatch()..start();
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var index = 0; index < sources.length; index++) {
      if (cancelToken?.isCancelled == true) {
        Error.throwWithStackTrace(
            cancelToken!.cancelError!, StackTrace.current);
      }
      final remaining = totalDownloadTimeout - budget.elapsed;
      if (remaining <= Duration.zero) {
        if (lastError != null && lastStackTrace != null) {
          Error.throwWithStackTrace(lastError, lastStackTrace);
        }
        throw DioException.connectionTimeout(
          timeout: totalDownloadTimeout,
          requestOptions: RequestOptions(path: sources[index]),
        );
      }
      try {
        return await _downloadApkFromUrl(
          update,
          downloadUrl: sources[index],
          transferTimeout: remaining,
          targetDirectory: targetDirectory,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final canUseBackup = index + 1 < sources.length &&
            cancelToken?.isCancelled != true &&
            _canTryBackupSource(error);
        if (!canUseBackup) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        // A backup starts from a fresh temporary directory. Never append bytes
        // from two sources; the complete result is checked against this
        // manifest's single size/hash before publication.
        onProgress?.call(0, update.apkSize ?? -1);
      }
    }
    Error.throwWithStackTrace(
        lastError ?? StateError('没有可用的安装包下载源'), lastStackTrace!);
  }

  Future<File> _downloadApkFromUrl(
    AppUpdateInfo update, {
    required String downloadUrl,
    required Duration transferTimeout,
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
    await cleanupStaleDownloads(targetDirectory: baseDirectory.path);
    final file = File(
      '${baseDirectory.path}${Platform.pathSeparator}${_downloadFileName(update)}',
    );
    // Every attempt owns its temporary directory; cancellation cannot delete a
    // newer attempt's partial file or an already verified APK.
    final working = await baseDirectory.createTemp(_downloadDirectoryPrefix);
    final workingKey = working.absolute.path;
    _activeDownloadDirectories.add(workingKey);
    final partial =
        File('${working.path}${Platform.pathSeparator}download.part');
    final transfer = CancelToken();
    var active = true;
    if (cancelToken?.isCancelled == true) transfer.cancel('下载已取消');
    cancelToken?.whenCancel.then((error) {
      if (active) transfer.cancel(error.message);
    });
    final deadline = Timer(transferTimeout, () {
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
      await File(
        '${working.path}${Platform.pathSeparator}$_downloadOwnerFile',
      ).writeAsString(_downloadOwnerValue, flush: true);
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
            url: downloadUrl,
            size: declared,
            destination: partial,
            working: working,
            token: transfer,
            validateFullResponse: (response) =>
                _fullResponseSize(response, declared, downloadUrl),
            onProgress: onProgress);
      }
      var received = 0;
      int? expectedSize = declared;
      if (!parallel || response != null) {
        final fullResponse = response ??
            await guarded<Response<ResponseBody>>(
                ApkDownloadTransport(_dio).open(
              downloadUrl,
              token: transfer,
              validateHeaders: (response) =>
                  _fullResponseSize(response, declared, downloadUrl),
            ));
        expectedSize = _fullResponseSize(fullResponse, declared, downloadUrl);
        responseStream = fullResponse.data!.stream;
        chunks = StreamIterator<List<int>>(responseStream);
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
          throw ApkVerificationException('响应不是APK文件');
        }
        final digest = await sha256.bind(partial.openRead()).first;
        checkCancelled();
        if (digest.toString() != update.sha256Hash) {
          throw ApkVerificationException('安装包校验失败，请重新下载');
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
          try {
            if (await working.exists()) await working.delete(recursive: true);
          } finally {
            _activeDownloadDirectories.remove(workingKey);
          }
        }
      }
    }
    return file;
  }

  int? _fullResponseSize(
      Response<ResponseBody> response, int? declared, String expectedUrl) {
    if (response.statusCode != 200 || response.data == null) {
      throw ApkSourceUnavailableException(
        '下载 APK 失败',
        statusCode: response.statusCode,
      );
    }
    if (!_redirectChainIsSecure(response, expectedUrl)) {
      throw StateError('安装包下载重定向不安全');
    }
    final header = response.headers.value('content-length');
    final size = header == null ? null : int.tryParse(header);
    if ((header != null && (size == null || size <= 0)) ||
        (size != null && size > maxDownloadBytes) ||
        (size != null && declared != null && size != declared)) {
      throw StateError('安装包响应长度异常');
    }
    return declared ?? size;
  }

  /// Removes only stale, direct child directories created by this downloader.
  /// Cleanup is best-effort and never blocks a new download.
  Future<void> cleanupStaleDownloads({String? targetDirectory}) async {
    try {
      final baseDirectory = targetDirectory == null
          ? Directory(
              '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}updates',
            )
          : Directory(targetDirectory);
      if (!await baseDirectory.exists()) return;
      final cutoff = now().subtract(staleDownloadAge);
      await for (final entry in baseDirectory.list(followLinks: false)) {
        if (entry is! Directory ||
            !entry.path
                .split(Platform.pathSeparator)
                .last
                .startsWith(_downloadDirectoryPrefix)) {
          continue;
        }
        final key = entry.absolute.path;
        if (_activeDownloadDirectories.contains(key)) continue;
        if ((await entry.stat()).modified.isAfter(cutoff)) continue;
        if (!await _isOwnedDownloadDirectory(entry)) continue;
        try {
          await entry.delete(recursive: true);
        } catch (_) {
          // A lock or filesystem race must leave the directory for a later run.
        }
      }
    } catch (_) {
      // Startup cleanup must not interfere with update checking or downloading.
    }
  }

  Future<bool> _isOwnedDownloadDirectory(Directory directory) async {
    final marker = File(
      '${directory.path}${Platform.pathSeparator}$_downloadOwnerFile',
    );
    try {
      if (await marker.exists() &&
          await marker.readAsString() == _downloadOwnerValue) {
        return true;
      }
    } catch (_) {}

    var hasPartial = false;
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File) return false;
        final name = entry.path.split(Platform.pathSeparator).last;
        if (name == 'download.part' ||
            RegExp(r'^range-\d+\.part$').hasMatch(name)) {
          hasPartial = true;
          continue;
        }
        if (name != _downloadOwnerFile) return false;
      }
    } catch (_) {
      return false;
    }
    return hasPartial;
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

  bool _isSecureUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  bool _redirectChainIsSecure(Response<dynamic> response, String expectedUrl) {
    var current = Uri.tryParse(expectedUrl);
    if (current == null || !_isSafeDownloadUrl(current)) return false;
    for (final redirect in response.redirects) {
      final next = redirect.location.hasScheme
          ? redirect.location
          : current!.resolveUri(redirect.location);
      if (!_isSafeDownloadUrl(next)) return false;
      current = next;
    }
    return current != null && _isSafeDownloadUrl(current);
  }

  bool _isSafeDownloadUrl(Uri uri) {
    if (_isSecureUrl(uri.toString())) return true;
    return uri.scheme == 'http' &&
        uri.userInfo.isEmpty &&
        const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host);
  }

  Future<String?> _readManifestText(
    dynamic data,
    CancelToken? cancelToken,
  ) async {
    if (data is Map || data is List) {
      return jsonEncode(data);
    }
    if (data is String) {
      final bytes = utf8.encode(data);
      if (bytes.length > _maxManifestBytes) return null;
      return utf8.decode(bytes).replaceFirst('\uFEFF', '').trim();
    }
    if (data is! ResponseBody) return null;
    final chunks = StreamIterator<List<int>>(data.stream);
    final bytes = BytesBuilder(copy: false);
    try {
      while (await chunks.moveNext()) {
        if (cancelToken?.isCancelled == true) {
          throw cancelToken!.cancelError!;
        }
        bytes.add(chunks.current);
        if (bytes.length > _maxManifestBytes) {
          await chunks.cancel();
          return null;
        }
      }
    } finally {
      await chunks.cancel();
    }
    return utf8.decode(bytes.takeBytes()).replaceFirst('\uFEFF', '').trim();
  }

  List<String>? _parseBackupApkUrls(
    Map<String, dynamic> json, {
    required dynamic primaryUrl,
  }) {
    final rawSingle = json['backupApkUrl'];
    final rawList = json['backupApkUrls'];
    if (rawSingle == null && rawList == null) return const [];
    final values = <dynamic>[];
    if (rawSingle != null) values.add(rawSingle);
    if (rawList != null) {
      if (rawList is! List) return null;
      values.addAll(rawList);
    }
    if (values.length > 4) return null;
    final result = <String>[];
    for (final value in values) {
      if (value is! String || !_isSecureUrl(value)) return null;
      if (value == primaryUrl || result.contains(value)) continue;
      result.add(value);
    }
    return List<String>.unmodifiable(result);
  }

  bool _canTryBackupSource(Object error) {
    if (error is ApkSourceUnavailableException) {
      final status = error.statusCode;
      return status == null ||
          status == 404 ||
          status == 408 ||
          status == 410 ||
          status == 429 ||
          status >= 500;
    }
    if (error is! DioException) return false;
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.unknown ||
      DioExceptionType.cancel =>
        true,
      DioExceptionType.badResponse => switch (error.response?.statusCode) {
          null => false,
          404 || 408 || 410 || 429 => true,
          final status => status >= 500,
        },
      _ => false,
    };
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is String) {
      final text = value.replaceFirst('\uFEFF', '').trim();
      if (text.isEmpty) return null;
      value = jsonDecode(text);
    }
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

  String _downloadFileName(AppUpdateInfo update) {
    final safeName = _safeFileName(update.apkName);
    final digest = update.sha256Hash;
    if (digest == null || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(digest)) {
      return safeName;
    }
    final stem = safeName.substring(0, safeName.length - 4);
    // A different digest for the same release filename must not replace a
    // previously verified APK before the controller validates package
    // identity/signature. Equal digests represent the same file content.
    return '$stem-${digest.toLowerCase()}.apk';
  }
}

class ApkVerificationException extends StateError {
  ApkVerificationException(super.message);
}

class ApkSourceUnavailableException extends StateError {
  ApkSourceUnavailableException(super.message, {this.statusCode});

  final int? statusCode;
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
