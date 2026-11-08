import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/backup_screen.dart';
import 'package:study_assistant_mobile/src/models/backup_snapshot.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/services/backup_service.dart';
import 'package:study_assistant_mobile/src/services/local_notification_service.dart';
import 'package:study_assistant_mobile/src/services/secure_session_store.dart';
import 'package:study_assistant_mobile/src/services/widget_snapshot_service.dart';

void main() {
  testWidgets(
      'preview writes nothing and unsuccessful restore never announces success',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = _Store();
    addTearDown(store.dispose);
    await store.repository.activateAccount('alice');
    final snapshot = await store.repository.createBackupSnapshot('alice');
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    await t.pumpWidget(MaterialApp(
        home: BackupScreen(store: store, service: _Service(snapshot))));
    await t.enterText(find.byType(TextField).first, 'password');
    await t.tap(find.text('选择备份并预览'));
    await t.pumpAndSettle();
    expect(find.text('恢复预览'), findsOneWidget);
    expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
    expect(store.restores, 0);
    await t.scrollUntilVisible(find.text('恢复缺少的记录'), 300,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('恢复缺少的记录'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(store.restores, 0);
    await t.tap(find.text('确认恢复'));
    await t.pumpAndSettle();
    expect(store.restores, 1);
    expect(find.text('恢复未完成，请检查当前账号后重试'), findsOneWidget);
    expect(find.textContaining('本机记录已补入'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('leaving page while picker is pending safely disposes password',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = _Store();
    addTearDown(store.dispose);
    final service = _PendingService();
    await t.pumpWidget(
        MaterialApp(home: BackupScreen(store: store, service: service)));
    await t.enterText(find.byType(TextField).first, 'password');
    await t.tap(find.text('选择备份并预览'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    service.pending.complete(null);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('account roundtrip invalidates an existing preview', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = _Store();
    addTearDown(store.dispose);
    await store.repository.activateAccount('alice');
    final snapshot = await store.repository.createBackupSnapshot('alice');
    await t.pumpWidget(MaterialApp(
        home: BackupScreen(store: store, service: _Service(snapshot))));
    await t.enterText(find.byType(TextField).first, 'password');
    await t.tap(find.text('选择备份并预览'));
    await t.pumpAndSettle();
    expect(find.text('恢复预览'), findsOneWidget);
    store.changeAccount('bob');
    store.changeAccount('alice');
    await t.pumpAndSettle();
    expect(find.text('恢复预览'), findsNothing);
  });

  testWidgets('export blocks incomplete data and explains recovery warning',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = _Store();
    addTearDown(store.dispose);
    await store.repository.activateAccount('alice');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personal_workspace_v1', '{personal-broken');
    final service = _ExportService();
    await t.pumpWidget(
        MaterialApp(home: BackupScreen(store: store, service: service)));
    await t.enterText(find.byType(TextField).at(0), 'password');
    await t.enterText(find.byType(TextField).at(1), 'password');

    await t.tap(find.text('导出加密备份'));
    await t.pumpAndSettle();

    expect(service.encryptCalls, 0);
    expect(service.saveCalls, 0);
    expect(find.textContaining('恢复警告'), findsOneWidget);
    expect(find.textContaining('已阻止导出'), findsOneWidget);
    expect(prefs.getString('personal_workspace_v1'), '{personal-broken');
    expect(
      prefs.getString('personal_workspace_v1_recovery_backup'),
      '{personal-broken',
    );
  });
}

class _Store extends AssignmentStore {
  _Store()
      : super(
            sessionStore: SecureSessionStore(),
            notificationService: LocalNotificationService(),
            widgetSnapshotService: WidgetSnapshotService());
  int restores = 0;
  String activeAccount = 'alice';
  void changeAccount(String account) {
    activeAccount = account;
    notifyListeners();
  }

  @override
  String? get account => activeAccount;
  @override
  bool get isAuthenticated => true;
  @override
  Future<bool> restoreLocalBackup(BackupSnapshot snapshot) async {
    restores++;
    return false;
  }
}

class _Service extends BackupService {
  _Service(this.snapshot);
  final BackupSnapshot snapshot;
  @override
  Future<String?> pick() async => 'encrypted';
  @override
  Future<BackupSnapshot> decrypt(String envelope, String password) async =>
      snapshot;
}

class _PendingService extends BackupService {
  final pending = Completer<String?>();
  @override
  Future<String?> pick() => pending.future;
}

class _ExportService extends BackupService {
  int encryptCalls = 0;
  int saveCalls = 0;

  @override
  Future<String> encrypt(BackupSnapshot snapshot, String password) async {
    encryptCalls++;
    return 'encrypted';
  }

  @override
  Future<bool> save(String content, {required String suggestedName}) async {
    saveCalls++;
    return true;
  }
}
