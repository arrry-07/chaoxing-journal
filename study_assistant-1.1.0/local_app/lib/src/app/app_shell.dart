import '../features/widgets/update_scope.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';
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
          body: SafeArea(bottom: hideTabBar, child: widget.child),
          bottomNavigationBar:
              Column(mainAxisSize: MainAxisSize.min, children: [
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
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Journal.rule)),
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
        );
      },
    );
  }

  Future<void> _selectDestination(int index) async {
    Future<void> go() async {
      switch (index) {
        case 0:
          context.go('/assignments');
          break;
        case 1:
          context.go('/calendar');
          break;
        case 2:
          context.go('/stats');
          break;
        case 3:
          context.go('/profile');
          break;
      }
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
  static ThemeData get light {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: Journal.ink,
      brightness: Brightness.light,
      surface: Journal.paper,
      primary: Journal.ink,
      secondary: Journal.berry,
    ).copyWith(
      onPrimary: Journal.sheet,
      secondaryContainer: Journal.sage,
      onSecondaryContainer: Journal.ink,
      error: Journal.berry,
      onError: Journal.sheet,
      errorContainer: Journal.berryBg,
      onErrorContainer: Journal.berry,
      outline: Journal.ruleStrong,
      outlineVariant: Journal.rule,
      surfaceContainerHighest: Journal.parchment,
    );
    return ThemeData(
      colorScheme: baseScheme,
      scaffoldBackgroundColor: Journal.paper,
      useMaterial3: true,
      fontFamily: Journal.uiSansFamily,
      fontFamilyFallback: Journal.uiSansFallback,
      dividerColor: Journal.rule,
      textTheme: Typography.material2021().black.apply(
            fontFamily: Journal.uiSansFamily,
            fontFamilyFallback: Journal.uiSansFallback,
            bodyColor: Journal.ink,
            displayColor: Journal.ink,
          ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Journal.paper,
        foregroundColor: Journal.ink,
        titleTextStyle: Journal.section,
      ),
      cardTheme: CardThemeData(
        color: Journal.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Journal.rule),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Journal.sheet,
        selectedColor: Journal.sage,
        checkmarkColor: Journal.ink,
        side: const BorderSide(color: Journal.ruleStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: Journal.metadata.copyWith(
          color: Journal.ink,
          fontWeight: FontWeight.w500,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Journal.ink,
          side: const BorderSide(color: Journal.ruleStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Journal.ink,
          foregroundColor: Journal.sheet,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Journal.sheet,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Journal.ruleStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Journal.ruleStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Journal.ink, width: 1.5),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Journal.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Journal.ink,
        contentTextStyle: Journal.metadata.copyWith(color: Journal.sheet),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Journal.sheet,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Journal.sage,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? Journal.ink
                  : Journal.muted,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: Journal.uiSansFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? Journal.ink
                  : Journal.muted,
            )),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Journal.sheet,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: Journal.section,
        contentTextStyle: Journal.metadata.copyWith(color: Journal.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
