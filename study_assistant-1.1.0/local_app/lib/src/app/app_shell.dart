import '../features/widgets/update_scope.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';
import '../services/interaction_feedback_service.dart';
import 'journal.dart';
import 'unsaved_edit_guard.dart';
import 'transient_feedback.dart';

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
        final fromParam = configUri.queryParameters['from'] ??
            routerState.uri.queryParameters['from'];
        final hideTabBar = location.startsWith('/assignments/');
        return Scaffold(
          body: SafeArea(bottom: false, child: widget.child),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                  }),
              if (AppUpdateScope.maybeOf(context) case final updates?)
                UpdateDownloadBanner(controller: updates),
              if (!hideTabBar)
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: Journal.of(context).rule)),
                  ),
                  child: NavigationBar(
                    height: 72,
                    selectedIndex: _indexFor(location, from: fromParam),
                    onDestinationSelected: (index) {
                      unawaited(_selectDestination(index));
                    },
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.assignment_outlined),
                        selectedIcon: Icon(Icons.assignment),
                        label: '首页',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.calendar_today_outlined),
                        selectedIcon: Icon(Icons.calendar_today),
                        label: '日历',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.bar_chart_outlined),
                        selectedIcon: Icon(Icons.bar_chart),
                        label: '统计',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline),
                        selectedIcon: Icon(Icons.person),
                        label: '我的',
                      ),
                    ],
                  ),
                ),
            ]),
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
        InteractionFeedback.trigger(widget.assignmentStore.display);
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

  int _indexFor(String location, {String? from}) {
    if (location.startsWith('/calendar')) {
      return 1;
    }
    if (location.startsWith('/stats') ||
        (location.startsWith('/records') && from == 'stats')) {
      return 2;
    }
    if (location.startsWith('/profile') ||
        location.startsWith('/sync') ||
        location.startsWith('/reminders') ||
        location.startsWith('/courses') ||
        location.startsWith('/records') ||
        location.startsWith('/help') ||
        location.startsWith('/changes') ||
        location.startsWith('/backup') ||
        location.startsWith('/reminder-health') ||
        location.startsWith('/reminder-history') ||
        location.startsWith('/reminder-status/manual') ||
        location.startsWith('/reminder-status/summary') ||
        location.startsWith('/agenda') ||
        location.startsWith('/terms') ||
        location.startsWith('/plan') ||
        location.startsWith('/personal') ||
        location.startsWith('/course-hub')) {
      return 3;
    }
    return 0;
  }
}

class StudyAssistantTheme {
  static final light = _build(JournalPalette.light, Brightness.light);
  static final dark = _build(JournalPalette.dark, Brightness.dark);

  static ThemeData _build(JournalPalette journal, Brightness brightness) {
    final onAccent = journal == JournalPalette.dark
        ? JournalPalette.dark.paper
        : journal.sheet;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: journal.accent,
      brightness: brightness,
      surface: journal.paper,
      primary: journal.accent,
      secondary: journal.berry,
    ).copyWith(
      onPrimary: onAccent,
      secondaryContainer: journal.sage,
      onSecondaryContainer: journal.ink,
      error: journal.berry,
      onError: journal.sheet,
      errorContainer: journal.berryBg,
      onErrorContainer: journal.berry,
      outline: journal.ruleStrong,
      outlineVariant: journal.rule,
      surfaceContainerHighest: journal.parchment,
    );
    return ThemeData(
      colorScheme: baseScheme,
      scaffoldBackgroundColor: journal.paper,
      useMaterial3: true,
      fontFamily: Journal.bodyFamily,
      fontFamilyFallback: Journal.bodyFallback,
      dividerColor: journal.rule,
      textTheme: Typography.material2021().black.apply(
            fontFamily: Journal.bodyFamily,
            fontFamilyFallback: Journal.bodyFallback,
            bodyColor: journal.ink,
            displayColor: journal.ink,
          ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: journal.paper,
        foregroundColor: journal.ink,
        titleTextStyle: journal.section,
      ),
      cardTheme: CardThemeData(
        color: journal.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: journal.rule, width: 0.8),
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
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: journal.accent,
          foregroundColor: onAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? journal.accent : null),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: journal.sheet,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: journal.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: journal.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: journal.accent, width: 1.2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: journal.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: journal.ink,
        contentTextStyle: journal.metadata.copyWith(color: journal.sheet),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: journal.sheet,
        surfaceTintColor: Colors.transparent,
        indicatorColor: journal.sage,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? journal.ink
                  : journal.muted,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: Journal.bodyFamily,
              fontFamilyFallback: Journal.bodyFallback,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? journal.ink
                  : journal.muted,
            )),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: journal.sheet,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: journal.section,
        contentTextStyle: journal.metadata.copyWith(color: journal.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
