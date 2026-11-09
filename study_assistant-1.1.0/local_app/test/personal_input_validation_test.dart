import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/personal_work_screen.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';
import 'package:study_assistant_mobile/src/models/personal_workspace.dart';
import 'review_core_remediation_test.dart' as f;

Future<AssignmentStore> setup() async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = f.makeStore(f.Session());
  await store.restoreSession();
  await store.repository.mergeAndSave([f.sample('shared')]);
  await store.refreshAssignments();
  return store;
}

void main() {
  testWidgets('checklist removal has an independent accessible action',
      (tester) async {
    final store = await setup();
    addTearDown(store.dispose);
    await store.savePersonal(
        (w) => w.withWork('cx:work:1:2:shared',
            const PersonalWork(steps: [PersonalStep('QA step')])),
        store.accountEpoch);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
        home: PersonalWorkScreen(
            store: store, assignmentId: 'cx:work:1:2:shared')));
    final remove = find.byTooltip('移除此项');
    final removeId = tester.getSemantics(remove).id;
    final toggleId = tester.getSemantics(find.byType(CheckboxListTile)).id;
    handle.dispose();
    expect(removeId, isNot(toggleId),
        reason: 'delete must not disappear into the checkbox toggle semantics');
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('QA step'), findsNothing);
    final save = find.text('保存个人记录');
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.personal.work['cx:work:1:2:shared']!.steps, isEmpty);
  });
  testWidgets(
      'invalid link error belongs to the active dialog and correction can save',
      (tester) async {
    final store = await setup();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: PersonalWorkScreen(
            store: store, assignmentId: 'cx:work:1:2:shared')));
    final add = find.text('添加资料链接');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final fields =
        find.descendant(of: dialog, matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '资料');
    await tester.enterText(fields.at(1), 'http://example.com');
    final submit = find.descendant(of: dialog, matching: find.text('添加'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: dialog, matching: find.text('请输入不含账号信息的 HTTPS 链接')),
        findsOneWidget);
    expect(store.personal.work, isEmpty);
    await tester.enterText(fields.at(1), 'https://example.com');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    final save = find.text('保存个人记录');
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.personal.work['cx:work:1:2:shared']!.links.single.url,
        'https://example.com');
    await tester.pump(const Duration(milliseconds: 400));
  });
  testWidgets(
      'empty checklist item explains the missing field within the dialog',
      (tester) async {
    final store = await setup();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: PersonalWorkScreen(
            store: store, assignmentId: 'cx:work:1:2:shared')));
    await tester.tap(find.text('添加清单项'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('添加')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: dialog, matching: find.text('请填写要做的事')),
        findsOneWidget);
    expect(store.personal.work, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
