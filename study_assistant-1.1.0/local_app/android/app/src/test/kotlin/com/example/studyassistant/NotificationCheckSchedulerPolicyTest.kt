package com.example.studyassistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class NotificationCheckSchedulerPolicyTest {
    @Test
    fun noLiveCheckStartsOne() {
        assertEquals(
            NotificationCheckAction.START,
            NotificationCheckSchedulerPolicy.action(
                NotificationCheckWorkState.NONE,
            ),
        )
    }

    @Test
    fun queuedCheckIsKeptSoTheLatestVersionIsClaimedWhenItRuns() {
        assertEquals(
            NotificationCheckAction.KEEP,
            NotificationCheckSchedulerPolicy.action(
                NotificationCheckWorkState.QUEUED,
            ),
        )
    }

    @Test
    fun runningCheckWithoutQueuedSuccessorAppendsFollowUp() {
        assertEquals(
            NotificationCheckAction.APPEND_FOLLOW_UP,
            NotificationCheckSchedulerPolicy.action(
                NotificationCheckWorkState.RUNNING,
            ),
        )
    }

    @Test
    fun runningCheckWithQueuedSuccessorCoalescesSignals() {
        assertEquals(
            NotificationCheckAction.COALESCE,
            NotificationCheckSchedulerPolicy.action(
                NotificationCheckWorkState.RUNNING_WITH_QUEUED,
            ),
        )
    }

    @Test
    fun laterPendingSignalSchedulesOneFollowUp() {
        assertEquals(
            true,
            NotificationCheckSchedulerPolicy.shouldScheduleFollowUp(
                pendingSignalVersion = 7,
                consumedSignalVersion = 5,
                attemptedSignalVersion = 6,
            ),
        )
    }

    @Test
    fun consumedLatestSignalDoesNotScheduleAnotherCheck() {
        assertEquals(
            false,
            NotificationCheckSchedulerPolicy.shouldScheduleFollowUp(
                pendingSignalVersion = 7,
                consumedSignalVersion = 7,
                attemptedSignalVersion = 7,
            ),
        )
    }

    @Test
    fun attemptedButUnconsumedSignalDoesNotScheduleAnotherCheck() {
        assertEquals(
            false,
            NotificationCheckSchedulerPolicy.shouldScheduleFollowUp(
                pendingSignalVersion = 7,
                consumedSignalVersion = 5,
                attemptedSignalVersion = 7,
            ),
        )
        assertEquals(
            null,
            NotificationCheckSchedulerPolicy.claimableVersion(
                pendingSignalVersion = 7,
                consumedSignalVersion = 5,
                attemptedSignalVersion = 7,
            ),
        )
    }

    @Test
    fun signalArrivingDuringAttemptGetsExactlyOneLatestFollowUp() {
        assertEquals(
            9L,
            NotificationCheckSchedulerPolicy.claimableVersion(
                pendingSignalVersion = 9,
                consumedSignalVersion = 5,
                attemptedSignalVersion = 7,
            ),
        )
    }

    @Test
    fun cooldownUsesActualCheckAttempt() {
        assertEquals(
            600_000L,
            NotificationCheckSchedulerPolicy.cooldownAt(0L),
        )
        assertEquals(
            null,
            NotificationCheckSchedulerPolicy.cooldownAt(null),
        )
    }

    @Test
    fun cooldownMustElapseBeforeAnotherAttempt() {
        assertFalse(
            NotificationCheckSchedulerPolicy.isCooldownElapsed(
                now = 599_999L,
                lastSignalCheckAt = 0L,
            ),
        )
        assertTrue(
            NotificationCheckSchedulerPolicy.isCooldownElapsed(
                now = 600_000L,
                lastSignalCheckAt = 0L,
            ),
        )
        assertTrue(
            NotificationCheckSchedulerPolicy.isCooldownElapsed(
                now = 0L,
                lastSignalCheckAt = null,
            ),
        )
    }

    @Test
    fun claimRequiresBothDaytimeWindowAndCooldown() {
        val zone = ZoneId.of("Asia/Shanghai")
        assertFalse(
            NotificationCheckSchedulerPolicy.canClaimNow(
                Instant.parse("2026-11-17T23:59:00Z"),
                null,
                zone,
            ),
        )
        assertTrue(
            NotificationCheckSchedulerPolicy.canClaimNow(
                Instant.parse("2026-11-18T00:00:00Z"),
                null,
                zone,
            ),
        )
        assertFalse(
            NotificationCheckSchedulerPolicy.canClaimNow(
                Instant.parse("2026-11-17T16:30:00Z"),
                null,
                zone,
            ),
        )
        val now = Instant.parse("2026-11-18T01:00:00Z")
        assertFalse(
            NotificationCheckSchedulerPolicy.canClaimNow(
                now,
                now.toEpochMilli() - 5 * 60_000L,
                zone,
            ),
        )
        assertTrue(
            NotificationCheckSchedulerPolicy.canClaimNow(
                Instant.parse("2026-11-18T03:00:00Z"),
                1_000L,
                zone,
            ),
        )
    }

    @Test
    fun onlyTimelyUniqueOutsideWindowResultCanRollback() {
        assertTrue(
            NotificationAttemptRollbackPolicy.shouldRollback(
                received = true,
                stopped = false,
                success = false,
                skipped = true,
                skipReason = NotificationAttemptRollbackPolicy.OUTSIDE_WINDOW,
            ),
        )
        assertFalse(
            NotificationAttemptRollbackPolicy.shouldRollback(
                received = false,
                stopped = false,
                success = false,
                skipped = true,
                skipReason = NotificationAttemptRollbackPolicy.OUTSIDE_WINDOW,
            ),
        )
        assertFalse(
            NotificationAttemptRollbackPolicy.shouldRollback(
                received = true,
                stopped = true,
                success = false,
                skipped = true,
                skipReason = NotificationAttemptRollbackPolicy.OUTSIDE_WINDOW,
            ),
        )
        assertFalse(
            NotificationAttemptRollbackPolicy.shouldRollback(
                received = true,
                stopped = false,
                success = true,
                skipped = true,
                skipReason = NotificationAttemptRollbackPolicy.OUTSIDE_WINDOW,
            ),
        )
        assertFalse(
            NotificationAttemptRollbackPolicy.shouldRollback(
                received = true,
                stopped = false,
                success = false,
                skipped = false,
                skipReason = NotificationAttemptRollbackPolicy.OUTSIDE_WINDOW,
            ),
        )
        assertFalse(
            NotificationAttemptRollbackPolicy.shouldRollback(
                received = true,
                stopped = false,
                success = false,
                skipped = true,
                skipReason = "network",
            ),
        )
    }
}
