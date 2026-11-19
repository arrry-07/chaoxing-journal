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
import java.time.ZoneId

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

        assertTrue(database.rollbackUnstartedNotificationAttempt(claim))
        val state = database.readAccount(accountHash)!!
        assertEquals(claim.priorAttemptedVersion, state.attemptedSignalVersion)
        assertEquals(newer, state.pendingSignalVersion)
        assertEquals(newer, database.claimNotificationSignal(accountHash, epoch))
    }

    @Test
    fun releaseKeepsPartiallyAdvancedConsumptionAndNewerPending() {
        repeat(7) { index ->
            database.recordSignal(
                accountHash,
                epoch,
                "synthetic-partial-$index",
                System.currentTimeMillis() + index,
            )
        }
        database.consumeSignal(accountHash, 5, epoch)
        val claim = database.claimNotificationAttempt(accountHash, epoch)!!
        assertEquals(7L, claim.version)
        assertEquals(5L, claim.priorConsumedVersion)

        database.consumeSignal(accountHash, 6, epoch)
        assertTrue(database.releaseNotificationAttempt(claim))
        val state = database.readAccount(accountHash)!!
        assertEquals(6L, state.consumedSignalVersion)
        assertEquals(7L, state.pendingSignalVersion)
        assertNull(state.claimToken)
        assertEquals(7L, database.claimNotificationSignal(accountHash, epoch))
    }

    @Test
    fun sameWorkSpecResumesClaimAndAuthorizesOnlyInsideWindow() {
        database.recordSignal(
            accountHash,
            epoch,
            "synthetic-owner",
            System.currentTimeMillis(),
        )
        val first = database.claimNotificationAttempt(
            accountHash,
            epoch,
            ownerWorkId = "work-1",
        )!!
        val resumed = database.claimNotificationAttempt(
            accountHash,
            epoch,
            ownerWorkId = "work-1",
        )!!
        assertEquals(first.token, resumed.token)
        assertEquals(first.claimedAt, resumed.claimedAt)

        val granted = database.authorizeNotificationRemoteStart(
            accountHash,
            epoch,
            first.token,
            "work-1",
            now = Instant.parse("2026-11-18T10:00:00Z"),
            zone = ZoneId.of("UTC"),
        )
        assertEquals(NotificationRemoteAuthorization.GRANTED, granted)
        assertEquals(
            NotificationRemoteAuthorization.GRANTED,
            database.authorizeNotificationRemoteStart(
                accountHash,
                epoch,
                first.token,
                "work-1",
                now = Instant.parse("2026-11-18T11:00:00Z"),
                zone = ZoneId.of("UTC"),
            ),
        )
        assertTrue(
            database.settleNotificationAttempt(
                accountHash,
                epoch,
                first.token,
                ownerWorkId = "work-1",
            ),
        )
        assertEquals(
            NotificationRemoteAuthorization.STALE,
            database.authorizeNotificationRemoteStart(
                accountHash,
                epoch,
                first.token,
                "work-1",
                now = Instant.parse("2026-11-18T12:00:00Z"),
                zone = ZoneId.of("UTC"),
            ),
        )
    }

    @Test
    fun authorizationOutsideWindowDefersAndReleases() {
        database.recordSignal(
            accountHash,
            epoch,
            "synthetic-night",
            System.currentTimeMillis(),
        )
        val claim = database.claimNotificationAttempt(
            accountHash,
            epoch,
            ownerWorkId = "work-night",
        )!!
        assertEquals(
            NotificationRemoteAuthorization.OUTSIDE_WINDOW,
            database.authorizeNotificationRemoteStart(
                accountHash,
                epoch,
                claim.token,
                "work-night",
                now = Instant.parse("2026-11-18T00:30:00Z"),
                zone = ZoneId.of("UTC"),
            ),
        )
        assertTrue(database.releaseNotificationAttempt(claim))
        assertEquals(claim.version, database.claimNotificationSignal(accountHash, epoch))
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
