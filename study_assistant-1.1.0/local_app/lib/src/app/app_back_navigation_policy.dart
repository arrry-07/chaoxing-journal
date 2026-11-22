import 'package:flutter/widgets.dart';

enum AppBackAction {
  popNavigator,
  goHome,
  armHomeExit,
  exitApp,
}

/// Evaluates Android system back priority without reaching into Navigator
/// internals: active modals/routes pop first, stackless recovery/deep links
/// and secondary tabs return to `/assignments`, and clean home exits only on
/// a second back within [exitWindow].
class AppBackNavigationPolicy {
  AppBackNavigationPolicy({
    DateTime Function()? clock,
    this.exitWindow = const Duration(seconds: 2),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration exitWindow;
  DateTime? _lastHomeBackAt;

  static bool isCleanHome(Uri uri) =>
      uri.path == '/assignments' && !uri.hasQuery;

  void resetExitWindow() {
    _lastHomeBackAt = null;
  }

  AppBackAction decide({
    required Uri currentUri,
    required bool canPopNavigator,
  }) {
    if (canPopNavigator) {
      resetExitWindow();
      return AppBackAction.popNavigator;
    }
    if (!isCleanHome(currentUri)) {
      resetExitWindow();
      return AppBackAction.goHome;
    }
    final now = _clock();
    final previous = _lastHomeBackAt;
    if (previous != null) {
      final elapsed = now.difference(previous);
      if (!elapsed.isNegative && elapsed <= exitWindow) {
        resetExitWindow();
        return AppBackAction.exitApp;
      }
    }
    _lastHomeBackAt = now;
    return AppBackAction.armHomeExit;
  }
}

class OverlayResetNotifier extends ChangeNotifier {
  void markChanged() => notifyListeners();
}

/// Notifies [AppShell] whenever any page or modal route pushes/pops so the
/// 2-second home exit timer never carries across an overlay interaction.
class AppNavigationObserver extends NavigatorObserver {
  AppNavigationObserver(this.onRouteChanged);

  final VoidCallback onRouteChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onRouteChanged();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onRouteChanged();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onRouteChanged();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      onRouteChanged();
}
