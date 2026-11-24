import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/app/app_shell.dart';
import 'package:study_assistant_mobile/src/features/backup_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/manual_entry_detail_screen.dart';
import 'package:study_assistant_mobile/src/features/widgets/manual_home_card.dart';
import 'package:study_assistant_mobile/src/models/manual_attachment.dart';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/manual_attachment_service.dart';

import 'review_core_remediation_test.dart' as core;

ManualAttachment _att(
  String id, {
  String kind = ManualAttachment.kindImage,
  int sizeBytes = 2048,
}) =>
    ManualAttachment(
      id: id,
      kind: kind,
      name: kind == ManualAttachment.kindImage ? '$id.jpg' : '$id.pdf',
      relativePath: kind == ManualAttachment.kindImage
          ? 'manual_attachments/$id.jpg'
          : 'manual_attachments/$id.pdf',
      mimeType:
          kind == ManualAttachment.kindImage ? 'image/jpeg' : 'application/pdf',
      sizeBytes: sizeBytes,
      addedAt: DateTime.utc(2026, 11, 25, 6, 0).toLocal(),
    );

class _FakeAttachmentService extends ManualAttachmentService {
  _FakeAttachmentService({this.rootDir});

  final Directory? rootDir;
  AttachmentSingleResult nextCamera = const AttachmentSingleResult();
  AttachmentBatchResult nextGallery = const AttachmentBatchResult();
  AttachmentSingleResult nextFile = const AttachmentSingleResult();
  AttachmentOpenStatus nextOpenStatus = AttachmentOpenStatus.ok;
  int? lastPickImagesMaxCount;
  final openedAttachments = <ManualAttachment>[];
  final deletedPaths = <String>[];

  @override
  Future<String?> getAttachmentRoot({bool refresh = false}) async {
    if (rootDir == null) return null;
    setCachedRootPathForTest(rootDir!.path);
    return rootDir!.path;
  }

  @override
  Future<AttachmentSingleResult> capturePhoto() async => nextCamera;

  @override
  Future<AttachmentBatchResult> pickImages({required int maxCount}) async {
    lastPickImagesMaxCount = maxCount;
    return nextGallery;
  }

  @override
  Future<AttachmentSingleResult> pickAttachmentFile() async => nextFile;

  @override
  Future<AttachmentOpenStatus> openAttachment(
    ManualAttachment attachment,
  ) async {
    openedAttachments.add(attachment);
    return nextOpenStatus;
  }

  @override
  Future<int> deleteFiles(Iterable<String> relativePaths) async {
    final items = relativePaths.toList();
    deletedPaths.addAll(items);
    return items.length;
  }
}

Future<AssignmentStore> _makeStore(_FakeAttachmentService attachments) async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = AssignmentStore(
    sessionStore: core.Session(),
    notificationService: core.Notifications(),
    widgetSnapshotService: core.WidgetService(),
    manualAttachmentService: attachments,
  );
  await store.restoreSession();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'editor adds camera/gallery/file attachments, enforces 9-image & 20-total & 20MB caps, and cleans draft-only files on cancel',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    final tempRoot = Directory.systemTemp.createTempSync('att_ui_test_');
    addTearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });
    // Minimal 1x1 transparent PNG bytes so Image.file decodes cleanly in widget tests.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    for (final name in ['saved.jpg', 'cam_1.jpg']) {
      File('${tempRoot.path}${Platform.pathSeparator}$name')
          .writeAsBytesSync(pngBytes);
    }

    final service = _FakeAttachmentService(rootDir: tempRoot);
    final store = await _makeStore(service);
    addTearDown(store.dispose);

    final existingSaved = _att('saved');
    final initialEntry = ManualEntry(
      id: 'm-edit',
      title: '已有待办',
      kind: ManualEntry.kindTodo,
      attachments: [existingSaved],
    );
    await store.saveNotebook(
      (_) => StudyNotebook(entries: [initialEntry]),
      store.accountEpoch,
    );

    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: ManualEntryEditor(store: store, entry: initialEntry),
      ),
    );
    await tester.pumpAndSettle();

    // Oversized file shows 20 MB limit warning without adding.
    service.nextFile = const AttachmentSingleResult(
      issue: AttachmentPickIssue.tooLarge,
      message: '单个文件不能超过 20 MB',
    );
    final fileBtn = find.byKey(const ValueKey('attachment-add-file'));
    await tester.scrollUntilVisible(
      fileBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(fileBtn);
    await tester.pumpAndSettle();
    expect(find.text('单个文件不能超过 20 MB'), findsOneWidget);

    // Camera photo adds 1 image.
    service.nextCamera = AttachmentSingleResult(attachment: _att('cam_1'));
    final cameraBtn = find.byKey(const ValueKey('attachment-add-camera'));
    await tester.tap(cameraBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('图片 2/9 · 总计 2/20'), findsOneWidget);

    // Removing the draft camera photo cleans it immediately.
    await tester.tap(find.byKey(const ValueKey('attachment-remove-cam_1')));
    await tester.pumpAndSettle();
    expect(service.deletedPaths, ['manual_attachments/cam_1.jpg']);
    expect(find.textContaining('图片 1/9 · 总计 1/20'), findsOneWidget);

    // Gallery adds 8 more images to reach the 9-image cap.
    service.nextGallery = AttachmentBatchResult(
      attachments: [for (var i = 1; i <= 8; i++) _att('gal_$i')],
    );
    final galleryBtn = find.byKey(const ValueKey('attachment-add-gallery'));
    await tester.tap(galleryBtn);
    await tester.pumpAndSettle();
    expect(service.lastPickImagesMaxCount, 8);
    expect(find.textContaining('图片 9/9 · 总计 9/20'), findsOneWidget);
    expect(
      find.text('图片已达 9 张上限，仍可继续添加文档或压缩包文件。'),
      findsOneWidget,
    );
    expect(
      tester.widget<OutlinedButton>(cameraBtn).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(galleryBtn).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(fileBtn).onPressed,
      isNotNull,
    );

    // Fill remaining 11 file slots to hit 20-attachment cap.
    for (var i = 1; i <= 11; i++) {
      service.nextFile = AttachmentSingleResult(
        attachment: _att('doc_$i', kind: ManualAttachment.kindFile),
      );
      await tester.ensureVisible(fileBtn);
      await tester.tap(fileBtn);
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('图片 9/9 · 总计 20/20'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(fileBtn).onPressed, isNull);
    expect(
      find.text('已达单条 20 个附件上限，删除部分附件后可继续添加。'),
      findsOneWidget,
    );

    // Disposing without saving cleans ONLY draft additions, NEVER saved.jpg!
    service.deletedPaths.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(
        service.deletedPaths, isNot(contains('manual_attachments/saved.jpg')));
    expect(service.deletedPaths, hasLength(19));
    expect(store.notebook.entries.single.attachments, [existingSaved]);
  });

  testWidgets(
      'saving editor keeps newly attached files, persists updatedAt, and cleans removed saved files cleanly',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    final service = _FakeAttachmentService();
    final store = await _makeStore(service);
    addTearDown(store.dispose);

    final keepExisting = _att('saved_keep');
    final dropExisting = _att('saved_drop');
    final existingEntry = ManualEntry(
      id: 'm-save-diff',
      title: '既有待办',
      kind: ManualEntry.kindTodo,
      attachments: [keepExisting, dropExisting],
    );
    await store.saveNotebook(
      (_) => StudyNotebook(entries: [existingEntry]),
      store.accountEpoch,
    );

    service.nextCamera = AttachmentSingleResult(attachment: _att('cam_keep'));
    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: ManualEntryEditor(store: store, entry: existingEntry),
      ),
    );
    await tester.pumpAndSettle();

    final dropBtn = find.byKey(const ValueKey('attachment-remove-saved_drop'));
    await tester.scrollUntilVisible(
      dropBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(dropBtn);
    await tester.pumpAndSettle();
    // Removing a previously saved file must wait until save commits.
    expect(service.deletedPaths, isEmpty);

    final camBtn = find.byKey(const ValueKey('attachment-add-camera'));
    await tester.scrollUntilVisible(
      camBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(camBtn);
    await tester.pumpAndSettle();

    final saveBtn = find.text('保存个人安排');
    await tester.scrollUntilVisible(
      saveBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(store.notebook.entries, hasLength(1));
    expect(store.notebook.entries.single.updatedAt, isNotNull);
    expect(
      store.notebook.entries.single.attachments.map((e) => e.relativePath),
      ['manual_attachments/saved_keep.jpg', 'manual_attachments/cam_keep.jpg'],
    );
    expect(service.deletedPaths, ['manual_attachments/saved_drop.jpg']);
  });

  testWidgets(
      'ManualEntryDetailScreen opens fullscreen viewer and system file open cleanly across light/dark at 320dp@2x',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    final tempRoot = Directory.systemTemp.createTempSync('att_detail_test_');
    addTearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    for (final name in ['p1.jpg', 'p2.jpg']) {
      File('${tempRoot.path}${Platform.pathSeparator}$name')
          .writeAsBytesSync(pngBytes);
    }

    final service = _FakeAttachmentService(rootDir: tempRoot);
    final store = await _makeStore(service);
    addTearDown(store.dispose);

    final entry = ManualEntry(
      id: 'm-detail',
      title: '实验报告待办',
      kind: ManualEntry.kindTodo,
      course: '软件工程',
      note: '附截图和PDF',
      attachments: [
        _att('p1'),
        _att('p2'),
        _att('report', kind: ManualAttachment.kindFile, sizeBytes: 1536),
      ],
    );
    await store.saveNotebook(
      (_) => StudyNotebook(entries: [entry]),
      store.accountEpoch,
    );

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final mode in <({String name, ThemeData theme, double scale})>[
      (name: 'light-1.3x', theme: StudyAssistantTheme.light, scale: 1.3),
      (name: 'dark-2.0x', theme: StudyAssistantTheme.dark, scale: 2.0),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: mode.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(mode.scale),
            ),
            child: child!,
          ),
          home: ManualEntryDetailScreen(store: store, entryId: 'm-detail'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: mode.name);

      final fileTile =
          find.byKey(const ValueKey('detail-attachment-file-report'));
      await tester.scrollUntilVisible(
        fileTile,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(fileTile),
        alignment: 0.35,
      );
      await tester.pumpAndSettle();
      expect(find.text('附件（3）'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);

      if (mode.name == 'light-1.3x') {
        service.nextOpenStatus = AttachmentOpenStatus.noApp;
        await tester.tap(fileTile);
        await tester.pumpAndSettle();
        expect(find.text('未找到可打开此类型文件的应用'), findsOneWidget);

        // Open fullscreen image viewer & swipe to second image.
        final imgTile =
            find.byKey(const ValueKey('detail-attachment-image-p1'));
        await Scrollable.ensureVisible(
          tester.element(imgTile),
          alignment: 0.25,
        );
        await tester.pumpAndSettle();
        await tester.tap(imgTile);
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        await tester.fling(
          find.byType(PageView),
          const Offset(-300, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('attachment-viewer-close')));
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsNothing);
      }
      expect(tester.takeException(), isNull, reason: '${mode.name} end');
    }
  });

  testWidgets(
      'ManualHomeCard shows 附件 N indicator and BackupScreen discloses exclusion',
      (tester) async {
    await initializeDateFormatting('zh_CN');
    final fixedNow = DateTime(2026, 11, 25, 10, 0);
    final withAttachments = ManualEntry(
      id: 'm-card',
      title: '带附件首页卡片',
      kind: ManualEntry.kindTodo,
      at: fixedNow.add(const Duration(hours: 3)),
      attachments: [_att('a1'), _att('a2', kind: ManualAttachment.kindFile)],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: Scaffold(
          body: ManualHomeCard(
            entry: withAttachments,
            now: fixedNow,
            onTap: () {},
            onToggleDone: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('附件 2'), findsOneWidget);

    final store = await _makeStore(_FakeAttachmentService());
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: StudyAssistantTheme.light,
        home: BackupScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('不包含本地图片与文件附件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
