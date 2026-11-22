package com.example.studyassistant

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

@RunWith(AndroidJUnit4::class)
class ReminderDatabaseRetentionTest {
    private lateinit var context: Context
    private lateinit var database: ReminderDatabase
    private lateinit var name: String
    private lateinit var account: ReminderAccountState
    private val accountHash = "retention-account"
    private val inactiveHash = "retention-inactive"
    private val assignmentId = "cx:work:1:2:retention"
    private val day = 86_400_000L
    private val sevenDays = 7 * day
    private val thirtyDays = 30 * day

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        name = "retention-${System.nanoTime()}.db"
        database = ReminderDatabase.openForTest(context, name)
        account = database.ensureActiveAccount(accountHash)
    }

    @After
    fun tearDown() {
        database.close()
        context.deleteDatabase(name)
    }

    @Test
    fun recordSignalDropsOnlyRowsOlderThanSevenDays() {
        val now = System.currentTimeMillis()
        val cutoff = now - sevenDays
        database.updateSettings(
            accountHash, account.sessionEpoch, backgroundEnabled = true,
            intervalMinutes = 240, listenerEnabled = true,
            newAssignmentEnabled = true, showDetails = false,
        )
        seedSignal("expired", cutoff - 60_000L)
        seedSignal("boundary", cutoff + 60_000L)

        assertEquals(1L, database.recordSignal(accountHash, account.sessionEpoch, "current", now))

        val keys = database.readableDatabase.rawQuery(
            "SELECT signal_key FROM notification_signals", null,
        ).use { cursor ->
            buildSet { while (cursor.moveToNext()) add(cursor.getString(0)) }
        }
        assertEquals(setOf("boundary", "current"), keys)
    }

    @Test
    fun applyPlanPrunesTerminalEventsButKeepsPendingAndFutureDeadlines() {
        val now = System.currentTimeMillis()
        val old = now - thirtyDays - day
        val expired = now - day
        val upcoming = now + day
        seedEvent("old-cancelled", ReminderDatabase.STATUS_CANCELLED, old, expired)
        seedEvent("old-submitted", ReminderDatabase.STATUS_SUBMITTED, old, null, inactiveHash)
        seedEvent("inactive-pending", ReminderDatabase.STATUS_PENDING, old, expired, inactiveHash)
        seedEvent("old-invalid", ReminderDatabase.STATUS_INVALID, old, expired)
        seedEvent("pending", ReminderDatabase.STATUS_PENDING, old, upcoming)
        seedEvent("future-deadline", ReminderDatabase.STATUS_CANCELLED, old, upcoming)
        seedEvent("recent-terminal", ReminderDatabase.STATUS_CANCELLED, now - day, expired)

        assertEquals(2, database.eventsForAccount(inactiveHash).size)
        val pending = database.eventsForAccount(accountHash).single { it.eventId == "pending" }
        applyPlan(now, upcoming, listOf(pending))

        assertEquals(
            setOf("pending", "future-deadline", "recent-terminal"),
            database.eventsForAccount(accountHash).map { it.eventId }.toSet(),
        )
        assertEquals(
            listOf("pending"),
            database.pendingDeadlineEvents(accountHash).map { it.eventId },
        )
        assertEquals(
            listOf("inactive-pending"),
            database.eventsForAccount(inactiveHash).map { it.eventId },
        )
    }

    @Test
    fun applyPlanPrunesEvidenceOnlyWhenBothTimesAreOldAndRecoveryIsSettled() {
        val now = System.currentTimeMillis()
        val old = now - thirtyDays - day
        val recent = now - day
        seedEvidence("old-both", "scheduled", old, old)
        seedEvidence("old-no-schedule", "scheduled", old, null)
        seedEvidence("recovery", "recoveryPending", old, old)
        seedEvidence("recent-confirmation", "scheduled", recent, old)
        seedEvidence("recent-schedule", "scheduled", old, recent)

        applyPlan(now, now + day, emptyList())

        assertEquals(
            setOf("recovery", "recent-confirmation", "recent-schedule"),
            database.scheduleEvidenceForSubject(accountHash, 1, "assignment", assignmentId)
                .map { it.logicalKey }.toSet(),
        )
    }

    @Test
    fun malformedStoredValuesKeepTheirSafeFallbacks() {
        assertNull(ReminderDatabase.parseInstant("fixture-invalid-time"))
        assertNull(ReminderDatabase.parseInstant(Instant.MAX.toString()))
        assertTrue(ReminderDatabase.stringSet("fixture-invalid-json").isEmpty())
        val now = System.currentTimeMillis()
        seedEvent("invalid-offsets", ReminderDatabase.STATUS_CANCELLED, now, null)
        database.writableDatabase.execSQL(
            "UPDATE events SET offsets = ? WHERE event_id = ?",
            arrayOf("fixture-invalid-offsets", "invalid-offsets"),
        )
        assertTrue(database.eventsForAccount(accountHash).single().offsets.isEmpty())
    }

    private fun seedSignal(key: String, receivedAt: Long) {
        database.writableDatabase.execSQL(
            "INSERT INTO notification_signals " +
                "(account_hash, session_epoch, signal_key, received_at) VALUES (?, ?, ?, ?)",
            arrayOf(accountHash, account.sessionEpoch, key, receivedAt),
        )
    }

    private fun seedEvent(
        id: String,
        status: String,
        updatedAt: Long,
        deadline: Long?,
        owner: String = accountHash,
    ) {
        database.writableDatabase.execSQL(
            "INSERT INTO events (event_id, account_hash, session_epoch, type, assignment_id, " +
                "course_name, title, notify_at, deadline_at, status, notification_id, " +
                "created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            arrayOf(
                id, owner, account.sessionEpoch, ReminderDatabase.EVENT_DEADLINE,
                assignmentId, "fixture course", "fixture work", (deadline ?: updatedAt) - 60_000L,
                deadline, status, ReminderDatabase.stableNotificationId(id), updatedAt, updatedAt,
            ),
        )
    }

    private fun seedEvidence(key: String, state: String, confirmedAt: Long, scheduledAt: Long?) {
        assertTrue(database.recordReminderScheduleEvidence(ReminderScheduleEvidenceRow(
            accountHash = accountHash,
            historyGeneration = 1,
            logicalKey = key,
            sessionEpoch = account.sessionEpoch,
            operationSequence = 1,
            subjectKind = "assignment",
            subjectId = assignmentId,
            category = "deadline",
            scheduledAt = scheduledAt,
            notificationId = null,
            expectedPayload = null,
            state = state,
            confirmedAt = confirmedAt,
        )))
    }

    private fun applyPlan(now: Long, deadline: Long, events: List<StoredReminderEvent>) {
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = account.sessionEpoch,
            baselineCompleted = true,
            knownIds = setOf(assignmentId),
            snapshots = listOf(StoredReminderSnapshot(
                accountHash = accountHash,
                assignmentId = assignmentId,
                sessionEpoch = account.sessionEpoch,
                courseName = "fixture course",
                title = "fixture work",
                deadlineAt = deadline,
                deadlineTrusted = true,
                deadlineReadFailed = false,
                status = "pending",
                completed = false,
                hidden = false,
                followed = true,
                formal = true,
            )),
            events = events,
            completedAt = now,
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = account.mutationVersion,
        )
    }
}
