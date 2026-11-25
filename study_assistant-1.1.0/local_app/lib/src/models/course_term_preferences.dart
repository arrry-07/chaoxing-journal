import 'dart:convert';

import 'assignment.dart';

enum CourseArchiveMode { auto, archived, restored }

enum CourseBlockMode { auto, blocked, allowed }

class CourseTermOverride {
  const CourseTermOverride({
    this.manualTermKey,
    this.archiveMode = CourseArchiveMode.auto,
    this.blockMode = CourseBlockMode.auto,
    this.dismissedRecallCursorUtc,
  });

  final String? manualTermKey;
  final CourseArchiveMode archiveMode;
  final CourseBlockMode blockMode;
  final DateTime? dismissedRecallCursorUtc;

  bool get isEmpty =>
      manualTermKey == null &&
      archiveMode == CourseArchiveMode.auto &&
      blockMode == CourseBlockMode.auto &&
      dismissedRecallCursorUtc == null;

  CourseTermOverride copyWith({
    String? manualTermKey,
    bool clearManualTerm = false,
    CourseArchiveMode? archiveMode,
    CourseBlockMode? blockMode,
    DateTime? dismissedRecallCursorUtc,
    bool clearDismissedRecallCursor = false,
  }) =>
      CourseTermOverride(
        manualTermKey:
            clearManualTerm ? null : (manualTermKey ?? this.manualTermKey),
        archiveMode: archiveMode ?? this.archiveMode,
        blockMode: blockMode ?? this.blockMode,
        dismissedRecallCursorUtc: clearDismissedRecallCursor
            ? null
            : (dismissedRecallCursorUtc ?? this.dismissedRecallCursorUtc)
                ?.toUtc(),
      );

  Map<String, dynamic> toJson() => {
        if (manualTermKey != null) 'manualTermKey': manualTermKey,
        if (archiveMode != CourseArchiveMode.auto)
          'archiveMode': archiveMode.name,
        if (blockMode != CourseBlockMode.auto) 'blockMode': blockMode.name,
        if (dismissedRecallCursorUtc != null)
          'dismissedRecallCursorUtc':
              dismissedRecallCursorUtc!.toUtc().toIso8601String(),
      };

  static final RegExp _termKeyPattern = RegExp(r'^(20\d{2})-(fall|spring)$');

  static bool isValidTermKey(String? raw) {
    if (raw == null) return false;
    final match = _termKeyPattern.firstMatch(raw);
    if (match == null) return false;
    final year = int.tryParse(match.group(1)!);
    return year != null && year >= 2000 && year <= 2100;
  }

  factory CourseTermOverride.fromJson(dynamic raw, {bool strict = false}) {
    if (raw is! Map) {
      throw const FormatException('课程学期覆盖条目格式无效');
    }
    const allowedKeys = {
      'manualTermKey',
      'archiveMode',
      'blockMode',
      'dismissedRecallCursorUtc',
    };
    if (strict && raw.keys.any((k) => !allowedKeys.contains(k))) {
      throw const FormatException('课程学期覆盖包含未知字段');
    }
    final rawTerm = raw['manualTermKey'];
    String? manualTerm;
    if (rawTerm != null) {
      if (rawTerm is! String || !isValidTermKey(rawTerm)) {
        throw const FormatException('手动学期标识无效');
      }
      manualTerm = rawTerm;
    }
    final rawArchive = raw['archiveMode'];
    var archiveMode = CourseArchiveMode.auto;
    if (rawArchive != null) {
      if (rawArchive is! String) {
        throw const FormatException('课程归档模式格式无效');
      }
      final parsedMode = CourseArchiveMode.values
          .where((m) => m.name == rawArchive)
          .firstOrNull;
      if (parsedMode == null) {
        throw const FormatException('课程归档模式未知');
      }
      if (strict && parsedMode == CourseArchiveMode.auto) {
        throw const FormatException('课程归档默认值不应冗余序列化');
      }
      archiveMode = parsedMode;
    }
    final rawBlock = raw['blockMode'];
    var blockMode = CourseBlockMode.auto;
    if (rawBlock != null) {
      if (rawBlock is! String) {
        throw const FormatException('课程屏蔽模式格式无效');
      }
      final parsedBlock =
          CourseBlockMode.values.where((m) => m.name == rawBlock).firstOrNull;
      if (parsedBlock == null) {
        throw const FormatException('课程屏蔽模式未知');
      }
      if (strict && parsedBlock == CourseBlockMode.auto) {
        throw const FormatException('课程屏蔽默认值不应冗余序列化');
      }
      blockMode = parsedBlock;
    }
    final rawCursor = raw['dismissedRecallCursorUtc'];
    DateTime? cursorUtc;
    if (rawCursor != null) {
      if (rawCursor is! String ||
          !Assignment.hasExplicitTimeZone(rawCursor) ||
          rawCursor.length > 40) {
        throw const FormatException('召回忽略游标格式无效');
      }
      final parsed = DateTime.tryParse(rawCursor);
      if (parsed == null ||
          parsed.year < 1970 ||
          parsed.year > 2200 ||
          (strict && parsed.toUtc().toIso8601String() != rawCursor)) {
        throw const FormatException('召回忽略游标时间戳无效');
      }
      cursorUtc = parsed.toUtc();
    }
    final entry = CourseTermOverride(
      manualTermKey: manualTerm,
      archiveMode: archiveMode,
      blockMode: blockMode,
      dismissedRecallCursorUtc: cursorUtc,
    );
    if (strict && entry.isEmpty) {
      throw const FormatException('课程学期覆盖不允许空条目');
    }
    return entry;
  }

  @override
  bool operator ==(Object other) =>
      other is CourseTermOverride &&
      manualTermKey == other.manualTermKey &&
      archiveMode == other.archiveMode &&
      blockMode == other.blockMode &&
      (dismissedRecallCursorUtc == null
          ? other.dismissedRecallCursorUtc == null
          : other.dismissedRecallCursorUtc != null &&
              dismissedRecallCursorUtc!
                  .isAtSameMomentAs(other.dismissedRecallCursorUtc!));

  @override
  int get hashCode => Object.hash(
        manualTermKey,
        archiveMode,
        blockMode,
        dismissedRecallCursorUtc?.toUtc(),
      );
}

class CourseTermPreferences {
  CourseTermPreferences({
    Map<String, CourseTermOverride> entries = const {},
  }) : entries = Map.unmodifiable({
          for (final entry in entries.entries)
            if (isValidCourseKey(entry.key) && !entry.value.isEmpty)
              entry.key: entry.value,
        });

  const CourseTermPreferences.empty() : entries = const {};

  static const int maxEntries = 2000;
  static final RegExp _courseKeyPattern =
      RegExp(r'^[^\s:]{1,100}:[^\s:]{1,100}$');

  static bool isValidCourseKey(Object? raw) =>
      raw is String && _courseKeyPattern.hasMatch(raw);

  final Map<String, CourseTermOverride> entries;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  CourseTermOverride? entryFor(String courseKey) => entries[courseKey];

  CourseTermPreferences _withEntry(
    String courseKey,
    CourseTermOverride next,
  ) {
    if (!isValidCourseKey(courseKey)) return this;
    final updated = Map<String, CourseTermOverride>.from(entries);
    if (next.isEmpty) {
      updated.remove(courseKey);
    } else {
      updated[courseKey] = next;
    }
    return CourseTermPreferences(entries: updated);
  }

  CourseTermPreferences withManualTerm(String courseKey, String? termKey) {
    if (termKey != null && !CourseTermOverride.isValidTermKey(termKey)) {
      return this;
    }
    final current = entries[courseKey] ?? const CourseTermOverride();
    return _withEntry(
      courseKey,
      current.copyWith(
        manualTermKey: termKey,
        clearManualTerm: termKey == null,
      ),
    );
  }

  CourseTermPreferences withArchiveMode(
    String courseKey,
    CourseArchiveMode mode,
  ) {
    final current = entries[courseKey] ?? const CourseTermOverride();
    return _withEntry(courseKey, current.copyWith(archiveMode: mode));
  }

  CourseTermPreferences withBlockMode(
    String courseKey,
    CourseBlockMode mode,
  ) {
    final current = entries[courseKey] ?? const CourseTermOverride();
    return _withEntry(courseKey, current.copyWith(blockMode: mode));
  }

  CourseTermPreferences withDismissedRecallCursor(
    String courseKey,
    DateTime? cursorUtc,
  ) {
    final current = entries[courseKey] ?? const CourseTermOverride();
    return _withEntry(
      courseKey,
      current.copyWith(
        dismissedRecallCursorUtc: cursorUtc?.toUtc(),
        clearDismissedRecallCursor: cursorUtc == null,
      ),
    );
  }

  CourseTermPreferences withBatchArchive(Iterable<String> courseKeys) {
    final updated = Map<String, CourseTermOverride>.from(entries);
    for (final key in courseKeys) {
      if (!isValidCourseKey(key)) continue;
      final current = updated[key] ?? const CourseTermOverride();
      updated[key] = current.copyWith(archiveMode: CourseArchiveMode.archived);
    }
    return CourseTermPreferences(entries: updated);
  }

  CourseTermPreferences withBatchManualTerm(
    Iterable<String> courseKeys,
    String? termKey,
  ) {
    if (termKey != null && !CourseTermOverride.isValidTermKey(termKey)) {
      return this;
    }
    final updated = Map<String, CourseTermOverride>.from(entries);
    for (final key in courseKeys) {
      if (!isValidCourseKey(key)) continue;
      final current = updated[key] ?? const CourseTermOverride();
      final next = current.copyWith(
        manualTermKey: termKey,
        clearManualTerm: termKey == null,
      );
      if (next.isEmpty) {
        updated.remove(key);
      } else {
        updated[key] = next;
      }
    }
    return CourseTermPreferences(entries: updated);
  }

  CourseTermPreferences withBatchBlockMode(
    Iterable<String> courseKeys,
    CourseBlockMode mode,
  ) {
    final updated = Map<String, CourseTermOverride>.from(entries);
    for (final key in courseKeys) {
      if (!isValidCourseKey(key)) continue;
      final current = updated[key] ?? const CourseTermOverride();
      final next = current.copyWith(blockMode: mode);
      if (next.isEmpty) {
        updated.remove(key);
      } else {
        updated[key] = next;
      }
    }
    return CourseTermPreferences(entries: updated);
  }

  CourseTermPreferences mergeBackup(CourseTermPreferences imported) {
    if (imported.isEmpty) return this;
    final merged = Map<String, CourseTermOverride>.from(entries);
    for (final entry in imported.entries.entries) {
      if (merged.containsKey(entry.key)) continue;
      if (merged.length >= maxEntries) break;
      merged[entry.key] = entry.value;
    }
    return CourseTermPreferences(entries: merged);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'entries': {
          for (final entry in entries.entries)
            if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
        },
      };

  String encode() => jsonEncode(toJson());

  factory CourseTermPreferences.decode(String raw) {
    final decoded = jsonDecode(raw);
    return CourseTermPreferences.fromJson(decoded, strict: true);
  }

  factory CourseTermPreferences.fromJson(dynamic raw, {bool strict = false}) {
    if (raw is! Map) {
      throw const FormatException('课程学期配置格式无效');
    }
    const rootKeys = {'version', 'entries'};
    if (strict &&
        (raw.length != rootKeys.length || !rootKeys.every(raw.containsKey))) {
      throw const FormatException('课程学期配置字段无效');
    }
    if (raw['version'] != 1) {
      throw const FormatException('课程学期配置版本不受支持');
    }
    final rawEntries = raw['entries'];
    if (rawEntries is! Map || rawEntries.length > maxEntries) {
      throw const FormatException('课程学期配置条目表无效');
    }
    final parsed = <String, CourseTermOverride>{};
    for (final item in rawEntries.entries) {
      final key = item.key;
      if (!isValidCourseKey(key)) {
        throw const FormatException('课程学期配置课程标识无效');
      }
      parsed[key as String] = CourseTermOverride.fromJson(
        item.value,
        strict: strict,
      );
    }
    return CourseTermPreferences(entries: parsed);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CourseTermPreferences ||
        entries.length != other.entries.length) {
      return false;
    }
    for (final entry in entries.entries) {
      if (other.entries[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll(entries.entries.map((e) => Object.hash(e.key, e.value)));
}
