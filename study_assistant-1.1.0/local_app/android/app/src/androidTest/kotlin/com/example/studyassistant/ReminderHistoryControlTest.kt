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
}
