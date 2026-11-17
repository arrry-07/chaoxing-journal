package com.example.studyassistant

import android.content.Context
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
class ReminderHistoryControlTest {
    private lateinit var context: Context
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private var epoch = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences(
            ReminderHistoryStore.PREFS,
            Context.MODE_PRIVATE,
        ).edit().clear().commit()
        database = ReminderDatabase.get(context)
        accountHash = "history-control-${System.nanoTime()}"
        epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = epoch,
            backgroundEnabled = false,
            intervalMinutes = 240,
            listenerEnabled = true,
            newAssignmentEnabled = true,
            showDetails = false,
        )
    }

    @After
    fun tearDown() {
        runCatching { database.clearActiveAccount(accountHash) }
        context.getSharedPreferences(
            ReminderHistoryStore.PREFS,
            Context.MODE_PRIVATE,
        ).edit().clear().commit()
    }

    @Test
    fun firstInstallIsReadOnlyDisabledAndGenerationOne() {
        val control = ReminderHistoryStore.controlSnapshot(
            context,
            accountHash,
            epoch,
        )
        assertEquals(1L, control.historyGeneration)
        assertFalse(control.recordingEnabled)
        assertFalse(control.ownerMatches)
        assertFalse(control.purgePending)
        assertNull(control.purgeToken)
    }

    @Test
    fun logoutPausesOldGenerationAndFinishClearsHistoryIdempotently() {
        val enabled = ReminderHistoryStore.enableSession(
            context,
            database,
            accountHash,
            epoch,
            1,
        )
        assertEquals(1L, enabled["historyGeneration"])
        val first = ReminderHistoryStore.acquireObservationContext(
            context,
            database,
            accountHash,
            epoch,
        )
        val second = ReminderHistoryStore.acquireObservationContext(
            context,
            database,
            accountHash,
            epoch,
        )
        assertEquals(first.operationSequence + 1, second.operationSequence)
        assertEquals(
            "inserted",
            ReminderHistoryStore.appendObservation(
                context,
                database,
                first,
                ReminderHistoryObservationInput(
                    observationId = "control-observation",
                    ordinal = 0,
                    subjectKind = "assignment",
                    subjectId = "cx:work:1:2:3",
                    logicalKey = "control-event",
                    category = "deadline",
                    stage = "scheduled",
                    reasonCode = null,
                    observedAt = System.currentTimeMillis(),
                    scheduledAt = System.currentTimeMillis() + 60_000,
                    notificationId = 1,
                    batchKey = null,
                ),
            ),
        )

        val started = ReminderHistoryStore.beginLogout(
            context,
            1,
            "logout-request",
        )
        assertEquals("pending", started["state"])
        assertEquals(2L, started["historyGeneration"])
        val token = started["purgeToken"] as String
        assertNotNull(token)
        assertEquals(
            "pending",
            ReminderHistoryStore.beginLogout(
                context,
                1,
                "logout-request",
            )["state"],
        )
        val stale = runCatching {
            ReminderHistoryStore.acquireObservationContext(
                context,
                database,
                accountHash,
                epoch,
            )
        }.exceptionOrNull() as ReminderHistoryException
        assertEquals("history_unavailable", stale.code)

        val finished = ReminderHistoryStore.finishLogout(
            context,
            database,
            token,
        )
        assertEquals(true, finished["cleared"])
        assertEquals(2L, finished["historyGeneration"])
        assertEquals(
            true,
            ReminderHistoryStore.finishLogout(
                context,
                database,
                token,
            )["cleared"],
        )
        val afterLogout = runCatching {
            ReminderHistoryStore.appendObservation(
                context,
                database,
                second,
                ReminderHistoryObservationInput(
                    observationId = "after-logout",
                    ordinal = 0,
                    subjectKind = "assignment",
                    subjectId = "cx:work:1:2:3",
                    logicalKey = "after-logout",
                    category = "deadline",
                    stage = "scheduled",
                    reasonCode = null,
                    observedAt = System.currentTimeMillis(),
                    scheduledAt = null,
                    notificationId = null,
                    batchKey = null,
                ),
            )
        }.exceptionOrNull() as ReminderHistoryException
        assertEquals("history_unavailable", afterLogout.code)
    }

    @Test
    fun staleLogoutGenerationIsRejected() {
        val error = runCatching {
            ReminderHistoryStore.beginLogout(
                context,
                99,
                "old-request",
            )
        }.exceptionOrNull() as ReminderHistoryException
        assertEquals("stale_history_generation", error.code)
        assertTrue(
            ReminderHistoryStore.controlSnapshot(
                context,
                accountHash,
                epoch,
            ).historyGeneration == 1L,
        )
    }

    @Test
    fun finishLogoutClearsPrunedWatermarksInPrefs() {
        ReminderHistoryStore.enableSession(context, database, accountHash, epoch, 1)
        val obsContext = ReminderHistoryStore.acquireObservationContext(
            context,
            database,
            accountHash,
            epoch,
        )
        val now = System.currentTimeMillis()
        for (index in 1..501) {
            ReminderHistoryStore.appendObservation(
                context,
                database,
                obsContext,
                ReminderHistoryObservationInput(
                    observationId = "logout-prune-$index",
                    ordinal = index,
                    subjectKind = "assignment",
                    subjectId = "cx:work:1:2:3",
                    logicalKey = "logout-prune-$index",
                    category = "deadline",
                    stage = "scheduled",
                    reasonCode = null,
                    observedAt = now + index,
                    scheduledAt = now + 60_000L + index,
                    notificationId = 1,
                    batchKey = null,
                ),
            )
        }
        val prefs = context.getSharedPreferences(
            ReminderHistoryStore.PREFS,
            Context.MODE_PRIVATE,
        )
        assertTrue(prefs.all.keys.any { it.startsWith("pruned_through_") })

        val started = ReminderHistoryStore.beginLogout(context, 1, "logout-prune-req")
        val token = started["purgeToken"] as String
        ReminderHistoryStore.finishLogout(context, database, token)

        assertTrue(prefs.all.keys.none { it.startsWith("pruned_through_") })
    }

    @Test
    fun inspectSubjectsIncludesAlarmScheduledAndUsesUpdatedAtAsEvidenceTime() {
        ReminderHistoryStore.enableSession(context, database, accountHash, epoch, 1)
        val obsContext = ReminderHistoryStore.acquireObservationContext(
            context,
            database,
            accountHash,
            epoch,
        )
        val state = database.loadPlanState(accountHash, epoch)
        val assignmentId = "cx:work:inspect:subject:1"
        val now = System.currentTimeMillis()
        val deadlineAt = now + 3_600_000L
        val notifyAt = now + 1_800_000L
        val eventId = "$accountHash|$assignmentId|deadline:$deadlineAt|30"
        val event = StoredReminderEvent(
            eventId = eventId,
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = assignmentId,
            courseName = "探测课程",
            title = "探测作业",
            notifyAt = notifyAt,
            deadlineAt = deadlineAt,
            offsets = listOf(30),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId(eventId),
        )
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
                    courseName = "探测课程",
                    title = "探测作业",
                    deadlineAt = deadlineAt,
                    deadlineTrusted = true,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = true,
                    inAssignmentScope = true,
                ),
            ),
            events = listOf(event),
            completedAt = now,
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )
        AssignmentAlarmScheduler.scheduleDeadline(context, event)
        try {
            @Suppress("UNCHECKED_CAST")
            val inspected = ReminderHistoryStore.inspectSubjects(
                context,
                database,
                obsContext,
                listOf("assignment" to assignmentId),
            )["nativeEvents"] as List<Map<String, Any?>>
            val row = inspected.single()
            assertEquals(true, row["alarmScheduled"])
            val evidenceAt = row["evidenceAt"] as Long
            assertTrue(evidenceAt != notifyAt)
            assertTrue(evidenceAt >= now - 5_000L && evidenceAt <= System.currentTimeMillis() + 5_000L)

            AssignmentAlarmScheduler.cancelDeadline(context, event)
            @Suppress("UNCHECKED_CAST")
            val afterCancel = ReminderHistoryStore.inspectSubjects(
                context,
                database,
                obsContext,
                listOf("assignment" to assignmentId),
            )["nativeEvents"] as List<Map<String, Any?>>
            assertEquals(false, afterCancel.single()["alarmScheduled"])
        } finally {
            AssignmentAlarmScheduler.cancelDeadline(context, event)
        }
    }

    @Test
    fun finishLogoutClearsPurgeRequestId() {
        val generation = ReminderHistoryStore.enableSession(
            context,
            database,
            accountHash,
            epoch,
            1L,
        )["historyGeneration"] as Long
        val begin = ReminderHistoryStore.beginLogout(context, generation, "req-clear-id")
        val token = begin["purgeToken"] as String
        assertEquals("req-clear-id", ReminderHistoryStore.controlSnapshot(context, accountHash, epoch).purgeRequestId)

        ReminderHistoryStore.finishLogout(context, database, token)

        val after = ReminderHistoryStore.controlSnapshot(context, accountHash, epoch)
        assertFalse(after.purgePending)
        assertNull(after.purgeToken)
        assertNull(after.purgeRequestId)
    }
}
