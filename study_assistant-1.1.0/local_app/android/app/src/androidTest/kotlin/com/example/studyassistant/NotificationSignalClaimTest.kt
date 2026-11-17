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

@RunWith(AndroidJUnit4::class)
class NotificationSignalClaimTest {
    private lateinit var context: Context
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private var epoch = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = ReminderDatabase.get(context)
        accountHash = "instrumentation-claim-${System.nanoTime()}"
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
    }

    @Test
    fun claimPersistsAttemptBeforeEngineAndBlocksTheSameVersion() {
        val version = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-one",
            System.currentTimeMillis(),
        )
        val attemptedAt = System.currentTimeMillis()

        assertEquals(
            version,
            database.claimNotificationSignal(accountHash, epoch, attemptedAt),
        )
        val state = database.readAccount(accountHash)!!
        assertEquals(version, state.attemptedSignalVersion)
        assertEquals(0L, state.consumedSignalVersion)
        assertEquals(attemptedAt, state.lastSignalCheckAt)
        assertNull(database.claimNotificationSignal(accountHash, epoch))
    }

    @Test
    fun failedAttemptLeavesSignalUnconsumedForNormalChecksButNotAnotherChain() {
        val version = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-failure",
            System.currentTimeMillis(),
        )
        assertEquals(version, database.claimNotificationSignal(accountHash, epoch))

        val state = database.readAccount(accountHash)!!
        assertEquals(version, state.pendingSignalVersion)
        assertEquals(0L, state.consumedSignalVersion)
        assertEquals(version, state.attemptedSignalVersion)
        assertNull(database.claimNotificationSignal(accountHash, epoch))
    }

    @Test
    fun newerSignalArrivingDuringRunIsClaimedByTheSingleSuccessor() {
        val first = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-first",
            System.currentTimeMillis(),
        )
        assertEquals(first, database.claimNotificationSignal(accountHash, epoch))
        val second = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-second",
            System.currentTimeMillis() + 1_000L,
        )

        assertEquals(second, database.claimNotificationSignal(accountHash, epoch))
        assertNull(database.claimNotificationSignal(accountHash, epoch))
    }

    @Test
    fun successConsumesOnlyClaimedVersionAndLeavesNewerSignalClaimable() {
        val first = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-claimed",
            System.currentTimeMillis(),
        )
        assertEquals(first, database.claimNotificationSignal(accountHash, epoch))
        val second = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-newer",
            System.currentTimeMillis() + 1_000L,
        )

        database.consumeSignal(accountHash, first, epoch)
        val state = database.readAccount(accountHash)!!
        assertEquals(first, state.consumedSignalVersion)
        assertEquals(second, state.pendingSignalVersion)
        assertEquals(second, database.claimNotificationSignal(accountHash, epoch))
    }

    @Test
    fun wrongSessionAndDisabledListenerCannotClaim() {
        val version = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-session",
            System.currentTimeMillis(),
        )
        assertNull(database.claimNotificationSignal(accountHash, epoch + 1))

        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = epoch,
            backgroundEnabled = false,
            intervalMinutes = 240,
            listenerEnabled = false,
            newAssignmentEnabled = true,
            showDetails = false,
        )
        assertNull(database.claimNotificationSignal(accountHash, epoch))
        assertEquals(version, database.readAccount(accountHash)!!.pendingSignalVersion)
    }

    @Test
    fun accountSwitchRejectsTheOldSessionBeforeClaim() {
        database.recordSignal(
            accountHash,
            epoch,
            "synthetic-switch",
            System.currentTimeMillis(),
        )
        val other = "instrumentation-claim-other-${System.nanoTime()}"
        database.ensureActiveAccount(other)
        database.switchAccount(accountHash, other)

        assertTrue(database.readAccount(accountHash)!!.sessionEpoch > epoch)
        assertNull(database.claimNotificationSignal(accountHash, epoch))
        database.clearActiveAccount(other)
    }

    @Test
    fun rollbackRestoresThePriorAttemptOnlyOnce() {
        val version = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-rollback",
            System.currentTimeMillis(),
        )
        val before = database.readAccount(accountHash)!!
        val claim = database.claimNotificationAttempt(accountHash, epoch)!!

        assertEquals(version, claim.version)
        assertTrue(database.rollbackUnstartedNotificationAttempt(claim))
        val restored = database.readAccount(accountHash)!!
        assertEquals(before.attemptedSignalVersion, restored.attemptedSignalVersion)
        assertEquals(before.lastSignalCheckAt, restored.lastSignalCheckAt)
        assertNull(restored.claimToken)
        assertTrue(!database.rollbackUnstartedNotificationAttempt(claim))
        assertEquals(version, database.claimNotificationSignal(accountHash, epoch))
    }

    @Test
    fun rollbackRejectsANewerPendingSignal() {
        database.recordSignal(
            accountHash,
            epoch,
            "synthetic-rollback-first",
            System.currentTimeMillis(),
        )
        val claim = database.claimNotificationAttempt(accountHash, epoch)!!
        val newer = database.recordSignal(
            accountHash,
            epoch,
            "synthetic-rollback-second",
            System.currentTimeMillis() + 1_000L,
        )

        assertTrue(!database.rollbackUnstartedNotificationAttempt(claim))
        val state = database.readAccount(accountHash)!!
        assertEquals(claim.version, state.attemptedSignalVersion)
        assertEquals(newer, state.pendingSignalVersion)
        assertEquals(newer, database.claimNotificationSignal(accountHash, epoch))
    }

    @Test
    fun rollbackRejectsACompletedClaim() {
        database.recordSignal(
            accountHash,
            epoch,
            "synthetic-rollback-consumed",
            System.currentTimeMillis(),
        )
        val claim = database.claimNotificationAttempt(accountHash, epoch)!!
        database.consumeSignal(accountHash, claim.version, epoch)

        assertTrue(!database.rollbackUnstartedNotificationAttempt(claim))
        assertEquals(
            claim.version,
            database.readAccount(accountHash)!!.consumedSignalVersion,
        )
    }

    @Test
    fun accountSwitchInvalidatesTheClaimToken() {
        database.recordSignal(
            accountHash,
            epoch,
            "synthetic-rollback-switch",
            System.currentTimeMillis(),
        )
        val claim = database.claimNotificationAttempt(accountHash, epoch)!!
        val other = "instrumentation-claim-rollback-other-${System.nanoTime()}"
        database.ensureActiveAccount(other)
        database.switchAccount(accountHash, other)

        assertTrue(!database.rollbackUnstartedNotificationAttempt(claim))
        assertNull(database.readAccount(accountHash)!!.claimToken)
        database.clearActiveAccount(other)
    }
}
