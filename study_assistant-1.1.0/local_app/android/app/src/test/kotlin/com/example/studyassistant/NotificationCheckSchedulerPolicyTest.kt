package com.example.studyassistant

import org.junit.Assert.assertEquals
import org.junit.Test

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
    fun queuedCheckIsReplacedWithLatestSignalVersion() {
        assertEquals(
            NotificationCheckAction.REPLACE,
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
}
