package com.example.studyassistant

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import java.time.Instant
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

object BackgroundWorkScheduler {
    const val REASON_DAYTIME = "daytime"
    const val REASON_NOTIFICATION = "notification_signal"

    private const val DAYTIME_WORK = "daytime_assignment_check"
    internal const val NOTIFICATION_WORK = "notification_assignment_check"

    fun reconcileDaytime(
        context: Context,
        database: ReminderDatabase,
        targetAt: Long?,
        enabled: Boolean,
        intervalMinutes: Int,
    ) {
        val workManager = WorkManager.getInstance(context)
        if (!enabled) {
            workManager.cancelUniqueWork(DAYTIME_WORK)
            database.activeAccount()?.let {
                database.setNextCheckAt(it.accountHash, null)
            }
            return
        }
        val target = targetAt
            ?: nextWindowStart()
        val account = database.activeAccount() ?: return
        val existing = liveWork(workManager, DAYTIME_WORK)
        if (existing?.state == WorkInfo.State.RUNNING) {
            return
        }
        if (existing != null &&
            account.nextCheckAt != null &&
            kotlin.math.abs(account.nextCheckAt - target) < 30_000L
        ) {
            return
        }
        val request = daytimeRequest(target, intervalMinutes, account.accountHash)
        workManager.enqueueUniqueWork(DAYTIME_WORK, ExistingWorkPolicy.REPLACE, request)
        database.setNextCheckAt(account.accountHash, target)
    }

    fun scheduleDaytimeAfterRun(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        targetAt: Long,
        intervalMinutes: Int,
    ) {
        val account = database.readAccount(accountHash)
        if (account == null || !account.active || !account.backgroundEnabled) {
            return
        }
        val request = daytimeRequest(
            targetAt,
            account.intervalMinutes,
            accountHash,
        )
        WorkManager.getInstance(context).enqueueUniqueWork(
            DAYTIME_WORK,
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            request,
        )
        database.setNextCheckAt(accountHash, targetAt)
    }

    fun reconcileAfterSystemChange(context: Context, database: ReminderDatabase) {
        val account = database.activeAccount() ?: return
        if (account.backgroundEnabled) {
            val target = nextTargetFor(account)
            WorkManager.getInstance(context).enqueueUniqueWork(
                DAYTIME_WORK,
                ExistingWorkPolicy.REPLACE,
                daytimeRequest(target, account.intervalMinutes, account.accountHash),
            )
            database.setNextCheckAt(account.accountHash, target)
        }
        reconcileNotification(context, database, account.accountHash)
    }

    fun reconcileNotification(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
    ) {
        val account = database.readAccount(accountHash) ?: return
        if (!account.active || !account.listenerEnabled) {
            WorkManager.getInstance(context).cancelUniqueWork(NOTIFICATION_WORK)
            return
        }
        scheduleNotificationFollowUpIfNeeded(context, database, accountHash)
    }

    @Synchronized
    fun scheduleNotificationCheck(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        signalVersion: Long,
    ) {
        val account = database.readAccount(accountHash) ?: return
        if (!account.active || !account.listenerEnabled) return
        val workManager = WorkManager.getInstance(context)
        val state = notificationWorkState(workManager)
        val request = notificationRequest(database, accountHash, signalVersion)
        val action = NotificationCheckSchedulerPolicy.action(state)
        if (action == NotificationCheckAction.COALESCE) return
        val policy = when (action) {
            NotificationCheckAction.START -> ExistingWorkPolicy.KEEP
            NotificationCheckAction.REPLACE -> ExistingWorkPolicy.REPLACE
            NotificationCheckAction.APPEND_FOLLOW_UP ->
                ExistingWorkPolicy.APPEND_OR_REPLACE
            NotificationCheckAction.COALESCE -> return
        }
        runCatching {
            workManager.enqueueUniqueWork(NOTIFICATION_WORK, policy, request)
                .getResult()
                .get(5, TimeUnit.SECONDS)
        }
        // The persisted signal remains pending and will be picked up by the
        // normal daytime check if WorkManager cannot accept this request.
    }

    fun scheduleNotificationFollowUpIfNeeded(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
    ) {
        val account = database.readAccount(accountHash) ?: return
        if (!account.active ||
            !account.listenerEnabled ||
            !NotificationCheckSchedulerPolicy.shouldScheduleFollowUp(
                account.pendingSignalVersion,
                account.consumedSignalVersion,
            )
        ) {
            return
        }
        scheduleNotificationCheck(
            context,
            database,
            accountHash,
            account.pendingSignalVersion,
        )
    }

    private fun notificationRequest(
        database: ReminderDatabase,
        accountHash: String,
        signalVersion: Long,
    ): OneTimeWorkRequest {
        val now = System.currentTimeMillis()
        val cooldownAt = (database.lastSignalAt(accountHash) ?: 0L) + 10 * 60_000L
        val delayAt = NativeReminderPolicy.notificationTargetAt(
            Instant.ofEpochMilli(now),
            Instant.ofEpochMilli(cooldownAt),
        ).toEpochMilli()
        return OneTimeWorkRequestBuilder<FlutterCheckWorker>()
            .setInitialDelay(
                (delayAt - now).coerceAtLeast(1_000L),
                TimeUnit.MILLISECONDS,
            )
            .setInputData(
                Data.Builder()
                    .putString(FlutterCheckWorker.KEY_REASON, REASON_NOTIFICATION)
                    .putString(FlutterCheckWorker.KEY_ACCOUNT_HASH, accountHash)
                    .putLong(FlutterCheckWorker.KEY_SIGNAL_VERSION, signalVersion)
                    .putLong(FlutterCheckWorker.KEY_REQUESTED_AT, System.currentTimeMillis())
                    .build(),
            )
            .build()
    }

    fun cancelAllForAccount(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(DAYTIME_WORK)
        WorkManager.getInstance(context).cancelUniqueWork(NOTIFICATION_WORK)
    }

    fun nextWindowStart(now: ZonedDateTime = ZonedDateTime.now()): Long {
        val today = now.toLocalDate().atStartOfDay(now.zone).plusHours(8)
        return (if (now.isBefore(today)) today else today.plusDays(1))
            .toInstant()
            .toEpochMilli()
    }

    private fun nextTargetFor(account: ReminderAccountState): Long {
        val now = ZonedDateTime.now()
        if (now.hour < 8) return nextWindowStart(now)
        val last = account.lastAttemptAt
            ?.let { java.time.Instant.ofEpochMilli(it).atZone(now.zone) }
        if (last == null || last.toLocalDate() != now.toLocalDate()) {
            return now.toInstant().toEpochMilli()
        }
        if (last.isAfter(now)) {
            return now.plusMinutes(account.intervalMinutes.toLong())
                .toInstant()
                .toEpochMilli()
        }
        val candidate = last.plusMinutes(account.intervalMinutes.toLong())
        if (candidate.isAfter(now)) return candidate.toInstant().toEpochMilli()
        if (!candidate.isBefore(
                now.toLocalDate().plusDays(1).atStartOfDay(now.zone),
            )
        ) {
            return now.toLocalDate().plusDays(1).atStartOfDay(now.zone)
                .plusHours(8)
                .toInstant()
                .toEpochMilli()
        }
        return now.toInstant().toEpochMilli()
    }

    private fun daytimeRequest(
        targetAt: Long,
        intervalMinutes: Int,
        accountHash: String,
    ) = OneTimeWorkRequestBuilder<FlutterCheckWorker>()
        .setInitialDelay(
            (targetAt - System.currentTimeMillis()).coerceAtLeast(0L),
            TimeUnit.MILLISECONDS,
        )
        .setInputData(
            Data.Builder()
                .putString(FlutterCheckWorker.KEY_REASON, REASON_DAYTIME)
                .putString(FlutterCheckWorker.KEY_ACCOUNT_HASH, accountHash)
                .putInt(FlutterCheckWorker.KEY_INTERVAL_MINUTES, intervalMinutes)
                .putLong(FlutterCheckWorker.KEY_REQUESTED_AT, System.currentTimeMillis())
                .build(),
        )
        .build()

    private fun liveWork(workManager: WorkManager, name: String): WorkInfo? {
        return runCatching {
            workManager.getWorkInfosForUniqueWork(name).get(5, TimeUnit.SECONDS)
                .firstOrNull {
                    it.state == WorkInfo.State.ENQUEUED ||
                        it.state == WorkInfo.State.RUNNING ||
                        it.state == WorkInfo.State.BLOCKED
                }
        }.getOrNull()
    }

    private fun notificationWorkState(workManager: WorkManager): NotificationCheckWorkState {
        val states = runCatching {
            workManager.getWorkInfosForUniqueWork(NOTIFICATION_WORK)
                .get(5, TimeUnit.SECONDS)
                .map { it.state }
        }.getOrDefault(emptyList())
        val running = states.contains(WorkInfo.State.RUNNING)
        val queued = states.any {
            it == WorkInfo.State.ENQUEUED || it == WorkInfo.State.BLOCKED
        }
        return when {
            running && queued -> NotificationCheckWorkState.RUNNING_WITH_QUEUED
            running -> NotificationCheckWorkState.RUNNING
            queued -> NotificationCheckWorkState.QUEUED
            else -> NotificationCheckWorkState.NONE
        }
    }
}
