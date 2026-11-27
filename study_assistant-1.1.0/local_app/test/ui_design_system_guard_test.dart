import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/app/journal.dart';
import 'package:study_assistant_mobile/src/app/journal_motion.dart';
import 'package:study_assistant_mobile/src/features/assignment_list_screen.dart';
import 'package:study_assistant_mobile/src/features/calendar_screen.dart';
import 'package:study_assistant_mobile/src/features/profile_screen.dart';
import 'package:study_assistant_mobile/src/features/stats_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_context_menu.dart';
import 'package:study_assistant_mobile/src/features/widgets/journal_modal_sheet.dart';
import 'package:study_assistant_mobile/src/models/assignment.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelPrivateSchedules() async {}

  @override
  Future<void> rescheduleAssignments(
    List<Assignment> assignments, {
    List<int>? offsetsMinutes,
  }) async {}
}

class _Snapshot extends WidgetSnapshotService {
  @override
  Future<void> saveAssignments(List<Assignment> assignments) async {}
}

class _Session extends SecureSessionStore {
  @override
  Future<String?> readChaoxingAccount() async => 'student-ui-guard';

  @override
  Future<String?> readChaoxingPassword() async => 'secret';

  @override
  Future<String?> readChaoxingDisplayName() async => '手记同学';

  @override
  Future<String?> readChaoxingAvatarUrl() async => null;
}

Future<AssignmentStore> _seededStore(DateTime now) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  FlutterSecureStorage.setMockInitialValues({});
  final store = AssignmentStore(
    sessionStore: _Session(),
    notificationService: _Notifications(),
    widgetSnapshotService: _Snapshot(),
  );
  await store.restoreSession();
  await store.repository.mergeAndSave([
    Assignment(
      id: 'cx:work:1:2:due-today',
      courseName: '数据结构',
      title: '红黑树实验报告',
      deadlineAt: now.add(const Duration(hours: 4)),
      deadlineTrusted: true,
      requirementsText: '提交 PDF 报告与核心代码',
      status: 'pending',
      lastSyncedAt: now,
    ),
    Assignment(
      id: 'cx:work:1:2:overdue',
      courseName: '高等数学',
      title: '定积分练习',
      deadlineAt: now.subtract(const Duration(days: 1)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'pending',
      lastSyncedAt: now,
    ),
    Assignment(
      id: 'cx:work:1:2:done',
      courseName: '大学英语',
      title: 'Unit 4 阅读反思',
      deadlineAt: now.add(const Duration(days: 2)),
      deadlineTrusted: true,
      requirementsText: '',
      status: 'submitted',
      lastSyncedAt: now,
    ),
  ]);
  await store.restoreSession();
  return store;
}

Directory _resolveLibDir() {
  final direct = Directory('lib');
  if (direct.existsSync()) return direct;
  final nested = Directory('study_assistant-1.1.0/local_app/lib');
  if (nested.existsSync()) return nested;
  throw StateError(
    'Unable to locate lib from cwd ${Directory.current.path}',
  );
}

Directory _resolveFeaturesDir() {
  final direct = Directory('lib/src/features');
  if (direct.existsSync()) return direct;
  final nested = Directory('study_assistant-1.1.0/local_app/lib/src/features');
  if (nested.existsSync()) return nested;
  throw StateError(
    'Unable to locate lib/src/features from cwd ${Directory.current.path}',
  );
}

List<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

bool _isIdentifierChar(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
    codeUnit == 0x5F ||
    codeUnit == 0x24;

/// Advances past a Dart comment or string literal starting at [index], or
/// returns [index] unchanged if none starts there.
int _skipDartCommentOrString(String source, int index) {
  final len = source.length;
  if (index >= len) return index;
  if (source.startsWith('//', index)) {
    final nl = source.indexOf('\n', index + 2);
    return nl == -1 ? len : nl + 1;
  }
  if (source.startsWith('/*', index)) {
    var depth = 1;
    var pos = index + 2;
    while (pos < len && depth > 0) {
      if (source.startsWith('/*', pos)) {
        depth++;
        pos += 2;
      } else if (source.startsWith('*/', pos)) {
        depth--;
        pos += 2;
      } else {
        pos++;
      }
    }
    return pos;
  }
  var raw = false;
  var pos = index;
  if (source[pos] == 'r' &&
      (pos == 0 || !_isIdentifierChar(source.codeUnitAt(pos - 1))) &&
      pos + 1 < len &&
      (source[pos + 1] == "'" || source[pos + 1] == '"')) {
    raw = true;
    pos++;
  }
  final ch = source[pos];
  if (ch != "'" && ch != '"') return index;
  final triple =
      pos + 2 < len && source[pos + 1] == ch && source[pos + 2] == ch;
  final delim = triple ? ch * 3 : ch;
  pos += delim.length;
  while (pos < len) {
    if (!raw && source[pos] == r'\') {
      pos = pos + 1 < len ? pos + 2 : len;
      continue;
    }
    if (source.startsWith(delim, pos)) return pos + delim.length;
    pos++;
  }
  return len;
}

String _stripDartCommentsAndStrings(String source) {
  final len = source.length;
  final out = StringBuffer();
  var i = 0;
  while (i < len) {
    final skipped = _skipDartCommentOrString(source, i);
    if (skipped > i) {
      for (var k = i; k < skipped; k++) {
        out.write(source[k] == '\n' ? '\n' : ' ');
      }
      i = skipped;
      continue;
    }
    out.write(source[i]);
    i++;
  }
  return out.toString();
}

List<String> _findRawShowModalBottomSheetViolations(
  String source,
  String filePath,
) {
  final stripped = _stripDartCommentsAndStrings(source);
  final rawLines = source.split('\n');
  final violations = <String>[];
  final identRe = RegExp(r'\bshowModalBottomSheet\b');
  final len = stripped.length;

  int skipWhitespace(int pos) {
    while (pos < len) {
      final ch = stripped[pos];
      if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
        pos++;
      } else {
        break;
      }
    }
    return pos;
  }

  for (final match in identRe.allMatches(stripped)) {
    var pos = skipWhitespace(match.end);
    if (pos < len && stripped[pos] == '<') {
      var depth = 1;
      pos++;
      while (pos < len && depth > 0) {
        final ch = stripped[pos];
        if (ch == ';') break;
        if (ch == '<') {
          depth++;
        } else if (ch == '>') {
          depth--;
        }
        pos++;
      }
      if (depth != 0) continue;
      pos = skipWhitespace(pos);
    }
    if (pos < len && stripped[pos] == '(') {
      final line =
          '\n'.allMatches(stripped.substring(0, match.start)).length + 1;
      violations.add('$filePath:$line: ${rawLines[line - 1].trimLeft()}');
    }
  }
  return violations;
}

/// Source text between an opening bracket (already consumed at [start]) and
/// its matching closer, ignoring brackets inside strings and comments.
String _balancedArgs(String source, int start) {
  var depth = 1;
  var i = start;
  while (i < source.length && depth > 0) {
    final skipped = _skipDartCommentOrString(source, i);
    if (skipped > i) {
      i = skipped;
      continue;
    }
    final c = source[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    i++;
  }
  return source.substring(start, i - 1);
}

/// Top-level comma-separated items of a list literal opened at [start],
/// ignoring delimiters inside strings and comments.
List<String> _directListItems(String source, int start) {
  final items = <String>[];
  var depth = 1;
  var itemStart = start;
  var i = start;
  while (i < source.length) {
    final skipped = _skipDartCommentOrString(source, i);
    if (skipped > i) {
      i = skipped;
      continue;
    }
    final c = source[i];
    if ('([{'.contains(c)) {
      depth++;
    } else if (')]}'.contains(c)) {
      depth--;
      if (depth == 0) {
        items.add(source.substring(itemStart, i));
        break;
      }
    } else if (c == ',' && depth == 1) {
      items.add(source.substring(itemStart, i));
      itemStart = i + 1;
    }
    i++;
  }
  return items.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

bool _isSpacerItem(String item) {
  if (RegExp(r'^(?:const\s+)?SizedBox\(').hasMatch(item)) return true;
  final spread =
      RegExp(r'^(?:if\s*\([^\[]*\)\s*)?\.\.\.\s*\[').firstMatch(item);
  if (spread == null) return false;
  return _directListItems(item, spread.end).any(_isSpacerItem);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wave B-1 UI static design-system contract', () {
    test(
        'features contain zero legacy native pickers, popup menus, ExpansionTiles, or eyebrows',
        () {
      final featuresDir = _resolveFeaturesDir();
      final legacyWidgetRe = RegExp(
        r'\b(?:DropdownButtonFormField|DropdownButton|PopupMenuButton|DropdownMenu|SimpleDialog|ExpansionTile)\b',
      );
      final eyebrowArgRe = RegExp(r'\beyebrow\s*:');
      final violations = <String>[];

      final dartFiles = featuresDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(dartFiles, isNotEmpty);

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//')) continue;
          if (legacyWidgetRe.hasMatch(trimmed)) {
            violations.add('${file.path}:${i + 1} legacy widget: $trimmed');
          }
          if (eyebrowArgRe.hasMatch(trimmed)) {
            violations
                .add('${file.path}:${i + 1} eyebrow regression: $trimmed');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'UI design-system static contract violated:\n'
            '${violations.join('\n')}',
      );
    });

    test('app and pages route snackbars through the shared feedback entries',
        () {
      final libDir = _resolveLibDir();
      final violations = <String>[];
      for (final file in _dartFiles(libDir)) {
        final norm = file.path.replaceAll('\\', '/');
        if (norm.endsWith('lib/src/app/transient_feedback.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//')) continue;
          if (trimmed.contains('showSnackBar(')) {
            violations.add('${file.path}:${i + 1}: $trimmed');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Use showJournalMessage or TransientFeedbackController:\n'
            '${violations.join('\n')}',
      );
    });

    test(
        'app and pages route modal bottom sheets through showJournalModalSheet',
        () {
      final libDir = _resolveLibDir();
      final violations = <String>[];
      for (final file in _dartFiles(libDir)) {
        final norm = file.path.replaceAll('\\', '/');
        if (norm
            .endsWith('lib/src/features/widgets/journal_modal_sheet.dart')) {
          continue;
        }
        violations.addAll(
          _findRawShowModalBottomSheetViolations(
            file.readAsStringSync(),
            file.path,
          ),
        );
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Use showJournalModalSheet instead of raw showModalBottomSheet:\n'
            '${violations.join('\n')}',
      );
    });

    test(
        'modal bottom sheet detector catches bypasses and ignores comments and strings',
        () {
      const multilineCall = '''
Future<void> open(BuildContext context) {
  return showModalBottomSheet
      (
    context: context,
    builder: (_) => const SizedBox(),
  );
}
''';
      expect(
        _findRawShowModalBottomSheetViolations(multilineCall, 'a.dart'),
        hasLength(1),
      );

      const nestedGenericsCall = '''
Future<void> open(BuildContext context) {
  return showModalBottomSheet<List<Map<String, int>>>(
    context: context,
    builder: (_) => const SizedBox(),
  );
}
''';
      expect(
        _findRawShowModalBottomSheetViolations(nestedGenericsCall, 'b.dart'),
        hasLength(1),
      );

      const blockCommentCall = '''
Future<void> open(BuildContext context) {
  return showModalBottomSheet/* ok */(
    context: context,
    builder: (_) => const SizedBox(),
  );
}
Future<void> open2(BuildContext context) {
  return showModalBottomSheet /* a */ <List<int>> /* b */ (
    context: context,
    builder: (_) => const SizedBox(),
  );
}
''';
      expect(
        _findRawShowModalBottomSheetViolations(blockCommentCall, 'c.dart'),
        hasLength(2),
      );

      const safeSamples = r"""
// showModalBottomSheet(context: context, builder: (_) => const SizedBox());
/*
  showModalBottomSheet(context: context, builder: (_) => const SizedBox());
  /* nested comment showModalBottomSheet<List<int>>( */
  showModalBottomSheet/* still inside outer comment */(
*/
const a = 'showModalBottomSheet(';
const b = "showModalBottomSheet<int>(";
const c = 'escaped \' showModalBottomSheet(';
const d = 'trailing \\';
const e = r'raw showModalBottomSheet(';
const f = r"raw showModalBottomSheet<List<int>>(";
const h = '''
triple single showModalBottomSheet(
''';
""";
      const safeTripleDouble = r'''
const g = """
triple double showModalBottomSheet(
""";
''';
      expect(
        _findRawShowModalBottomSheetViolations(safeSamples, 'safe.dart'),
        isEmpty,
      );
      expect(
        _findRawShowModalBottomSheetViolations(
          safeTripleDouble,
          'safe_double.dart',
        ),
        isEmpty,
      );
    });

    test('JournalGroupedCard children never include bare spacers', () {
      // The card inserts a divider between direct children, so a SizedBox
      // spacer there draws stray rules; free-form content goes in one Column.
      final featuresDir = _resolveFeaturesDir();
      final violations = <String>[];
      for (final file in _dartFiles(featuresDir)) {
        final source = file.readAsStringSync();
        for (final call in RegExp(r'JournalGroupedCard\(').allMatches(source)) {
          final args = _balancedArgs(source, call.end);
          final children = RegExp(r'\bchildren:\s*(?:const\s*)?\[').firstMatch(
            args,
          );
          if (children == null) continue;
          final items = _directListItems(args, children.end);
          if (items.any(_isSpacerItem)) {
            final line =
                '\n'.allMatches(source.substring(0, call.start)).length;
            violations.add('${file.path}:${line + 1}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Wrap free-form card content in a single Column:\n'
            '${violations.join('\n')}',
      );
    });

    test('grouped card parser ignores brackets inside strings and comments',
        () {
      const sample = '''
JournalGroupedCard(
  title: '含右括号)与]的标题', // comment with ) and ]
  children: [
    /* block comment ) ] */
    const Text('正常内容 (示例)'),
    const SizedBox(height: 8),
  ],
)
''';
      final match = RegExp(r'JournalGroupedCard\(').firstMatch(sample)!;
      final args = _balancedArgs(sample, match.end);
      final children =
          RegExp(r'\bchildren:\s*(?:const\s*)?\[').firstMatch(args);
      expect(children, isNotNull);
      final items = _directListItems(args, children!.end);
      expect(items.any(_isSpacerItem), isTrue);
    });

    test('light and dark themes expose distinct Journal tokens and WenKai', () {
      final light = StudyAssistantTheme.light.extension<JournalPalette>();
      final dark = StudyAssistantTheme.dark.extension<JournalPalette>();
      expect(light, isNotNull);
      expect(dark, isNotNull);
      expect(light!.paper, isNot(equals(dark!.paper)));
      expect(light.sheet, isNot(equals(dark.sheet)));
      expect(light.ink, isNot(equals(dark.ink)));
      expect(light.berryBorder, const Color(0xFFECD0C8));
      expect(dark.berryBorder, const Color(0xFF61403C));
      expect(StudyAssistantTheme.light.colorScheme.error, light.berry);
      expect(StudyAssistantTheme.dark.colorScheme.error, dark.berry);
      expect(Journal.titleFamily, 'LXGW WenKai Screen');
      expect(Journal.bodyFamily, 'LXGW WenKai Screen');
      expect(StudyAssistantTheme.light.textTheme.bodyMedium?.fontFamily,
          Journal.bodyFamily);
      expect(StudyAssistantTheme.dark.textTheme.bodyMedium?.fontFamily,
          Journal.bodyFamily);
    });
  });

  group('Wave B-1 dual-theme smoke rendering', () {
    final fixedNow = DateTime(2026, 11, 22, 10, 0);

    for (final mode in <({String name, ThemeData theme})>[
      (name: 'light', theme: StudyAssistantTheme.light),
      (name: 'dark', theme: StudyAssistantTheme.dark),
    ]) {
      testWidgets(
        'primary tabs and AppShell render cleanly in ${mode.name} theme',
        (tester) async {
          await initializeDateFormatting('zh_CN');
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final store = await _seededStore(fixedNow);
          addTearDown(store.dispose);
          final expectedJournal = mode.theme.extension<JournalPalette>()!;

          final pages = <({String title, Widget child})>[
            (
              title: '课业手记',
              child: AssignmentListScreen(store: store, clock: () => fixedNow),
            ),
            (
              title: '课业日历',
              child: CalendarScreen(store: store, clock: () => fixedNow),
            ),
            (
              title: '课业统计',
              child: StatsScreen(store: store, clock: () => fixedNow),
            ),
            (
              title: '我的手帐',
              child: ProfileScreen(store: store),
            ),
          ];

          for (final page in pages) {
            await tester.pumpWidget(
              MaterialApp(
                theme: mode.theme,
                home: Scaffold(body: page.child),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '${page.title} threw in ${mode.name}');
            expect(find.text(page.title), findsOneWidget,
                reason: '${page.title} missing in ${mode.name}');
            final ctx = tester.element(find.text(page.title));
            expect(Journal.of(ctx).paper, expectedJournal.paper,
                reason: '${page.title} paper token mismatch in ${mode.name}');
          }

          final router = GoRouter(
            initialLocation: '/assignments',
            routes: [
              ShellRoute(
                builder: (_, __, child) =>
                    AppShell(assignmentStore: store, child: child),
                routes: [
                  GoRoute(
                    path: '/assignments',
                    builder: (_, __) => AssignmentListScreen(
                      store: store,
                      clock: () => fixedNow,
                    ),
                  ),
                ],
              ),
            ],
          );
          addTearDown(router.dispose);

          await tester.pumpWidget(
            MaterialApp.router(
              theme: mode.theme,
              routerConfig: router,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'AppShell threw in ${mode.name}');
          for (final tab in ['首页', '日历', '统计', '我的']) {
            expect(find.text(tab), findsOneWidget,
                reason: 'Floating nav tab $tab missing in ${mode.name}');
          }
        },
      );
    }
  });

  group('M3 · JournalPalette.subtle, modal sheet, and context menu', () {
    double contrastRatio(Color fg, Color bg) {
      final l1 = fg.computeLuminance();
      final l2 = bg.computeLuminance();
      return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
    }

    test('JournalPalette.subtle meets WCAG AA across paper/sheet/parchment',
        () {
      expect(Journal.muted, const Color(0xFF363C44));
      expect(Journal.entryTitle.fontSize, 15.5);
      expect(Journal.entryTitle.height, 1.38);
      expect(Journal.entryTitle.fontWeight, FontWeight.w400);
      expect(Journal.display.fontSize, 30);
      expect(Journal.display.fontWeight, FontWeight.w400);

      final light = StudyAssistantTheme.light.extension<JournalPalette>()!;
      final dark = StudyAssistantTheme.dark.extension<JournalPalette>()!;
      expect(light.subtle, const Color(0xFF565E69));
      expect(dark.subtle, const Color(0xFFA5A096));

      for (final p in [light, dark]) {
        expect(contrastRatio(p.subtle, p.paper), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(p.subtle, p.sheet), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(p.subtle, p.parchment), greaterThanOrEqualTo(4.5));
      }

      final copied = light.copyWith(subtle: const Color(0xFF445566));
      expect(copied.subtle, const Color(0xFF445566));
      expect(copied, isNot(equals(light)));
      expect(copied.hashCode, isNot(equals(light.hashCode)));
      expect(light.copyWith(), equals(light));
      expect(light.copyWith().hashCode, equals(light.hashCode));

      final mid = light.lerp(dark, 0.5);
      expect(mid.subtle, Color.lerp(light.subtle, dark.subtle, 0.5));
    });

    testWidgets(
        'modalSheetAnimationStyle uses 180ms easeOut dismiss and honors reduced motion',
        (tester) async {
      late AnimationStyle normalStyle;
      late AnimationStyle reducedStyle;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              normalStyle = JournalMotion.modalSheetAnimationStyle(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reducedStyle = JournalMotion.modalSheetAnimationStyle(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(normalStyle.duration, const Duration(milliseconds: 280));
      expect(normalStyle.reverseDuration, const Duration(milliseconds: 180));
      expect(normalStyle.curve, JournalMotion.criticalCurve);
      expect(normalStyle.reverseCurve, JournalMotion.easeOut);
      expect(reducedStyle, AnimationStyle.noAnimation);
    });

    testWidgets(
        'showJournalModalSheet injects animation style without forcing transparent surface',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudyAssistantTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showJournalModalSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(
                      height: 120,
                      child: Center(child: Text('共享弹窗内容')),
                    ),
                  );
                },
                child: const Text('打开弹窗'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();

      expect(find.text('共享弹窗内容'), findsOneWidget);
      final route = ModalRoute.of(tester.element(find.text('共享弹窗内容')))
          as ModalBottomSheetRoute<void>;
      expect(
        route.sheetAnimationStyle?.reverseDuration,
        const Duration(milliseconds: 180),
      );
      expect(route.sheetAnimationStyle?.reverseCurve, JournalMotion.easeOut);
      final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(
        bottomSheet.backgroundColor,
        StudyAssistantTheme.light.extension<JournalPalette>()!.sheet,
      );
      expect(bottomSheet.backgroundColor, isNot(Colors.transparent));
    });

    testWidgets(
        'JournalContextMenuAction.selected highlights with accent and keeps destructive priority',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: StudyAssistantTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    showJournalContextMenu(
                      context: context,
                      anchorRect: const Rect.fromLTWH(40, 80, 140, 40),
                      useSelectionFeedback: true,
                      actions: [
                        JournalContextMenuAction(
                          label: '当前排序',
                          icon: Icons.schedule_rounded,
                          selected: true,
                          onSelected: () {},
                        ),
                        JournalContextMenuAction(
                          label: '危险操作',
                          icon: Icons.delete_outline_rounded,
                          destructive: true,
                          selected: true,
                          onSelected: () {},
                        ),
                      ],
                    );
                  },
                  child: const Text('打开菜单'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('打开菜单'));
        await tester.pumpAndSettle();

        final light = StudyAssistantTheme.light.extension<JournalPalette>()!;
        final selectedText = tester.widget<Text>(find.text('当前排序'));
        expect(selectedText.style?.color, light.accent);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        final checkIcon = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
        expect(checkIcon.color, light.accent);
        final selectedSemantics =
            tester.getSemantics(find.text('当前排序')).getSemanticsData();
        expect(selectedSemantics.flagsCollection.isSelected, Tristate.isTrue);

        final destructiveText = tester.widget<Text>(find.text('危险操作'));
        expect(destructiveText.style?.color, light.berry);
        final destructiveSemantics =
            tester.getSemantics(find.text('危险操作')).getSemanticsData();
        expect(
          destructiveSemantics.flagsCollection.isSelected,
          isNot(Tristate.isTrue),
        );
      } finally {
        semantics.dispose();
      }
    });
  });
}
