import 'dart:async';
import 'package:flutter/material.dart';

import 'journal.dart';

Duration feedbackDuration({bool action = false, bool accessible = false}) =>
    Duration(seconds: accessible ? (action ? 30 : 10) : (action ? 12 : 5));

/// One-off text feedback for pages that do not own a
/// [TransientFeedbackController]. A new message replaces the visible one
/// instead of queueing behind it, and shares the app-wide duration and the
/// themed floating snackbar style.
void showJournalMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  TransientFeedbackController.revokeOwner(messenger);
  final duration =
      feedbackDuration(accessible: MediaQuery.accessibleNavigationOf(context));
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message), duration: duration));
}

/// Rounded floating container shared by the banners stacked above the
/// floating nav bar, so they match the capsule language instead of reading
/// as full-bleed Material strips.
class JournalFloatingBanner extends StatelessWidget {
  const JournalFloatingBanner({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.only(left: 16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final journal = Journal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: journal.sage,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: journal.sageBorder, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Owned by the presenting page; dispose when leaving it. The explicit timer
/// also bounds action snackbars when Flutter keeps them for accessibility.
class TransientFeedbackController {
  static final _owners = Expando<TransientFeedbackController>();

  /// Revokes any live or disposing controller's ownership of [messenger] so its
  /// pending post-frame cleanup will not dismiss a replacement snackbar.
  static void revokeOwner(ScaffoldMessengerState messenger) {
    _owners[messenger]?._forget();
    _owners[messenger] = null;
  }

  Timer? _timer;
  ScaffoldMessengerState? _messenger;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _current;
  bool _disposed = false;

  void show(BuildContext context, SnackBar bar) {
    if (_disposed) return;
    dismiss();
    final messenger = ScaffoldMessenger.of(context);
    // Revoke the previous presenter synchronously, before closing its bar can
    // complete `closed` in a microtask. Its dispose/timer must not touch ours.
    _owners[messenger]?._forget();
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    final duration = feedbackDuration(
        action: bar.action != null,
        accessible: MediaQuery.accessibleNavigationOf(context));
    final current = messenger.showSnackBar(SnackBar(
      content: bar.content,
      action: bar.action,
      duration: duration,
      behavior: bar.behavior,
      backgroundColor: bar.backgroundColor,
    ));
    _messenger = messenger;
    _owners[messenger] = this;
    _current = current;
    _timer = Timer(duration, () {
      if (identical(_current, current)) dismiss();
    });
    unawaited(current.closed.then((_) {
      if (identical(_current, current)) {
        _forget();
      }
    }));
  }

  void dismiss() {
    final messenger = _messenger;
    final ownsMessage =
        messenger != null && identical(_owners[messenger], this);
    _forget();
    // Never call a stale feature controller's close(): Flutter binds it to
    // hideCurrentSnackBar, which could close a replacement or assert.
    if (messenger != null && ownsMessage && messenger.mounted) {
      messenger.removeCurrentSnackBar();
    }
  }

  void _forget() {
    _timer?.cancel();
    _timer = null;
    _current = null;
    final messenger = _messenger;
    if (messenger != null && identical(_owners[messenger], this)) {
      _owners[messenger] = null;
    }
    _messenger = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _current = null;
    final messenger = _messenger;
    _messenger = null;
    if (messenger == null || !identical(_owners[messenger], this)) return;
    // A mounted Messenger may still contain deactivated Scaffolds during
    // route unmount. Updating its animation now calls _isRoot on an inactive
    // ancestor. Wait until disposal/unregistration finishes, retaining only
    // a revocable ownership reservation so a new presenter is never removed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_owners[messenger], this)) return;
      _owners[messenger] = null;
      if (messenger.mounted) messenger.removeCurrentSnackBar();
    });
    // A callback registered while idle does not request a frame itself. An
    // explicit dispose outside widget teardown must still finish its cleanup.
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

/// Value-keyed by the caller so unrelated Store notifications do not restart
/// the timeout and a replacement message gets its own full lifetime.
class TimedReturnCheck extends StatefulWidget {
  const TimedReturnCheck(
      {super.key, required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  State<TimedReturnCheck> createState() => _TimedReturnCheckState();
}

class _TimedReturnCheckState extends State<TimedReturnCheck> {
  Timer? _timer;
  bool? _accessible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessible = MediaQuery.accessibleNavigationOf(context);
    if (_accessible == accessible) return;
    _accessible = accessible;
    _timer?.cancel();
    _timer = Timer(feedbackDuration(accessible: accessible), widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => JournalFloatingBanner(
        child: Row(children: [
          Expanded(
              child: Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.message,
                    style: Journal.of(context)
                        .metadata
                        .copyWith(color: Journal.of(context).ink),
                  ))),
          IconButton(
              tooltip: '关闭核对提示',
              onPressed: widget.onDismiss,
              icon: const Icon(Icons.close)),
        ]),
      );
}
