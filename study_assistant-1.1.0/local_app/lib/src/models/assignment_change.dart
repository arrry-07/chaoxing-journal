import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'assignment.dart';

enum AssignmentChangeKind { published, deadline, status }

class AssignmentChange {
  const AssignmentChange({
    required this.assignmentId,
    required this.title,
    required this.courseName,
    required this.kind,
    required this.at,
    required this.before,
    required this.after,
    this.changeId,
    this.beforeDeadlineUtc,
    this.afterDeadlineUtc,
  });

  final String assignmentId, title, courseName, before, after;
  final AssignmentChangeKind kind;
  final DateTime at;
  final String? changeId;
  final DateTime? beforeDeadlineUtc;
  final DateTime? afterDeadlineUtc;

  DateTime? get effectiveBeforeUtc =>
      beforeDeadlineUtc ??
      (kind == AssignmentChangeKind.deadline && before.trim().isNotEmpty
          ? DateTime.tryParse(before.trim())?.toUtc()
          : null);

  DateTime? get effectiveAfterUtc =>
      afterDeadlineUtc ??
      (kind == AssignmentChangeKind.deadline && after.trim().isNotEmpty
          ? DateTime.tryParse(after.trim())?.toUtc()
          : null);

  String get effectiveChangeId =>
      (changeId != null && changeId!.trim().isNotEmpty)
          ? changeId!.trim()
          : computeChangeId(
              kind: kind,
              assignmentId: assignmentId,
              at: at,
              before: before,
              after: after,
              beforeDeadlineUtc: effectiveBeforeUtc,
              afterDeadlineUtc: effectiveAfterUtc,
            );

  bool get isAdvanceDeadlineAlert {
    if (kind != AssignmentChangeKind.deadline) return false;
    final afterUtc = effectiveAfterUtc;
    if (afterUtc == null) return false;
    final beforeUtc = effectiveBeforeUtc;
    if (beforeUtc != null) {
      return afterUtc.isBefore(beforeUtc);
    }
    final atUtc = at.toUtc();
    return afterUtc.isAfter(atUtc) &&
        !afterUtc.isAfter(atUtc.add(const Duration(hours: 72)));
  }

  static String computeChangeId({
    required AssignmentChangeKind kind,
    required String assignmentId,
    required DateTime at,
    required String before,
    required String after,
    DateTime? beforeDeadlineUtc,
    DateTime? afterDeadlineUtc,
  }) {
    final payload = [
      kind.name,
      assignmentId,
      at.toUtc().toIso8601String(),
      beforeDeadlineUtc?.toUtc().toIso8601String() ?? before,
      afterDeadlineUtc?.toUtc().toIso8601String() ?? after,
    ].join('|');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Map<String, dynamic> toJson() => {
        'id': assignmentId,
        'title': title,
        'course': courseName,
        'kind': kind.name,
        'at': at.toUtc().toIso8601String(),
        'before': before,
        'after': after,
        'changeId': effectiveChangeId,
        if (effectiveBeforeUtc != null)
          'beforeUtc': effectiveBeforeUtc!.toIso8601String(),
        if (effectiveAfterUtc != null)
          'afterUtc': effectiveAfterUtc!.toIso8601String(),
      };

  static DateTime? _parseOptionalUtc(dynamic value) =>
      value is String && value.trim().isNotEmpty
          ? DateTime.tryParse(value.trim())?.toUtc()
          : null;

  factory AssignmentChange.fromJson(Map<String, dynamic> j) => AssignmentChange(
        assignmentId: j['id'] as String,
        title: j['title'] as String,
        courseName: j['course'] as String,
        kind: AssignmentChangeKind.values.byName(j['kind'] as String),
        at: DateTime.parse(j['at'] as String).toLocal(),
        before: j['before'] as String,
        after: j['after'] as String,
        changeId: j['changeId'] is String &&
                (j['changeId'] as String).trim().isNotEmpty
            ? (j['changeId'] as String).trim()
            : null,
        beforeDeadlineUtc: _parseOptionalUtc(j['beforeUtc']),
        afterDeadlineUtc: _parseOptionalUtc(j['afterUtc']),
      );

  static List<AssignmentChange> compare(List<Assignment> previous,
      List<Assignment> current, Set<String> observedIds, DateTime at) {
    final old = {for (final a in previous) a.id: a};
    final changes = <AssignmentChange>[];
    for (final a in current.where((a) => observedIds.contains(a.id))) {
      final prior = old[a.id];
      void add(
        AssignmentChangeKind kind,
        String before,
        String after, {
        DateTime? beforeDeadlineUtc,
        DateTime? afterDeadlineUtc,
      }) =>
          changes.add(AssignmentChange(
            assignmentId: a.id,
            title: a.title,
            courseName: a.courseName,
            kind: kind,
            at: at,
            before: before,
            after: after,
            changeId: computeChangeId(
              kind: kind,
              assignmentId: a.id,
              at: at,
              before: before,
              after: after,
              beforeDeadlineUtc: beforeDeadlineUtc,
              afterDeadlineUtc: afterDeadlineUtc,
            ),
            beforeDeadlineUtc: beforeDeadlineUtc,
            afterDeadlineUtc: afterDeadlineUtc,
          ));
      if (prior == null) {
        add(AssignmentChangeKind.published, '', '新读取到作业');
        continue;
      }
      final before = prior.deadlineAt;
      final after = a.deadlineAt;
      final sameDeadline = before == null
          ? after == null
          : after != null && before.isAtSameMomentAs(after);
      final isBackupPlaceholder =
          prior.lastSyncedAt.millisecondsSinceEpoch <= 0 &&
              !prior.deadlineTrusted &&
              prior.deadlineRawText == '备份记录，待同步确认';
      if (prior.deadlineTrusted &&
          !prior.deadlineReadFailed &&
          a.deadlineTrusted &&
          !a.deadlineReadFailed &&
          !sameDeadline) {
        add(
          AssignmentChangeKind.deadline,
          before?.toUtc().toIso8601String() ?? '',
          after?.toUtc().toIso8601String() ?? '',
          beforeDeadlineUtc: before?.toUtc(),
          afterDeadlineUtc: after?.toUtc(),
        );
      } else if (!isBackupPlaceholder &&
          (!prior.deadlineTrusted || prior.deadlineReadFailed) &&
          a.deadlineTrusted &&
          !a.deadlineReadFailed &&
          after != null) {
        final sameTrustedRecovery = prior.deadlineTrusted &&
            prior.deadlineReadFailed &&
            before != null &&
            before.isAtSameMomentAs(after);
        final atUtc = at.toUtc();
        final afterUtc = after.toUtc();
        final withinAdvanceWindow = afterUtc.isAfter(atUtc) &&
            !afterUtc.isAfter(atUtc.add(const Duration(hours: 72)));
        if (!sameTrustedRecovery && withinAdvanceWindow) {
          add(
            AssignmentChangeKind.deadline,
            '',
            afterUtc.toIso8601String(),
            beforeDeadlineUtc: null,
            afterDeadlineUtc: afterUtc,
          );
        }
      }
      if (prior.statusLabel != a.statusLabel && a.statusLabel != '提交状态未知') {
        add(AssignmentChangeKind.status, prior.statusLabel, a.statusLabel);
      }
    }
    return changes;
  }
}
