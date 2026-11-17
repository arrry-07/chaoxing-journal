package com.example.studyassistant

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
        }

        val database = ReminderDatabase.openForTest(context, name)
        val account = database.readAccount("migration-v3")!!

        assertEquals(6, database.readableDatabase.version)
        assertEquals(3L, account.pendingSignalVersion)
        assertEquals(2L, account.consumedSignalVersion)
        assertEquals(0L, account.attemptedSignalVersion)
        assertNull(account.lastSignalCheckAt)
        assertNull(account.claimToken)
        assertEquals(
            0L,
            database.readableDatabase.rawQuery(
                "SELECT COUNT(*) FROM notification_attempts",
                null,
            ).use { it.moveToFirst(); it.getLong(0) },
        )
        assertEquals(
            0L,
            database.readableDatabase.rawQuery(
                "SELECT COUNT(*) FROM reminder_history",
                null,
            ).use { it.moveToFirst(); it.getLong(0) },
        )
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
        }

        val database = ReminderDatabase.openForTest(context, name)
        val account = database.readAccount("migration-v4")!!

        assertEquals(6, database.readableDatabase.version)
        assertEquals(8L, account.pendingSignalVersion)
        assertEquals(6L, account.consumedSignalVersion)
        assertEquals(7L, account.attemptedSignalVersion)
        assertEquals(123_456L, account.lastSignalCheckAt)
        assertNull(account.claimToken)
    }

    private fun createDatabase(
        name: String,
        version: Int,
        includeAttemptColumns: Boolean,
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
            db.version = version
            seed(db)
        } finally {
            db.close()
        }
    }

    private fun insertAccount(
        db: SQLiteDatabase,
        accountHash: String,
        pendingVersion: Long,
        consumedVersion: Long,
        attemptedVersion: Long = 0,
        lastSignalCheckAt: Long? = null,
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
            put("migration_state", "native_active")
            put("updated_at", 222L)
        }
        db.insertOrThrow("accounts", null, values)
    }
}
