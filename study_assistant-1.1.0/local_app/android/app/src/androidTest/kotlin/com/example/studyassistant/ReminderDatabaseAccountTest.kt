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
}
