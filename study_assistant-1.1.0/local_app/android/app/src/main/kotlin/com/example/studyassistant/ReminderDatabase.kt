package com.example.studyassistant

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import androidx.annotation.VisibleForTesting
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.util.UUID

data class ReminderAccountState(
    val accountHash: String,
    val sessionEpoch: Long,
    val active: Boolean,
    val backgroundEnabled: Boolean,
    val intervalMinutes: Int,
    val listenerEnabled: Boolean,
    val newAssignmentEnabled: Boolean,
    val showDetails: Boolean,
    val baselineCompleted: Boolean,
    val knownAssignmentIds: Set<String>,
    val sentNewAssignmentIds: Set<String>,
    val pendingUpdate: Boolean,
    val mutationVersion: Long,
    val pendingSignalVersion: Long,
    val consumedSignalVersion: Long,
    val attemptedSignalVersion: Long,
    val lastSignalCheckAt: Long?,
    val lastAttemptAt: Long?,
    val lastDataSuccessAt: Long?,
    val lastFullSuccessAt: Long?,
    val lastFailure: String?,
    val nextCheckAt: Long?,
    val migrationState: String,
    val baselinedSources: Set<String> =
        if (baselineCompleted) setOf("courseWork") else emptySet(),
    val claimToken: String? = null,
    val allowUrgentNightBreakthrough: Boolean = false,
    val deadlineChannelId: String = AssignmentNotificationPublisher.CHANNEL_DEADLINES,
)

data class NotificationSignalClaim(
    val accountHash: String,
    val sessionEpoch: Long,
    val version: Long,
    val token: String,
    val claimedAt: Long,
    val priorAttemptedVersion: Long,
    val priorLastSignalCheckAt: Long?,
    val priorPendingVersion: Long,
    val priorConsumedVersion: Long,
    val ownerWorkId: String? = null,
)

enum class NotificationAttemptPhase(val value: String) {
    CLAIMED("claimed"),
    REMOTE_AUTHORIZED("remoteAuthorized"),
    WINDOW_DEFERRED("windowDeferred"),
    SETTLED("settled");

    companion object {
        fun from(value: String?): NotificationAttemptPhase? =
            entries.firstOrNull { it.value == value }
    }
}

data class NotificationAttempt(
    val accountHash: String,
    val sessionEpoch: Long,
    val claimToken: String,
    val ownerWorkId: String?,
    val claimedVersion: Long,
    val claimedAt: Long,
    val priorAttemptedVersion: Long,
    val priorLastSignalCheckAt: Long?,
    val priorConsumedVersion: Long,
    val phase: NotificationAttemptPhase,
)

enum class NotificationRemoteAuthorization {
    GRANTED,
    OUTSIDE_WINDOW,
    STALE,
}

data class StoredReminderSnapshot(
    val accountHash: String,
    val assignmentId: String,
    val sessionEpoch: Long,
    val courseName: String,
    val title: String,
    val deadlineAt: Long?,
    val deadlineTrusted: Boolean,
    val deadlineReadFailed: Boolean,
    val status: String,
    val completed: Boolean,
    val hidden: Boolean,
    val followed: Boolean,
    val formal: Boolean,
    val inAssignmentScope: Boolean = formal,
    val eventKind: String = "deadline",
    val deadlineSource: String = "official",
) {
    fun eligibleAt(now: Long): Boolean =
        inAssignmentScope && followed && !completed && !hidden &&
            (status == "pending" || status == "returned") &&
            deadlineTrusted && !deadlineReadFailed &&
            (eventKind == "deadline" || eventKind == "examStart") &&
            (eventKind != "examStart" || deadlineAt != null) &&
            (deadlineAt == null || deadlineAt > now)

    fun matchesEvent(event: StoredReminderEvent, now: Long): Boolean =
        eligibleAt(now) && accountHash == event.accountHash &&
            sessionEpoch == event.sessionEpoch && assignmentId == event.assignmentId &&
            eventKind == event.eventKind && deadlineAt == event.deadlineAt &&
            (event.type == ReminderDatabase.EVENT_NEW ||
                (event.type == ReminderDatabase.EVENT_DEADLINE &&
                    DeadlineQuietHoursPolicy.isTrustedSource(deadlineSource) &&
                    deadlineSource == event.deadlineSource &&
                    deadlineAt != null && event.notifyAt < deadlineAt))
}

data class StoredReminderEvent(
    val eventId: String,
    val accountHash: String,
    val sessionEpoch: Long,
    val type: String,
    val assignmentId: String,
    val courseName: String,
    val title: String,
    val notifyAt: Long,
    val deadlineAt: Long?,
    val offsets: List<Int>,
    val batchId: String?,
    val status: String,
    val notificationId: Int,
    val eventKind: String = "deadline",
    val updatedAt: Long = 0L,
    val deadlineSource: String = "official",
)

data class ReminderHistoryRow(
    val id: Long,
    val accountHash: String,
    val sessionEpoch: Long,
    val historyGeneration: Long,
    val observationId: String,
    val operationSequence: Long,
    val subjectKind: String,
    val subjectId: String?,
    val logicalKey: String,
    val category: String,
    val stage: String,
    val reasonCode: String?,
    val observedAt: Long,
    val scheduledAt: Long?,
    val notificationId: Int?,
    val batchKey: String?,
)

data class ReminderScheduleEvidenceRow(
    val accountHash: String,
    val historyGeneration: Long,
    val logicalKey: String,
    val sessionEpoch: Long,
    val operationSequence: Long,
    val subjectKind: String,
    val subjectId: String?,
    val category: String,
    val scheduledAt: Long?,
    val notificationId: Int?,
    val expectedPayload: String?,
    val state: String,
    val confirmedAt: Long,
)

enum class ReminderHistoryInsertResult {
    INSERTED,
    DUPLICATE,
    EXPIRED,
}

class ReminderDatabase private constructor(
    context: Context,
    databaseName: String = DATABASE_NAME,
) : SQLiteOpenHelper(context.applicationContext, databaseName, null, DATABASE_VERSION) {

    override fun onCreate(db: SQLiteDatabase) = logSchemaFailure("onCreate") {
        db.execSQL(
            """
            CREATE TABLE accounts (
                account_hash TEXT PRIMARY KEY,
                session_epoch INTEGER NOT NULL DEFAULT 0,
                active INTEGER NOT NULL DEFAULT 0,
                background_enabled INTEGER NOT NULL DEFAULT 1,
                interval_minutes INTEGER NOT NULL DEFAULT 240,
                listener_enabled INTEGER NOT NULL DEFAULT 0,
                new_assignment_enabled INTEGER NOT NULL DEFAULT 1,
                show_details INTEGER NOT NULL DEFAULT 0,
                baseline_completed INTEGER NOT NULL DEFAULT 0,
                baselined_sources TEXT NOT NULL DEFAULT '[]',
                known_ids TEXT NOT NULL DEFAULT '[]',
                sent_new_ids TEXT NOT NULL DEFAULT '[]',
                pending_update INTEGER NOT NULL DEFAULT 0,
                mutation_version INTEGER NOT NULL DEFAULT 0,
                pending_signal_version INTEGER NOT NULL DEFAULT 0,
                consumed_signal_version INTEGER NOT NULL DEFAULT 0,
                last_signal_at INTEGER,
                attempted_signal_version INTEGER NOT NULL DEFAULT 0,
                last_signal_check_at INTEGER,
                claim_token TEXT,
                last_attempt_at INTEGER,
                last_data_success_at INTEGER,
                last_full_success_at INTEGER,
                last_failure TEXT,
                next_check_at INTEGER,
                migration_state TEXT NOT NULL DEFAULT 'legacy_pending',
                allow_urgent_night_breakthrough INTEGER NOT NULL DEFAULT 0,
                deadline_channel_id TEXT NOT NULL DEFAULT 'assignment_deadlines',
                updated_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE snapshots (
                account_hash TEXT NOT NULL,
                assignment_id TEXT NOT NULL,
                session_epoch INTEGER NOT NULL,
                course_name TEXT NOT NULL,
                title TEXT NOT NULL,
                deadline_at INTEGER,
                event_kind TEXT NOT NULL DEFAULT 'deadline',
                deadline_source TEXT NOT NULL DEFAULT 'unknown',
                deadline_trusted INTEGER NOT NULL,
                deadline_read_failed INTEGER NOT NULL,
                completed INTEGER NOT NULL,
                hidden INTEGER NOT NULL,
                followed INTEGER NOT NULL,
                formal INTEGER NOT NULL,
                in_assignment_scope INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'unknown',
                PRIMARY KEY (account_hash, assignment_id)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE events (
                event_id TEXT PRIMARY KEY,
                account_hash TEXT NOT NULL,
                session_epoch INTEGER NOT NULL,
                type TEXT NOT NULL,
                assignment_id TEXT NOT NULL,
                course_name TEXT NOT NULL,
                title TEXT NOT NULL,
                notify_at INTEGER NOT NULL,
                deadline_at INTEGER,
                event_kind TEXT NOT NULL DEFAULT 'deadline',
                deadline_source TEXT NOT NULL DEFAULT 'unknown',
                offsets TEXT NOT NULL DEFAULT '[]',
                batch_id TEXT,
                status TEXT NOT NULL,
                notification_id INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX events_account_status ON events(account_hash, status, notify_at)",
        )
        db.execSQL(
            """
            CREATE TABLE notification_signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_hash TEXT NOT NULL,
                session_epoch INTEGER NOT NULL,
                signal_key TEXT NOT NULL,
                received_at INTEGER NOT NULL,
                consumed_version INTEGER,
                UNIQUE(account_hash, signal_key, received_at)
            )
            """.trimIndent(),
        )
        createNotificationAttempts(db)
        createReminderHistory(db)
        createReminderScheduleEvidence(db)
        ensureV7Indices(db)
    }

    override fun onUpgrade(
        db: SQLiteDatabase,
        oldVersion: Int,
        newVersion: Int,
    ) = logSchemaFailure("onUpgrade") {
        if (oldVersion < 2 && newVersion >= 2) {
            db.execSQL("ALTER TABLE accounts ADD COLUMN baselined_sources TEXT NOT NULL DEFAULT '[]'")
            db.execSQL("ALTER TABLE snapshots ADD COLUMN in_assignment_scope INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE snapshots ADD COLUMN status TEXT NOT NULL DEFAULT 'unknown'")
            db.execSQL("UPDATE snapshots SET in_assignment_scope = formal")
            db.execSQL(
                "UPDATE accounts SET baselined_sources = '[\"courseWork\"]' " +
                    "WHERE baseline_completed = 1",
            )
            // v1 never persisted personal status. Wait for Dart to rebuild the
            // snapshot before allowing any restored event to be delivered.
            db.execSQL("UPDATE accounts SET pending_update = 1, mutation_version = mutation_version + 1")
        }
        if (oldVersion < 3 && newVersion >= 3) {
            db.execSQL("ALTER TABLE snapshots ADD COLUMN event_kind TEXT NOT NULL DEFAULT 'deadline'")
            db.execSQL("ALTER TABLE events ADD COLUMN event_kind TEXT NOT NULL DEFAULT 'deadline'")
        }
        if (oldVersion < 4 && newVersion >= 4) {
            db.execSQL(
                "ALTER TABLE accounts ADD COLUMN attempted_signal_version " +
                    "INTEGER NOT NULL DEFAULT 0",
            )
            db.execSQL("ALTER TABLE accounts ADD COLUMN last_signal_check_at INTEGER")
        }
        if (oldVersion < 5 && newVersion >= 5) {
            db.execSQL("ALTER TABLE accounts ADD COLUMN claim_token TEXT")
        }
        if (oldVersion < 6 && newVersion >= 6) {
            createNotificationAttempts(db)
            createReminderHistory(db)
            createReminderScheduleEvidence(db)
        }
        if (oldVersion < 7 && newVersion >= 7) {
            ensureV7Indices(db)
        }
        if (oldVersion < 8 && newVersion >= 8) {
            db.execSQL(
                "ALTER TABLE accounts ADD COLUMN allow_urgent_night_breakthrough " +
                    "INTEGER NOT NULL DEFAULT 0",
            )
            db.execSQL(
                "ALTER TABLE accounts ADD COLUMN deadline_channel_id " +
                    "TEXT NOT NULL DEFAULT 'assignment_deadlines'",
            )
            db.execSQL(
                "ALTER TABLE snapshots ADD COLUMN deadline_source " +
                    "TEXT NOT NULL DEFAULT 'unknown'",
            )
            db.execSQL(
                "ALTER TABLE events ADD COLUMN deadline_source " +
                    "TEXT NOT NULL DEFAULT 'unknown'",
            )
        }
    }

    private inline fun logSchemaFailure(stage: String, changeSchema: () -> Unit) {
        try {
            changeSchema()
        } catch (error: SQLiteException) {
            Log.w(TAG, "$stage ${error.javaClass.simpleName}")
            throw error
        }
    }

    private fun ensureV7Indices(db: SQLiteDatabase) {
        db.execSQL("CREATE INDEX IF NOT EXISTS events_notification_id ON events(notification_id)")
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS events_account_assignment " +
                "ON events(account_hash, assignment_id, updated_at)",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS notification_signals_received_at " +
                "ON notification_signals(account_hash, received_at)",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS reminder_schedule_evidence_subject " +
                "ON reminder_schedule_evidence(" +
                "account_hash, history_generation, subject_kind, subject_id, confirmed_at)",
        )
    }

    private fun createNotificationAttempts(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS notification_attempts (
                account_hash TEXT PRIMARY KEY,
                session_epoch INTEGER NOT NULL,
                claim_token TEXT NOT NULL,
                owner_work_id TEXT,
                claimed_version INTEGER NOT NULL,
                claimed_at INTEGER NOT NULL,
                prior_attempted_version INTEGER NOT NULL,
                prior_last_signal_check_at INTEGER,
                prior_consumed_version INTEGER NOT NULL,
                phase TEXT NOT NULL
            )
            """.trimIndent(),
        )
    }

    private fun createReminderHistory(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS reminder_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_hash TEXT NOT NULL,
                session_epoch INTEGER NOT NULL,
                history_generation INTEGER NOT NULL,
                observation_id TEXT NOT NULL,
                operation_sequence INTEGER NOT NULL,
                subject_kind TEXT NOT NULL,
                subject_id TEXT,
                logical_key TEXT NOT NULL,
                category TEXT NOT NULL,
                stage TEXT NOT NULL,
                reason_code TEXT,
                observed_at INTEGER NOT NULL,
                scheduled_at INTEGER,
                notification_id INTEGER,
                batch_key TEXT
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS reminder_history_account_id " +
                "ON reminder_history(account_hash, history_generation, id)",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS reminder_history_account_key " +
                "ON reminder_history(account_hash, history_generation, logical_key, id)",
        )
        db.execSQL(
            "CREATE UNIQUE INDEX IF NOT EXISTS reminder_history_observation " +
                "ON reminder_history(account_hash, history_generation, observation_id)",
        )
    }

    private fun createReminderScheduleEvidence(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS reminder_schedule_evidence (
                account_hash TEXT NOT NULL,
                history_generation INTEGER NOT NULL,
                logical_key TEXT NOT NULL,
                session_epoch INTEGER NOT NULL,
                operation_sequence INTEGER NOT NULL,
                subject_kind TEXT NOT NULL,
                subject_id TEXT,
                category TEXT NOT NULL,
                scheduled_at INTEGER,
                notification_id INTEGER,
                expected_payload TEXT,
                state TEXT NOT NULL,
                confirmed_at INTEGER NOT NULL,
                PRIMARY KEY(account_hash, history_generation, logical_key)
            )
            """.trimIndent(),
        )
    }

    @Synchronized
    fun ensureActiveAccount(accountHash: String): ReminderAccountState =
        transaction {
            requireAccount(accountHash)
            writableDatabase.execSQL("UPDATE accounts SET active = 0")
            writableDatabase.execSQL(
                "UPDATE accounts SET active = 1, updated_at = ? WHERE account_hash = ?",
                arrayOf<Any?>(System.currentTimeMillis(), accountHash),
            )
            readAccount(accountHash)!!
        }

    @Synchronized
    fun switchAccount(previousHash: String?, targetHash: String): ReminderAccountState =
        transaction {
            val now = System.currentTimeMillis()
            val switchingAccount = previousHash?.takeIf {
                it.isNotBlank() && it != targetHash
            }
            requireAccount(targetHash)
            purgeReminderStateLocked(keepAccountHash = targetHash.takeIf { switchingAccount == null })
            clearAccountPlaintextLocked(keepAccountHash = targetHash)
            if (switchingAccount != null) {
                writableDatabase.execSQL(
                    "UPDATE accounts SET session_epoch = session_epoch + 1, updated_at = ? " +
                        "WHERE account_hash IN (?, ?)",
                    arrayOf<Any?>(now, switchingAccount, targetHash),
                )
            } else {
                deleteNotificationAttemptLocked(targetHash)
            }
            writableDatabase.execSQL(
                "UPDATE accounts SET active = 1, updated_at = ? WHERE account_hash = ?",
                arrayOf<Any?>(now, targetHash),
            )
            readAccount(targetHash)!!
        }

    @Synchronized
    fun rotateSessionEpoch(accountHash: String): Long =
        transaction {
            val now = System.currentTimeMillis()
            requireAccount(accountHash)
            writableDatabase.execSQL(
                "UPDATE accounts SET session_epoch = session_epoch + 1, claim_token = NULL, " +
                    "updated_at = ? " +
                    "WHERE account_hash = ?",
                arrayOf<Any?>(now, accountHash),
            )
            deleteNotificationAttemptLocked(accountHash)
            cancelEventsLocked(accountHash, now)
            readAccount(accountHash)!!.sessionEpoch
        }

    @Synchronized
    fun clearActiveAccount(accountHash: String): Long =
        transaction {
            val now = System.currentTimeMillis()
            // A retry of an earlier logout may arrive after a different login.
            val keepActiveHash = activeAccount()?.accountHash?.takeIf { it != accountHash }
            requireAccount(accountHash)
            purgeReminderStateLocked(keepAccountHash = keepActiveHash)
            clearAccountPlaintextLocked(keepAccountHash = keepActiveHash)
            writableDatabase.execSQL(
                "UPDATE accounts SET session_epoch = session_epoch + 1, " +
                    "last_attempt_at = NULL, last_data_success_at = NULL, " +
                    "last_full_success_at = NULL, " +
                    "next_check_at = NULL, migration_state = 'legacy_pending', " +
                    "mutation_version = mutation_version + 1, updated_at = ? " +
                    "WHERE account_hash = ?",
                arrayOf<Any?>(now, accountHash),
            )
            readAccount(accountHash)!!.sessionEpoch
        }

    private fun purgeReminderStateLocked(keepAccountHash: String?) {
        val selection = keepAccountHash?.let { "account_hash != ?" }
        val args = keepAccountHash?.let { arrayOf(it) }
        writableDatabase.delete("snapshots", selection, args)
        writableDatabase.delete("events", selection, args)
        writableDatabase.delete("notification_signals", selection, args)
        writableDatabase.delete("notification_attempts", selection, args)
        // Reset the watermarks together with their signals and claims.
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("pending_signal_version", 0)
                put("consumed_signal_version", 0)
                put("attempted_signal_version", 0)
                putNull("last_signal_at")
                putNull("last_signal_check_at")
                putNull("claim_token")
            },
            selection,
            args,
        )
    }

    private fun clearAccountPlaintextLocked(keepAccountHash: String?) {
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("active", 0)
                put("baseline_completed", 0)
                put("baselined_sources", "[]")
                put("known_ids", "[]")
                put("sent_new_ids", "[]")
                putNull("last_failure")
                put("pending_update", 0)
                put("allow_urgent_night_breakthrough", 0)
            },
            keepAccountHash?.let { "account_hash != ?" },
            keepAccountHash?.let { arrayOf(it) },
        )
    }

    @Synchronized
    fun isSessionCurrent(accountHash: String, sessionEpoch: Long): Boolean {
        val account = readAccount(accountHash) ?: return false
        return account.active && account.sessionEpoch == sessionEpoch
    }

    @Synchronized
    fun readAccount(accountHash: String): ReminderAccountState? {
        readableDatabase.query(
            "accounts",
            null,
            "account_hash = ?",
            arrayOf(accountHash),
            null,
            null,
            null,
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.toAccount() else null
        }
    }

    @Synchronized
    fun activeAccount(): ReminderAccountState? {
        readableDatabase.query(
            "accounts",
            null,
            "active = 1",
            null,
            null,
            null,
            "updated_at DESC",
            "1",
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.toAccount() else null
        }
    }

    @Synchronized
    fun updateSettings(
        accountHash: String,
        sessionEpoch: Long,
        backgroundEnabled: Boolean,
        intervalMinutes: Int,
        listenerEnabled: Boolean,
        newAssignmentEnabled: Boolean,
        showDetails: Boolean,
        allowUrgentNightBreakthrough: Boolean? = null,
        deadlineChannelId: String? = null,
    ): ReminderAccountState {
        validateSession(accountHash, sessionEpoch)
        val currentAccount = readAccount(accountHash)!!
        val mutationVersion = currentAccount.mutationVersion + 1
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("background_enabled", if (backgroundEnabled) 1 else 0)
                put("interval_minutes", normalizeInterval(intervalMinutes))
                put("listener_enabled", if (listenerEnabled) 1 else 0)
                put("new_assignment_enabled", if (newAssignmentEnabled) 1 else 0)
                put("show_details", if (showDetails) 1 else 0)
                if (allowUrgentNightBreakthrough != null) {
                    put(
                        "allow_urgent_night_breakthrough",
                        if (allowUrgentNightBreakthrough) 1 else 0,
                    )
                }
                if (!deadlineChannelId.isNullOrBlank()) {
                    put("deadline_channel_id", deadlineChannelId)
                }
                put("mutation_version", mutationVersion)
                put("updated_at", System.currentTimeMillis())
            },
            "account_hash = ?",
            arrayOf(accountHash),
        )
        if (!listenerEnabled) {
            deleteNotificationAttemptLocked(accountHash)
            writableDatabase.execSQL(
                "UPDATE accounts SET claim_token = NULL WHERE account_hash = ?",
                arrayOf(accountHash),
            )
        }
        return readAccount(accountHash)!!
    }

    @Synchronized
    fun loadPlanState(accountHash: String, sessionEpoch: Long): ReminderAccountState {
        validateSession(accountHash, sessionEpoch)
        return readAccount(accountHash)!!
    }

    @Synchronized
    fun markPendingUpdate(accountHash: String, sessionEpoch: Long) {
        validateSession(accountHash, sessionEpoch)
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("pending_update", 1)
                put("mutation_version", readAccount(accountHash)!!.mutationVersion + 1)
                put("updated_at", System.currentTimeMillis())
            },
            "account_hash = ?",
            arrayOf(accountHash),
        )
    }

    @Synchronized
    fun recordAttempt(
        accountHash: String,
        sessionEpoch: Long,
        attemptedAt: Long,
        dataSucceeded: Boolean,
        fullSucceeded: Boolean,
        failure: String?,
    ) {
        validateSession(accountHash, sessionEpoch)
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("last_attempt_at", attemptedAt)
                if (dataSucceeded) put("last_data_success_at", attemptedAt)
                if (fullSucceeded) put("last_full_success_at", attemptedAt)
                put("last_failure", failure)
                put("updated_at", System.currentTimeMillis())
            },
            "account_hash = ?",
            arrayOf(accountHash),
        )
    }

    @Synchronized
    fun setNextCheckAt(accountHash: String, nextCheckAt: Long?) {
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("next_check_at", nextCheckAt)
                put("updated_at", System.currentTimeMillis())
            },
            "account_hash = ?",
            arrayOf(accountHash),
        )
    }

    @Synchronized
    fun mutateSignalSettings(
        accountHash: String,
        listenerEnabled: Boolean,
    ) {
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("listener_enabled", if (listenerEnabled) 1 else 0)
                put("updated_at", System.currentTimeMillis())
            },
            "account_hash = ?",
            arrayOf(accountHash),
        )
    }

    data class PlanApplication(
        val desiredDeadlineEvents: List<StoredReminderEvent>,
        val invalidatedEvents: List<StoredReminderEvent>,
        val newEvents: List<StoredReminderEvent>,
        val pendingNewCount: Int,
        val pendingDeadlineCount: Int,
        val scheduledDeadlineEvents: List<StoredReminderEvent> = emptyList(),
    )

    @Synchronized
    fun applyPlan(
        accountHash: String,
        sessionEpoch: Long,
        baselineCompleted: Boolean,
        knownIds: Set<String>,
        snapshots: List<StoredReminderSnapshot>,
        events: List<StoredReminderEvent>,
        completedAt: Long,
        failure: String?,
        syncCompleted: Boolean,
        expectedMutationVersion: Long,
        baselinedSources: Set<String>? = null,
    ): PlanApplication = transaction {
        validateSession(accountHash, sessionEpoch)
        val currentAccount = readAccount(accountHash)!!
        if (currentAccount.mutationVersion != expectedMutationVersion) {
            throw IllegalStateException("本机提醒状态已变化，请重新生成计划")
        }
        val now = System.currentTimeMillis()
        writableDatabase.delete(
            "snapshots",
            "account_hash = ?",
            arrayOf(accountHash),
        )
        snapshots.forEach { snapshot ->
            writableDatabase.insertOrThrow(
                "snapshots",
                null,
                ContentValues().apply {
                    put("account_hash", accountHash)
                    put("assignment_id", snapshot.assignmentId)
                    put("session_epoch", sessionEpoch)
                    put("course_name", snapshot.courseName)
                    put("title", snapshot.title)
                    put("event_kind", snapshot.eventKind)
                    put("deadline_source", snapshot.deadlineSource)
                    snapshot.deadlineAt?.let { put("deadline_at", it) }
                        ?: putNull("deadline_at")
                    put("deadline_trusted", if (snapshot.deadlineTrusted) 1 else 0)
                    put("deadline_read_failed", if (snapshot.deadlineReadFailed) 1 else 0)
                    put("completed", if (snapshot.completed) 1 else 0)
                    put("hidden", if (snapshot.hidden) 1 else 0)
                    put("followed", if (snapshot.followed) 1 else 0)
                    put("formal", if (snapshot.formal) 1 else 0)
                    put("in_assignment_scope", if (snapshot.inAssignmentScope) 1 else 0)
                    put("status", snapshot.status)
                },
            )
        }

        val snapshotsById = snapshots.associateBy { it.assignmentId }
        val validEvents = events.filter {
            it.accountHash == accountHash && it.sessionEpoch == sessionEpoch &&
                snapshotsById[it.assignmentId]?.matchesEvent(it, now) == true
        }
        val desiredDeadline = validEvents.filter { it.type == EVENT_DEADLINE }
        val desiredIds = desiredDeadline.map { it.eventId }.toSet()
        val invalidatedEvents = mutableListOf<StoredReminderEvent>()
        val existing = eventsForAccount(accountHash)
        val existingById = existing.associateBy { it.eventId }
        val existingIds = existingById.keys.toMutableSet()
        existing.filter {
            (it.status == STATUS_PENDING || it.status == STATUS_SUBMITTED) &&
                (snapshotsById[it.assignmentId]?.matchesEvent(it, now) != true ||
                    (it.type == EVENT_DEADLINE && it.status == STATUS_PENDING &&
                        it.eventId !in desiredIds))
        }.forEach {
            invalidatedEvents.add(it)
            writableDatabase.update(
                "events",
                ContentValues().apply {
                    put("status", STATUS_CANCELLED)
                    put("updated_at", now)
                },
                "event_id = ?",
                arrayOf(it.eventId),
            )
        }
        val scheduledDeadlineEvents = mutableListOf<StoredReminderEvent>()
        desiredDeadline.forEach { event ->
            val current = existingById[event.eventId]
            when {
                current == null -> {
                    insertEvent(event, now)
                    existingIds.add(event.eventId)
                    scheduledDeadlineEvents.add(event)
                }
                current.status == STATUS_PENDING -> {
                    val scheduleChanged =
                        current.notifyAt != event.notifyAt ||
                            current.deadlineAt != event.deadlineAt ||
                            current.deadlineSource != event.deadlineSource ||
                            current.sessionEpoch != sessionEpoch
                    updateEvent(event, sessionEpoch, now)
                    if (scheduleChanged) {
                        scheduledDeadlineEvents.add(event)
                    }
                }
                current.status == STATUS_CANCELLED -> {
                    // Hiding an assignment cancels its deadline events. When it
                    // becomes eligible again the planner emits the same stable
                    // event id; reactivate it instead of silently dropping the
                    // reminder forever.
                    updateEvent(event, sessionEpoch, now, status = STATUS_PENDING)
                    scheduledDeadlineEvents.add(event)
                }
            }
        }

        val newEvents = mutableListOf<StoredReminderEvent>()
        validEvents.filter { it.type == EVENT_NEW }.forEach { event ->
            if (existingIds.add(event.eventId)) {
                insertEvent(event, now)
                newEvents.add(event)
            }
        }

        val nextSources = baselinedSources ?: if (baselineCompleted) {
            currentAccount.baselinedSources + "courseWork"
        } else {
            currentAccount.baselinedSources - "courseWork"
        }
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("baseline_completed", if ("courseWork" in nextSources) 1 else 0)
                put("baselined_sources", JSONArray(nextSources.toList()).toString())
                put("known_ids", JSONArray(knownIds.toList()).toString())
                put("pending_update", 0)
                if (syncCompleted) {
                    put("last_attempt_at", completedAt)
                    put("last_data_success_at", completedAt)
                    if (failure == null) put("last_full_success_at", completedAt)
                    put("last_failure", failure)
                }
                put("migration_state", "native_active")
                put("updated_at", now)
            },
            "account_hash = ?",
            arrayOf(accountHash),
        )

        pruneStaleDataLocked(now)
        val pendingEvents = eventsForAccount(accountHash).filter { it.status == STATUS_PENDING }
        PlanApplication(
            desiredDeadlineEvents = desiredDeadline,
            invalidatedEvents = invalidatedEvents,
            newEvents = newEvents,
            pendingNewCount = pendingEvents.count { it.type == EVENT_NEW },
            pendingDeadlineCount = pendingEvents.count { it.type == EVENT_DEADLINE },
            scheduledDeadlineEvents = scheduledDeadlineEvents,
        )
    }

    private fun updateEvent(
        event: StoredReminderEvent,
        sessionEpoch: Long,
        now: Long,
        status: String = STATUS_PENDING,
    ) {
        writableDatabase.update(
            "events",
            ContentValues().apply {
                // A restored or renamed assignment keeps its stable event id,
                // so the display text must follow the latest snapshot instead
                // of the row that was created before it was hidden/renamed.
                put("course_name", event.courseName)
                put("title", event.title)
                put("session_epoch", sessionEpoch)
                put("notify_at", event.notifyAt)
                put("deadline_at", event.deadlineAt)
                put("event_kind", event.eventKind)
                put("deadline_source", event.deadlineSource)
                put("offsets", JSONArray(event.offsets).toString())
                put("status", status)
                put("updated_at", now)
            },
            "event_id = ?",
            arrayOf(event.eventId),
        )
    }

    /**
     * Notification ids owned by the native reminder database, across accounts.
     * Legacy plugin notifications can share the same numeric id range, so an id
     * alone is never ownership evidence; this set only protects rows the native
     * publisher may still be showing.
     */
    @Synchronized
    fun notificationIds(): Set<Int> {
        readableDatabase.query(
            "events",
            arrayOf("notification_id"),
            null,
            null,
            null,
            null,
            null,
        ).use { cursor ->
            val ids = mutableSetOf<Int>()
            while (cursor.moveToNext()) {
                if (!cursor.isNull(0)) ids.add(cursor.getInt(0))
            }
            return ids
        }
    }

    @Synchronized
    fun eventsForAccount(accountHash: String): List<StoredReminderEvent> {
        readableDatabase.query(
            "events",
            null,
            "account_hash = ?",
            arrayOf(accountHash),
            null,
            null,
            "notify_at ASC",
        ).use { cursor ->
            val rows = mutableListOf<StoredReminderEvent>()
            while (cursor.moveToNext()) rows.add(cursor.toEvent())
            return rows
        }
    }

    @Synchronized
    fun eventsForNotification(notificationId: Int): List<StoredReminderEvent> {
        readableDatabase.query(
            "events",
            null,
            "notification_id = ?",
            arrayOf(notificationId.toString()),
            null,
            null,
            "notify_at ASC",
        ).use { cursor ->
            val rows = mutableListOf<StoredReminderEvent>()
            while (cursor.moveToNext()) rows.add(cursor.toEvent())
            return rows
        }
    }

    @Synchronized
    fun submittedNotificationMembers(notificationId: Int, now: Long): List<StoredReminderEvent> =
        eventsForNotification(notificationId).mapNotNull { event ->
            if (event.status != STATUS_SUBMITTED) return@mapNotNull null
            val account = readAccount(event.accountHash) ?: return@mapNotNull null
            if (!account.active || account.sessionEpoch != event.sessionEpoch ||
                (event.type == EVENT_NEW && !account.newAssignmentEnabled)
            ) return@mapNotNull null
            val snapshot = snapshot(event.accountHash, event.assignmentId) ?: return@mapNotNull null
            if (!snapshot.matchesEvent(event, now)) return@mapNotNull null
            event.copy(courseName = snapshot.courseName, title = snapshot.title)
        }

    @Synchronized
    fun event(eventId: String): StoredReminderEvent? {
        readableDatabase.query(
            "events",
            null,
            "event_id = ?",
            arrayOf(eventId),
            null,
            null,
            null,
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.toEvent() else null
        }
    }

    @Synchronized
    fun pendingNewEvents(accountHash: String): List<StoredReminderEvent> =
        eventsForAccount(accountHash)
            .filter { it.type == EVENT_NEW && it.status == STATUS_PENDING }

    @Synchronized
    fun pendingDeadlineEvents(accountHash: String): List<StoredReminderEvent> =
        eventsForAccount(accountHash)
            .filter { it.type == EVENT_DEADLINE && it.status == STATUS_PENDING }

    @Synchronized
    fun markEventSubmitted(
        eventId: String,
        notificationId: Int,
        accountHash: String,
        assignmentId: String,
        type: String,
    ) {
        transaction {
            writableDatabase.update(
                "events",
                ContentValues().apply {
                    put("status", STATUS_SUBMITTED)
                    put("notification_id", notificationId)
                    put("updated_at", System.currentTimeMillis())
                },
                "event_id = ? AND status = ?",
                arrayOf(eventId, STATUS_PENDING),
            )
            if (type == EVENT_NEW) {
                val account = readAccount(accountHash)
                val sent = account?.sentNewAssignmentIds.orEmpty().toMutableSet()
                sent.add(assignmentId)
                writableDatabase.update(
                    "accounts",
                    ContentValues().apply {
                        put("sent_new_ids", JSONArray(sent.toList()).toString())
                        put("updated_at", System.currentTimeMillis())
                    },
                    "account_hash = ?",
                    arrayOf(accountHash),
                )
            }
        }
    }

    @Synchronized
    fun updateEventNotifyAt(eventId: String, notifyAt: Long) {
        writableDatabase.update(
            "events",
            ContentValues().apply {
                put("notify_at", notifyAt)
                put("updated_at", System.currentTimeMillis())
            },
            "event_id = ? AND status = ?",
            arrayOf(eventId, STATUS_PENDING),
        )
    }

    @Synchronized
    fun cancelEvent(eventId: String): ReminderAccountState? {
        val event = event(eventId) ?: return null
        writableDatabase.update(
            "events",
            ContentValues().apply {
                put("status", STATUS_CANCELLED)
                put("updated_at", System.currentTimeMillis())
            },
            "event_id = ?",
            arrayOf(eventId),
        )
        return readAccount(event.accountHash)
    }

    @Synchronized
    fun cancelAssignmentReminders(accountHash: String): List<StoredReminderEvent> =
        transaction {
            val cancelled = eventsForAccount(accountHash)
                .filter { it.status == STATUS_PENDING || it.status == STATUS_SUBMITTED }
            val now = System.currentTimeMillis()
            writableDatabase.update(
                "events",
                ContentValues().apply {
                    put("status", STATUS_CANCELLED)
                    put("updated_at", now)
                },
                "account_hash = ? AND status IN (?, ?)",
                arrayOf(accountHash, STATUS_PENDING, STATUS_SUBMITTED),
            )
            cancelled
        }

    @Synchronized
    fun snapshot(accountHash: String, assignmentId: String): StoredReminderSnapshot? {
        readableDatabase.query(
            "snapshots",
            null,
            "account_hash = ? AND assignment_id = ?",
            arrayOf(accountHash, assignmentId),
            null,
            null,
            null,
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.toSnapshot() else null
        }
    }

    @Synchronized
    fun recordSignal(
        accountHash: String,
        sessionEpoch: Long,
        signalKey: String,
        receivedAt: Long,
    ): Long {
        validateSession(accountHash, sessionEpoch)
        val account = readAccount(accountHash)!!
        if (!account.listenerEnabled) return account.pendingSignalVersion
        val duplicateWindow = receivedAt - 60_000L
        readableDatabase.query(
            "notification_signals",
            arrayOf("id"),
            "account_hash = ? AND signal_key = ? AND received_at >= ?",
            arrayOf(accountHash, signalKey, duplicateWindow.toString()),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            if (cursor.moveToFirst()) return account.pendingSignalVersion
        }
        val version = account.pendingSignalVersion + 1
        transaction {
            pruneStaleSignalsLocked(receivedAt)
            writableDatabase.insertOrThrow(
                "notification_signals",
                null,
                ContentValues().apply {
                    put("account_hash", accountHash)
                    put("session_epoch", sessionEpoch)
                    put("signal_key", signalKey)
                    put("received_at", receivedAt)
                },
            )
            writableDatabase.update(
                "accounts",
                ContentValues().apply {
                    put("pending_signal_version", version)
                    put("last_signal_at", receivedAt)
                    put("updated_at", System.currentTimeMillis())
                },
                "account_hash = ?",
                arrayOf(accountHash),
            )
        }
        return version
    }

    @Synchronized
    fun pruneStaleData(now: Long = System.currentTimeMillis()) {
        transaction { pruneStaleDataLocked(now) }
    }

    private fun pruneStaleDataLocked(now: Long) {
        pruneStaleSignalsLocked(now)
        val cutoff = (now - 30 * DAY_MILLIS).toString()
        writableDatabase.delete(
            "events",
            "status IN (?, ?, ?) AND updated_at < ? " +
                "AND (type != ? OR deadline_at IS NULL OR deadline_at < ?)",
            arrayOf(
                STATUS_CANCELLED, STATUS_SUBMITTED, STATUS_INVALID, cutoff, EVENT_DEADLINE, now.toString(),
            ),
        )
        writableDatabase.delete(
            "reminder_schedule_evidence",
            "state != ? AND confirmed_at < ? AND (scheduled_at IS NULL OR scheduled_at < ?)",
            arrayOf("recoveryPending", cutoff, cutoff),
        )
    }

    private fun pruneStaleSignalsLocked(now: Long) {
        writableDatabase.delete(
            "notification_signals",
            "received_at < ?",
            arrayOf((now - 7 * DAY_MILLIS).toString()),
        )
    }

    @Synchronized
    fun consumeSignal(accountHash: String, version: Long) {
        consumeSignal(accountHash, version, null)
    }

    @Synchronized
    fun consumeSignal(accountHash: String, version: Long, sessionEpoch: Long?) {
        transaction {
            val account = readAccount(accountHash) ?: return@transaction
            if (sessionEpoch != null && account.sessionEpoch != sessionEpoch) {
                return@transaction
            }
            val consumed = maxOf(account.consumedSignalVersion, version)
            writableDatabase.update(
                "accounts",
                ContentValues().apply {
                    put("consumed_signal_version", consumed)
                    put("updated_at", System.currentTimeMillis())
                },
                "account_hash = ?",
                arrayOf(accountHash),
            )
            val attempt = readNotificationAttemptLocked(accountHash)
            if (attempt != null && consumed >= attempt.claimedVersion) {
                deleteNotificationAttemptLocked(accountHash)
                if (account.claimToken == attempt.claimToken) {
                    writableDatabase.execSQL(
                        "UPDATE accounts SET claim_token = NULL WHERE account_hash = ?",
                        arrayOf(accountHash),
                    )
                }
            } else if (attempt == null &&
                account.claimToken != null &&
                consumed >= account.attemptedSignalVersion
            ) {
                writableDatabase.execSQL(
                    "UPDATE accounts SET claim_token = NULL WHERE account_hash = ?",
                    arrayOf(accountHash),
                )
            }
        }
    }

    /**
     * Claims the latest signal that has not already been consumed or attempted.
     *
     * The attempted version is persisted before the Flutter engine starts, so
     * failures, timeouts and process death cannot re-create a chain for the
     * same signal. The unconsumed signal remains available to a normal daytime
     * or manual check.
     */
    @Synchronized
    fun claimNotificationSignal(
        accountHash: String,
        sessionEpoch: Long,
        attemptedAt: Long = System.currentTimeMillis(),
    ): Long? = claimNotificationAttempt(
        accountHash,
        sessionEpoch,
        attemptedAt,
    )?.version

    @Synchronized
    fun claimNotificationAttempt(
        accountHash: String,
        sessionEpoch: Long,
        attemptedAt: Long = System.currentTimeMillis(),
        ownerWorkId: String? = null,
    ): NotificationSignalClaim? = transaction {
        val account = readAccount(accountHash) ?: return@transaction null
        if (!account.active ||
            !account.listenerEnabled ||
            account.sessionEpoch != sessionEpoch
        ) {
            return@transaction null
        }
        val existing = readNotificationAttemptLocked(accountHash)
        if (existing != null &&
            ownerWorkId != null &&
            existing.ownerWorkId == ownerWorkId &&
            existing.sessionEpoch == sessionEpoch &&
            (existing.phase == NotificationAttemptPhase.CLAIMED ||
                existing.phase == NotificationAttemptPhase.WINDOW_DEFERRED) &&
            account.attemptedSignalVersion == existing.claimedVersion &&
            account.claimToken == existing.claimToken &&
            account.consumedSignalVersion < existing.claimedVersion
        ) {
            return@transaction existing.toClaim(account.pendingSignalVersion)
        }
        val claimed = NotificationCheckSchedulerPolicy.claimableVersion(
            account.pendingSignalVersion,
            account.consumedSignalVersion,
            account.attemptedSignalVersion,
        ) ?: return@transaction null
        val token = UUID.randomUUID().toString()
        val updated = writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("attempted_signal_version", claimed)
                put("last_signal_check_at", attemptedAt)
                put("claim_token", token)
                put("updated_at", System.currentTimeMillis())
            },
            "account_hash = ? AND session_epoch = ? AND attempted_signal_version = ? " +
                "AND pending_signal_version = ? AND consumed_signal_version = ?",
            arrayOf(
                accountHash,
                sessionEpoch.toString(),
                account.attemptedSignalVersion.toString(),
                account.pendingSignalVersion.toString(),
                account.consumedSignalVersion.toString(),
            ),
        )
        if (updated != 1) return@transaction null
        writableDatabase.insertWithOnConflict(
            "notification_attempts",
            null,
            ContentValues().apply {
                put("account_hash", accountHash)
                put("session_epoch", sessionEpoch)
                put("claim_token", token)
                if (ownerWorkId == null) putNull("owner_work_id")
                else put("owner_work_id", ownerWorkId)
                put("claimed_version", claimed)
                put("claimed_at", attemptedAt)
                put("prior_attempted_version", account.attemptedSignalVersion)
                if (account.lastSignalCheckAt == null) {
                    putNull("prior_last_signal_check_at")
                } else {
                    put("prior_last_signal_check_at", account.lastSignalCheckAt)
                }
                put("prior_consumed_version", account.consumedSignalVersion)
                put("phase", NotificationAttemptPhase.CLAIMED.value)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
        NotificationSignalClaim(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            version = claimed,
            token = token,
            claimedAt = attemptedAt,
            priorAttemptedVersion = account.attemptedSignalVersion,
            priorLastSignalCheckAt = account.lastSignalCheckAt,
            priorPendingVersion = account.pendingSignalVersion,
            priorConsumedVersion = account.consumedSignalVersion,
            ownerWorkId = ownerWorkId,
        )
    }

    @Synchronized
    fun rollbackUnstartedNotificationAttempt(claim: NotificationSignalClaim): Boolean {
        return releaseNotificationAttempt(claim)
    }

    /**
     * Releases a still-unconsumed claim even when another valid sync moved the
     * consumed watermark inside the claimed range. The token, owner, attempt
     * phase and the real consumption boundary are checked together.
     */
    @Synchronized
    fun releaseNotificationAttempt(claim: NotificationSignalClaim): Boolean =
        transaction {
            val attempt = readNotificationAttemptLocked(claim.accountHash)
                ?: return@transaction false
            if (attempt.sessionEpoch != claim.sessionEpoch ||
                attempt.claimToken != claim.token ||
                attempt.claimedVersion != claim.version ||
                attempt.claimedAt != claim.claimedAt ||
                (attempt.phase != NotificationAttemptPhase.CLAIMED &&
                    attempt.phase != NotificationAttemptPhase.WINDOW_DEFERRED) ||
                (claim.ownerWorkId != null &&
                    attempt.ownerWorkId != claim.ownerWorkId)
            ) {
                return@transaction false
            }
            val account = readAccount(claim.accountHash) ?: return@transaction false
            if (!account.active ||
                !account.listenerEnabled ||
                account.sessionEpoch != claim.sessionEpoch ||
                account.claimToken != claim.token ||
                account.attemptedSignalVersion != claim.version ||
                account.lastSignalCheckAt != claim.claimedAt ||
                account.pendingSignalVersion < claim.version ||
                account.consumedSignalVersion < claim.priorConsumedVersion ||
                account.consumedSignalVersion >= claim.version
            ) {
                return@transaction false
            }
            val values = ContentValues().apply {
                put("attempted_signal_version", claim.priorAttemptedVersion)
                if (claim.priorLastSignalCheckAt == null) {
                    putNull("last_signal_check_at")
                } else {
                    put("last_signal_check_at", claim.priorLastSignalCheckAt)
                }
                putNull("claim_token")
                put("updated_at", System.currentTimeMillis())
            }
            val updated = writableDatabase.update(
                "accounts",
                values,
                "account_hash = ? AND active = 1 AND listener_enabled = 1 " +
                    "AND session_epoch = ? AND claim_token = ? " +
                    "AND attempted_signal_version = ? AND last_signal_check_at = ? " +
                    "AND pending_signal_version >= ? " +
                    "AND consumed_signal_version >= ? " +
                    "AND consumed_signal_version < ?",
                arrayOf(
                    claim.accountHash,
                    claim.sessionEpoch.toString(),
                    claim.token,
                    claim.version.toString(),
                    claim.claimedAt.toString(),
                    claim.version.toString(),
                    claim.priorConsumedVersion.toString(),
                    claim.version.toString(),
                ),
            )
            if (updated != 1) return@transaction false
            deleteNotificationAttemptLocked(claim.accountHash)
            true
        }

    @Synchronized
    fun notificationAttempt(accountHash: String): NotificationAttempt? =
        readNotificationAttemptLocked(accountHash)

    @Synchronized
    fun markNotificationAttemptPhase(
        accountHash: String,
        sessionEpoch: Long,
        claimToken: String,
        phase: NotificationAttemptPhase,
        ownerWorkId: String? = null,
        allowRemoteAuthorizedDowngrade: Boolean = false,
    ): Boolean = transaction {
        val attempt = readNotificationAttemptLocked(accountHash)
            ?: return@transaction false
        if (attempt.sessionEpoch != sessionEpoch ||
            attempt.claimToken != claimToken ||
            (ownerWorkId != null && attempt.ownerWorkId != ownerWorkId)
        ) {
            return@transaction false
        }
        if (attempt.phase == phase) return@transaction true
        val allowed = when (attempt.phase) {
            NotificationAttemptPhase.CLAIMED ->
                phase == NotificationAttemptPhase.REMOTE_AUTHORIZED ||
                    phase == NotificationAttemptPhase.WINDOW_DEFERRED ||
                    phase == NotificationAttemptPhase.SETTLED
            NotificationAttemptPhase.WINDOW_DEFERRED ->
                phase == NotificationAttemptPhase.SETTLED
            NotificationAttemptPhase.REMOTE_AUTHORIZED ->
                phase == NotificationAttemptPhase.SETTLED ||
                    (allowRemoteAuthorizedDowngrade &&
                        phase == NotificationAttemptPhase.WINDOW_DEFERRED)
            NotificationAttemptPhase.SETTLED -> false
        }
        if (!allowed) return@transaction false
        val updated = writableDatabase.update(
            "notification_attempts",
            ContentValues().apply { put("phase", phase.value) },
            "account_hash = ? AND session_epoch = ? AND claim_token = ?",
            arrayOf(accountHash, sessionEpoch.toString(), claimToken),
        )
        updated == 1
    }

    @Synchronized
    fun settleNotificationAttempt(
        accountHash: String,
        sessionEpoch: Long,
        claimToken: String,
        ownerWorkId: String? = null,
    ): Boolean = markNotificationAttemptPhase(
        accountHash = accountHash,
        sessionEpoch = sessionEpoch,
        claimToken = claimToken,
        phase = NotificationAttemptPhase.SETTLED,
        ownerWorkId = ownerWorkId,
    )

    @Synchronized
    fun authorizeNotificationRemoteStart(
        accountHash: String,
        sessionEpoch: Long,
        claimToken: String,
        ownerWorkId: String,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): NotificationRemoteAuthorization = transaction {
        val account = readAccount(accountHash)
            ?: return@transaction NotificationRemoteAuthorization.STALE
        val attempt = readNotificationAttemptLocked(accountHash)
            ?: return@transaction NotificationRemoteAuthorization.STALE
        if (!account.active ||
            !account.listenerEnabled ||
            account.sessionEpoch != sessionEpoch ||
            attempt.sessionEpoch != sessionEpoch ||
            attempt.claimToken != claimToken ||
            attempt.ownerWorkId != ownerWorkId ||
            account.claimToken != claimToken ||
            account.attemptedSignalVersion != attempt.claimedVersion
        ) {
            return@transaction NotificationRemoteAuthorization.STALE
        }
        when (attempt.phase) {
            NotificationAttemptPhase.REMOTE_AUTHORIZED ->
                return@transaction NotificationRemoteAuthorization.GRANTED
            NotificationAttemptPhase.CLAIMED,
            NotificationAttemptPhase.WINDOW_DEFERRED -> Unit
            NotificationAttemptPhase.SETTLED ->
                return@transaction NotificationRemoteAuthorization.STALE
        }
        if (!NativeReminderPolicy.isInDaytimeWindow(now, zone)) {
            writableDatabase.update(
                "notification_attempts",
                ContentValues().apply {
                    put("phase", NotificationAttemptPhase.WINDOW_DEFERRED.value)
                },
                "account_hash = ? AND claim_token = ?",
                arrayOf(accountHash, claimToken),
            )
            return@transaction NotificationRemoteAuthorization.OUTSIDE_WINDOW
        }
        writableDatabase.update(
            "notification_attempts",
            ContentValues().apply {
                put("phase", NotificationAttemptPhase.REMOTE_AUTHORIZED.value)
            },
            "account_hash = ? AND claim_token = ?",
            arrayOf(accountHash, claimToken),
        )
        NotificationRemoteAuthorization.GRANTED
    }

    @Synchronized
    fun lastSignalAt(accountHash: String): Long? =
        readAccount(accountHash)?.let {
            readableDatabase.rawQuery(
                "SELECT last_signal_at FROM accounts WHERE account_hash = ?",
                arrayOf(accountHash),
            ).use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
            }
        }

    @Synchronized
    fun lastSignalCheckAt(accountHash: String): Long? =
        readAccount(accountHash)?.lastSignalCheckAt

    @Synchronized
    fun counts(
        accountHash: String,
    ): Triple<Int, Int, Int> {
        val events = eventsForAccount(accountHash)
        val pendingNew = events.count { it.type == EVENT_NEW && it.status == STATUS_PENDING }
        val pendingDeadline =
            events.count { it.type == EVENT_DEADLINE && it.status == STATUS_PENDING }
        val pendingSignals = readAccount(accountHash)?.let {
            (it.pendingSignalVersion - it.consumedSignalVersion).coerceAtLeast(0).toInt()
        } ?: 0
        return Triple(pendingNew, pendingDeadline, pendingSignals)
    }

    @Synchronized
    fun insertReminderHistory(
        accountHash: String,
        sessionEpoch: Long,
        historyGeneration: Long,
        observationId: String,
        operationSequence: Long,
        subjectKind: String,
        subjectId: String?,
        logicalKey: String,
        category: String,
        stage: String,
        reasonCode: String?,
        observedAt: Long,
        scheduledAt: Long?,
        notificationId: Int?,
        batchKey: String?,
        retentionCutoff: Long,
        maxRows: Int,
        currentPrunedThrough: () -> Long,
        persistPrunedThrough: (Long) -> Unit,
    ): ReminderHistoryInsertResult = transaction {
        val duplicate = readableDatabase.rawQuery(
            "SELECT 1 FROM reminder_history " +
                "WHERE account_hash = ? AND history_generation = ? " +
                "AND observation_id = ? LIMIT 1",
            arrayOf(
                accountHash,
                historyGeneration.toString(),
                observationId,
            ),
        ).use { it.moveToFirst() }
        if (duplicate) return@transaction ReminderHistoryInsertResult.DUPLICATE
        if (operationSequence <= currentPrunedThrough()) {
            return@transaction ReminderHistoryInsertResult.EXPIRED
        }

        pruneHistoryBeforeLocked(
            accountHash,
            historyGeneration,
            retentionCutoff,
            currentPrunedThrough,
            persistPrunedThrough,
        )
        writableDatabase.insertOrThrow(
            "reminder_history",
            null,
            ContentValues().apply {
                put("account_hash", accountHash)
                put("session_epoch", sessionEpoch)
                put("history_generation", historyGeneration)
                put("observation_id", observationId)
                put("operation_sequence", operationSequence)
                put("subject_kind", subjectKind)
                if (subjectId == null) putNull("subject_id") else put("subject_id", subjectId)
                put("logical_key", logicalKey)
                put("category", category)
                put("stage", stage)
                if (reasonCode == null) putNull("reason_code") else put("reason_code", reasonCode)
                put("observed_at", observedAt)
                if (scheduledAt == null) putNull("scheduled_at") else put("scheduled_at", scheduledAt)
                if (notificationId == null) {
                    putNull("notification_id")
                } else {
                    put("notification_id", notificationId)
                }
                if (batchKey == null) putNull("batch_key") else put("batch_key", batchKey)
            },
        )
        trimHistoryCountLocked(
            accountHash,
            historyGeneration,
            maxRows,
            currentPrunedThrough,
            persistPrunedThrough,
        )
        ReminderHistoryInsertResult.INSERTED
    }

    private fun pruneHistoryBeforeLocked(
        accountHash: String,
        historyGeneration: Long,
        retentionCutoff: Long,
        currentPrunedThrough: () -> Long,
        persistPrunedThrough: (Long) -> Unit,
    ) {
        val removedMax = readableDatabase.rawQuery(
            "SELECT MAX(operation_sequence) FROM reminder_history " +
                "WHERE account_hash = ? AND history_generation = ? " +
                "AND observed_at < ?",
            arrayOf(
                accountHash,
                historyGeneration.toString(),
                retentionCutoff.toString(),
            ),
        ).use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
        } ?: return
        if (removedMax > currentPrunedThrough()) persistPrunedThrough(removedMax)
        writableDatabase.delete(
            "reminder_history",
            "account_hash = ? AND history_generation = ? AND observed_at < ?",
            arrayOf(
                accountHash,
                historyGeneration.toString(),
                retentionCutoff.toString(),
            ),
        )
    }

    private fun trimHistoryCountLocked(
        accountHash: String,
        historyGeneration: Long,
        maxRows: Int,
        currentPrunedThrough: () -> Long,
        persistPrunedThrough: (Long) -> Unit,
    ) {
        val removedMax = readableDatabase.rawQuery(
            "SELECT MAX(operation_sequence) FROM reminder_history " +
                "WHERE account_hash = ? AND history_generation = ? AND id NOT IN (" +
                "SELECT id FROM reminder_history WHERE account_hash = ? " +
                "AND history_generation = ? ORDER BY id DESC LIMIT ?)",
            arrayOf(
                accountHash,
                historyGeneration.toString(),
                accountHash,
                historyGeneration.toString(),
                maxRows.toString(),
            ),
        ).use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
        } ?: return
        if (removedMax > currentPrunedThrough()) persistPrunedThrough(removedMax)
        writableDatabase.execSQL(
            "DELETE FROM reminder_history WHERE account_hash = ? " +
                "AND history_generation = ? AND id NOT IN (" +
                "SELECT id FROM reminder_history WHERE account_hash = ? " +
                "AND history_generation = ? ORDER BY id DESC LIMIT ?)",
            arrayOf<Any?>(
                accountHash,
                historyGeneration,
                accountHash,
                historyGeneration,
                maxRows,
            ),
        )
    }

    @Synchronized
    fun maxReminderHistoryId(
        accountHash: String,
        historyGeneration: Long,
    ): Long = readableDatabase.rawQuery(
        "SELECT MAX(id) FROM reminder_history " +
            "WHERE account_hash = ? AND history_generation = ?",
        arrayOf(accountHash, historyGeneration.toString()),
    ).use { cursor ->
        if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else 0L
    }

    @Synchronized
    fun listReminderHistory(
        accountHash: String,
        historyGeneration: Long,
        snapshotMaxId: Long?,
        beforeId: Long?,
        category: String?,
        subjectRefs: List<Pair<String, String?>>,
        limit: Int = 50,
    ): List<ReminderHistoryRow> {
        val selection = StringBuilder(
            "account_hash = ? AND history_generation = ?",
        )
        val arguments = mutableListOf<Any?>(
            accountHash,
            historyGeneration.toString(),
        )
        if (snapshotMaxId != null) {
            selection.append(" AND id <= ?")
            arguments.add(snapshotMaxId.toString())
        }
        if (beforeId != null) {
            selection.append(" AND id < ?")
            arguments.add(beforeId.toString())
        }
        if (category != null) {
            selection.append(" AND category = ?")
            arguments.add(category)
        }
        if (subjectRefs.isNotEmpty()) {
            selection.append(" AND (")
            subjectRefs.forEachIndexed { index, ref ->
                if (index > 0) selection.append(" OR ")
                if (ref.second == null) {
                    selection.append("(subject_kind = ? AND subject_id IS NULL)")
                    arguments.add(ref.first)
                } else {
                    selection.append("(subject_kind = ? AND subject_id = ?)")
                    arguments.add(ref.first)
                    arguments.add(ref.second)
                }
            }
            selection.append(")")
        }
        readableDatabase.query(
            "reminder_history",
            null,
            selection.toString(),
            arguments.map { it?.toString() }.toTypedArray(),
            null,
            null,
            "id DESC",
            limit.toString(),
        ).use { cursor ->
            return buildList {
                while (cursor.moveToNext()) add(cursor.toReminderHistory())
            }
        }
    }

    @Synchronized
    fun recordReminderScheduleEvidence(
        row: ReminderScheduleEvidenceRow,
    ): Boolean = transaction {
        val existing = readableDatabase.rawQuery(
            "SELECT operation_sequence FROM reminder_schedule_evidence " +
                "WHERE account_hash = ? AND history_generation = ? AND logical_key = ?",
            arrayOf(
                row.accountHash,
                row.historyGeneration.toString(),
                row.logicalKey,
            ),
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getLong(0) else null
        }
        if (existing != null && existing > row.operationSequence) {
            return@transaction false
        }
        writableDatabase.insertWithOnConflict(
            "reminder_schedule_evidence",
            null,
            ContentValues().apply {
                put("account_hash", row.accountHash)
                put("history_generation", row.historyGeneration)
                put("logical_key", row.logicalKey)
                put("session_epoch", row.sessionEpoch)
                put("operation_sequence", row.operationSequence)
                put("subject_kind", row.subjectKind)
                if (row.subjectId == null) putNull("subject_id")
                else put("subject_id", row.subjectId)
                put("category", row.category)
                if (row.scheduledAt == null) putNull("scheduled_at")
                else put("scheduled_at", row.scheduledAt)
                if (row.notificationId == null) putNull("notification_id")
                else put("notification_id", row.notificationId)
                if (row.expectedPayload == null) putNull("expected_payload")
                else put("expected_payload", row.expectedPayload)
                put("state", row.state)
                put("confirmed_at", row.confirmedAt)
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
        true
    }

    @Synchronized
    fun removeReminderScheduleEvidence(
        accountHash: String,
        historyGeneration: Long,
        logicalKey: String,
        operationSequence: Long,
    ): Boolean {
        val existing = readableDatabase.rawQuery(
            "SELECT operation_sequence FROM reminder_schedule_evidence " +
                "WHERE account_hash = ? AND history_generation = ? AND logical_key = ?",
            arrayOf(accountHash, historyGeneration.toString(), logicalKey),
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getLong(0) else null
        } ?: return true
        if (existing > operationSequence) return false
        writableDatabase.delete(
            "reminder_schedule_evidence",
            "account_hash = ? AND history_generation = ? AND logical_key = ?",
            arrayOf(accountHash, historyGeneration.toString(), logicalKey),
        )
        return true
    }

    @Synchronized
    fun scheduleEvidenceForSubject(
        accountHash: String,
        historyGeneration: Long,
        subjectKind: String,
        subjectId: String?,
    ): List<ReminderScheduleEvidenceRow> {
        val selection = "account_hash = ? AND history_generation = ? " +
            "AND subject_kind = ? AND " +
            if (subjectId == null) "subject_id IS NULL" else "subject_id = ?"
        val arguments = mutableListOf<Any?>(
            accountHash,
            historyGeneration.toString(),
            subjectKind,
        )
        if (subjectId != null) arguments.add(subjectId)
        return readableDatabase.query(
            "reminder_schedule_evidence",
            null,
            selection,
            arguments.map { it?.toString() }.toTypedArray(),
            null,
            null,
            "confirmed_at DESC",
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.toScheduleEvidence())
            }
        }
    }

    @Synchronized
    fun eventsForSubject(
        accountHash: String,
        subjectId: String?,
        sessionEpoch: Long? = null,
    ): List<StoredReminderEvent> {
        val selection = buildString {
            append("account_hash = ?")
            if (sessionEpoch != null) append(" AND session_epoch = ?")
            append(
                if (subjectId == null) {
                    " AND assignment_id IS NULL"
                } else {
                    " AND assignment_id = ?"
                },
            )
        }
        val arguments = buildList<String> {
            add(accountHash)
            if (sessionEpoch != null) add(sessionEpoch.toString())
            if (subjectId != null) add(subjectId)
        }.toTypedArray()
        return readableDatabase.query(
            "events",
            null,
            selection,
            arguments,
            null,
            null,
            "updated_at DESC",
            "50",
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.toEvent())
            }
        }
    }

    @Synchronized
    fun deleteReminderHistoryForGeneration(
        accountHash: String,
        historyGeneration: Long,
    ) {
        writableDatabase.delete(
            "reminder_history",
            "account_hash = ? AND history_generation = ?",
            arrayOf(accountHash, historyGeneration.toString()),
        )
        writableDatabase.delete(
            "reminder_schedule_evidence",
            "account_hash = ? AND history_generation = ?",
            arrayOf(accountHash, historyGeneration.toString()),
        )
    }

    @Synchronized
    fun deleteAllReminderHistory() {
        transaction {
            writableDatabase.delete("reminder_history", null, null)
            writableDatabase.delete("reminder_schedule_evidence", null, null)
        }
    }

    @Synchronized
    fun deleteReminderHistoryBefore(
        accountHash: String,
        historyGeneration: Long,
        cutoff: Long,
    ): Int = writableDatabase.delete(
        "reminder_history",
        "account_hash = ? AND history_generation = ? AND observed_at < ?",
        arrayOf(accountHash, historyGeneration.toString(), cutoff.toString()),
    )

    private fun requireAccount(accountHash: String) {
        val exists = readableDatabase.rawQuery(
            "SELECT 1 FROM accounts WHERE account_hash = ? LIMIT 1",
            arrayOf(accountHash),
        ).use { it.moveToFirst() }
        if (exists) return
        writableDatabase.insertOrThrow(
            "accounts",
            null,
            ContentValues().apply {
                put("account_hash", accountHash)
                put("session_epoch", 1)
                put("active", 0)
                put("updated_at", System.currentTimeMillis())
            },
        )
    }

    private fun validateSession(accountHash: String, sessionEpoch: Long) {
        val account = readAccount(accountHash)
            ?: throw IllegalStateException("账号提醒状态不存在")
        if (!account.active || account.sessionEpoch != sessionEpoch) {
            throw IllegalStateException("账号会话已变化，旧提醒状态已拒绝")
        }
    }

    private fun readNotificationAttemptLocked(
        accountHash: String,
    ): NotificationAttempt? = readableDatabase.query(
        "notification_attempts",
        null,
        "account_hash = ?",
        arrayOf(accountHash),
        null,
        null,
        null,
    ).use { cursor ->
        if (cursor.moveToFirst()) cursor.toNotificationAttempt() else null
    }

    private fun deleteNotificationAttemptLocked(accountHash: String) {
        writableDatabase.delete(
            "notification_attempts",
            "account_hash = ?",
            arrayOf(accountHash),
        )
    }

    private fun insertEvent(event: StoredReminderEvent, now: Long) {
        writableDatabase.insertOrThrow(
            "events",
            null,
            ContentValues().apply {
                put("event_id", event.eventId)
                put("account_hash", event.accountHash)
                put("session_epoch", event.sessionEpoch)
                put("type", event.type)
                put("assignment_id", event.assignmentId)
                put("course_name", event.courseName)
                put("title", event.title)
                put("notify_at", event.notifyAt)
                put("event_kind", event.eventKind)
                put("deadline_source", event.deadlineSource)
                event.deadlineAt?.let { put("deadline_at", it) } ?: putNull("deadline_at")
                put("offsets", JSONArray(event.offsets).toString())
                event.batchId?.let { put("batch_id", it) } ?: putNull("batch_id")
                put("status", STATUS_PENDING)
                put("notification_id", event.notificationId)
                put("created_at", now)
                put("updated_at", now)
            },
        )
    }

    private fun cancelEventsLocked(accountHash: String, now: Long) {
        writableDatabase.update(
            "events",
            ContentValues().apply {
                put("status", STATUS_CANCELLED)
                put("updated_at", now)
            },
            "account_hash = ? AND status IN (?, ?)",
            arrayOf(accountHash, STATUS_PENDING, STATUS_SUBMITTED),
        )
    }

    private fun normalizeInterval(minutes: Int): Int =
        if (minutes == 120 || minutes == 240 || minutes == 360) minutes else 240

    private fun <T> transaction(block: () -> T): T {
        writableDatabase.beginTransaction()
        return try {
            val value = block()
            writableDatabase.setTransactionSuccessful()
            value
        } finally {
            writableDatabase.endTransaction()
        }
    }

    private fun Cursor.toAccount() = ReminderAccountState(
        accountHash = getString(getColumnIndexOrThrow("account_hash")),
        sessionEpoch = getLong(getColumnIndexOrThrow("session_epoch")),
        active = getInt(getColumnIndexOrThrow("active")) == 1,
        backgroundEnabled = getInt(getColumnIndexOrThrow("background_enabled")) == 1,
        intervalMinutes = getInt(getColumnIndexOrThrow("interval_minutes")),
        listenerEnabled = getInt(getColumnIndexOrThrow("listener_enabled")) == 1,
        newAssignmentEnabled = getInt(getColumnIndexOrThrow("new_assignment_enabled")) == 1,
        showDetails = getInt(getColumnIndexOrThrow("show_details")) == 1,
        baselineCompleted = getInt(getColumnIndexOrThrow("baseline_completed")) == 1,
        baselinedSources = stringSet(getString(getColumnIndexOrThrow("baselined_sources"))),
        knownAssignmentIds = stringSet(getString(getColumnIndexOrThrow("known_ids"))),
        sentNewAssignmentIds = stringSet(getString(getColumnIndexOrThrow("sent_new_ids"))),
        pendingUpdate = getInt(getColumnIndexOrThrow("pending_update")) == 1,
        mutationVersion = getLong(getColumnIndexOrThrow("mutation_version")),
        pendingSignalVersion = getLong(getColumnIndexOrThrow("pending_signal_version")),
        consumedSignalVersion = getLong(getColumnIndexOrThrow("consumed_signal_version")),
        attemptedSignalVersion = getLong(getColumnIndexOrThrow("attempted_signal_version")),
        lastSignalCheckAt = nullableLong("last_signal_check_at"),
        lastAttemptAt = nullableLong("last_attempt_at"),
        lastDataSuccessAt = nullableLong("last_data_success_at"),
        lastFullSuccessAt = nullableLong("last_full_success_at"),
        lastFailure = nullableString("last_failure"),
        nextCheckAt = nullableLong("next_check_at"),
        migrationState = getString(getColumnIndexOrThrow("migration_state")),
        claimToken = nullableString("claim_token"),
        allowUrgentNightBreakthrough = getInt(getColumnIndexOrThrow("allow_urgent_night_breakthrough")) == 1,
        deadlineChannelId = getString(getColumnIndexOrThrow("deadline_channel_id")),
    )

    private fun Cursor.toNotificationAttempt(): NotificationAttempt {
        val phase = NotificationAttemptPhase.from(
            getString(getColumnIndexOrThrow("phase")),
        ) ?: throw IllegalStateException("未知提醒尝试阶段")
        return NotificationAttempt(
            accountHash = getString(getColumnIndexOrThrow("account_hash")),
            sessionEpoch = getLong(getColumnIndexOrThrow("session_epoch")),
            claimToken = getString(getColumnIndexOrThrow("claim_token")),
            ownerWorkId = nullableString("owner_work_id"),
            claimedVersion = getLong(getColumnIndexOrThrow("claimed_version")),
            claimedAt = getLong(getColumnIndexOrThrow("claimed_at")),
            priorAttemptedVersion =
                getLong(getColumnIndexOrThrow("prior_attempted_version")),
            priorLastSignalCheckAt = nullableLong("prior_last_signal_check_at"),
            priorConsumedVersion =
                getLong(getColumnIndexOrThrow("prior_consumed_version")),
            phase = phase,
        )
    }

    private fun NotificationAttempt.toClaim(pendingVersion: Long) =
        NotificationSignalClaim(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            version = claimedVersion,
            token = claimToken,
            claimedAt = claimedAt,
            priorAttemptedVersion = priorAttemptedVersion,
            priorLastSignalCheckAt = priorLastSignalCheckAt,
            priorPendingVersion = pendingVersion,
            priorConsumedVersion = priorConsumedVersion,
            ownerWorkId = ownerWorkId,
        )

    private fun Cursor.toSnapshot() = StoredReminderSnapshot(
        accountHash = getString(getColumnIndexOrThrow("account_hash")),
        assignmentId = getString(getColumnIndexOrThrow("assignment_id")),
        sessionEpoch = getLong(getColumnIndexOrThrow("session_epoch")),
        courseName = getString(getColumnIndexOrThrow("course_name")),
        title = getString(getColumnIndexOrThrow("title")),
        deadlineAt = nullableLong("deadline_at"),
        deadlineTrusted = getInt(getColumnIndexOrThrow("deadline_trusted")) == 1,
        deadlineReadFailed = getInt(getColumnIndexOrThrow("deadline_read_failed")) == 1,
        status = getString(getColumnIndexOrThrow("status")),
        completed = getInt(getColumnIndexOrThrow("completed")) == 1,
        hidden = getInt(getColumnIndexOrThrow("hidden")) == 1,
        followed = getInt(getColumnIndexOrThrow("followed")) == 1,
        formal = getInt(getColumnIndexOrThrow("formal")) == 1,
        inAssignmentScope = getInt(getColumnIndexOrThrow("in_assignment_scope")) == 1,
        eventKind = getString(getColumnIndexOrThrow("event_kind")),
        deadlineSource = getString(getColumnIndexOrThrow("deadline_source")),
    )

    private fun Cursor.toEvent() = StoredReminderEvent(
        eventId = getString(getColumnIndexOrThrow("event_id")),
        accountHash = getString(getColumnIndexOrThrow("account_hash")),
        sessionEpoch = getLong(getColumnIndexOrThrow("session_epoch")),
        type = getString(getColumnIndexOrThrow("type")),
        assignmentId = getString(getColumnIndexOrThrow("assignment_id")),
        courseName = getString(getColumnIndexOrThrow("course_name")),
        title = getString(getColumnIndexOrThrow("title")),
        notifyAt = getLong(getColumnIndexOrThrow("notify_at")),
        deadlineAt = nullableLong("deadline_at"),
        offsets = intList(getString(getColumnIndexOrThrow("offsets"))),
        batchId = nullableString("batch_id"),
        status = getString(getColumnIndexOrThrow("status")),
        notificationId = getInt(getColumnIndexOrThrow("notification_id")),
        eventKind = getString(getColumnIndexOrThrow("event_kind")),
        updatedAt = getLong(getColumnIndexOrThrow("updated_at")),
        deadlineSource = getString(getColumnIndexOrThrow("deadline_source")),
    )

    private fun Cursor.toReminderHistory() = ReminderHistoryRow(
        id = getLong(getColumnIndexOrThrow("id")),
        accountHash = getString(getColumnIndexOrThrow("account_hash")),
        sessionEpoch = getLong(getColumnIndexOrThrow("session_epoch")),
        historyGeneration = getLong(getColumnIndexOrThrow("history_generation")),
        observationId = getString(getColumnIndexOrThrow("observation_id")),
        operationSequence = getLong(getColumnIndexOrThrow("operation_sequence")),
        subjectKind = getString(getColumnIndexOrThrow("subject_kind")),
        subjectId = nullableString("subject_id"),
        logicalKey = getString(getColumnIndexOrThrow("logical_key")),
        category = getString(getColumnIndexOrThrow("category")),
        stage = getString(getColumnIndexOrThrow("stage")),
        reasonCode = nullableString("reason_code"),
        observedAt = getLong(getColumnIndexOrThrow("observed_at")),
        scheduledAt = nullableLong("scheduled_at"),
        notificationId = nullableLong("notification_id")?.toInt(),
        batchKey = nullableString("batch_key"),
    )

    private fun Cursor.toScheduleEvidence() = ReminderScheduleEvidenceRow(
        accountHash = getString(getColumnIndexOrThrow("account_hash")),
        historyGeneration = getLong(getColumnIndexOrThrow("history_generation")),
        logicalKey = getString(getColumnIndexOrThrow("logical_key")),
        sessionEpoch = getLong(getColumnIndexOrThrow("session_epoch")),
        operationSequence = getLong(getColumnIndexOrThrow("operation_sequence")),
        subjectKind = getString(getColumnIndexOrThrow("subject_kind")),
        subjectId = nullableString("subject_id"),
        category = getString(getColumnIndexOrThrow("category")),
        scheduledAt = nullableLong("scheduled_at"),
        notificationId = nullableLong("notification_id")?.toInt(),
        expectedPayload = nullableString("expected_payload"),
        state = getString(getColumnIndexOrThrow("state")),
        confirmedAt = getLong(getColumnIndexOrThrow("confirmed_at")),
    )

    private fun Cursor.nullableLong(column: String): Long? {
        val index = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getLong(index)
    }

    private fun Cursor.nullableString(column: String): String? {
        val index = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getString(index)
    }

    companion object {
        const val EVENT_NEW = "newAssignment"
        const val EVENT_DEADLINE = "deadline"
        const val STATUS_PENDING = "pending"
        const val STATUS_SUBMITTED = "submitted"
        const val STATUS_CANCELLED = "cancelled"
        const val STATUS_INVALID = "invalid"

        private const val DATABASE_NAME = "assignment_reminders_v1.db"
        private const val DATABASE_VERSION = 8
        private const val DAY_MILLIS = 86_400_000L
        private const val TAG = "ReminderDatabase"

        @Volatile
        private var instance: ReminderDatabase? = null

        fun get(context: Context): ReminderDatabase =
            instance ?: synchronized(this) {
                instance ?: ReminderDatabase(context.applicationContext)
                    .also { instance = it }
            }

        @VisibleForTesting
        fun openForTest(context: Context, databaseName: String): ReminderDatabase =
            ReminderDatabase(context.applicationContext, databaseName)

        fun parseInstant(value: Any?): Long? {
            val text = value as? String ?: return null
            if (text.isBlank()) return null
            return try {
                Instant.parse(text).toEpochMilli()
            } catch (error: DateTimeParseException) {
                Log.w(TAG, "parseInstant ${error.javaClass.simpleName}")
                null
            } catch (error: ArithmeticException) {
                // A valid Instant can still be outside the range of epoch milliseconds.
                Log.w(TAG, "parseInstant ${error.javaClass.simpleName}")
                null
            }
        }

        fun stringSet(raw: String?): Set<String> = try {
            val array = JSONArray(raw ?: "[]")
            buildSet {
                for (index in 0 until array.length()) {
                    array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
                }
            }
        } catch (error: JSONException) {
            Log.w(TAG, "stringSet ${error.javaClass.simpleName}")
            emptySet()
        }

        private fun intList(raw: String?): List<Int> = try {
            val array = JSONArray(raw ?: "[]")
            buildList {
                for (index in 0 until array.length()) add(array.optInt(index))
            }
        } catch (error: JSONException) {
            Log.w(TAG, "intList ${error.javaClass.simpleName}")
            emptyList()
        }

        fun eventFromJson(
            accountHash: String,
            sessionEpoch: Long,
            json: JSONObject,
        ): StoredReminderEvent {
            val eventId = json.getString("eventId")
            val offsets = json.optJSONArray("offsets")?.let { array ->
                buildList {
                    for (index in 0 until array.length()) add(array.optInt(index))
                }
            }.orEmpty()
            return StoredReminderEvent(
                eventId = eventId,
                accountHash = accountHash,
                sessionEpoch = sessionEpoch,
                type = json.getString("type"),
                eventKind = json.optString("eventKind", "deadline"),
                deadlineSource = json.optString("deadlineSource", "unknown")
                    .ifBlank { "unknown" },
                assignmentId = json.getString("assignmentId"),
                courseName = json.optString("courseName"),
                title = json.optString("title"),
                notifyAt = parseInstant(json.optString("notifyAt")) ?: 0L,
                deadlineAt = parseInstant(json.opt("deadlineAt")),
                offsets = offsets,
                batchId = json.optString("batchId").takeIf { it.isNotBlank() },
                status = STATUS_PENDING,
                notificationId = stableNotificationId(eventId),
            )
        }

        fun snapshotFromJson(
            accountHash: String,
            sessionEpoch: Long,
            json: JSONObject,
        ) = StoredReminderSnapshot(
            accountHash = accountHash,
            assignmentId = json.getString("assignmentId"),
            sessionEpoch = sessionEpoch,
            courseName = json.optString("courseName"),
            title = json.optString("title"),
            deadlineAt = parseInstant(json.opt("deadlineAt")),
            deadlineTrusted = json.optBoolean("deadlineTrusted"),
            deadlineReadFailed = json.optBoolean("deadlineReadFailed"),
            status = json.optString("status", "unknown"),
            completed = json.optBoolean("completed"),
            hidden = json.optBoolean("hidden"),
            followed = json.optBoolean("followed", true),
            formal = json.optBoolean("formal"),
            eventKind = json.optString("eventKind", "deadline"),
            deadlineSource = json.optString("deadlineSource", "unknown")
                .ifBlank { "unknown" },
            inAssignmentScope = json.optBoolean("inAssignmentScope", json.optBoolean("formal")),
        )

        fun stableNotificationId(eventId: String): Int =
            NativeReminderPolicy.notificationId(eventId)
    }
}
