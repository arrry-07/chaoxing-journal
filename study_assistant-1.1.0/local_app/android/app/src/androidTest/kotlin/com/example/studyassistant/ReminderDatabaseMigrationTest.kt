package com.example.studyassistant

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReminderDatabaseMigrationTest {
    private lateinit var context: Context
    private val names = mutableListOf<String>()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    @After
    fun tearDown() {
        for (name in names) {
            runCatching { context.deleteDatabase(name) }
        }
    }

    @Test
    fun v3ToV6PreservesAccountAndAddsClaimAndAttemptTables() {
        val name = "migration-v3-${System.nanoTime()}.db"
        names.add(name)
        createDatabase(name, version = 3, includeAttemptColumns = false) { db ->
            insertAccount(
                db,
                accountHash = "migration-v3",
                pendingVersion = 3,
                consumedVersion = 2,
            )
            seedLegacyRows(db, "migration-v3")
        }

        val database = ReminderDatabase.openForTest(context, name)
        val account = database.readAccount("migration-v3")!!

        assertEquals(6, database.readableDatabase.version)
        assertEquals(3L, account.pendingSignalVersion)
        assertEquals(2L, account.consumedSignalVersion)
        assertEquals(0L, account.attemptedSignalVersion)
        assertNull(account.lastSignalCheckAt)
        assertNull(account.claimToken)
        assertMigratedBusinessDataIntact(database, "migration-v3")
        assertV6HistoryPruneWorks(database, "migration-v3")
    }

    @Test
    fun v4ToV6PreservesAttemptStateAndAddsNullableToken() {
        val name = "migration-v4-${System.nanoTime()}.db"
        names.add(name)
        createDatabase(name, version = 4, includeAttemptColumns = true) { db ->
            insertAccount(
                db,
                accountHash = "migration-v4",
                pendingVersion = 8,
                consumedVersion = 6,
                attemptedVersion = 7,
                lastSignalCheckAt = 123_456L,
            )
            seedLegacyRows(db, "migration-v4")
        }

        val database = ReminderDatabase.openForTest(context, name)
        val account = database.readAccount("migration-v4")!!

        assertEquals(6, database.readableDatabase.version)
        assertEquals(8L, account.pendingSignalVersion)
        assertEquals(6L, account.consumedSignalVersion)
        assertEquals(7L, account.attemptedSignalVersion)
        assertEquals(123_456L, account.lastSignalCheckAt)
        assertNull(account.claimToken)
        assertMigratedBusinessDataIntact(database, "migration-v4")
    }

    @Test
    fun v5ToV6PreservesAllTablesAndConsumeClearsLegacyClaimToken() {
        val name = "migration-v5-${System.nanoTime()}.db"
        names.add(name)
        createDatabase(
            name,
            version = 5,
            includeAttemptColumns = true,
            includeClaimToken = true,
        ) { db ->
            insertAccount(
                db,
                accountHash = "migration-v5",
                pendingVersion = 8,
                consumedVersion = 5,
                attemptedVersion = 7,
                lastSignalCheckAt = 123_456L,
                claimToken = "legacy-v5-token",
            )
            seedLegacyRows(db, "migration-v5")
        }

        val database = ReminderDatabase.openForTest(context, name)
        val account = database.readAccount("migration-v5")!!

        assertEquals(6, database.readableDatabase.version)
        assertEquals("legacy-v5-token", account.claimToken)
        assertMigratedBusinessDataIntact(database, "migration-v5")

        // v5 stored claim_token only on accounts without notification_attempts rows;
        // consumeSignal in v6 must still clear that dangling token once caught up.
        database.consumeSignal("migration-v5", 7L, 4L)
        assertNull(database.readAccount("migration-v5")!!.claimToken)

        val claim = database.claimNotificationAttempt("migration-v5", 4L)
        assertNotNull(claim)
        assertEquals(8L, claim!!.version)
        assertTrue(database.rollbackUnstartedNotificationAttempt(claim))
        assertNull(database.readAccount("migration-v5")!!.claimToken)
        assertV6HistoryPruneWorks(database, "migration-v5")
    }

    private fun createDatabase(
        name: String,
        version: Int,
        includeAttemptColumns: Boolean,
        includeClaimToken: Boolean = false,
        seed: (SQLiteDatabase) -> Unit,
    ) {
        val db = context.openOrCreateDatabase(name, Context.MODE_PRIVATE, null)
        try {
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
                    ${if (includeAttemptColumns) {
                        "attempted_signal_version INTEGER NOT NULL DEFAULT 0, " +
                            "last_signal_check_at INTEGER,"
                    } else {
                        ""
                    }}
                    ${if (includeClaimToken) {
                        "claim_token TEXT,"
                    } else {
                        ""
                    }}
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
                    event_kind TEXT NOT NULL DEFAULT 'deadline',
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
            db.version = version
            seed(db)
        } finally {
            db.close()
        }
    }

    private fun seedLegacyRows(db: SQLiteDatabase, accountHash: String) {
        val now = System.currentTimeMillis()
        val deadlineAt = now + 7_200_000L
        db.insertOrThrow(
            "snapshots",
            null,
            ContentValues().apply {
                put("account_hash", accountHash)
                put("assignment_id", "cx:work:1:2:migrated")
                put("session_epoch", 4L)
                put("course_name", "迁移测试课程")
                put("title", "迁移测试作业")
                put("deadline_at", deadlineAt)
                put("event_kind", "deadline")
                put("deadline_trusted", 1)
                put("deadline_read_failed", 0)
                put("completed", 0)
                put("hidden", 0)
                put("followed", 1)
                put("formal", 1)
                put("in_assignment_scope", 1)
                put("status", "pending")
            },
        )
        val eventId = "$accountHash|cx:work:1:2:migrated|deadline:$deadlineAt|60"
        db.insertOrThrow(
            "events",
            null,
            ContentValues().apply {
                put("event_id", eventId)
                put("account_hash", accountHash)
                put("session_epoch", 4L)
                put("type", "deadline")
                put("assignment_id", "cx:work:1:2:migrated")
                put("course_name", "迁移测试课程")
                put("title", "迁移测试作业")
                put("notify_at", deadlineAt - 3_600_000L)
                put("deadline_at", deadlineAt)
                put("event_kind", "deadline")
                put("offsets", "[60]")
                putNull("batch_id")
                put("status", "pending")
                put("notification_id", ReminderDatabase.stableNotificationId(eventId))
                put("created_at", now - 10_000L)
                put("updated_at", now - 5_000L)
            },
        )
        db.insertOrThrow(
            "notification_signals",
            null,
            ContentValues().apply {
                put("account_hash", accountHash)
                put("session_epoch", 4L)
                put("signal_key", "sig-$accountHash")
                put("received_at", now - 1_000L)
                putNull("consumed_version")
            },
        )
    }

    private fun assertMigratedBusinessDataIntact(
        database: ReminderDatabase,
        accountHash: String,
    ) {
        val db = database.readableDatabase
        assertEquals(
            0L,
            db.rawQuery("SELECT COUNT(*) FROM notification_attempts", null)
                .use { it.moveToFirst(); it.getLong(0) },
        )
        assertEquals(
            0L,
            db.rawQuery("SELECT COUNT(*) FROM reminder_history", null)
                .use { it.moveToFirst(); it.getLong(0) },
        )
        assertEquals(
            0L,
            db.rawQuery("SELECT COUNT(*) FROM reminder_schedule_evidence", null)
                .use { it.moveToFirst(); it.getLong(0) },
        )
        val snapshot = database.snapshot(accountHash, "cx:work:1:2:migrated")
        assertNotNull(snapshot)
        assertEquals("迁移测试作业", snapshot!!.title)
        val events = database.eventsForAccount(accountHash)
        assertEquals(1, events.size)
        assertEquals("迁移测试作业", events.single().title)
        assertEquals(
            1L,
            db.rawQuery(
                "SELECT COUNT(*) FROM notification_signals WHERE account_hash = ?",
                arrayOf(accountHash),
            ).use { it.moveToFirst(); it.getLong(0) },
        )
    }

    private fun assertV6HistoryPruneWorks(
        database: ReminderDatabase,
        accountHash: String,
    ) {
        var watermark = 0L
        val now = System.currentTimeMillis()
        for (i in 1..501) {
            val inserted = database.insertReminderHistory(
                accountHash = accountHash,
                sessionEpoch = 4L,
                historyGeneration = 1L,
                observationId = "mig-$accountHash-$i",
                operationSequence = i.toLong(),
                subjectKind = "assignment",
                subjectId = "cx:work:1:2:migrated",
                logicalKey = "mig-$i",
                category = "deadline",
                stage = "scheduled",
                reasonCode = null,
                observedAt = now + i,
                scheduledAt = now + 60_000L + i,
                notificationId = 1,
                batchKey = null,
                retentionCutoff = now - 30L * 24L * 60L * 60L * 1000L,
                maxRows = 500,
                currentPrunedThrough = { watermark },
                persistPrunedThrough = { watermark = it },
            )
            assertEquals(ReminderHistoryInsertResult.INSERTED, inserted)
        }
        assertEquals(1L, watermark)
        assertNotNull(database.snapshot(accountHash, "cx:work:1:2:migrated"))
        assertEquals(1, database.eventsForAccount(accountHash).size)
    }

    private fun insertAccount(
        db: SQLiteDatabase,
        accountHash: String,
        pendingVersion: Long,
        consumedVersion: Long,
        attemptedVersion: Long = 0,
        lastSignalCheckAt: Long? = null,
        claimToken: String? = null,
    ) {
        val values = ContentValues().apply {
            put("account_hash", accountHash)
            put("session_epoch", 4L)
            put("active", 1)
            put("background_enabled", 1)
            put("interval_minutes", 240)
            put("listener_enabled", 1)
            put("new_assignment_enabled", 1)
            put("show_details", 0)
            put("baseline_completed", 1)
            put("baselined_sources", "[\"courseWork\"]")
            put("known_ids", "[]")
            put("sent_new_ids", "[]")
            put("pending_update", 0)
            put("mutation_version", 9L)
            put("pending_signal_version", pendingVersion)
            put("consumed_signal_version", consumedVersion)
            put("last_signal_at", 111L)
            if (db.version >= 4) {
                put("attempted_signal_version", attemptedVersion)
                if (lastSignalCheckAt == null) {
                    putNull("last_signal_check_at")
                } else {
                    put("last_signal_check_at", lastSignalCheckAt)
                }
            }
            if (db.version >= 5) {
                if (claimToken == null) {
                    putNull("claim_token")
                } else {
                    put("claim_token", claimToken)
                }
            }
            put("migration_state", "native_active")
            put("updated_at", 222L)
        }
        db.insertOrThrow("accounts", null, values)
    }
}
