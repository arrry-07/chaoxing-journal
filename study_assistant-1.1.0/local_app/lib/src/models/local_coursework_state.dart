import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'assignment.dart';

/// Account-scoped local state for individual coursework items.
///
/// Official server observations remain authoritative in [Assignment]; entries
/// here supply opt-in local overrides or flags (such as manual deadlines while
/// the official deadline is unconfirmed).
@immutable
class LocalCourseworkEntry {
  const LocalCourseworkEntry({
    this.manualDeadlineAt,
    this.officialTakenOver = false,
  });

  final DateTime? manualDeadlineAt;
  final bool officialTakenOver;

  bool get isEmpty => manualDeadlineAt == null;

  LocalCourseworkEntry copyWith({
    DateTime? manualDeadlineAt,
    bool clearManualDeadlineAt = false,
    bool? officialTakenOver,
  }) {
    final nextManual = clearManualDeadlineAt
        ? null
        : manualDeadlineAt ?? this.manualDeadlineAt;
    return LocalCourseworkEntry(
      manualDeadlineAt: nextManual,
      officialTakenOver: nextManual == null
          ? false
          : (officialTakenOver ?? this.officialTakenOver),
    );
  }

  Map<String, dynamic> toJson() => {
        'manualDeadlineAt': manualDeadlineAt?.toUtc().toIso8601String(),
        'officialTakenOver': manualDeadlineAt != null && officialTakenOver,
      };

  static LocalCourseworkEntry fromJson(dynamic raw, {bool strict = false}) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('课业本地状态条目格式无效');
    }
    if (strict &&
        (raw.length != 2 ||
            !raw.containsKey('manualDeadlineAt') ||
            !raw.containsKey('officialTakenOver'))) {
      throw const FormatException('课业本地状态字段校验失败');
    }
    final rawTakenOver = raw['officialTakenOver'];
    if (rawTakenOver is! bool) {
      throw const FormatException('官方接管标记类型无效');
    }
    final manualRaw = raw['manualDeadlineAt'];
    DateTime? manualDeadlineAt;
    if (manualRaw != null) {
      if (manualRaw is! String ||
          manualRaw.length > 40 ||
          !Assignment.hasExplicitTimeZone(manualRaw)) {
        throw const FormatException('手动截止时间格式无效');
      }
      final parsed = DateTime.tryParse(manualRaw);
      if (parsed == null ||
          parsed.year < 1970 ||
          parsed.year > 2200 ||
          parsed.toUtc().toIso8601String() != manualRaw) {
        throw const FormatException('手动截止时间校验失败');
      }
      manualDeadlineAt = parsed.toLocal();
    }
    return LocalCourseworkEntry(
      manualDeadlineAt: manualDeadlineAt,
      officialTakenOver: manualDeadlineAt != null && rawTakenOver,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LocalCourseworkEntry) return false;
    final leftUtc = manualDeadlineAt?.toUtc();
    final rightUtc = other.manualDeadlineAt?.toUtc();
    return leftUtc == rightUtc && officialTakenOver == other.officialTakenOver;
  }

  @override
  int get hashCode => Object.hash(manualDeadlineAt?.toUtc(), officialTakenOver);
}

@immutable
class LocalCourseworkState {
  LocalCourseworkState({
    Map<String, LocalCourseworkEntry> entries = const {},
  }) : entries = Map.unmodifiable({
          for (final entry in entries.entries)
            if (entry.key.trim().isNotEmpty && !entry.value.isEmpty)
              entry.key.trim(): entry.value,
        });

  const LocalCourseworkState.empty()
      : entries = const <String, LocalCourseworkEntry>{};

  static final RegExp _forbiddenKeyPattern =
      RegExp(r'(?:https?:|[\x00-\x1f])', caseSensitive: false);
  static const int _maxEntries = 5000;
  static const int _maxKeyLength = 300;

  final Map<String, LocalCourseworkEntry> entries;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  LocalCourseworkEntry? entryForAliases(Iterable<String> aliases) {
    if (entries.isEmpty) return null;
    for (final raw in aliases) {
      final key = raw.trim();
      if (key.isEmpty) continue;
      final found = entries[key];
      if (found != null) return found;
    }
    return null;
  }

  LocalCourseworkState withEntry(
    String canonicalKey,
    Iterable<String> aliases,
    LocalCourseworkEntry? nextEntry,
  ) {
    final cleanKey = canonicalKey.trim();
    if (cleanKey.isEmpty) return this;
    final aliasSet = <String>{
      cleanKey,
      for (final raw in aliases)
        if (raw.trim().isNotEmpty) raw.trim(),
    };
    final next = <String, LocalCourseworkEntry>{
      for (final item in entries.entries)
        if (!aliasSet.contains(item.key)) item.key: item.value,
    };
    if (nextEntry != null && !nextEntry.isEmpty) {
      next[cleanKey] = nextEntry;
    }
    return LocalCourseworkState(entries: next);
  }

  LocalCourseworkState withManualDeadline(
    String canonicalKey,
    Iterable<String> aliases,
    DateTime? deadlineAt,
  ) {
    if (deadlineAt == null) {
      return withEntry(canonicalKey, aliases, null);
    }
    final existing = entryForAliases(aliases);
    return withEntry(
      canonicalKey,
      aliases,
      (existing ?? const LocalCourseworkEntry()).copyWith(
        manualDeadlineAt: deadlineAt.toLocal(),
        officialTakenOver: false,
      ),
    );
  }

  /// Non-destructively merges imported backup entries: local entries win per key.
  LocalCourseworkState mergeBackup(LocalCourseworkState imported) {
    if (imported.isEmpty) return this;
    if (isEmpty) return imported;
    final merged = <String, LocalCourseworkEntry>{...entries};
    for (final entry in imported.entries.entries) {
      merged.putIfAbsent(entry.key, () => entry.value);
    }
    return LocalCourseworkState(entries: merged);
  }

  Map<String, dynamic> toJson() => {
        'entries': {
          for (final entry in entries.entries) entry.key: entry.value.toJson(),
        },
      };

  String encode() => jsonEncode(toJson());

  static LocalCourseworkState decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const LocalCourseworkState.empty();
    }
    final decoded = jsonDecode(raw);
    return fromJson(decoded, strict: true);
  }

  static LocalCourseworkState fromJson(dynamic raw, {bool strict = false}) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('课业本地状态格式无效');
    }
    if (strict && (raw.length != 1 || !raw.containsKey('entries'))) {
      throw const FormatException('课业本地状态顶层字段校验失败');
    }
    final entriesRaw = raw['entries'];
    if (entriesRaw is! Map<String, dynamic> ||
        entriesRaw.length > _maxEntries) {
      throw const FormatException('课业本地状态列表无效');
    }
    final parsed = <String, LocalCourseworkEntry>{};
    for (final item in entriesRaw.entries) {
      final key = item.key;
      if (key.trim().isEmpty ||
          key != key.trim() ||
          key.length > _maxKeyLength ||
          _forbiddenKeyPattern.hasMatch(key)) {
        throw const FormatException('课业本地状态包含非法标识');
      }
      final value = LocalCourseworkEntry.fromJson(item.value, strict: strict);
      if (value.isEmpty) {
        if (strict) throw const FormatException('课业本地状态不允许空条目');
        continue;
      }
      parsed[key] = value;
    }
    return LocalCourseworkState(entries: parsed);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalCourseworkState && mapEquals(entries, other.entries);
  }

  @override
  int get hashCode =>
      Object.hashAll(entries.entries.map((e) => Object.hash(e.key, e.value)));
}
