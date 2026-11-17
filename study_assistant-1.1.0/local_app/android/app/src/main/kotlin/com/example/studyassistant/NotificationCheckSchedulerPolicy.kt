package com.example.studyassistant

import java.time.Instant
import java.time.ZoneId

internal enum class NotificationCheckWorkState {
    NONE,
    QUEUED,
    RUNNING,
    RUNNING_WITH_QUEUED,
}

internal enum class NotificationCheckAction {
    START,
    KEEP,
    APPEND_FOLLOW_UP,
    COALESCE,
}

internal object NotificationCheckSchedulerPolicy {
    fun action(state: NotificationCheckWorkState): NotificationCheckAction =
        when (state) {
            NotificationCheckWorkState.NONE -> NotificationCheckAction.START
            NotificationCheckWorkState.QUEUED -> NotificationCheckAction.KEEP
            NotificationCheckWorkState.RUNNING -> NotificationCheckAction.APPEND_FOLLOW_UP
            else -> NotificationCheckAction.COALESCE
        }

    fun shouldScheduleFollowUp(
        pendingSignalVersion: Long,
        consumedSignalVersion: Long,
        attemptedSignalVersion: Long,
    ): Boolean = claimableVersion(
        pendingSignalVersion,
        consumedSignalVersion,
        attemptedSignalVersion,
    ) != null

    fun claimableVersion(
        pendingSignalVersion: Long,
        consumedSignalVersion: Long,
        attemptedSignalVersion: Long,
    ): Long? = pendingSignalVersion.takeIf {
        it > maxOf(consumedSignalVersion, attemptedSignalVersion)
    }

    fun cooldownAt(lastSignalCheckAt: Long?): Long? =
        lastSignalCheckAt?.plus(NOTIFICATION_COOLDOWN_MILLIS)

    fun isCooldownElapsed(now: Long, lastSignalCheckAt: Long?): Boolean =
        lastSignalCheckAt == null || now >= lastSignalCheckAt + NOTIFICATION_COOLDOWN_MILLIS

    fun canClaimNow(
        now: Instant,
        lastSignalCheckAt: Long?,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Boolean =
        NativeReminderPolicy.isInDaytimeWindow(now, zone) &&
            isCooldownElapsed(now.toEpochMilli(), lastSignalCheckAt)

    private const val NOTIFICATION_COOLDOWN_MILLIS = 10 * 60_000L
}

internal object NotificationAttemptRollbackPolicy {
    const val OUTSIDE_WINDOW = "outsideWindow"

    fun shouldRollback(
        received: Boolean,
        stopped: Boolean,
        success: Boolean,
        skipped: Boolean,
        skipReason: String?,
    ): Boolean =
        received &&
            !stopped &&
            !success &&
            skipped &&
            skipReason == OUTSIDE_WINDOW
}
