import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/widgets/journal_floating_nav_bar.dart';
import '../features/widgets/update_scope.dart';
import '../services/assignment_store.dart';
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
  });

  final AssignmentStore assignmentStore;
  final Widget child;
  final UnsavedEditGuard? leaveGuard;

  static const Set<String> primaryTabPaths = {
    '/assignments',
    '/calendar',
    '/stats',
    '/profile',
  };

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  Timer? _returnTimer;
  UnsavedEditGuard? _leaveGuard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.assignmentStore.runDueAutoSync();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _leaveGuard = widget.leaveGuard ?? UnsavedEditGuardScope.maybeOf(context);
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
    return ListenableBuilder(
      listenable: router.routeInformationProvider,
      builder: (context, _) {
        final routerState = GoRouterState.of(context);
        final configUri = router.routeInformationProvider.value.uri;
        final location = configUri.path.isNotEmpty
            ? configUri.path
            : routerState.matchedLocation;
        final showTabBar = AppShell.primaryTabPaths.contains(location);
        final updates = AppUpdateScope.maybeOf(context);

        return Scaffold(
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
                if (updates != null) UpdateDownloadBanner(controller: updates),
                AnimatedSwitcher(
                  duration: JournalMotion.duration(
                    context,
                    const Duration(milliseconds: 200),
                  ),
                  switchInCurve: JournalMotion.easeOut,
                  switchOutCurve: Curves.easeInCubic,
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
        );
      },
    );
  }

  Future<void> _selectDestination(int index) async {
    Future<void> go() async {
      final router = GoRouter.of(context);
      final from = router.routeInformationProvider.value.uri.path;
      final to = switch (index) {
        0 => '/assignments',
        1 => '/calendar',
        2 => '/stats',
        3 => '/profile',
        _ => null,
      };
      if (to == null) return;
      if (to != from) {
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
      textTheme: baseText,
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
                ? Colors.white
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
        checkColor: WidgetStateProperty.all(Colors.white),
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
          color: journal.onPrimaryFill,
        ),
        actionTextColor: journal.isDark ? journal.slate : journal.slateBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: journal.sheetElevated,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: journal.section,
        contentTextStyle: journal.metadata.copyWith(color: journal.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
