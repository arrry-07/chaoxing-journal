package com.example.studyassistant

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

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
    val lastAttemptAt: Long?,
    val lastDataSuccessAt: Long?,
    val lastFullSuccessAt: Long?,
    val lastFailure: String?,
    val nextCheckAt: Long?,
    val migrationState: String,
)

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
)

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
)

class ReminderDatabase private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
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
                known_ids TEXT NOT NULL DEFAULT '[]',
                sent_new_ids TEXT NOT NULL DEFAULT '[]',
                pending_update INTEGER NOT NULL DEFAULT 0,
                mutation_version INTEGER NOT NULL DEFAULT 0,
                pending_signal_version INTEGER NOT NULL DEFAULT 0,
                consumed_signal_version INTEGER NOT NULL DEFAULT 0,
                last_signal_at INTEGER,
                last_attempt_at INTEGER,
                last_data_success_at INTEGER,
                last_full_success_at INTEGER,
                last_failure TEXT,
                next_check_at INTEGER,
                migration_state TEXT NOT NULL DEFAULT 'legacy_pending',
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
                deadline_trusted INTEGER NOT NULL,
                deadline_read_failed INTEGER NOT NULL,
                completed INTEGER NOT NULL,
                hidden INTEGER NOT NULL,
                followed INTEGER NOT NULL,
                formal INTEGER NOT NULL,
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
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Version 1 is the first persisted format. Future upgrades must migrate
        // in place and must never drop reminder history or task identities.
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
            if (switchingAccount != null) {
                writableDatabase.execSQL(
                    "UPDATE accounts SET session_epoch = session_epoch + 1, active = 0, " +
                        "updated_at = ? WHERE account_hash = ?",
                    arrayOf<Any?>(now, switchingAccount),
                )
                cancelEventsLocked(switchingAccount, now)
            }
            requireAccount(targetHash)
            if (switchingAccount != null) {
                writableDatabase.execSQL(
                    "UPDATE accounts SET session_epoch = session_epoch + 1, active = 0",
                )
            } else {
                writableDatabase.execSQL("UPDATE accounts SET active = 0")
            }
            writableDatabase.execSQL(
                "UPDATE accounts SET active = 1, updated_at = ? WHERE account_hash = ?",
                arrayOf<Any?>(now, targetHash),
            )
            if (switchingAccount != null) {
                cancelEventsLocked(targetHash, now)
            }
            readAccount(targetHash)!!
        }

    @Synchronized
    fun rotateSessionEpoch(accountHash: String): Long =
        transaction {
            val now = System.currentTimeMillis()
            requireAccount(accountHash)
            writableDatabase.execSQL(
                "UPDATE accounts SET session_epoch = session_epoch + 1, updated_at = ? " +
                    "WHERE account_hash = ?",
                arrayOf<Any?>(now, accountHash),
            )
            cancelEventsLocked(accountHash, now)
            readAccount(accountHash)!!.sessionEpoch
        }

    @Synchronized
    fun clearActiveAccount(accountHash: String): Long =
        transaction {
            val now = System.currentTimeMillis()
            requireAccount(accountHash)
            writableDatabase.delete(
                "snapshots",
                "account_hash = ?",
                arrayOf(accountHash),
            )
            writableDatabase.delete(
                "events",
                "account_hash = ?",
                arrayOf(accountHash),
            )
            writableDatabase.delete(
                "notification_signals",
                "account_hash = ?",
                arrayOf(accountHash),
            )
            writableDatabase.execSQL(
                "UPDATE accounts SET session_epoch = session_epoch + 1, active = 0, " +
                    "baseline_completed = 0, known_ids = '[]', sent_new_ids = '[]', " +
                    "pending_update = 0, pending_signal_version = 0, " +
                    "consumed_signal_version = 0, last_signal_at = NULL, " +
                    "last_attempt_at = NULL, last_data_success_at = NULL, " +
                    "last_full_success_at = NULL, last_failure = NULL, " +
                    "next_check_at = NULL, migration_state = 'legacy_pending', " +
                    "mutation_version = mutation_version + 1, updated_at = ? " +
                    "WHERE account_hash = ?",
                arrayOf<Any?>(now, accountHash),
            )
            readAccount(accountHash)!!.sessionEpoch
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
    ): ReminderAccountState {
        validateSession(accountHash, sessionEpoch)
        val mutationVersion = readAccount(accountHash)!!.mutationVersion + 1
        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("background_enabled", if (backgroundEnabled) 1 else 0)
                put("interval_minutes", normalizeInterval(intervalMinutes))
                put("listener_enabled", if (listenerEnabled) 1 else 0)
                put("new_assignment_enabled", if (newAssignmentEnabled) 1 else 0)
                put("show_details", if (showDetails) 1 else 0)
                put("mutation_version", mutationVersion)
                put("updated_at", System.currentTimeMillis())
            },
            "account_hash = ?",
            arrayOf(accountHash),
        )
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
                    snapshot.deadlineAt?.let { put("deadline_at", it) }
                        ?: putNull("deadline_at")
                    put("deadline_trusted", if (snapshot.deadlineTrusted) 1 else 0)
                    put("deadline_read_failed", if (snapshot.deadlineReadFailed) 1 else 0)
                    put("completed", if (snapshot.completed) 1 else 0)
                    put("hidden", if (snapshot.hidden) 1 else 0)
                    put("followed", if (snapshot.followed) 1 else 0)
                    put("formal", if (snapshot.formal) 1 else 0)
                },
            )
        }

        val desiredDeadline = events.filter { it.type == EVENT_DEADLINE }
        val desiredIds = desiredDeadline.map { it.eventId }.toSet()
        val invalidatedEvents = mutableListOf<StoredReminderEvent>()
        val existing = eventsForAccount(accountHash)
        val eligibleAssignmentIds = snapshots
            .filter { it.formal && it.followed && !it.completed && !it.hidden }
            .map { it.assignmentId }
            .toSet()
        existing.filter {
            (it.status == STATUS_PENDING || it.status == STATUS_SUBMITTED) &&
                it.assignmentId !in eligibleAssignmentIds
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
        existing.filter {
            it.type == EVENT_DEADLINE &&
                it.status == STATUS_PENDING &&
                it.eventId !in desiredIds &&
                it.assignmentId in eligibleAssignmentIds
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

        desiredDeadline.forEach { event ->
            val current = existing.firstOrNull { it.eventId == event.eventId }
            when {
                current == null -> insertEvent(event, now)
                current.status == STATUS_PENDING ->
                    updateEvent(event, sessionEpoch, now)
                current.status == STATUS_CANCELLED ->
                    // Hiding an assignment cancels its deadline events. When it
                    // becomes eligible again the planner emits the same stable
                    // event id; reactivate it instead of silently dropping the
                    // reminder forever.
                    updateEvent(event, sessionEpoch, now, status = STATUS_PENDING)
            }
        }

        val newEvents = mutableListOf<StoredReminderEvent>()
        events.filter { it.type == EVENT_NEW }.forEach { event ->
            if (eventsForAccount(accountHash).none { it.eventId == event.eventId }) {
                insertEvent(event, now)
                newEvents.add(event)
            }
        }

        writableDatabase.update(
            "accounts",
            ContentValues().apply {
                put("baseline_completed", if (baselineCompleted) 1 else 0)
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

        PlanApplication(
            desiredDeadlineEvents = desiredDeadline,
            invalidatedEvents = invalidatedEvents,
            newEvents = newEvents,
            pendingNewCount = eventsForAccount(accountHash)
                .count { it.type == EVENT_NEW && it.status == STATUS_PENDING },
            pendingDeadlineCount = eventsForAccount(accountHash)
                .count { it.type == EVENT_DEADLINE && it.status == STATUS_PENDING },
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
    fun event(eventId: String): StoredReminderEvent? {        readableDatabase.query(
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
    fun consumeSignal(accountHash: String, version: Long) {
        val account = readAccount(accountHash) ?: return
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
        knownAssignmentIds = stringSet(getString(getColumnIndexOrThrow("known_ids"))),
        sentNewAssignmentIds = stringSet(getString(getColumnIndexOrThrow("sent_new_ids"))),
        pendingUpdate = getInt(getColumnIndexOrThrow("pending_update")) == 1,
        mutationVersion = getLong(getColumnIndexOrThrow("mutation_version")),
        pendingSignalVersion = getLong(getColumnIndexOrThrow("pending_signal_version")),
        consumedSignalVersion = getLong(getColumnIndexOrThrow("consumed_signal_version")),
        lastAttemptAt = nullableLong("last_attempt_at"),
        lastDataSuccessAt = nullableLong("last_data_success_at"),
        lastFullSuccessAt = nullableLong("last_full_success_at"),
        lastFailure = nullableString("last_failure"),
        nextCheckAt = nullableLong("next_check_at"),
        migrationState = getString(getColumnIndexOrThrow("migration_state")),
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
        status = "",
        completed = getInt(getColumnIndexOrThrow("completed")) == 1,
        hidden = getInt(getColumnIndexOrThrow("hidden")) == 1,
        followed = getInt(getColumnIndexOrThrow("followed")) == 1,
        formal = getInt(getColumnIndexOrThrow("formal")) == 1,
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
        private const val DATABASE_VERSION = 1

        @Volatile
        private var instance: ReminderDatabase? = null

        fun get(context: Context): ReminderDatabase =
            instance ?: synchronized(this) {
                instance ?: ReminderDatabase(context.applicationContext)
                    .also { instance = it }
            }

        fun parseInstant(value: Any?): Long? {
            val text = value as? String ?: return null
            if (text.isBlank()) return null
            return runCatching { Instant.parse(text).toEpochMilli() }.getOrNull()
        }

        fun stringSet(raw: String?): Set<String> = runCatching {
            val array = JSONArray(raw ?: "[]")
            buildSet {
                for (index in 0 until array.length()) {
                    array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
                }
            }
        }.getOrDefault(emptySet())

        private fun intList(raw: String?): List<Int> = runCatching {
            val array = JSONArray(raw ?: "[]")
            buildList {
                for (index in 0 until array.length()) add(array.optInt(index))
            }
        }.getOrDefault(emptyList())

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
            status = json.optString("status"),
            completed = json.optBoolean("completed"),
            hidden = json.optBoolean("hidden"),
            followed = json.optBoolean("followed", true),
            formal = json.optBoolean("formal"),
        )

        fun stableNotificationId(eventId: String): Int =
            NativeReminderPolicy.notificationId(eventId)
    }
}
