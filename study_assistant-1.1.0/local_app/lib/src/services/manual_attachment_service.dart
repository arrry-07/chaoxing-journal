import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/manual_attachment.dart';

enum AttachmentPickIssue {
  none,
  tooLarge,
  noCamera,
  busy,
  invalid,
  failed,
}

@immutable
class AttachmentSingleResult {
  const AttachmentSingleResult({
    this.attachment,
    this.issue = AttachmentPickIssue.none,
    this.message,
  });

  final ManualAttachment? attachment;
  final AttachmentPickIssue issue;
  final String? message;

  bool get cancelled => attachment == null && issue == AttachmentPickIssue.none;
}

@immutable
class AttachmentBatchResult {
  const AttachmentBatchResult({
    this.attachments = const [],
    this.skippedTooLarge = 0,
    this.skippedFailed = 0,
    this.issue = AttachmentPickIssue.none,
    this.message,
  });

  final List<ManualAttachment> attachments;
  final int skippedTooLarge;
  final int skippedFailed;
  final AttachmentPickIssue issue;
  final String? message;
}

enum AttachmentOpenStatus {
  ok,
  missingFile,
  noApp,
  failed,
}

class ManualAttachmentService {
  ManualAttachmentService({MethodChannel? channel})
      : _channel = channel ?? ManualAttachmentService.channel;

  static const MethodChannel channel =
      MethodChannel('study_assistant/manual_attachments');

  final MethodChannel _channel;
  String? _cachedRootPath;

  String? get cachedRootPath => _cachedRootPath;

  @visibleForTesting
  void setCachedRootPathForTest(String? path) {
    _cachedRootPath = path;
  }

  static bool _isUnmockedTestChannel(MethodChannel channel) {
    if (!kDebugMode) return false;
    if (BindingBase.debugBindingType() == null) return true;
    try {
      final messenger = ServicesBinding.instance.defaultBinaryMessenger;
      if (messenger.runtimeType.toString() == 'TestDefaultBinaryMessenger') {
        final dynamic testMessenger = messenger;
        if (testMessenger.allMessagesHandler == null &&
            testMessenger.checkMockMessageHandler(channel.name, null) == true) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<String?> getAttachmentRoot({bool refresh = false}) async {
    if (!refresh && _cachedRootPath != null) return _cachedRootPath;
    if (_isUnmockedTestChannel(_channel)) return _cachedRootPath;
    try {
      final root = await _channel.invokeMethod<String>('getAttachmentRoot');
      if (root != null && root.trim().isNotEmpty) {
        _cachedRootPath = root.trim();
      }
      return _cachedRootPath;
    } on PlatformException {
      return _cachedRootPath;
    } on MissingPluginException {
      return _cachedRootPath;
    }
  }

  File? resolveLocalFile(String relativePath, {String? rootPath}) {
    if (!ManualAttachment.isValidRelativePath(relativePath)) return null;
    final effectiveRoot = rootPath ?? _cachedRootPath;
    if (effectiveRoot == null || effectiveRoot.isEmpty) return null;
    final tail = relativePath.substring(ManualAttachment.storagePrefix.length);
    final segments = tail.split('/');
    final normalizedRoot = effectiveRoot.endsWith(Platform.pathSeparator)
        ? effectiveRoot.substring(0, effectiveRoot.length - 1)
        : effectiveRoot;
    return File([normalizedRoot, ...segments].join(Platform.pathSeparator));
  }

  Future<AttachmentSingleResult> capturePhoto() =>
      _invokeSingle('capturePhoto', defaultFailureMessage: '拍照失败，请重试');

  Future<AttachmentSingleResult> pickAttachmentFile() =>
      _invokeSingle('pickAttachmentFile', defaultFailureMessage: '选择文件失败，请重试');

  Future<AttachmentBatchResult> pickImages({
    required int maxCount,
  }) async {
    if (maxCount <= 0) return const AttachmentBatchResult();
    final capped = maxCount.clamp(1, ManualAttachment.maxImagesPerEntry);
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'pickImages',
        {'maxCount': capped},
      );
      if (raw == null) return const AttachmentBatchResult();
      final skippedTooLarge =
          raw['skippedTooLarge'] is int ? raw['skippedTooLarge'] as int : 0;
      final skippedFailed =
          raw['skippedFailed'] is int ? raw['skippedFailed'] as int : 0;
      final rawItems = raw['items'];
      final parsed = <ManualAttachment>[];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            try {
              parsed.add(
                  _parseChannelAttachment(Map<String, dynamic>.from(item)));
              if (parsed.length >= capped) break;
            } on FormatException {
              // Skip malformed channel item rather than corrupting notebook state.
            }
          }
        }
      }
      String? summary;
      if (skippedTooLarge > 0 && skippedFailed > 0) {
        summary = '已跳过 $skippedTooLarge 张超过 20 MB 的图片和 $skippedFailed 张无法读取的图片';
      } else if (skippedTooLarge > 0) {
        summary = parsed.isEmpty
            ? '所选图片超过 20 MB 上限，无法添加'
            : '已跳过 $skippedTooLarge 张超过 20 MB 上限的图片';
      } else if (skippedFailed > 0) {
        summary =
            parsed.isEmpty ? '所选图片无法读取，请重试' : '已跳过 $skippedFailed 张无法读取的图片';
      }
      return AttachmentBatchResult(
        attachments: List<ManualAttachment>.unmodifiable(parsed),
        skippedTooLarge: skippedTooLarge,
        skippedFailed: skippedFailed,
        issue: parsed.isEmpty && skippedTooLarge > 0
            ? AttachmentPickIssue.tooLarge
            : parsed.isEmpty && skippedFailed > 0
                ? AttachmentPickIssue.invalid
                : AttachmentPickIssue.none,
        message: summary,
      );
    } on PlatformException catch (error) {
      return AttachmentBatchResult(
        issue: _mapPlatformIssue(error.code),
        message: _friendlyErrorMessage(error, fallback: '选择图片失败，请重试'),
      );
    } on MissingPluginException {
      return const AttachmentBatchResult(
        issue: AttachmentPickIssue.failed,
        message: '当前平台不支持选择图片',
      );
    }
  }

  Future<AttachmentOpenStatus> openAttachment(
    ManualAttachment attachment,
  ) async {
    if (!ManualAttachment.isValidRelativePath(attachment.relativePath)) {
      return AttachmentOpenStatus.missingFile;
    }
    try {
      final code = await _channel.invokeMethod<String>('openAttachment', {
        'relativePath': attachment.relativePath,
        'mimeType': attachment.mimeType,
      });
      return switch (code) {
        'ok' => AttachmentOpenStatus.ok,
        'missing_file' => AttachmentOpenStatus.missingFile,
        'no_app' => AttachmentOpenStatus.noApp,
        _ => AttachmentOpenStatus.failed,
      };
    } on PlatformException {
      return AttachmentOpenStatus.failed;
    } on MissingPluginException {
      return AttachmentOpenStatus.failed;
    }
  }

  Future<int> deleteFiles(Iterable<String> relativePaths) async {
    final validPaths = [
      for (final path in relativePaths.toSet())
        if (ManualAttachment.isValidRelativePath(path)) path,
    ];
    if (validPaths.isEmpty || _isUnmockedTestChannel(_channel)) return 0;
    try {
      return await _channel.invokeMethod<int>('deleteAttachmentFiles', {
            'relativePaths': validPaths,
          }) ??
          0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<bool> deleteAllAttachments() async {
    if (_isUnmockedTestChannel(_channel)) return false;
    try {
      return await _channel.invokeMethod<bool>('deleteAllAttachments') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<AttachmentSingleResult> _invokeSingle(
    String method, {
    required String defaultFailureMessage,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(method);
      if (raw == null) return const AttachmentSingleResult();
      final attachment = _parseChannelAttachment(raw);
      return AttachmentSingleResult(attachment: attachment);
    } on PlatformException catch (error) {
      return AttachmentSingleResult(
        issue: _mapPlatformIssue(error.code),
        message: _friendlyErrorMessage(error, fallback: defaultFailureMessage),
      );
    } on MissingPluginException {
      return const AttachmentSingleResult(
        issue: AttachmentPickIssue.failed,
        message: '当前平台暂不支持此附件操作',
      );
    } on FormatException {
      return const AttachmentSingleResult(
        issue: AttachmentPickIssue.invalid,
        message: '附件信息格式无效，未添加',
      );
    }
  }

  ManualAttachment _parseChannelAttachment(Map<String, dynamic> raw) {
    final addedAtMs = raw['addedAtMs'];
    final addedAtIso = addedAtMs is int
        ? DateTime.fromMillisecondsSinceEpoch(addedAtMs, isUtc: true)
            .toIso8601String()
        : raw['addedAt'];
    return ManualAttachment.fromJson({
      'id': raw['id'],
      'kind': raw['kind'],
      'name': raw['name'],
      'relativePath': raw['relativePath'],
      'mimeType': raw['mimeType'],
      'sizeBytes': raw['sizeBytes'],
      'addedAt': addedAtIso,
    });
  }

  AttachmentPickIssue _mapPlatformIssue(String code) => switch (code) {
        'file_too_large' => AttachmentPickIssue.tooLarge,
        'no_camera' => AttachmentPickIssue.noCamera,
        'file_busy' => AttachmentPickIssue.busy,
        'file_invalid' => AttachmentPickIssue.invalid,
        _ => AttachmentPickIssue.failed,
      };

  String _friendlyErrorMessage(
    PlatformException error, {
    required String fallback,
  }) {
    final msg = error.message?.trim();
    if (msg != null && msg.isNotEmpty) return msg;
    return switch (error.code) {
      'file_too_large' => '单个文件不能超过 20 MB',
      'no_camera' => '未找到可用的相机应用',
      'file_busy' => '上一次附件操作仍在进行，请稍候',
      _ => fallback,
    };
  }
}
