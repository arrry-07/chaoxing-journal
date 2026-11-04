import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assignment_store.dart';
import 'journal.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.assignmentStore,
    required this.child,
  });

  final AssignmentStore assignmentStore;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.assignmentStore.runDueAutoSync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.assignmentStore.runDueAutoSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return Scaffold(
      body: SafeArea(bottom: false, child: widget.child),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _indexFor(location),
        onDestinationSelected: (index) {
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
    );
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
        location.startsWith('/reminders')) {
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
      fontFamily: 'JournalBody',
      dividerColor: Journal.rule,
      textTheme: ThemeData.light().textTheme.apply(
            fontFamily: 'JournalBody',
            bodyColor: Journal.ink,
            displayColor: Journal.ink,
          ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Journal.paper,
        foregroundColor: Journal.ink,
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
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Journal.sheet,
        indicatorColor: Journal.sage,
      ),
    );
  }
}
