package com.example.studyassistant

import android.content.Context
import android.database.DatabaseUtils
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
class ReminderDatabaseAccountTest {
    private lateinit var context: Context
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        accountHash = "instrumentation-account-${System.nanoTime()}"
        database = ReminderDatabase.openForTest(context, "$accountHash.db")
    }

    @After
    fun tearDown() {
        database.close()
        context.deleteDatabase("$accountHash.db")
    }

    @Test
    fun sameAccountReauthenticationKeepsPendingReminderEvents() {
        val first = database.ensureActiveAccount(accountHash)
        val state = database.loadPlanState(accountHash, first.sessionEpoch)
        val assignmentId = "cx:work:account:class:pending"
        val eventId = "$accountHash|$assignmentId|new"
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = first.sessionEpoch,
            baselineCompleted = true,
            knownIds = setOf(assignmentId),
            snapshots = listOf(
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = assignmentId,
                    sessionEpoch = first.sessionEpoch,
                    courseName = "合成课程",
                    title = "合成待发作业",
                    deadlineAt = null,
                    deadlineTrusted = true,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = true,
                ),
            ),
            events = listOf(
                StoredReminderEvent(
                    eventId = eventId,
                    accountHash = accountHash,
                    sessionEpoch = first.sessionEpoch,
                    type = ReminderDatabase.EVENT_NEW,
                    assignmentId = assignmentId,
                    courseName = "合成课程",
                    title = "合成待发作业",
                    notifyAt = System.currentTimeMillis(),
                    deadlineAt = null,
                    offsets = emptyList(),
                    batchId = null,
                    status = ReminderDatabase.STATUS_PENDING,
                    notificationId = ReminderDatabase.stableNotificationId(eventId),
                ),
            ),
            completedAt = System.currentTimeMillis(),
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )

        val after = database.switchAccount(accountHash, accountHash)

        assertEquals(first.sessionEpoch, after.sessionEpoch)
        assertTrue(
            database.eventsForAccount(accountHash).any {
                it.eventId == eventId &&
                    it.status == ReminderDatabase.STATUS_PENDING
            },
        )
    }

    @Test
    fun cancelledDeadlineEventIsReactivatedWhenAssignmentBecomesEligibleAgain() {
        val first = database.ensureActiveAccount(accountHash)
        val assignmentId = "cx:work:account:class:restore"
        val deadlineAt = System.currentTimeMillis() + 3_600_000L
        val notifyAt = System.currentTimeMillis() + 60_000L
        val eventId = "$accountHash|$assignmentId|deadline:$deadlineAt|60"

        fun snapshot(
            hidden: Boolean,
            courseName: String = "合成课程",
            title: String = "合成截止作业",
        ) = StoredReminderSnapshot(
            accountHash = accountHash,
            assignmentId = assignmentId,
            sessionEpoch = first.sessionEpoch,
            courseName = courseName,
            title = title,
            deadlineAt = deadlineAt,
            deadlineTrusted = true,
            deadlineReadFailed = false,
            status = "pending",
            completed = false,
            hidden = hidden,
            followed = true,
            formal = true,
        )

        fun event(
            courseName: String = "合成课程",
            title: String = "合成截止作业",
        ) = StoredReminderEvent(
            eventId = eventId,
            accountHash = accountHash,
            sessionEpoch = first.sessionEpoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = assignmentId,
            courseName = courseName,
            title = title,
            notifyAt = notifyAt,
            deadlineAt = deadlineAt,
            offsets = listOf(60),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId(eventId),
        )

        fun apply(
            hidden: Boolean,
            events: List<StoredReminderEvent>,
            courseName: String = "合成课程",
            title: String = "合成截止作业",
        ) {
            val state = database.loadPlanState(accountHash, first.sessionEpoch)
            database.applyPlan(
                accountHash = accountHash,
                sessionEpoch = first.sessionEpoch,
                baselineCompleted = true,
                knownIds = setOf(assignmentId),
                snapshots = listOf(snapshot(hidden, courseName, title)),
                events = events,
                completedAt = System.currentTimeMillis(),
                failure = null,
                syncCompleted = false,
                expectedMutationVersion = state.mutationVersion,
            )
        }

        apply(hidden = false, events = listOf(event()))
        assertTrue(
            database.pendingDeadlineEvents(accountHash).any {
                it.eventId == eventId
            },
        )

        // Hiding the assignment invalidates the pending deadline event.
        apply(hidden = true, events = emptyList())
        assertTrue(
            database.eventsForAccount(accountHash).any {
                it.eventId == eventId &&
                    it.status == ReminderDatabase.STATUS_CANCELLED
            },
        )

        // Restoring it must reactivate the same stable event id and refresh
        // the display metadata that the publisher uses.
        apply(
            hidden = false,
            events = listOf(event(courseName = "改名课程", title = "改名后的作业")),
            courseName = "改名课程",
            title = "改名后的作业",
        )
        val restored = database.eventsForAccount(accountHash).single {
            it.eventId == eventId
        }
        assertEquals(ReminderDatabase.STATUS_PENDING, restored.status)
        assertEquals("改名课程", restored.courseName)
        assertEquals("改名后的作业", restored.title)
        assertTrue(
            database.pendingDeadlineEvents(accountHash).any {
                it.eventId == eventId
            },
        )

        // A still-pending deadline also follows a rename on the next sync.
        apply(
            hidden = false,
            events = listOf(event(courseName = "再次改名", title = "再次更名作业")),
            courseName = "再次改名",
            title = "再次更名作业",
        )
        val renamed = database.eventsForAccount(accountHash).single {
            it.eventId == eventId
        }
        assertEquals("再次改名", renamed.courseName)
        assertEquals("再次更名作业", renamed.title)
    }

    @Test
    fun switchAccountIncrementsPreviousAndTargetEpochsOnce() {
        val otherAccount = "instrumentation-other-${System.nanoTime()}"
        try {
            val prevBefore = database.ensureActiveAccount(accountHash)
            val targetBefore = database.ensureActiveAccount(otherAccount)

            val switched = database.switchAccount(accountHash, otherAccount)

            val prevAfter = database.readAccount(accountHash)!!
            assertEquals(prevBefore.sessionEpoch + 1L, prevAfter.sessionEpoch)
            assertEquals(targetBefore.sessionEpoch + 1L, switched.sessionEpoch)
            assertTrue(switched.active)
            assertTrue(!prevAfter.active)
        } finally {
            runCatching { database.clearActiveAccount(otherAccount) }
        }
    }

    @Test
    fun reauthenticationKeepsTargetSnapshotsAndEventsAndPurgesInactivePlaintext() {
        val stale = seedPlaintext("stale")
        val target = seedPlaintext(accountHash)

        val refreshed = database.switchAccount(accountHash, accountHash)

        assertEquals(target.sessionEpoch, refreshed.sessionEpoch)
        assertEquals(1L, rowCount("snapshots", accountHash))
        assertEquals(1L, rowCount("events", accountHash))
        assertEquals(1L, rowCount("notification_signals", accountHash))
        assertCleared(stale.accountHash)
        assertEquals(stale.sessionEpoch, database.readAccount(stale.accountHash)!!.sessionEpoch)
    }

    @Test
    fun switchingPurgesPreviousThirdAndStaleTargetRowsWithoutRotatingThirdEpoch() {
        val stale = seedPlaintext("stale")
        val target = seedPlaintext("target")
        val previous = seedPlaintext(accountHash)

        val switched = database.switchAccount(previous.accountHash, target.accountHash)

        assertCleared(previous.accountHash)
        assertCleared(stale.accountHash)
        for (table in plaintextTables) {
            assertEquals(table, 0L, rowCount(table, target.accountHash))
        }
        assertEquals(previous.sessionEpoch + 1, database.readAccount(accountHash)!!.sessionEpoch)
        assertEquals(stale.sessionEpoch, database.readAccount(stale.accountHash)!!.sessionEpoch)
        assertEquals(target.sessionEpoch + 1, switched.sessionEpoch)
        assertEquals(target.accountHash, database.activeAccount()!!.accountHash)
    }

    @Test
    fun logoutPurgesAllAccountsAndRotatesOnlyTheLoggedOutEpoch() {
        val stale = seedPlaintext("stale")
        val active = seedPlaintext(accountHash)

        val epoch = database.clearActiveAccount(accountHash)

        assertNull(database.activeAccount())
        for (table in plaintextTables) {
            assertEquals(table, 0L, rowCount(table))
        }
        assertCleared(active.accountHash)
        assertCleared(stale.accountHash)
        assertEquals(active.sessionEpoch + 1, epoch)
        assertEquals(stale.sessionEpoch, database.readAccount(stale.accountHash)!!.sessionEpoch)
    }

    private val plaintextTables = listOf(
        "snapshots", "events", "notification_signals", "notification_attempts",
    )

    private fun rowCount(table: String, account: String? = null): Long =
        DatabaseUtils.queryNumEntries(
            database.readableDatabase,
            table,
            account?.let { "account_hash = ?" },
            account?.let { arrayOf(it) },
        )

    private fun assertCleared(account: String) {
        for (table in plaintextTables) {
            assertEquals("$account $table", 0L, rowCount(table, account))
        }
        val row = database.readAccount(account)!!
        assertFalse(row.active)
        assertFalse(row.baselineCompleted)
        assertTrue(row.baselinedSources.isEmpty())
        assertTrue(row.knownAssignmentIds.isEmpty())
        assertTrue(row.sentNewAssignmentIds.isEmpty())
        assertNull(row.lastFailure)
        assertFalse(row.pendingUpdate)
    }

    private fun seedPlaintext(account: String): ReminderAccountState {
        val active = database.ensureActiveAccount(account)
        val settings = database.updateSettings(
            account, active.sessionEpoch, backgroundEnabled = true,
            intervalMinutes = 240, listenerEnabled = true,
            newAssignmentEnabled = true, showDetails = false,
        )
        val now = System.currentTimeMillis()
        val assignment = "cx:work:1:2:fixture"
        val eventId = "$account|$assignment|new"
        database.applyPlan(
            accountHash = account,
            sessionEpoch = settings.sessionEpoch,
            baselineCompleted = true,
            knownIds = setOf(assignment),
            snapshots = listOf(StoredReminderSnapshot(
                accountHash = account,
                assignmentId = assignment,
                sessionEpoch = settings.sessionEpoch,
                courseName = "fixture course",
                title = "fixture work",
                deadlineAt = null,
                deadlineTrusted = true,
                deadlineReadFailed = false,
                status = "pending",
                completed = false,
                hidden = false,
                followed = true,
                formal = true,
            )),
            events = listOf(StoredReminderEvent(
                eventId = eventId,
                accountHash = account,
                sessionEpoch = settings.sessionEpoch,
                type = ReminderDatabase.EVENT_NEW,
                assignmentId = assignment,
                courseName = "fixture course",
                title = "fixture work",
                notifyAt = now,
                deadlineAt = null,
                offsets = emptyList(),
                batchId = null,
                status = ReminderDatabase.STATUS_PENDING,
                notificationId = ReminderDatabase.stableNotificationId(eventId),
            )),
            completedAt = now,
            failure = "fixture failure",
            syncCompleted = true,
            expectedMutationVersion = settings.mutationVersion,
        )
        database.recordSignal(account, settings.sessionEpoch, "fixture signal", now)
        assertNotNull(database.claimNotificationAttempt(account, settings.sessionEpoch))
        database.markPendingUpdate(account, settings.sessionEpoch)
        database.writableDatabase.execSQL(
            "UPDATE accounts SET sent_new_ids = ? WHERE account_hash = ?",
            arrayOf("[\"fixture-sent\"]", account),
        )
        for (table in plaintextTables) {
            assertEquals("fixture $table", 1L, rowCount(table, account))
        }
        return database.readAccount(account)!!
    }
}
