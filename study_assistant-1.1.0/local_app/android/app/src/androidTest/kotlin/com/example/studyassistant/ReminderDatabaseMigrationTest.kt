package com.example.studyassistant

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun v3ToV7PreservesAccountAndAddsClaimAndAttemptTables() {
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

        assertEquals(9, database.readableDatabase.version)
        assertEquals(3L, account.pendingSignalVersion)
        assertEquals(2L, account.consumedSignalVersion)
        assertEquals(0L, account.attemptedSignalVersion)
        assertNull(account.lastSignalCheckAt)
        assertNull(account.claimToken)
        assertMigratedBusinessDataIntact(database, "migration-v3")
        assertV6HistoryPruneWorks(database, "migration-v3")
    }

    @Test
    fun v4ToV7PreservesAttemptStateAndAddsNullableToken() {
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

        assertEquals(9, database.readableDatabase.version)
        assertEquals(8L, account.pendingSignalVersion)
        assertEquals(6L, account.consumedSignalVersion)
        assertEquals(7L, account.attemptedSignalVersion)
        assertEquals(123_456L, account.lastSignalCheckAt)
        assertNull(account.claimToken)
        assertMigratedBusinessDataIntact(database, "migration-v4")
    }

    @Test
    fun v5ToV7PreservesAllTablesAndConsumeClearsLegacyClaimToken() {
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

        assertEquals(9, database.readableDatabase.version)
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

    @Test
    fun freshDatabaseHasV7Indices() {
        val name = "fresh-v9-${System.nanoTime()}.db"
        names.add(name)
        val database = ReminderDatabase.openForTest(context, name)
        try {
            assertV7Indices(database.readableDatabase)
            assertEquals(9, database.readableDatabase.version)
        } finally {
            database.close()
        }
    }

    @Test
    fun v6ToV7AddsIndicesAndPreservesExistingRows() {
        val name = "migration-v6-${System.nanoTime()}.db"
        val account = "migration-v6"
        names.add(name)
        createDatabase(name, version = 6, includeAttemptColumns = true, includeClaimToken = true) { db ->
            seedV6Schema(db)
            insertAccount(db, account, pendingVersion = 8, consumedVersion = 6)
            seedLegacyRows(db, account)
            db.execSQL(
                "INSERT INTO reminder_schedule_evidence " +
                    "(account_hash, history_generation, logical_key, session_epoch, " +
                    "operation_sequence, subject_kind, subject_id, category, state, confirmed_at) " +
                    "VALUES (?, 1, 'v6-evidence', 4, 1, 'assignment', 'cx:work:1:2:migrated', " +
                    "'deadline', 'recoveryPending', ?)",
                arrayOf(account, System.currentTimeMillis()),
            )
        }

        val database = ReminderDatabase.openForTest(context, name)
        try {
            val db = database.readableDatabase
            assertEquals(8L, database.readAccount(account)!!.pendingSignalVersion)
            assertEquals("迁移测试作业", database.snapshot(account, "cx:work:1:2:migrated")!!.title)
            assertEquals("迁移测试作业", database.eventsForAccount(account).single().title)
            assertEquals(
                1L,
                db.rawQuery(
                    "SELECT COUNT(*) FROM notification_signals WHERE account_hash = ?",
                    arrayOf(account),
                ).use { it.moveToFirst(); it.getLong(0) },
            )
            val evidence = database.scheduleEvidenceForSubject(account, 1, "assignment", "cx:work:1:2:migrated")
            assertEquals("v6-evidence", evidence.single().logicalKey)
            assertEquals("recoveryPending", evidence.single().state)
            assertV7Indices(db)
            assertEquals(9, db.version)
        } finally {
            database.close()
        }
    }

    @Test
    fun v7ToV8AddsQuietHoursColumnsAndMarksLegacySourceUnknown() {
        val name = "migration-v7-${System.nanoTime()}.db"
        val account = "migration-v7"
        names.add(name)
        createDatabase(name, version = 7, includeAttemptColumns = true, includeClaimToken = true) { db ->
            seedV6Schema(db)
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
            insertAccount(db, account, pendingVersion = 3, consumedVersion = 2)
            seedLegacyRows(db, account)
        }

        val database = ReminderDatabase.openForTest(context, name)
        try {
            assertEquals(9, database.readableDatabase.version)
            val state = database.readAccount(account)!!
            assertFalse(state.allowUrgentNightBreakthrough)
            assertEquals(AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2, state.deadlineChannelId)
            val legacySnapshot = database.snapshot(account, "cx:work:1:2:migrated")!!
            val legacyEvent = database.eventsForAccount(account).single()
            assertEquals("unknown", legacySnapshot.deadlineSource)
            assertEquals("unknown", legacyEvent.deadlineSource)
            // Legacy v7 deadline event lacking source must not be allowed to deliver/match.
            assertFalse(legacySnapshot.matchesEvent(legacyEvent, System.currentTimeMillis()))
        } finally {
            database.close()
        }
    }

    @Test
    fun v8ToV9MigratesLegacyDeadlineChannelToV2() {
        val name = "migration-v8-${System.nanoTime()}.db"
        val legacyAccount = "migration-v8-legacy"
        val v2Account = "migration-v8-v2"
        names.add(name)
        createDatabase(name, version = 8, includeAttemptColumns = true, includeClaimToken = true) { db ->
            seedV6Schema(db)
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
            insertAccount(db, legacyAccount, pendingVersion = 5, consumedVersion = 4)
            db.execSQL(
                "UPDATE accounts SET allow_urgent_night_breakthrough = 1, " +
                    "deadline_channel_id = ? WHERE account_hash = ?",
                arrayOf(AssignmentNotificationPublisher.CHANNEL_DEADLINES, legacyAccount),
            )
            insertAccount(db, v2Account, pendingVersion = 2, consumedVersion = 2)
            db.execSQL(
                "UPDATE accounts SET deadline_channel_id = ? WHERE account_hash = ?",
                arrayOf(AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2, v2Account),
            )
            seedLegacyRows(db, legacyAccount)
            db.execSQL(
                "UPDATE snapshots SET deadline_source = 'courseWork' WHERE account_hash = ?",
                arrayOf(legacyAccount),
            )
            db.execSQL(
                "UPDATE events SET deadline_source = 'courseWork' WHERE account_hash = ?",
                arrayOf(legacyAccount),
            )
        }

        val database = ReminderDatabase.openForTest(context, name)
        try {
            assertEquals(9, database.readableDatabase.version)
            val legacyState = database.readAccount(legacyAccount)!!
            assertTrue(legacyState.allowUrgentNightBreakthrough)
            assertEquals(
                AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
                legacyState.deadlineChannelId,
            )
            assertEquals(5L, legacyState.pendingSignalVersion)
            assertEquals(4L, legacyState.consumedSignalVersion)
            assertEquals("courseWork", database.snapshot(legacyAccount, "cx:work:1:2:migrated")!!.deadlineSource)
            assertEquals("courseWork", database.eventsForAccount(legacyAccount).single().deadlineSource)

            val v2State = database.readAccount(v2Account)!!
            assertEquals(
                AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
                v2State.deadlineChannelId,
            )
        } finally {
            database.close()
        }
    }

    private fun seedV6Schema(db: SQLiteDatabase) {
        db.execSQL("CREATE INDEX events_account_status ON events(account_hash, status, notify_at)")
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

    private val v7Indices = mapOf(
        "events_notification_id" to listOf("notification_id"),
        "events_account_assignment" to listOf("account_hash", "assignment_id", "updated_at"),
        "notification_signals_received_at" to listOf("account_hash", "received_at"),
        "reminder_schedule_evidence_subject" to listOf(
            "account_hash", "history_generation", "subject_kind", "subject_id", "confirmed_at",
        ),
    )

    private fun assertV7Indices(db: SQLiteDatabase) {
        for ((index, columns) in v7Indices) {
            val actual = db.rawQuery("PRAGMA index_info($index)", null).use { cursor ->
                val name = cursor.getColumnIndexOrThrow("name")
                buildList {
                    while (cursor.moveToNext()) add(cursor.getString(name))
                }
            }
            assertEquals(index, columns, actual)
        }
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
