package com.example.studyassistant

import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReminderClickRoutingTest {
    private lateinit var context: Context
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private val assignmentId = "cx:work:routing:class:assignment"

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = ReminderDatabase.get(context)
        accountHash = "instrumentation-routing-${System.nanoTime()}"
        val epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        val state = database.loadPlanState(accountHash, epoch)
        val now = System.currentTimeMillis()
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(assignmentId),
            snapshots = listOf(
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = assignmentId,
                    sessionEpoch = epoch,
                    courseName = "合成课程",
                    title = "合成作业",
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
            events = emptyList(),
            completedAt = now,
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )
    }

    @After
    fun tearDown() {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .remove("flutter.notification_click_missing_v1")
            .commit()
        runCatching { database.clearActiveAccount(accountHash) }
    }

    @Test
    fun validAssignmentOpensItsDetailRoute() {
        val decision = ReminderClickRouter.resolve(
            context,
            accountHash,
            assignmentId,
        )

        assertFalse(decision.missing)
        assertEquals(
            "studyassistant://assignments/${Uri.encode(assignmentId)}",
            decision.location,
        )
    }

    @Test
    fun missingAssignmentFallsBackToTheList() {
        val decision = ReminderClickRouter.resolve(
            context,
            accountHash,
            "cx:work:routing:class:missing",
        )

        assertTrue(decision.missing)
        assertEquals("studyassistant://assignments", decision.location)
        assertEquals(
            ReminderClickRouter.MISSING_MESSAGE,
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.notification_click_missing_v1", null),
        )
    }

    @Test
    fun differentAccountFallsBackToTheList() {
        val decision = ReminderClickRouter.resolve(
            context,
            "instrumentation-routing-other-account",
            assignmentId,
        )

        assertTrue(decision.missing)
        assertEquals("studyassistant://assignments", decision.location)
    }

    @Test
    fun summaryNotificationWithoutAssignmentOpensTheListWithoutWarning() {
        val decision = ReminderClickRouter.resolve(
            context,
            accountHash,
            null,
        )

        assertFalse(decision.missing)
        assertEquals("studyassistant://assignments", decision.location)
    }
}
