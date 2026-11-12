import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistant_mobile/src/features/manual_agenda_screen.dart';
import 'package:study_assistant_mobile/src/features/personal_work_screen.dart';
import 'package:study_assistant_mobile/src/services/assignment_store.dart';

import 'review_core_remediation_test.dart' as f;

Future<AssignmentStore> _store() async {
  SharedPreferences.setMockInitialValues({'auto_sync_interval_minutes': 0});
  final store = f.makeStore(f.Session());
  await store.restoreSession();
  await store.repository.mergeAndSave([f.sample('shared')]);
  await store.refreshAssignments();
  return store;
}

Future<void> _push(
  WidgetTester tester,
  Widget page,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => page),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('personal notes back navigation asks before discarding edits',
      (tester) async {
    final store = await _store();
    addTearDown(store.dispose);

    await _push(
      tester,
      PersonalWorkScreen(
        store: store,
        assignmentId: 'cx:work:1:2:shared',
      ),
    );
    await tester.enterText(find.byType(TextField).first, '未保存的备注');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);

    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('个人清单与备注'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('个人清单与备注'), findsNothing);
  });

  testWidgets('manual agenda editor asks before discarding edits',
      (tester) async {
    final store = await _store();
    addTearDown(store.dispose);

    await _push(tester, ManualEntryEditor(store: store));
    await tester.enterText(find.byType(TextFormField).first, '未保存的待办');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);

    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('添加个人安排'), findsNothing);
  });
}
