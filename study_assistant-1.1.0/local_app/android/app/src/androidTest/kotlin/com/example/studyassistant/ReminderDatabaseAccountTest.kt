package com.example.studyassistant

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
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
        database = ReminderDatabase.get(context)
        accountHash = "instrumentation-account-${System.nanoTime()}"
    }

    @After
    fun tearDown() {
        runCatching { database.clearActiveAccount(accountHash) }
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
                    deadlineTrusted = false,
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

        fun snapshot(hidden: Boolean) = StoredReminderSnapshot(
            accountHash = accountHash,
            assignmentId = assignmentId,
            sessionEpoch = first.sessionEpoch,
            courseName = "合成课程",
            title = "合成截止作业",
            deadlineAt = deadlineAt,
            deadlineTrusted = true,
            deadlineReadFailed = false,
            status = "pending",
            completed = false,
            hidden = hidden,
            followed = true,
            formal = true,
        )

        fun event() = StoredReminderEvent(
            eventId = eventId,
            accountHash = accountHash,
            sessionEpoch = first.sessionEpoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = assignmentId,
            courseName = "合成课程",
            title = "合成截止作业",
            notifyAt = notifyAt,
            deadlineAt = deadlineAt,
            offsets = listOf(60),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId(eventId),
        )

        fun apply(hidden: Boolean, events: List<StoredReminderEvent>) {
            val state = database.loadPlanState(accountHash, first.sessionEpoch)
            database.applyPlan(
                accountHash = accountHash,
                sessionEpoch = first.sessionEpoch,
                baselineCompleted = true,
                knownIds = setOf(assignmentId),
                snapshots = listOf(snapshot(hidden)),
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

        // Restoring it must reactivate the same stable event id.
        apply(hidden = false, events = listOf(event()))
        assertTrue(
            database.eventsForAccount(accountHash).any {
                it.eventId == eventId &&
                    it.status == ReminderDatabase.STATUS_PENDING
            },
        )
        assertTrue(
            database.pendingDeadlineEvents(accountHash).any {
                it.eventId == eventId
            },
        )
    }
}
