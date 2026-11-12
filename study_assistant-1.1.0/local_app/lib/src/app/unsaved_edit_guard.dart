import 'package:flutter/widgets.dart';

/// Asks a page to confirm leaving while it still holds unsaved edits.
typedef UnsavedEditConfirmation = Future<bool> Function();

/// Shared guard for pages with unsaved drafts.
///
/// Pages register themselves while mounted. Route replacements (bottom tabs,
/// notification deep links, GoRoute.onExit) and back navigation all ask the
/// same guard, so a single confirmation covers the whole exit and concurrent
/// requests share one dialog. Registrations are removed when the page is
/// disposed; no draft content is stored outside the page itself.
class UnsavedEditGuard {
  final List<_UnsavedEditEntry> _entries = [];
  Future<bool>? _pendingConfirmation;

  bool get hasUnsavedChanges =>
      _entries.any((entry) => entry.hasUnsavedChanges() && !entry.isStale());

  void register(
    Object owner, {
    required bool Function() hasUnsavedChanges,
    required UnsavedEditConfirmation confirmDiscard,
    bool Function()? isStale,
  }) {
    unregister(owner);
    _entries.add(_UnsavedEditEntry(
      owner: owner,
      hasUnsavedChanges: hasUnsavedChanges,
      confirmDiscard: confirmDiscard,
      isStale: isStale,
    ));
  }

  void unregister(Object owner) {
    _entries.removeWhere((entry) => identical(entry.owner, owner));
  }

  /// Returns true when navigation may continue.
  ///
  /// A stale registration (account change or logout) never blocks cleanup.
  /// Once the user confirms, the entry stays approved until it is disposed so
  /// a back confirmation and the following route exit do not prompt twice.
  Future<bool> confirmLeave() {
    // A stale page (account switch/logout) must never be blocked by a dialog
    // that belongs to the previous account.
    if (!hasUnsavedChanges) return Future<bool>.value(true);
    final pending = _pendingConfirmation;
    if (pending != null) return pending;
    final entry = _topDirtyEntry();
    if (entry == null || entry.leaveApproved) {
      return Future<bool>.value(true);
    }
    if (entry.isStale()) return Future<bool>.value(true);

    final confirmation = entry.confirmDiscard().then((leave) {
      if (leave) entry.leaveApproved = true;
      return leave;
    });
    _pendingConfirmation = confirmation;
    return confirmation.whenComplete(() {
      if (identical(_pendingConfirmation, confirmation)) {
        _pendingConfirmation = null;
      }
    });
  }

  _UnsavedEditEntry? _topDirtyEntry() {
    for (final entry in _entries.reversed) {
      if (!entry.hasUnsavedChanges()) continue;
      if (entry.isStale()) continue;
      return entry;
    }
    return null;
  }
}

/// Exposes the app-wide [UnsavedEditGuard] to pages and the shell.
class UnsavedEditGuardScope extends InheritedWidget {
  const UnsavedEditGuardScope({
    super.key,
    required this.guard,
    required super.child,
  });

  final UnsavedEditGuard guard;

  static UnsavedEditGuard? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<UnsavedEditGuardScope>()
        ?.guard;
  }

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
  }) : _isStaleCheck = isStale;

  final Object owner;
  final bool Function() hasUnsavedChanges;
  final UnsavedEditConfirmation confirmDiscard;
  final bool Function()? _isStaleCheck;
  bool leaveApproved = false;

  bool isStale() => _isStaleCheck?.call() ?? false;
}
