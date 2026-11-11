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
}
