package com.example.studyassistant

internal enum class NotificationCheckWorkState {
    NONE,
    QUEUED,
    RUNNING,
    RUNNING_WITH_QUEUED,
}

internal enum class NotificationCheckAction {
    START,
    REPLACE,
    APPEND_FOLLOW_UP,
    COALESCE,
}

internal object NotificationCheckSchedulerPolicy {
    fun action(state: NotificationCheckWorkState): NotificationCheckAction =
        when (state) {
            NotificationCheckWorkState.NONE -> NotificationCheckAction.START
            NotificationCheckWorkState.QUEUED -> NotificationCheckAction.REPLACE
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

    private const val NOTIFICATION_COOLDOWN_MILLIS = 10 * 60_000L
}
