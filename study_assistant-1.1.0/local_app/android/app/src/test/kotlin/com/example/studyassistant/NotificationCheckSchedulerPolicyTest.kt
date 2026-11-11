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
            ),
        )
    }
}
