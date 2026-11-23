import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Account-scoped ordered pinned coursework keys with explicit manual-order bit.
@immutable
class PinnedAssignments {
  const PinnedAssignments._({
    required this.keys,
    required this.manuallyOrdered,
  });

  factory PinnedAssignments({
    Iterable<String> keys = const <String>[],
    bool manuallyOrdered = false,
  }) {
    final cleaned = <String>[];
    final seen = <String>{};
    for (final raw in keys) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      cleaned.add(trimmed);
    }
    return PinnedAssignments._(
      keys: List<String>.unmodifiable(cleaned),
      manuallyOrdered:
          cleaned.length <= 1 && !manuallyOrdered ? false : manuallyOrdered,
    );
  }

  const PinnedAssignments.empty()
      : keys = const <String>[],
        manuallyOrdered = false;

  /// Migrates legacy v1 unordered set of IDs with no manual order implied.
  factory PinnedAssignments.fromLegacyV1(Iterable<String> ids) {
    final sorted = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return PinnedAssignments._(
      keys: List<String>.unmodifiable(sorted),
      manuallyOrdered: false,
    );
  }

  static final RegExp _forbiddenKeyPattern =
      RegExp(r'(?:https?:|[\x00-\x1f])', caseSensitive: false);
  static const int _maxKeys = 500;
  static const int _maxKeyLength = 300;

  final List<String> keys;
  final bool manuallyOrdered;

  bool get isEmpty => keys.isEmpty;
  bool get isNotEmpty => keys.isNotEmpty;

  bool containsAny(Iterable<String> aliases) {
    if (keys.isEmpty) return false;
    final set = keys.toSet();
    return aliases.any(set.contains);
  }

  PinnedAssignments toggle(String canonicalKey, Iterable<String> aliases) {
    final cleanCanonical = canonicalKey.trim();
    if (cleanCanonical.isEmpty) return this;
    final aliasSet = <String>{
      cleanCanonical,
      for (final a in aliases)
        if (a.trim().isNotEmpty) a.trim(),
    };
    final alreadyPinned = keys.any(aliasSet.contains);
    final next = <String>[
      for (final k in keys)
        if (!aliasSet.contains(k)) k,
      if (!alreadyPinned) cleanCanonical,
    ];
    return PinnedAssignments(
      keys: next,
      manuallyOrdered: next.isEmpty ? false : manuallyOrdered,
    );
  }

  /// Migrates legacy/notice aliases in-place while retaining pins temporarily
  /// excluded from partial syncs, previews, or unfollowed courses. Only
  /// explicitly completed or hidden coursework keys are removed.
  PinnedAssignments migrateAndPrune({
    required Map<String, String> aliasToCanonical,
    required Set<String> explicitlyCompletedOrHiddenKeys,
  }) {
    if (keys.isEmpty) return this;
    final next = <String>[];
    final seen = <String>{};
    for (final existing in keys) {
      final canonical = aliasToCanonical[existing] ?? existing;
      if (explicitlyCompletedOrHiddenKeys.contains(existing) ||
          explicitlyCompletedOrHiddenKeys.contains(canonical)) {
        continue;
      }
      if (seen.add(canonical)) {
        next.add(canonical);
      }
    }
    return PinnedAssignments(
      keys: next,
      manuallyOrdered: next.isEmpty ? false : manuallyOrdered,
    );
  }

  /// Reorders only currently visible pinned slots in-place while keeping
  /// hidden/out-of-scope pinned keys anchored in their original slots.
  PinnedAssignments? reorderVisible(
    List<String> visibleOrderedKeys,
    Set<String> visibleKeySet,
  ) {
    if (visibleOrderedKeys.length != visibleKeySet.length) return null;
    if (!visibleOrderedKeys.toSet().containsAll(visibleKeySet)) return null;
    final currentSet = keys.toSet();
    if (!currentSet.containsAll(visibleKeySet)) return null;

    var cursor = 0;
    final next = <String>[
      for (final k in keys)
        if (visibleKeySet.contains(k)) visibleOrderedKeys[cursor++] else k,
    ];
    return PinnedAssignments(keys: next, manuallyOrdered: true);
  }

  List<T> orderItems<T>(
    List<T> items, {
    required String Function(T item) keyOf,
    required int Function(T left, T right) defaultComparator,
  }) {
    final sorted = List<T>.of(items);
    if (!manuallyOrdered) {
      sorted.sort(defaultComparator);
      return sorted;
    }
    final slotByKey = <String, int>{
      for (var i = 0; i < keys.length; i++) keys[i]: i,
    };
    sorted.sort((left, right) {
      final li = slotByKey[keyOf(left)];
      final ri = slotByKey[keyOf(right)];
      if (li != null && ri != null) return li.compareTo(ri);
      if (li != null) return -1;
      if (ri != null) return 1;
      return defaultComparator(left, right);
    });
    return sorted;
  }

  PinnedAssignments mergeBackup(PinnedAssignments imported) {
    if (imported.isEmpty && !imported.manuallyOrdered) return this;
    if (isEmpty) return imported;
    if (manuallyOrdered) {
      return PinnedAssignments(
        keys: [...keys, ...imported.keys],
        manuallyOrdered: true,
      );
    }
    if (imported.manuallyOrdered) {
      return PinnedAssignments(
        keys: [...imported.keys, ...keys],
        manuallyOrdered: true,
      );
    }
    return PinnedAssignments(
      keys: [...keys, ...imported.keys],
      manuallyOrdered: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'keys': keys,
        'manuallyOrdered': manuallyOrdered,
      };

  String encode() => jsonEncode(toJson());

  static PinnedAssignments decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const PinnedAssignments.empty();
    }
    final decoded = jsonDecode(raw);
    return fromJson(decoded, strict: true);
  }

  static PinnedAssignments fromJson(dynamic raw, {bool strict = false}) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('置顶记录格式无效');
    }
    if (strict &&
        (raw.length != 2 ||
            !raw.containsKey('keys') ||
            !raw.containsKey('manuallyOrdered'))) {
      throw const FormatException('置顶记录字段完整度校验失败');
    }
    final rawKeys = raw['keys'];
    final rawManual = raw['manuallyOrdered'];
    if (rawKeys is! List || rawKeys.length > _maxKeys || rawManual is! bool) {
      throw const FormatException('置顶记录类型校验失败');
    }
    final parsed = <String>[];
    final seen = <String>{};
    for (final entry in rawKeys) {
      if (entry is! String ||
          entry.length > _maxKeyLength ||
          entry.trim().isEmpty ||
          entry != entry.trim() ||
          _forbiddenKeyPattern.hasMatch(entry)) {
        throw const FormatException('置顶记录存在非法课业标识');
      }
      if (!seen.add(entry)) {
        if (strict) {
          throw const FormatException('置顶记录存在重复课业标识');
        }
        continue;
      }
      parsed.add(entry);
    }
    return PinnedAssignments._(
      keys: List<String>.unmodifiable(parsed),
      manuallyOrdered: rawManual,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PinnedAssignments &&
          manuallyOrdered == other.manuallyOrdered &&
          listEquals(keys, other.keys);

  @override
  int get hashCode => Object.hash(manuallyOrdered, Object.hashAll(keys));
}
