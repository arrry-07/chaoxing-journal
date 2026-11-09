// Test data only. Normal app startup performs all notification scheduling.
import 'dart:convert';
import 'dart:io';
import 'package:study_assistant_mobile/src/models/study_notebook.dart';

void main(List<String> args) {
  if (args.length != 2 ||
      !RegExp(r'^qa-r03-[A-Za-z0-9_-]{1,85}$').hasMatch(args.first)) {
    throw ArgumentError('Expected QA case ID and trigger epoch milliseconds');
  }
  final fire =
      DateTime.fromMillisecondsSinceEpoch(int.parse(args[1]), isUtc: true);
  if (fire.difference(DateTime.now().toUtc()) < const Duration(minutes: 10)) {
    throw ArgumentError('Trigger must leave at least ten minutes for recovery');
  }
  final book = StudyNotebook(entries: [
    ManualEntry(
        id: args[0],
        title: 'QA recovery ${args[0]}',
        kind: 'todo',
        at: fire.add(const Duration(minutes: 30)),
        remind: true)
  ]);
  final encoded = book.encode();
  final restored = StudyNotebook.decode(encoded).entries.single;
  if (restored.at!.subtract(const Duration(minutes: 30)) != fire) {
    throw StateError('Notification fixture did not round-trip');
  }
  stdout.writeln(jsonEncode({
    'caseId': args[0],
    'triggerUtc': fire.toIso8601String(),
    'triggerEpochMs': fire.millisecondsSinceEpoch,
    'notebookEncoded': encoded
  }));
}
