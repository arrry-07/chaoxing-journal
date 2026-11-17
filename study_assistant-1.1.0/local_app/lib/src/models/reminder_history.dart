class ReminderHistoryException implements Exception {
  const ReminderHistoryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '提醒记录操作失败（$code）：$message';
}

class ReminderReadContext {
  const ReminderReadContext({
    required this.accountHash,
    required this.sessionEpoch,
    required this.historyGeneration,
  });

  final String accountHash;
  final int sessionEpoch;
  final int historyGeneration;

  Map<String, Object?> toJson() => {
        'accountHash': accountHash,
        'sessionEpoch': sessionEpoch,
        'historyGeneration': historyGeneration,
      };
}

class ReminderSubjectRef {
  const ReminderSubjectRef(this.kind, this.id);

  final String kind;
  final String? id;
}

class ReminderObservationContext extends ReminderReadContext {
  const ReminderObservationContext({
    required super.accountHash,
    required super.sessionEpoch,
    required super.historyGeneration,
    required this.operationSequence,
  });

  final int operationSequence;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'operationSequence': operationSequence,
      };
}

class ReminderHistoryControl {
  const ReminderHistoryControl({
    required this.historyGeneration,
    required this.recordingEnabled,
    required this.ownerMatches,
    required this.purgePending,
    required this.purgeToken,
  });

  final int historyGeneration;
  final bool recordingEnabled;
  final bool ownerMatches;
  final bool purgePending;
  final String? purgeToken;
}

class ReminderObservation {
  const ReminderObservation({
    this.observationId,
    this.ordinal = 0,
    required this.subjectKind,
    this.subjectId,
    required this.logicalKey,
    required this.category,
    required this.stage,
    this.reasonCode,
    this.observedAt,
    this.scheduledAt,
    this.notificationId,
    this.batchKey,
  });

  final String? observationId;
  final int ordinal;
  final String subjectKind;
  final String? subjectId;
  final String logicalKey;
  final String category;
  final String stage;
  final String? reasonCode;
  final DateTime? observedAt;
  final DateTime? scheduledAt;
  final int? notificationId;
  final String? batchKey;

  Map<String, Object?> toJson() => {
        if (observationId != null) 'observationId': observationId,
        'ordinal': ordinal,
        'subjectKind': subjectKind,
        if (subjectId != null) 'subjectId': subjectId,
        'logicalKey': logicalKey,
        'category': category,
        'stage': stage,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (observedAt != null)
          'observedAt': observedAt!.toUtc().toIso8601String(),
        if (scheduledAt != null)
          'scheduledAt': scheduledAt!.toUtc().toIso8601String(),
        if (notificationId != null) 'notificationId': notificationId,
        if (batchKey != null) 'batchKey': batchKey,
      };
}

class ReminderHistoryItem {
  const ReminderHistoryItem({
    required this.id,
    required this.observationId,
    required this.operationSequence,
    required this.subjectKind,
    required this.subjectId,
    required this.logicalKey,
    required this.category,
    required this.stage,
    required this.reasonCode,
    required this.observedAt,
    required this.scheduledAt,
    required this.notificationId,
    required this.batchKey,
  });

  final int id;
  final String observationId;
  final int operationSequence;
  final String subjectKind;
  final String? subjectId;
  final String logicalKey;
  final String category;
  final String stage;
  final String? reasonCode;
  final DateTime observedAt;
  final DateTime? scheduledAt;
  final int? notificationId;
  final String? batchKey;
}

class ReminderHistoryPage {
  const ReminderHistoryPage({
    required this.items,
    required this.snapshotMaxId,
    required this.nextBeforeId,
    required this.checkedAt,
    required this.historyGeneration,
  });

  final List<ReminderHistoryItem> items;
  final int snapshotMaxId;
  final int? nextBeforeId;
  final DateTime checkedAt;
  final int historyGeneration;
}

class ReminderNativeSubjectEvidence {
  const ReminderNativeSubjectEvidence({
    required this.subjectKind,
    required this.subjectId,
    required this.eventId,
    required this.category,
    required this.logicalKey,
    required this.state,
    required this.scheduledAt,
    required this.notificationId,
    required this.evidenceAt,
    this.alarmScheduled,
  });

  final String subjectKind;
  final String? subjectId;
  final String eventId;
  final String category;
  final String logicalKey;
  final String state;
  final DateTime? scheduledAt;
  final int? notificationId;
  final DateTime? evidenceAt;
  final bool? alarmScheduled;
}

class ReminderPluginSubjectEvidence {
  const ReminderPluginSubjectEvidence({
    required this.subjectKind,
    required this.subjectId,
    required this.logicalKey,
    required this.category,
    required this.state,
    required this.scheduledAt,
    required this.notificationId,
    required this.expectedPayload,
    required this.evidenceAt,
  });

  final String subjectKind;
  final String subjectId;
  final String logicalKey;
  final String category;
  final String state;
  final DateTime? scheduledAt;
  final int? notificationId;
  final String? expectedPayload;
  final DateTime? evidenceAt;
}

class ReminderSubjectEvidence {
  const ReminderSubjectEvidence({
    required this.checkedAt,
    required this.nativeEvents,
    required this.pluginEvidence,
    required this.queryWarnings,
    required this.historyGeneration,
  });

  final DateTime checkedAt;
  final List<ReminderNativeSubjectEvidence> nativeEvents;
  final List<ReminderPluginSubjectEvidence> pluginEvidence;
  final List<String> queryWarnings;
  final int historyGeneration;
}

class ReminderScheduleOutcome {
  const ReminderScheduleOutcome({
    required this.subjectKind,
    this.subjectId,
    required this.logicalKey,
    required this.category,
    required this.stage,
    this.reasonCode,
    this.observedAt,
    this.scheduledAt,
    this.notificationId,
    this.expectedPayload,
    this.evidenceState,
    this.batchKey,
  });

  final String subjectKind;
  final String? subjectId;
  final String logicalKey;
  final String category;
  final String stage;
  final String? reasonCode;
  final DateTime? observedAt;
  final DateTime? scheduledAt;
  final int? notificationId;
  final String? expectedPayload;
  final String? evidenceState;
  final String? batchKey;

  Map<String, Object?> toJson() => {
        'subjectKind': subjectKind,
        if (subjectId != null) 'subjectId': subjectId,
        'logicalKey': logicalKey,
        'category': category,
        'stage': stage,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (observedAt != null)
          'observedAt': observedAt!.toUtc().toIso8601String(),
        if (scheduledAt != null)
          'scheduledAt': scheduledAt!.toUtc().toIso8601String(),
        if (notificationId != null) 'notificationId': notificationId,
        if (expectedPayload != null) 'expectedPayload': expectedPayload,
        if (evidenceState != null) 'evidenceState': evidenceState,
        if (batchKey != null) 'batchKey': batchKey,
      };
}

class ReminderScheduleOutcomeResult {
  const ReminderScheduleOutcomeResult({
    required this.evidenceUpdated,
    required this.evidenceIgnored,
    required this.inserted,
    required this.duplicate,
    required this.expired,
    required this.warning,
  });

  final int evidenceUpdated;
  final int evidenceIgnored;
  final int inserted;
  final int duplicate;
  final int expired;
  final String? warning;
}

class PluginScheduleEvidence {
  const PluginScheduleEvidence({
    required this.id,
    required this.payload,
    required this.channelId,
    required this.pending,
    required this.active,
  });

  final int id;
  final String? payload;
  final String? channelId;
  final bool pending;
  final bool active;
}

class PluginScheduleEvidenceSnapshot {
  const PluginScheduleEvidenceSnapshot({
    required this.items,
    required this.error,
    required this.checkedAt,
  });

  final List<PluginScheduleEvidence> items;
  final String? error;
  final DateTime checkedAt;
}

class ReminderHistoryLogoutStart {
  const ReminderHistoryLogoutStart({
    required this.historyGeneration,
    required this.purgeToken,
  });

  final int historyGeneration;
  final String purgeToken;
}

class ReminderHistoryLogoutFinish {
  const ReminderHistoryLogoutFinish({
    required this.cleared,
    required this.historyGeneration,
  });

  final bool cleared;
  final int historyGeneration;
}

enum ReminderExplanationStatus {
  planned,
  deferred,
  ineligible,
  unconfirmed,
  queryFailed,
}

class ReminderCategoryExplanation {
  const ReminderCategoryExplanation({
    required this.category,
    required this.status,
    required this.reasonCodes,
    required this.nextScheduledAt,
    required this.evidenceAt,
    required this.actionLabel,
  });

  final String category;
  final ReminderExplanationStatus status;
  final List<String> reasonCodes;
  final DateTime? nextScheduledAt;
  final DateTime? evidenceAt;
  final String? actionLabel;
}

class ReminderExplanation {
  const ReminderExplanation({
    required this.checkedAt,
    required this.subjectKind,
    required this.subjectId,
    required this.displayName,
    required this.categories,
    required this.queryWarnings,
  });

  final DateTime checkedAt;
  final String subjectKind;
  final String? subjectId;
  final String displayName;
  final List<ReminderCategoryExplanation> categories;
  final List<String> queryWarnings;
}
