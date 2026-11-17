import 'dart:async';

import 'package:flutter/material.dart';

typedef UnsavedEditConfirmation = Future<bool> Function();

/// Coordinates draft exits, including tabs, notifications and route onExit.
/// Approval exists only inside a navigation transaction, never on the page.
class UnsavedEditGuard {
  final List<_UnsavedEditEntry> _entries = [];
  final Set<DialogRoute<bool>> _dialogs = {};
  _PendingConfirmation? _pending;
  _ExitApproval? _approval;
  int _generation = 0;
  int _request = 0;

  bool get hasUnsavedChanges =>
      _entries.any((entry) => !entry.isStale() && entry.hasUnsavedChanges());

  void register(
    Object owner, {
    required bool Function() hasUnsavedChanges,
    required UnsavedEditConfirmation confirmDiscard,
    bool Function()? isStale,
    Object Function()? draftRevision,
    bool Function()? blocksNavigation,
    String? routeScope,
  }) {
    unregister(owner);
    _entries.add(_UnsavedEditEntry(
      owner: owner,
      hasUnsavedChanges: hasUnsavedChanges,
      confirmDiscard: confirmDiscard,
      isStale: isStale,
      draftRevision: draftRevision,
      blocksNavigation: blocksNavigation,
      routeScope: routeScope,
    ));
  }

  void unregister(Object owner) {
    _entries.removeWhere((entry) => identical(entry.owner, owner));
  }

  /// Account change/logout must cancel the old dialog, not the new page's one.
  void invalidate() {
    _generation++;
    _request++;
    _pending = null;
    _approval = null;
    for (final route in _dialogs.toList()) {
      if (route.isActive) route.navigator?.removeRoute(route, false);
    }
    _dialogs.clear();
  }

  /// A same-location/no-op request supersedes older queued destinations too.
  void cancelNavigation() => invalidate();

  _UnsavedEditEntry? _sourceFor({Object? owner, String? routeScope}) {
    if (owner != null) {
      for (final entry in _entries.reversed) {
        if (identical(entry.owner, owner) && !entry.isStale()) return entry;
      }
      return null;
    }
    _UnsavedEditEntry? fallback;
    for (final entry in _entries.reversed) {
      if (entry.isStale()) continue;
      if (routeScope != null &&
          entry.routeScope != null &&
          entry.routeScope != routeScope) {
        continue;
      }
      fallback ??= entry;
      if (entry.hasUnsavedChanges()) return entry;
    }
    return fallback;
  }

  bool _matches(
    _ExitApproval stamp, {
    Object? owner,
    String? routeScope,
  }) {
    if (stamp.generation != _generation) return false;
    final current = _sourceFor(owner: owner, routeScope: routeScope);
    if (stamp.source == null) return current == null;
    if (!_entries.contains(stamp.source) ||
        stamp.source!.isStale() ||
        stamp.revision != stamp.source!.revision) {
      return false;
    }
    if (identical(stamp.source, current)) return true;
    return routeScope != null &&
        (stamp.source!.routeScope == null ||
            stamp.source!.routeScope == routeScope);
  }

  _ExitApproval _stamp({Object? owner, String? routeScope}) {
    final source = _sourceFor(owner: owner, routeScope: routeScope);
    return _ExitApproval(
      _generation,
      source,
      source?.revision,
    );
  }

  /// Shared precheck and onExit reuse one approval only while [action] settles.
  /// Awaiters compete before invoking any navigation: last valid request wins.
  Future<void> navigate({
    Object? owner,
    required bool Function() isCurrent,
    required FutureOr<void> Function() action,
  }) async {
    if (!isCurrent()) return;
    final request = ++_request;
    final stamp = _stamp(owner: owner);
    if (!await confirmLeave(owner: owner)) return;
    if (request != _request || !isCurrent() || !_matches(stamp, owner: owner)) {
      return;
    }
    _approval = stamp;
    try {
      await action();
      // GoRouter.go returns before its onExit parse; keep the transaction only
      // through this frame, including pageless routes being removed by go.
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      if (identical(_approval, stamp)) _approval = null;
    }
  }

  Future<bool> confirmLeave({Object? owner, String? routeScope}) async {
    // Saving is a hard block, even when the same draft was just approved.
    for (final entry in _entries.reversed) {
      if (entry.isStale()) continue;
      if (owner != null && !identical(entry.owner, owner)) continue;
      if (routeScope != null &&
          entry.routeScope != null &&
          entry.routeScope != routeScope) {
        continue;
      }
      if (entry.blocksNavigation()) {
        await entry.confirmDiscard();
        return false;
      }
    }
    final entry = _sourceFor(owner: owner, routeScope: routeScope);
    if (entry == null || !entry.hasUnsavedChanges()) return true;
    final approval = _approval;
    if (approval != null &&
        _matches(approval, owner: owner, routeScope: routeScope)) {
      return true;
    }
    final stamp = _ExitApproval(_generation, entry, entry.revision);
    final pending = _pending;
    if (pending != null && pending.stamp.sameAs(stamp)) {
      return pending.result;
    }
    final confirmation = _PendingConfirmation(
      stamp,
      Future<bool>.sync(entry.confirmDiscard).then(
          (leave) => leave && _matches(stamp) && !entry.blocksNavigation()),
    );
    _pending = confirmation;
    try {
      return await confirmation.result;
    } finally {
      if (identical(_pending, confirmation)) _pending = null;
    }
  }

  Future<bool?> showConfirmation({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final route = DialogRoute<bool>(context: context, builder: builder);
    _dialogs.add(route);
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      _dialogs.remove(route);
    }
  }
}

Future<bool?> showUnsavedEditDialog({
  required BuildContext context,
  required UnsavedEditGuard? guard,
  required WidgetBuilder builder,
}) =>
    guard == null
        ? showDialog<bool>(context: context, builder: builder)
        : guard.showConfirmation(context: context, builder: builder);

class UnsavedEditGuardScope extends InheritedWidget {
  const UnsavedEditGuardScope({
    super.key,
    required this.guard,
    required super.child,
  });

  final UnsavedEditGuard guard;

  static UnsavedEditGuard? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<UnsavedEditGuardScope>()
      ?.guard;

  @override
  bool updateShouldNotify(UnsavedEditGuardScope oldWidget) =>
      !identical(guard, oldWidget.guard);
}

class _UnsavedEditEntry {
  _UnsavedEditEntry({
    required this.owner,
    required this.hasUnsavedChanges,
    required this.confirmDiscard,
    required bool Function()? isStale,
    required Object Function()? draftRevision,
    required bool Function()? blocksNavigation,
    this.routeScope,
  })  : _isStale = isStale,
        _draftRevision = draftRevision,
        _blocksNavigation = blocksNavigation;

  final Object owner;
  final bool Function() hasUnsavedChanges;
  final UnsavedEditConfirmation confirmDiscard;
  final String? routeScope;
  final bool Function()? _isStale;
  final Object Function()? _draftRevision;
  final bool Function()? _blocksNavigation;
  bool isStale() => _isStale?.call() ?? false;
  Object? get revision => _draftRevision?.call();
  bool blocksNavigation() => _blocksNavigation?.call() ?? false;
}

class _ExitApproval {
  const _ExitApproval(this.generation, this.source, this.revision);
  final int generation;
  final _UnsavedEditEntry? source;
  final Object? revision;

  bool sameAs(_ExitApproval other) =>
      generation == other.generation &&
      identical(source, other.source) &&
      revision == other.revision;
}

class _PendingConfirmation {
  _PendingConfirmation(this.stamp, this.result);
  final _ExitApproval stamp;
  final Future<bool> result;
}
