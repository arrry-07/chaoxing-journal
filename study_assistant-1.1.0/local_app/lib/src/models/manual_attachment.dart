import 'package:flutter/foundation.dart';

import 'personal_workspace.dart';

@immutable
class ManualAttachment {
  static const kindImage = 'image';
  static const kindFile = 'file';
  static const maxImagesPerEntry = 9;
  static const maxAttachmentsPerEntry = 20;
  static const maxFileBytes = 20 * 1024 * 1024;
  static const storagePrefix = 'manual_attachments/';
  static const maxRelativePathLength = 260;
  static const maxIdLength = 100;
  static const maxNameLength = 200;
  static const maxMimeLength = 120;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9._-]{1,100}$');
  static final RegExp _segmentPattern = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _mimePattern =
      RegExp(r'^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$');

  const ManualAttachment({
    required this.id,
    required this.kind,
    required this.name,
    required this.relativePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.addedAt,
  });

  final String id;
  final String kind;
  final String name;
  final String relativePath;
  final String mimeType;
  final int sizeBytes;
  final DateTime addedAt;

  bool get isImage => kind == kindImage;

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).ceil()} KB';
    }
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  static bool isValidRelativePath(String path) {
    if (path.isEmpty ||
        path.length > maxRelativePathLength ||
        !path.startsWith(storagePrefix) ||
        path.contains('\\') ||
        path.contains('..') ||
        path.contains('//') ||
        path.endsWith('/')) {
      return false;
    }
    final tail = path.substring(storagePrefix.length);
    if (tail.isEmpty || tail.startsWith('/')) return false;
    final segments = tail.split('/');
    for (final segment in segments) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          !_segmentPattern.hasMatch(segment)) {
        return false;
      }
    }
    return true;
  }

  static bool isValidId(String id) =>
      id.length <= maxIdLength &&
      id != '.' &&
      id != '..' &&
      !id.contains('..') &&
      _idPattern.hasMatch(id);

  static bool isValidMimeType(String mime) =>
      mime.length <= maxMimeLength && _mimePattern.hasMatch(mime);

  static DateTime _parseAddedAt(dynamic value) {
    final raw = PersonalWorkspace.text(value, 40);
    final date = DateTime.tryParse(raw);
    if (date == null ||
        date.year < 2000 ||
        date.year > 2200 ||
        date.toUtc().toIso8601String() != raw) {
      PersonalWorkspace.bad();
    }
    return date.toLocal();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'relativePath': relativePath,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'addedAt': addedAt.toUtc().toIso8601String(),
      };

  factory ManualAttachment.fromJson(dynamic value) {
    final j = PersonalWorkspace.map(value, const {
      'id',
      'kind',
      'name',
      'relativePath',
      'mimeType',
      'sizeBytes',
      'addedAt',
    });
    final id = PersonalWorkspace.text(j['id'], maxIdLength);
    final kind = j['kind'];
    final name = PersonalWorkspace.text(j['name'], maxNameLength);
    final relativePath =
        PersonalWorkspace.text(j['relativePath'], maxRelativePathLength);
    final mimeType = PersonalWorkspace.text(j['mimeType'], maxMimeLength);
    final sizeBytes = j['sizeBytes'];
    if (!isValidId(id) ||
        (kind != kindImage && kind != kindFile) ||
        !isValidRelativePath(relativePath) ||
        !isValidMimeType(mimeType) ||
        sizeBytes is! int ||
        sizeBytes < 0 ||
        sizeBytes > maxFileBytes) {
      PersonalWorkspace.bad();
    }
    return ManualAttachment(
      id: id,
      kind: kind as String,
      name: name,
      relativePath: relativePath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      addedAt: _parseAddedAt(j['addedAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManualAttachment &&
          other.id == id &&
          other.kind == kind &&
          other.name == name &&
          other.relativePath == relativePath &&
          other.mimeType == mimeType &&
          other.sizeBytes == sizeBytes &&
          other.addedAt.millisecondsSinceEpoch ==
              addedAt.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        name,
        relativePath,
        mimeType,
        sizeBytes,
        addedAt.millisecondsSinceEpoch,
      );
}
