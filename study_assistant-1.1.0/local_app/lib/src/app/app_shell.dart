import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/widgets/journal_floating_nav_bar.dart';
import '../features/widgets/update_scope.dart';
import '../services/assignment_store.dart';
import '../services/interaction_feedback_service.dart';
import 'app_back_navigation_policy.dart';
import 'journal.dart';
import 'journal_motion.dart';
import 'transient_feedback.dart';
import 'unsaved_edit_guard.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.assignmentStore,
    required this.child,
    this.leaveGuard,
    this.clock,
    this.onExitApp,
    this.overlayResetListenable,
  });

  final AssignmentStore assignmentStore;
  final Widget child;
  final UnsavedEditGuard? leaveGuard;
  final DateTime Function()? clock;
  final Future<void> Function()? onExitApp;
  final Listenable? overlayResetListenable;

  static const Set<String> primaryTabPaths = {
    '/assignments',
    '/calendar',
    '/stats',
    '/profile',
  };

  /// Resolves the true top-most route URI (preserving query parameters),
  /// including imperative `push()` routes that `routeInformationProvider.value.uri`
  /// overwrites when `GoRouter.optionURLReflectsImperativeAPIs` is false.
  static Uri currentUriOf(GoRouter router) {
    final configuration = router.routerDelegate.currentConfiguration;
    final lastMatch = configuration.lastOrNull;
    if (lastMatch is ImperativeRouteMatch) {
      if (lastMatch.matches.uri.path.isNotEmpty) {
        return lastMatch.matches.uri;
      }
      if (lastMatch.matchedLocation.isNotEmpty) {
        return Uri.parse(lastMatch.matchedLocation);
      }
    }
    if (configuration.uri.path.isNotEmpty) {
      return configuration.uri;
    }
    if (lastMatch != null && lastMatch.matchedLocation.isNotEmpty) {
      return Uri.parse(lastMatch.matchedLocation);
    }
    return router.routeInformationProvider.value.uri;
  }

  /// Resolves the true top-most route path (without query parameters).
  static String currentLocationOf(GoRouter router) => currentUriOf(router).path;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  Timer? _returnTimer;
  UnsavedEditGuard? _leaveGuard;
  GoRouter? _boundRouter;
  Listenable? _routerListenable;
  late AppBackNavigationPolicy _backPolicy;
  final _exitFeedback = TransientFeedbackController();
  bool _handlingRootBack = false;
  String? _lastKnownUri;
  late int _lastAccountEpoch;
  String? _lastAccountHash;
  bool? _lastRouteIsCurrent;

  @override
  void initState() {
    super.initState();
    _backPolicy = AppBackNavigationPolicy(clock: widget.clock);
    _lastAccountEpoch = widget.assignmentStore.accountEpoch;
    _lastAccountHash = widget.assignmentStore.accountHash;
    widget.assignmentStore.addListener(_handleStoreIdentityChange);
    widget.overlayResetListenable?.addListener(_handleOverlayReset);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.assignmentStore.runDueAutoSync();
    });
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock) {
      _backPolicy = AppBackNavigationPolicy(clock: widget.clock);
    }
    if (oldWidget.assignmentStore != widget.assignmentStore) {
      oldWidget.assignmentStore.removeListener(_handleStoreIdentityChange);
      _lastAccountEpoch = widget.assignmentStore.accountEpoch;
      _lastAccountHash = widget.assignmentStore.accountHash;
      widget.assignmentStore.addListener(_handleStoreIdentityChange);
      _resetExitWindow();
    }
    if (oldWidget.overlayResetListenable != widget.overlayResetListenable) {
      oldWidget.overlayResetListenable?.removeListener(_handleOverlayReset);
      widget.overlayResetListenable?.addListener(_handleOverlayReset);
      _resetExitWindow();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _leaveGuard = widget.leaveGuard ?? UnsavedEditGuardScope.maybeOf(context);
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_lastRouteIsCurrent != null && _lastRouteIsCurrent != isCurrent) {
      _resetExitWindow();
    }
    _lastRouteIsCurrent = isCurrent;
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    widget.assignmentStore.removeListener(_handleStoreIdentityChange);
    widget.overlayResetListenable?.removeListener(_handleOverlayReset);
    _routerListenable?.removeListener(_handleRouteChange);
    _exitFeedback.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _resetExitWindow() {
    _backPolicy.resetExitWindow();
    _exitFeedback.dismiss();
  }

  void _handleOverlayReset() {
    _backPolicy.resetExitWindow();
    if (mounted) _exitFeedback.dismiss();
  }

  void _handleStoreIdentityChange() {
    final epoch = widget.assignmentStore.accountEpoch;
    final hash = widget.assignmentStore.accountHash;
    if (epoch != _lastAccountEpoch || hash != _lastAccountHash) {
      _lastAccountEpoch = epoch;
      _lastAccountHash = hash;
      _resetExitWindow();
    }
    final confirmation =
        widget.assignmentStore.consumeReturnCheckConfirmation();
    if (confirmation != null &&
        confirmation.accountEpoch == widget.assignmentStore.accountEpoch) {
      InteractionFeedback.trigger(
        widget.assignmentStore.display,
        kind: InteractionSoundKind.complete,
      );
    }
  }

  void _handleRouteChange() {
    final router = _boundRouter;
    if (router == null) return;
    final nextUri = AppShell.currentUriOf(router).toString();
    if (nextUri == _lastKnownUri) return;
    _lastKnownUri = nextUri;
    _resetExitWindow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resetExitWindow();
      _returnTimer?.cancel();
      _returnTimer = Timer(const Duration(milliseconds: 600), () async {
        await widget.assignmentStore.checkReturnedAssignment();
        if (mounted) widget.assignmentStore.runDueAutoSync();
      });
    } else {
      _returnTimer?.cancel();
      widget.assignmentStore.markAssignmentVisitLeftApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    if (!identical(_boundRouter, router)) {
      _routerListenable?.removeListener(_handleRouteChange);
      _boundRouter = router;
      _routerListenable = Listenable.merge([
        router.routerDelegate,
        router.routeInformationProvider,
      ]);
      _lastKnownUri = AppShell.currentUriOf(router).toString();
      _routerListenable!.addListener(_handleRouteChange);
    }
    return ListenableBuilder(
      listenable: _routerListenable!,
      builder: (context, _) {
        final resolved = AppShell.currentLocationOf(router);
        final location = resolved.isNotEmpty
            ? resolved
            : GoRouterState.of(context).matchedLocation;
        final showTabBar = AppShell.primaryTabPaths.contains(location);
        final canPopRoute = router.canPop();
        final updates = AppUpdateScope.maybeOf(context);

        return PopScope(
          canPop: canPopRoute,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            unawaited(_handleRootBack(router));
          },
          child: Scaffold(
            extendBody: showTabBar,
            body: SafeArea(bottom: !showTabBar, child: widget.child),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: widget.assignmentStore,
                    builder: (context, _) {
                      final message = widget.assignmentStore.returnCheckMessage;
                      if (message == null) return const SizedBox.shrink();
                      final epoch = widget.assignmentStore.accountEpoch;
                      return TimedReturnCheck(
                        key: ValueKey((epoch, message)),
                        message: message,
                        onDismiss: () {
                          if (widget.assignmentStore.accountEpoch == epoch &&
                              widget.assignmentStore.returnCheckMessage ==
                                  message) {
                            widget.assignmentStore.dismissReturnCheck();
                          }
                        },
                      );
                    },
                  ),
                  if (updates != null)
                    UpdateDownloadBanner(controller: updates),
                  AnimatedSwitcher(
                    duration: JournalMotion.duration(
                      context,
                      const Duration(milliseconds: 200),
                    ),
                    // Leaving a primary tab removes the bar at once: an outgoing
                    // bar would keep reserving layout height for 200ms and then
                    // make the pushed page jump when it finally disappeared.
                    reverseDuration: Duration.zero,
                    switchInCurve: JournalMotion.easeOut,
                    switchOutCurve: JournalMotion.easeOut,
                    transitionBuilder: (child, animation) => SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: showTabBar
                        ? JournalFloatingNavBar(
                            key: const ValueKey('journal-floating-nav'),
                            selectedIndex: _indexFor(location),
                            onSelected: (index) =>
                                unawaited(_selectDestination(index)),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('journal-floating-nav-hidden'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleRootBack(GoRouter router) async {
    if (_handlingRootBack || !mounted) return;
    _handlingRootBack = true;
    final epoch = widget.assignmentStore.accountEpoch;
    try {
      final currentUri = AppShell.currentUriOf(router);
      final canPop = router.canPop();
      final action = _backPolicy.decide(
        currentUri: currentUri,
        canPopNavigator: canPop,
      );
      switch (action) {
        case AppBackAction.popNavigator:
          if (canPop) await router.routerDelegate.popRoute();
          return;
        case AppBackAction.goHome:
          await _navigateHomeOnBack(router, epoch);
          return;
        case AppBackAction.armHomeExit:
          _showExitArmFeedback();
          return;
        case AppBackAction.exitApp:
          _exitFeedback.dismiss();
          final exit = widget.onExitApp ?? SystemNavigator.pop;
          await exit();
          return;
      }
    } finally {
      _handlingRootBack = false;
    }
  }

  Future<void> _navigateHomeOnBack(GoRouter router, int epoch) async {
    void goHome() {
      if (!mounted || widget.assignmentStore.accountEpoch != epoch) return;
      _resetExitWindow();
      router.go('/assignments');
    }

    final guard = _leaveGuard;
    if (guard == null) {
      goHome();
      return;
    }
    await guard.navigate(
      isCurrent: () => mounted && widget.assignmentStore.accountEpoch == epoch,
      action: goHome,
    );
  }

  void _showExitArmFeedback() {
    if (!mounted) return;
    final journal = Journal.of(context);
    _exitFeedback.show(
      context,
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: journal.ink,
        content: Text(
          '再滑一次退出课业手记',
          style: journal.metadata.copyWith(color: journal.onInvertedSurface),
        ),
      ),
    );
  }

  Future<void> _selectDestination(int index) async {
    Future<void> go() async {
      final router = GoRouter.of(context);
      final from = AppShell.currentUriOf(router).toString();
      final to = switch (index) {
        0 => '/assignments',
        1 => '/calendar',
        2 => '/stats',
        3 => '/profile',
        _ => null,
      };
      if (to == null) return;
      if (to != from) {
        _resetExitWindow();
        JournalMotion.tap(widget.assignmentStore.display);
      }
      router.go(to);
    }

    final guard = _leaveGuard;
    if (guard == null) {
      await go();
      return;
    }
    await guard.navigate(isCurrent: () => mounted, action: go);
  }

  int _indexFor(String location) {
    if (location.startsWith('/calendar')) return 1;
    if (location.startsWith('/stats')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }
}

class StudyAssistantTheme {
  static final light = _build(JournalPalette.light, Brightness.light);
  static final dark = _build(JournalPalette.dark, Brightness.dark);

  static ThemeData _build(JournalPalette journal, Brightness brightness) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: journal.accent,
      brightness: brightness,
      surface: journal.paper,
      primary: journal.accent,
      secondary: journal.accent,
    ).copyWith(
      onPrimary: journal.onPrimaryFill,
      secondaryContainer: journal.sage,
      onSecondaryContainer: journal.ink,
      error: journal.berry,
      onError: journal.onPrimaryFill,
      errorContainer: journal.berryBg,
      onErrorContainer: journal.berry,
      outline: journal.ruleStrong,
      outlineVariant: journal.rule,
      surfaceContainerHighest: journal.parchment,
      // Seeded tonal surfaces drift toward cold blue-grey; pin every container
      // tier to the paper palette so Material 3 pickers/menus stay warm.
      onSurface: journal.ink,
      onSurfaceVariant: journal.muted,
      surfaceDim: journal.paper,
      surfaceBright: journal.sheetElevated,
      surfaceContainerLowest: journal.paper,
      surfaceContainerLow: journal.sheet,
      surfaceContainer: journal.sheet,
      surfaceContainerHigh: journal.sheetElevated,
    );

    final baseText = Typography.material2021().black.apply(
          fontFamily: Journal.bodyFamily,
          fontFamilyFallback: Journal.bodyFallback,
          bodyColor: journal.ink,
          displayColor: journal.ink,
        );

    return ThemeData(
      colorScheme: baseScheme,
      extensions: [journal],
      scaffoldBackgroundColor: journal.paper,
      useMaterial3: true,
      fontFamily: Journal.bodyFamily,
      fontFamilyFallback: Journal.bodyFallback,
      dividerColor: journal.divider,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor:
          journal.ink.withValues(alpha: journal.isDark ? 0.08 : 0.055),
      hoverColor: journal.ink.withValues(alpha: journal.isDark ? 0.05 : 0.035),
      focusColor:
          journal.accent.withValues(alpha: journal.isDark ? 0.14 : 0.10),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: baseText,
      primaryTextTheme: baseText,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: journal.paper,
        foregroundColor: journal.ink,
        titleTextStyle: journal.pageTitle,
      ),
      cardTheme: CardThemeData(
        color: journal.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: journal.cardBorder, width: 0.8),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: journal.parchment,
        selectedColor: journal.sage,
        checkmarkColor: journal.ink,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: journal.metadata.copyWith(
          color: journal.ink,
          fontWeight: FontWeight.w500,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: journal.ink,
          backgroundColor: journal.parchment,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: journal.primaryFill,
          foregroundColor: journal.onPrimaryFill,
          disabledBackgroundColor: journal.parchment,
          disabledForegroundColor: journal.muted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: journal.ink,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? journal.onPrimaryFill
                : journal.muted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? journal.accent
                : journal.parchment),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.transparent
                : journal.ruleStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? journal.accent
                : Colors.transparent),
        checkColor: WidgetStateProperty.all(journal.onPrimaryFill),
        side: BorderSide(color: journal.ruleStrong, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: journal.sheet,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: journal.cardBorder, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: journal.cardBorder, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: journal.accent, width: 1.2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: journal.sheetElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: journal.ink,
        contentTextStyle: journal.metadata.copyWith(
          color: journal.onInvertedSurface,
        ),
        actionTextColor: journal.snackActionColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: journal.sheetElevated,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: journal.section,
        contentTextStyle: journal.metadata.copyWith(color: journal.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: journal.sheetElevated,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: journal.sheetElevated,
        headerForegroundColor: journal.ink,
        dividerColor: journal.divider,
        todayForegroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? journal.onPrimaryFill
                : journal.accent),
        todayBorder: BorderSide(color: journal.accent),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return journal.onPrimaryFill;
          }
          if (states.contains(WidgetState.disabled)) {
            return journal.muted.withValues(alpha: 0.65);
          }
          return journal.ink;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? journal.accent : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: journal.sheetElevated,
        dialBackgroundColor: journal.parchment,
        hourMinuteColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? journal.sage
                : journal.parchment),
        hourMinuteTextColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? journal.accent
                : journal.ink),
        dayPeriodBorderSide: BorderSide(color: journal.ruleStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
