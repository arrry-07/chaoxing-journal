import '../features/widgets/update_scope.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';
import 'journal.dart';
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
    final location = GoRouterState.of(context).matchedLocation;
    return Scaffold(
      body: SafeArea(bottom: false, child: widget.child),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
            animation: widget.assignmentStore,
            builder: (context, _) {
              final message = widget.assignmentStore.returnCheckMessage;
              if (message == null) return const SizedBox.shrink();
              return Material(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Row(children: [
                        Expanded(
                            child: Semantics(
                                liveRegion: true, child: Text(message))),
                        IconButton(
                            tooltip: '关闭核对提示',
                            onPressed:
                                widget.assignmentStore.dismissReturnCheck,
                            icon: const Icon(Icons.close)),
                      ])));
            }),
        if (AppUpdateScope.maybeOf(context) case final updates?)
          UpdateDownloadBanner(controller: updates),
        NavigationBar(
          height: 76,
          selectedIndex: _indexFor(location),
          onDestinationSelected: (index) {
            unawaited(_selectDestination(index));
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment),
              label: '作业',
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
      ]),
    );
  }

  Future<void> _selectDestination(int index) async {
    final guard = _leaveGuard;
    if (guard != null && !await guard.confirmLeave()) return;
    if (!mounted) return;
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

  int _indexFor(String location) {
    if (location.startsWith('/calendar')) {
      return 1;
    }
    if (location.startsWith('/stats')) {
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
        location.startsWith('/agenda') ||
        location.startsWith('/terms')) {
      return 3;
    }
    return 0;
  }
}

class StudyAssistantTheme {
  static ThemeData get light {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Journal.ink,
        brightness: Brightness.light,
        surface: Journal.paper,
        primary: Journal.ink,
        secondary: Journal.berry,
      ),
      scaffoldBackgroundColor: Journal.paper,
      useMaterial3: true,
      fontFamily: Journal.bodyFamily,
      fontFamilyFallback: Journal.bodyFallback,
      dividerColor: Journal.rule,
      textTheme: Typography.material2021().black.apply(
            fontFamily: Journal.bodyFamily,
            fontFamilyFallback: Journal.bodyFallback,
            bodyColor: Journal.ink,
            displayColor: Journal.ink,
          ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Journal.paper,
        foregroundColor: Journal.ink,
        titleTextStyle: Journal.section,
      ),
      cardTheme: CardThemeData(
        color: Journal.sheet,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Journal.rule),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Journal.sheet,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Journal.sheet,
        indicatorColor: Journal.sage,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? Journal.ink
                  : Journal.muted,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: Journal.bodyFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? Journal.ink
                  : Journal.muted,
            )),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Journal.sheet,
        titleTextStyle: Journal.section,
        contentTextStyle: Journal.metadata.copyWith(color: Journal.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
