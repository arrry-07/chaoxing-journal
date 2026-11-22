package com.example.studyassistant

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import java.time.Instant
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

enum class NotificationEnqueueState {
    CONFIRMED,
    NOT_NEEDED,
    FAILED,
}

data class NotificationEnqueueResult(
    val state: NotificationEnqueueState,
    val reasonCode: String? = null,
) {
    val confirmed: Boolean get() = state == NotificationEnqueueState.CONFIRMED
    val notNeeded: Boolean get() = state == NotificationEnqueueState.NOT_NEEDED

    companion object {
        val confirmedResult = NotificationEnqueueResult(NotificationEnqueueState.CONFIRMED)
        val notNeededResult = NotificationEnqueueResult(NotificationEnqueueState.NOT_NEEDED)

        fun failed(reasonCode: String) =
            NotificationEnqueueResult(NotificationEnqueueState.FAILED, reasonCode)
    }
}

object BackgroundWorkScheduler {
    private const val TAG = "BackgroundWorkScheduler"
    const val REASON_DAYTIME = "daytime"
    const val REASON_NOTIFICATION = "notification_signal"

    internal const val LEGACY_DAYTIME_WORK = "daytime_assignment_check"
    internal const val LEGACY_NOTIFICATION_WORK = "notification_assignment_check"

    private const val CONFIRM_TIMEOUT_SECONDS = 5L
    internal val networkConnectedConstraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()

    fun daytimeWorkName(accountHash: String, sessionEpoch: Long): String =
        "$LEGACY_DAYTIME_WORK:$accountHash:$sessionEpoch"

    fun notificationWorkName(accountHash: String, sessionEpoch: Long): String =
        "$LEGACY_NOTIFICATION_WORK:$accountHash:$sessionEpoch"

    fun reconcileDaytime(
        context: Context,
        database: ReminderDatabase,
        targetAt: Long?,
        enabled: Boolean,
        intervalMinutes: Int,
        accountHash: String? = null,
        sessionEpoch: Long? = null,
    ) {
        val workManager = WorkManager.getInstance(context)
        val account = database.activeAccount()
        val scopeHash = accountHash ?: account?.accountHash
        val scopeEpoch = sessionEpoch ?: account?.sessionEpoch
        if (!enabled) {
            if (scopeHash != null && scopeEpoch != null) {
                workManager.cancelUniqueWork(daytimeWorkName(scopeHash, scopeEpoch))
            }
            workManager.cancelUniqueWork(LEGACY_DAYTIME_WORK)
            account?.let { database.setNextCheckAt(it.accountHash, null) }
            return
        }
        if (account == null || scopeHash == null || scopeEpoch == null) return
        if (account.accountHash != scopeHash || account.sessionEpoch != scopeEpoch) return
        val name = daytimeWorkName(scopeHash, scopeEpoch)
        val target = targetAt ?: nextWindowStart()
        val existing = liveWork(workManager, name)
        if (existing?.state == WorkInfo.State.RUNNING) return
        if (existing != null &&
            account.nextCheckAt != null &&
            kotlin.math.abs(account.nextCheckAt - target) < 30_000L
        ) {
            return
        }
        val request = daytimeRequest(target, intervalMinutes, account)
        runCatching {
            workManager.enqueueUniqueWork(name, ExistingWorkPolicy.REPLACE, request)
                .getResult()
                .get(CONFIRM_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        }.onFailure { error ->
            Log.w(TAG, "daytime_reconcile_enqueue_failed:${error.javaClass.simpleName}")
        }
        database.setNextCheckAt(account.accountHash, target)
    }

    fun scheduleDaytimeAfterRun(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        targetAt: Long,
        intervalMinutes: Int,
        expectedSessionEpoch: Long? = null,
    ) {
        val account = database.readAccount(accountHash)
        if (account == null || !account.active || !account.backgroundEnabled) return
        if (expectedSessionEpoch != null &&
            account.sessionEpoch != expectedSessionEpoch
        ) {
            database.activeAccount()?.let { current ->
                if (current.backgroundEnabled) {
                    reconcileDaytime(
                        context,
                        database,
                        current.nextCheckAt ?: nextTargetFor(current),
                        true,
                        current.intervalMinutes,
                        current.accountHash,
                        current.sessionEpoch,
                    )
                }
            }
            return
        }
        val request = daytimeRequest(targetAt, account.intervalMinutes, account)
        runCatching {
            WorkManager.getInstance(context).enqueueUniqueWork(
                daytimeWorkName(account.accountHash, account.sessionEpoch),
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request,
            ).getResult().get(CONFIRM_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        }.onFailure { error ->
            Log.w(TAG, "daytime_successor_enqueue_failed:${error.javaClass.simpleName}")
        }
        database.setNextCheckAt(accountHash, targetAt)
    }

    fun reconcileAfterSystemChange(context: Context, database: ReminderDatabase) {
        retireLegacyWork(context)
        val account = database.activeAccount() ?: return
        if (account.backgroundEnabled) {
            val target = nextTargetFor(account)
            WorkManager.getInstance(context).enqueueUniqueWork(
                daytimeWorkName(account.accountHash, account.sessionEpoch),
                ExistingWorkPolicy.REPLACE,
                daytimeRequest(target, account.intervalMinutes, account),
            )
            database.setNextCheckAt(account.accountHash, target)
        }
        reconcileNotification(context, database, account.accountHash)
    }

    fun reconcileNotification(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        expectedSessionEpoch: Long? = null,
    ) {
        val account = database.readAccount(accountHash) ?: return
        if (expectedSessionEpoch != null &&
            account.sessionEpoch != expectedSessionEpoch
        ) {
            return
        }
        if (!account.active || !account.listenerEnabled) {
            WorkManager.getInstance(context).cancelUniqueWork(
                notificationWorkName(account.accountHash, account.sessionEpoch),
            )
            WorkManager.getInstance(context).cancelUniqueWork(LEGACY_NOTIFICATION_WORK)
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
        currentWorkId: String? = null,
    ): NotificationEnqueueResult {
        val account = database.readAccount(accountHash)
            ?: return NotificationEnqueueResult.notNeededResult
        if (!account.active || !account.listenerEnabled) {
            WorkManager.getInstance(context).cancelUniqueWork(
                notificationWorkName(account.accountHash, account.sessionEpoch),
            )
            return NotificationEnqueueResult.notNeededResult
        }
        val claimable = NotificationCheckSchedulerPolicy.claimableVersion(
            account.pendingSignalVersion,
            account.consumedSignalVersion,
            account.attemptedSignalVersion,
        ) ?: return NotificationEnqueueResult.notNeededResult
        val workManager = WorkManager.getInstance(context)
        val name = notificationWorkName(account.accountHash, account.sessionEpoch)
        val request = notificationRequest(
            database,
            accountHash,
            account.sessionEpoch,
            maxOf(signalVersion, claimable),
        )
        val action = enqueueAction(
            workManager = workManager,
            name = name,
            currentWorkId = currentWorkId,
        )
        if (action == NotificationCheckAction.COALESCE) {
            return NotificationEnqueueResult.confirmedResult
        }
        val policy = when (action) {
            NotificationCheckAction.START -> ExistingWorkPolicy.KEEP
            NotificationCheckAction.KEEP -> ExistingWorkPolicy.KEEP
            NotificationCheckAction.APPEND_FOLLOW_UP ->
                ExistingWorkPolicy.APPEND_OR_REPLACE
            NotificationCheckAction.COALESCE ->
                return NotificationEnqueueResult.confirmedResult
        }
        val accepted = runCatching {
            workManager.enqueueUniqueWork(name, policy, request)
                .getResult()
                .get(CONFIRM_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            true
        }.onFailure { error ->
            Log.w(TAG, "notification_enqueue_failed:${error.javaClass.simpleName}")
        }.getOrDefault(false)
        if (!accepted) return NotificationEnqueueResult.failed("enqueueFailed")
        return if (confirmSuccessor(workManager, name, currentWorkId)) {
            NotificationEnqueueResult.confirmedResult
        } else {
            NotificationEnqueueResult.failed("confirmationNotObserved")
        }
    }

    /**
     * Confirms a delayed successor for this account/session is already queued,
     * or enqueues one without treating the currently running worker as its own
     * successor. The durable enqueue result is verified by WorkInfo, not by the
     * Operation completion alone.
     */
    @Synchronized
    fun ensureDeferredNotificationSuccessor(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        expectedSessionEpoch: Long,
        currentWorkId: String?,
        claimToPreserve: NotificationSignalClaim? = null,
    ): NotificationEnqueueResult {
        val account = database.readAccount(accountHash)
            ?: return NotificationEnqueueResult.notNeededResult
        if (!account.active ||
            !account.listenerEnabled ||
            account.sessionEpoch != expectedSessionEpoch
        ) {
            return NotificationEnqueueResult.notNeededResult
        }
        val claimable = NotificationCheckSchedulerPolicy.claimableVersion(
            account.pendingSignalVersion,
            account.consumedSignalVersion,
            account.attemptedSignalVersion,
        )
        val version = claimToPreserve?.version
            ?: claimable
            ?: return NotificationEnqueueResult.notNeededResult
        val workManager = WorkManager.getInstance(context)
        val name = notificationWorkName(account.accountHash, account.sessionEpoch)
        val existingSuccessor = liveWorkIds(workManager, name)
            .any { info ->
                info.state in liveStates &&
                    (currentWorkId == null || info.id.toString() != currentWorkId)
            }
        if (existingSuccessor) return NotificationEnqueueResult.confirmedResult
        val currentRunning = currentWorkId != null && liveWorkIds(workManager, name)
            .any { it.id.toString() == currentWorkId && it.state == WorkInfo.State.RUNNING }
        val policy = if (currentRunning) {
            ExistingWorkPolicy.APPEND_OR_REPLACE
        } else {
            ExistingWorkPolicy.KEEP
        }
        val request = notificationRequest(
            database,
            accountHash,
            account.sessionEpoch,
            maxOf(account.pendingSignalVersion, version),
        )
        val accepted = runCatching {
            workManager.enqueueUniqueWork(name, policy, request)
                .getResult()
                .get(CONFIRM_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            true
        }.onFailure { error ->
            Log.w(TAG, "notification_successor_enqueue_failed:${error.javaClass.simpleName}")
        }.getOrDefault(false)
        if (!accepted) return NotificationEnqueueResult.failed("enqueueFailed")
        return if (confirmSuccessor(workManager, name, currentWorkId)) {
            NotificationEnqueueResult.confirmedResult
        } else {
            NotificationEnqueueResult.failed("confirmationNotObserved")
        }
    }

    fun scheduleNotificationFollowUpIfNeeded(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        currentWorkId: String? = null,
    ): NotificationEnqueueResult {
        val account = database.readAccount(accountHash)
            ?: return NotificationEnqueueResult.notNeededResult
        if (!account.active ||
            !account.listenerEnabled ||
            !NotificationCheckSchedulerPolicy.shouldScheduleFollowUp(
                account.pendingSignalVersion,
                account.consumedSignalVersion,
                account.attemptedSignalVersion,
            )
        ) {
            return NotificationEnqueueResult.notNeededResult
        }
        return scheduleNotificationCheck(
            context,
            database,
            accountHash,
            account.pendingSignalVersion,
            currentWorkId = currentWorkId,
        )
    }

    fun cancelForAccountScope(
        context: Context,
        accountHash: String,
        sessionEpoch: Long,
    ) {
        val workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork(daytimeWorkName(accountHash, sessionEpoch))
        workManager.cancelUniqueWork(notificationWorkName(accountHash, sessionEpoch))
    }

    fun cancelAllForAccount(
        context: Context,
        accountHash: String,
        sessionEpoch: Long,
    ) {
        cancelForAccountScope(context, accountHash, sessionEpoch)
        retireLegacyWork(context)
    }

    fun retireLegacyWork(context: Context) {
        val workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork(LEGACY_DAYTIME_WORK)
        workManager.cancelUniqueWork(LEGACY_NOTIFICATION_WORK)
    }

    private fun notificationRequest(
        database: ReminderDatabase,
        accountHash: String,
        sessionEpoch: Long,
        signalVersion: Long,
    ): OneTimeWorkRequest {
        val now = System.currentTimeMillis()
        val cooldownAt = NotificationCheckSchedulerPolicy.cooldownAt(
            database.lastSignalCheckAt(accountHash),
        ) ?: 0L
        val delayAt = NativeReminderPolicy.notificationTargetAt(
            Instant.ofEpochMilli(now),
            Instant.ofEpochMilli(cooldownAt),
        ).toEpochMilli()
        return OneTimeWorkRequestBuilder<FlutterCheckWorker>()
            .setConstraints(networkConnectedConstraints)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                10,
                TimeUnit.MINUTES,
            )
            .setInitialDelay(
                (delayAt - now).coerceAtLeast(1_000L),
                TimeUnit.MILLISECONDS,
            )
            .addTag(notificationWorkName(accountHash, sessionEpoch))
            .setInputData(
                Data.Builder()
                    .putString(FlutterCheckWorker.KEY_REASON, REASON_NOTIFICATION)
                    .putString(FlutterCheckWorker.KEY_ACCOUNT_HASH, accountHash)
                    .putLong(FlutterCheckWorker.KEY_SESSION_EPOCH, sessionEpoch)
                    .putLong(FlutterCheckWorker.KEY_SIGNAL_VERSION, signalVersion)
                    .putLong(FlutterCheckWorker.KEY_REQUESTED_AT, System.currentTimeMillis())
                    .build(),
            )
            .build()
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
        account: ReminderAccountState,
    ) = OneTimeWorkRequestBuilder<FlutterCheckWorker>()
        .setConstraints(networkConnectedConstraints)
        .setBackoffCriteria(
            BackoffPolicy.EXPONENTIAL,
            10,
            TimeUnit.MINUTES,
        )
        .setInitialDelay(
            (targetAt - System.currentTimeMillis()).coerceAtLeast(0L),
            TimeUnit.MILLISECONDS,
        )
        .addTag(daytimeWorkName(account.accountHash, account.sessionEpoch))
        .setInputData(
            Data.Builder()
                .putString(FlutterCheckWorker.KEY_REASON, REASON_DAYTIME)
                .putString(FlutterCheckWorker.KEY_ACCOUNT_HASH, account.accountHash)
                .putLong(FlutterCheckWorker.KEY_SESSION_EPOCH, account.sessionEpoch)
                .putInt(FlutterCheckWorker.KEY_INTERVAL_MINUTES, intervalMinutes)
                .putLong(FlutterCheckWorker.KEY_REQUESTED_AT, System.currentTimeMillis())
                .build(),
        )
        .build()

    private fun liveWork(workManager: WorkManager, name: String): WorkInfo? =
        liveWorkIds(workManager, name).firstOrNull { it.state in liveStates }

    private fun liveWorkIds(
        workManager: WorkManager,
        name: String,
    ): List<WorkInfo> = runCatching {
        workManager.getWorkInfosForUniqueWork(name)
            .get(CONFIRM_TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }.onFailure { error ->
        Log.w(TAG, "live_work_query_failed:${error.javaClass.simpleName}")
    }.getOrDefault(emptyList())

    private fun enqueueAction(
        workManager: WorkManager,
        name: String,
        currentWorkId: String?,
    ): NotificationCheckAction {
        if (currentWorkId == null) {
            return NotificationCheckSchedulerPolicy.action(
                notificationWorkState(workManager, name),
            )
        }
        val all = liveWorkIds(workManager, name)
        val otherLive = all.filter {
            it.id.toString() != currentWorkId && it.state in liveStates
        }
        if (otherLive.isNotEmpty()) return NotificationCheckAction.COALESCE
        val currentRunning = all.any {
            it.id.toString() == currentWorkId && it.state == WorkInfo.State.RUNNING
        }
        return if (currentRunning) {
            NotificationCheckAction.APPEND_FOLLOW_UP
        } else {
            NotificationCheckAction.START
        }
    }

    private fun confirmSuccessor(
        workManager: WorkManager,
        name: String,
        currentWorkId: String?,
    ): Boolean = liveWorkIds(workManager, name).any { info ->
        info.state in liveStates &&
            (currentWorkId == null || info.id.toString() != currentWorkId)
    }

    private fun notificationWorkState(
        workManager: WorkManager,
        name: String,
    ): NotificationCheckWorkState {
        val states = liveWorkIds(workManager, name).map { it.state }
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

    private val liveStates = setOf(
        WorkInfo.State.ENQUEUED,
        WorkInfo.State.RUNNING,
        WorkInfo.State.BLOCKED,
    )
}
