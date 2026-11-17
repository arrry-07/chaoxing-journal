package com.example.studyassistant

import android.content.Context
import android.util.Log
import java.util.UUID

data class ReminderObservationContext(
    val accountHash: String,
    val sessionEpoch: Long,
    val historyGeneration: Long,
    val operationSequence: Long,
)

data class ReminderHistoryControlSnapshot(
    val historyGeneration: Long,
    val recordingEnabled: Boolean,
    val ownerMatches: Boolean,
    val purgePending: Boolean,
    val purgeToken: String?,
    val purgeRequestId: String?,
)

data class ReminderHistoryObservationInput(
    val observationId: String?,
    val ordinal: Int,
    val subjectKind: String,
    val subjectId: String?,
    val logicalKey: String,
    val category: String,
    val stage: String,
    val reasonCode: String?,
    val observedAt: Long?,
    val scheduledAt: Long?,
    val notificationId: Int?,
    val batchKey: String?,
)

data class ReminderScheduleOutcomeInput(
    val subjectKind: String,
    val subjectId: String?,
    val logicalKey: String,
    val category: String,
    val stage: String,
    val reasonCode: String?,
    val observedAt: Long?,
    val scheduledAt: Long?,
    val notificationId: Int?,
    val expectedPayload: String?,
    val evidenceState: String?,
    val batchKey: String?,
)

class ReminderHistoryException(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

object ReminderHistoryStore {
    const val PREFS = "reminder_history_control"
    const val RETENTION_DAYS = 30L
    const val MAX_ROWS_PER_ACCOUNT = 500

    private const val KEY_GENERATION = "history_generation"
    private const val KEY_RECORDING = "recording_enabled"
    private const val KEY_OWNER_HASH = "owner_hash"
    private const val KEY_OWNER_EPOCH = "owner_epoch"
    private const val KEY_PURGE_PENDING = "purge_pending"
    private const val KEY_PURGE_TOKEN = "purge_token"
    private const val KEY_PURGE_REQUEST = "purge_request_id"
    private const val KEY_LAST_PURGE_TOKEN = "last_purge_token"
    private const val KEY_NEXT_SEQUENCE = "next_operation_sequence"
    private const val KEY_PRUNED_PREFIX = "pruned_through_"

    private val lock = Any()

    private val categories = setOf(
        "newAssignment",
        "deadline",
        "examStart",
        "personal",
        "summary",
        "backgroundCheck",
    )
    private val stages = setOf(
        "scheduled",
        "deferred",
        "submitted",
        "cancelled",
        "blocked",
        "scheduleFailed",
        "cancelFailed",
        "recoveryPending",
        "unconfirmed",
    )
    private val evidenceStates = setOf(
        "confirmedScheduled",
        "retainedOld",
        "recoveryPending",
    )
    private val subjectKinds = setOf("assignment", "manual", "summary", "account")

    fun controlSnapshot(
        context: Context,
        accountHash: String?,
        sessionEpoch: Long?,
    ): ReminderHistoryControlSnapshot = synchronized(lock) {
        val prefs = prefs(context)
        val generation = prefs.getLong(KEY_GENERATION, 1L).coerceAtLeast(1L)
        val ownerHash = prefs.getString(KEY_OWNER_HASH, null)
        val ownerEpoch = if (prefs.contains(KEY_OWNER_EPOCH)) {
            prefs.getLong(KEY_OWNER_EPOCH, 0L)
        } else {
            null
        }
        val purgePending = prefs.getBoolean(KEY_PURGE_PENDING, false)
        ReminderHistoryControlSnapshot(
            historyGeneration = generation,
            recordingEnabled = prefs.getBoolean(KEY_RECORDING, false),
            ownerMatches = accountHash != null &&
                sessionEpoch != null &&
                ownerHash == accountHash &&
                ownerEpoch == sessionEpoch,
            purgePending = purgePending,
            purgeToken = if (purgePending) prefs.getString(KEY_PURGE_TOKEN, null) else null,
            purgeRequestId = prefs.getString(KEY_PURGE_REQUEST, null),
        )
    }

    fun acquireObservationContext(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        sessionEpoch: Long,
    ): ReminderObservationContext = synchronized(lock) {
        val prefs = prefs(context)
        val generation = prefs.getLong(KEY_GENERATION, 1L).coerceAtLeast(1L)
        if (!prefs.getBoolean(KEY_RECORDING, false) ||
            prefs.getBoolean(KEY_PURGE_PENDING, false) ||
            prefs.getString(KEY_OWNER_HASH, null) != accountHash ||
            !prefs.contains(KEY_OWNER_EPOCH) ||
            prefs.getLong(KEY_OWNER_EPOCH, 0L) != sessionEpoch
        ) {
            throw ReminderHistoryException(
                "history_unavailable",
                "提醒历史记录尚未启用或正在清理",
            )
        }
        val account = database.readAccount(accountHash)
        if (account == null || !account.active || account.sessionEpoch != sessionEpoch) {
            throw ReminderHistoryException("stale_session", "提醒历史所属会话已变化")
        }
        val next = prefs.getLong(KEY_NEXT_SEQUENCE, 0L) + 1L
        if (!prefs.edit().putLong(KEY_NEXT_SEQUENCE, next).commit()) {
            throw ReminderHistoryException(
                "history_unavailable",
                "提醒历史操作序号未能保存",
            )
        }
        ReminderObservationContext(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            historyGeneration = generation,
            operationSequence = next,
        )
    }

    fun appendObservation(
        context: Context,
        database: ReminderDatabase,
        observationContext: ReminderObservationContext,
        observation: ReminderHistoryObservationInput,
    ): String = synchronized(lock) {
        appendLocked(context, database, observationContext, observation)
    }

    fun recordNativeObservations(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        observations: List<ReminderHistoryObservationInput>,
    ): String? {
        if (observations.isEmpty()) return null
        return synchronized(lock) {
            val prefs = prefs(context)
            if (!prefs.getBoolean(KEY_RECORDING, false) ||
                prefs.getBoolean(KEY_PURGE_PENDING, false) ||
                prefs.getString(KEY_OWNER_HASH, null) != accountHash
            ) {
                return@synchronized null
            }
            val epoch = prefs.getLong(KEY_OWNER_EPOCH, 0L)
            val generation = prefs.getLong(KEY_GENERATION, 1L).coerceAtLeast(1L)
            val next = prefs.getLong(KEY_NEXT_SEQUENCE, 0L) + 1L
            if (!prefs.edit().putLong(KEY_NEXT_SEQUENCE, next).commit()) {
                return@synchronized "提醒记录操作序号未能保存"
            }
            val observationContext = ReminderObservationContext(
                accountHash = accountHash,
                sessionEpoch = epoch,
                historyGeneration = generation,
                operationSequence = next,
            )
            var warning: String? = null
            for (observation in observations) {
                val result = runCatching {
                    appendLocked(
                        context,
                        database,
                        observationContext,
                        observation,
                    )
                }.getOrElse {
                    warning = "提醒记录未能保存：${it.message.orEmpty()}"
                    "unavailable"
                }
                if (result == "unavailable" || result == "stale") {
                    Log.w("ReminderHistory", "native_observation_$result")
                }
            }
            warning
        }
    }

    fun recordScheduleOutcome(
        context: Context,
        database: ReminderDatabase,
        observationContext: ReminderObservationContext,
        outcomes: List<ReminderScheduleOutcomeInput>,
    ): Map<String, Any?> = synchronized(lock) {
        validateContextLocked(context, database, observationContext)
        var evidenceUpdated = 0
        var evidenceIgnored = 0
        var inserted = 0
        var duplicate = 0
        var expired = 0
        var warning: String? = null
        val now = System.currentTimeMillis()
        for ((index, outcome) in outcomes.withIndex()) {
            validateObservation(
                outcome.subjectKind,
                outcome.category,
                outcome.stage,
                outcome.logicalKey,
            )
            if (outcome.evidenceState == "removed") {
                if (database.removeReminderScheduleEvidence(
                        observationContext.accountHash,
                        observationContext.historyGeneration,
                        outcome.logicalKey,
                        observationContext.operationSequence,
                    )
                ) {
                    evidenceUpdated++
                } else {
                    evidenceIgnored++
                }
            } else {
                val state = outcome.evidenceState
                if (state != null) {
                    require(state in evidenceStates) {
                        "未知提醒排期证据状态"
                    }
                    val row = ReminderScheduleEvidenceRow(
                        accountHash = observationContext.accountHash,
                        historyGeneration = observationContext.historyGeneration,
                        logicalKey = outcome.logicalKey,
                        sessionEpoch = observationContext.sessionEpoch,
                        operationSequence = observationContext.operationSequence,
                        subjectKind = outcome.subjectKind,
                        subjectId = outcome.subjectId,
                        category = outcome.category,
                        scheduledAt = outcome.scheduledAt,
                        notificationId = outcome.notificationId,
                        expectedPayload = outcome.expectedPayload,
                        state = state,
                        confirmedAt = outcome.observedAt ?: now,
                    )
                    if (database.recordReminderScheduleEvidence(row)) {
                        evidenceUpdated++
                    } else {
                        evidenceIgnored++
                    }
                }
            }
            val result = runCatching {
                appendLocked(
                    context,
                    database,
                    observationContext,
                    ReminderHistoryObservationInput(
                        observationId = null,
                        ordinal = index,
                        subjectKind = outcome.subjectKind,
                        subjectId = outcome.subjectId,
                        logicalKey = outcome.logicalKey,
                        category = outcome.category,
                        stage = outcome.stage,
                        reasonCode = outcome.reasonCode,
                        observedAt = outcome.observedAt,
                        scheduledAt = outcome.scheduledAt,
                        notificationId = outcome.notificationId,
                        batchKey = outcome.batchKey,
                    ),
                )
            }.getOrElse {
                warning = "提醒记录未能保存：${it.message.orEmpty()}"
                "unavailable"
            }
            when (result) {
                "inserted" -> inserted++
                "duplicate" -> duplicate++
                "expired" -> expired++
            }
        }
        mapOf(
            "evidenceUpdated" to evidenceUpdated,
            "evidenceIgnored" to evidenceIgnored,
            "inserted" to inserted,
            "duplicate" to duplicate,
            "expired" to expired,
            "warning" to warning,
        )
    }

    fun listHistory(
        context: Context,
        database: ReminderDatabase,
        observationContext: ReminderObservationContext,
        snapshotMaxId: Long?,
        beforeId: Long?,
        category: String?,
        subjectRefs: List<Pair<String, String?>>,
    ): Map<String, Any?> = synchronized(lock) {
        validateContextLocked(context, database, observationContext)
        if (category != null && category !in categories) {
            throw ReminderHistoryException(
                "invalid_history_argument",
                "未知提醒记录类别",
            )
        }
        subjectRefs.forEach { (kind, _) ->
            if (kind !in subjectKinds) {
                throw ReminderHistoryException(
                    "invalid_history_argument",
                    "未知事项类型",
                )
            }
        }
        val generation = observationContext.historyGeneration
        val maxId = snapshotMaxId
            ?: database.maxReminderHistoryId(
                observationContext.accountHash,
                generation,
            )
        val rows = database.listReminderHistory(
            accountHash = observationContext.accountHash,
            historyGeneration = generation,
            snapshotMaxId = if (maxId > 0) maxId else null,
            beforeId = beforeId,
            category = category,
            subjectRefs = subjectRefs,
        )
        mapOf(
            "items" to rows.map { it.toBridgeMap() },
            "snapshotMaxId" to maxId,
            "nextBeforeId" to if (rows.size == 50) rows.last().id else null,
            "checkedAt" to System.currentTimeMillis(),
            "historyGeneration" to generation,
        )
    }

    fun inspectSubjects(
        context: Context,
        database: ReminderDatabase,
        observationContext: ReminderObservationContext,
        subjectRefs: List<Pair<String, String?>>,
    ): Map<String, Any?> = synchronized(lock) {
        validateContextLocked(context, database, observationContext)
        val nativeEvents = mutableListOf<Map<String, Any?>>()
        val pluginEvidence = mutableListOf<Map<String, Any?>>()
        val warnings = mutableListOf<String>()
        for ((kind, id) in subjectRefs) {
            if (kind !in subjectKinds) {
                throw ReminderHistoryException(
                    "invalid_history_argument",
                    "未知事项类型",
                )
            }
            try {
                database.eventsForSubject(
                    observationContext.accountHash,
                    id,
                ).forEach { event ->
                    nativeEvents.add(
                        mapOf(
                            "subjectKind" to kind,
                            "subjectId" to id,
                            "eventId" to event.eventId,
                            "category" to
                                if (event.type == ReminderDatabase.EVENT_NEW) {
                                    "newAssignment"
                                } else {
                                    event.eventKind
                                },
                            "logicalKey" to event.eventId,
                            "state" to event.status,
                            "scheduledAt" to event.notifyAt,
                            "notificationId" to event.notificationId,
                            "evidenceAt" to event.notifyAt,
                        ),
                    )
                }
                database.scheduleEvidenceForSubject(
                    observationContext.accountHash,
                    observationContext.historyGeneration,
                    kind,
                    id,
                ).forEach { evidence ->
                    pluginEvidence.add(
                        mapOf(
                            "subjectKind" to kind,
                            "subjectId" to id,
                            "logicalKey" to evidence.logicalKey,
                            "category" to evidence.category,
                            "state" to evidence.state,
                            "scheduledAt" to evidence.scheduledAt,
                            "notificationId" to evidence.notificationId,
                            "expectedPayload" to evidence.expectedPayload,
                            "evidenceAt" to evidence.confirmedAt,
                        ),
                    )
                }
            } catch (error: Exception) {
                warnings.add("$kind:$id 查询失败")
            }
        }
        mapOf(
            "checkedAt" to System.currentTimeMillis(),
            "nativeEvents" to nativeEvents,
            "pluginEvidence" to pluginEvidence,
            "queryWarnings" to warnings,
            "historyGeneration" to observationContext.historyGeneration,
        )
    }

    fun beginLogout(
        context: Context,
        expectedHistoryGeneration: Long,
        requestId: String,
    ): Map<String, Any?> = synchronized(lock) {
        val prefs = prefs(context)
        val generation = prefs.getLong(KEY_GENERATION, 1L).coerceAtLeast(1L)
        val purgePending = prefs.getBoolean(KEY_PURGE_PENDING, false)
        if (purgePending) {
            val existingRequest = prefs.getString(KEY_PURGE_REQUEST, null)
            if (existingRequest == requestId) {
                return@synchronized mapOf(
                    "state" to "pending",
                    "historyGeneration" to generation,
                    "purgeToken" to prefs.getString(KEY_PURGE_TOKEN, null),
                )
            }
            return@synchronized mapOf(
                "state" to "pending",
                "historyGeneration" to generation,
                "purgeToken" to prefs.getString(KEY_PURGE_TOKEN, null),
            )
        }
        if (expectedHistoryGeneration != generation) {
            throw ReminderHistoryException(
                "stale_history_generation",
                "提醒历史代次已变化",
            )
        }
        val nextGeneration = generation + 1L
        val token = UUID.randomUUID().toString()
        val editor = prefs.edit()
            .putLong(KEY_GENERATION, nextGeneration)
            .putBoolean(KEY_RECORDING, false)
            .putBoolean(KEY_PURGE_PENDING, true)
            .putString(KEY_PURGE_TOKEN, token)
            .putString(KEY_PURGE_REQUEST, requestId)
            .remove(KEY_OWNER_HASH)
            .remove(KEY_OWNER_EPOCH)
        if (!editor.commit()) {
            throw ReminderHistoryException(
                "history_unavailable",
                "提醒历史暂停状态未能保存",
            )
        }
        mapOf(
            "state" to "pending",
            "historyGeneration" to nextGeneration,
            "purgeToken" to token,
        )
    }

    fun finishLogout(
        context: Context,
        database: ReminderDatabase,
        purgeToken: String,
    ): Map<String, Any?> = synchronized(lock) {
        val prefs = prefs(context)
        val purgePending = prefs.getBoolean(KEY_PURGE_PENDING, false)
        val generation = prefs.getLong(KEY_GENERATION, 1L).coerceAtLeast(1L)
        if (!purgePending) {
            if (prefs.getString(KEY_LAST_PURGE_TOKEN, null) == purgeToken) {
                return@synchronized mapOf(
                    "cleared" to true,
                    "historyGeneration" to generation,
                )
            }
            throw ReminderHistoryException(
                "stale_history_generation",
                "提醒历史清理请求已失效",
            )
        }
        if (prefs.getString(KEY_PURGE_TOKEN, null) != purgeToken) {
            throw ReminderHistoryException(
                "stale_history_generation",
                "提醒历史清理令牌已失效",
            )
        }
        try {
            database.deleteAllReminderHistory()
        } catch (error: Exception) {
            throw ReminderHistoryException(
                "history_unavailable",
                "本机提醒记录清理失败",
                error,
            )
        }
        val editor = prefs.edit()
            .putBoolean(KEY_PURGE_PENDING, false)
            .putString(KEY_LAST_PURGE_TOKEN, purgeToken)
            .remove(KEY_PURGE_TOKEN)
        if (!editor.commit()) {
            throw ReminderHistoryException(
                "history_unavailable",
                "提醒历史清理完成状态未能保存",
            )
        }
        mapOf(
            "cleared" to true,
            "historyGeneration" to generation,
        )
    }

    fun enableSession(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        sessionEpoch: Long,
        expectedHistoryGeneration: Long,
    ): Map<String, Any?> = synchronized(lock) {
        val prefs = prefs(context)
        val generation = prefs.getLong(KEY_GENERATION, 1L).coerceAtLeast(1L)
        if (generation != expectedHistoryGeneration) {
            throw ReminderHistoryException(
                "stale_history_generation",
                "提醒历史代次已变化",
            )
        }
        if (prefs.getBoolean(KEY_PURGE_PENDING, false)) {
            throw ReminderHistoryException(
                "history_unavailable",
                "提醒历史仍待清理",
            )
        }
        val account = database.readAccount(accountHash)
        if (account == null || !account.active || account.sessionEpoch != sessionEpoch) {
            throw ReminderHistoryException("stale_session", "提醒历史所属会话已变化")
        }
        val editor = prefs.edit()
            .putBoolean(KEY_RECORDING, true)
            .putString(KEY_OWNER_HASH, accountHash)
            .putLong(KEY_OWNER_EPOCH, sessionEpoch)
        if (!editor.commit()) {
            throw ReminderHistoryException(
                "history_unavailable",
                "提醒历史启用状态未能保存",
            )
        }
        mapOf(
            "historyGeneration" to generation,
            "recordingEnabled" to true,
        )
    }

    private fun appendLocked(
        context: Context,
        database: ReminderDatabase,
        observationContext: ReminderObservationContext,
        observation: ReminderHistoryObservationInput,
    ): String {
        validateContextLocked(context, database, observationContext)
        validateObservation(
            observation.subjectKind,
            observation.category,
            observation.stage,
            observation.logicalKey,
        )
        val prefs = prefs(context)
        val observationId = observation.observationId
            ?: "${observationContext.historyGeneration}:" +
            "${observationContext.operationSequence}:${observation.ordinal}"
        val now = System.currentTimeMillis()
        val result = database.insertReminderHistory(
            accountHash = observationContext.accountHash,
            sessionEpoch = observationContext.sessionEpoch,
            historyGeneration = observationContext.historyGeneration,
            observationId = observationId,
            operationSequence = observationContext.operationSequence,
            subjectKind = observation.subjectKind,
            subjectId = observation.subjectId,
            logicalKey = observation.logicalKey,
            category = observation.category,
            stage = observation.stage,
            reasonCode = observation.reasonCode,
            observedAt = observation.observedAt ?: now,
            scheduledAt = observation.scheduledAt,
            notificationId = observation.notificationId,
            batchKey = observation.batchKey,
            retentionCutoff = now - RETENTION_DAYS * 24L * 60L * 60L * 1000L,
            maxRows = MAX_ROWS_PER_ACCOUNT,
            currentPrunedThrough = {
                prunedThrough(prefs, observationContext.accountHash)
            },
            persistPrunedThrough = { watermark ->
                persistPrunedThrough(prefs, observationContext.accountHash, watermark)
            },
        )
        return when (result) {
            ReminderHistoryInsertResult.INSERTED -> "inserted"
            ReminderHistoryInsertResult.DUPLICATE -> "duplicate"
            ReminderHistoryInsertResult.EXPIRED -> "expired"
        }
    }

    private fun validateContextLocked(
        context: Context,
        database: ReminderDatabase,
        observationContext: ReminderObservationContext,
    ) {
        val prefs = prefs(context)
        val generation = prefs.getLong(KEY_GENERATION, 1L).coerceAtLeast(1L)
        if (!prefs.getBoolean(KEY_RECORDING, false) ||
            prefs.getBoolean(KEY_PURGE_PENDING, false)
        ) {
            throw ReminderHistoryException(
                "history_unavailable",
                "提醒历史记录当前不可用",
            )
        }
        if (generation != observationContext.historyGeneration) {
            throw ReminderHistoryException(
                "stale_history_generation",
                "提醒历史代次已变化",
            )
        }
        if (prefs.getString(KEY_OWNER_HASH, null) != observationContext.accountHash ||
            !prefs.contains(KEY_OWNER_EPOCH) ||
            prefs.getLong(KEY_OWNER_EPOCH, 0L) != observationContext.sessionEpoch
        ) {
            throw ReminderHistoryException(
                "stale_session",
                "提醒历史所属会话已变化",
            )
        }
        val account = database.readAccount(observationContext.accountHash)
        if (account == null ||
            !account.active ||
            account.sessionEpoch != observationContext.sessionEpoch
        ) {
            throw ReminderHistoryException(
                "stale_session",
                "提醒历史所属会话已变化",
            )
        }
    }

    private fun validateObservation(
        subjectKind: String,
        category: String,
        stage: String,
        logicalKey: String,
    ) {
        if (subjectKind !in subjectKinds ||
            category !in categories ||
            stage !in stages ||
            logicalKey.isBlank() ||
            logicalKey.length > 200
        ) {
            throw ReminderHistoryException(
                "invalid_history_argument",
                "提醒记录字段不在允许范围内",
            )
        }
    }

    private fun prunedThrough(
        prefs: android.content.SharedPreferences,
        accountHash: String,
    ): Long = prefs.getLong("$KEY_PRUNED_PREFIX$accountHash", 0L)

    private fun persistPrunedThrough(
        prefs: android.content.SharedPreferences,
        accountHash: String,
        watermark: Long,
    ) {
        if (!prefs.edit()
                .putLong("$KEY_PRUNED_PREFIX$accountHash", watermark)
                .commit()
        ) {
            throw ReminderHistoryException(
                "history_unavailable",
                "提醒记录裁剪水位未能保存",
            )
        }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun ReminderHistoryRow.toBridgeMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "observationId" to observationId,
        "operationSequence" to operationSequence,
        "subjectKind" to subjectKind,
        "subjectId" to subjectId,
        "logicalKey" to logicalKey,
        "category" to category,
        "stage" to stage,
        "reasonCode" to reasonCode,
        "observedAt" to observedAt,
        "scheduledAt" to scheduledAt,
        "notificationId" to notificationId,
        "batchKey" to batchKey,
    )
}
