package com.example.studyassistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class FlutterCheckWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val owner = "worker:${UUID.randomUUID()}"
    private val engineRef = AtomicReference<FlutterEngine?>(null)
    @Volatile private var channel: MethodChannel? = null
    @Volatile private var activeLatch: CountDownLatch? = null
    @Volatile private var stopped = false
    @Volatile private var activeClaim: NotificationSignalClaim? = null

    override fun doWork(): Result {
        val reason = inputData.getString(KEY_REASON) ?: return Result.success()
        val accountHash = inputData.getString(KEY_ACCOUNT_HASH) ?: return Result.success()
        val requestedAt = inputData.getLong(KEY_REQUESTED_AT, System.currentTimeMillis())
        val intervalMinutes = inputData.getInt(KEY_INTERVAL_MINUTES, 240)
        val expectedSessionEpoch = inputData.getLong(KEY_SESSION_EPOCH, -1L)
        val database = ReminderDatabase.get(applicationContext)
        val account = database.readAccount(accountHash)
        if (account == null ||
            !account.active ||
            expectedSessionEpoch <= 0L ||
            account.sessionEpoch != expectedSessionEpoch ||
            (reason == BackgroundWorkScheduler.REASON_DAYTIME && !account.backgroundEnabled) ||
            (reason == BackgroundWorkScheduler.REASON_NOTIFICATION && !account.listenerEnabled)
        ) {
            if (reason == BackgroundWorkScheduler.REASON_DAYTIME) {
                BackgroundWorkScheduler.reconcileAfterSystemChange(
                    applicationContext,
                    database,
                )
            }
            return Result.success()
        }

        var signalVersion = inputData.getLong(KEY_SIGNAL_VERSION, 0L)
        var claim: NotificationSignalClaim? = null
        if (reason == BackgroundWorkScheduler.REASON_NOTIFICATION) {
            val now = Instant.now()
            if (!NotificationCheckSchedulerPolicy.canClaimNow(
                    now,
                    database.lastSignalCheckAt(accountHash),
                    ZoneId.systemDefault(),
                )
            ) {
                val existing = database.notificationAttempt(accountHash)
                    ?.takeIf {
                        it.ownerWorkId == id.toString() &&
                            it.sessionEpoch == expectedSessionEpoch
                    }
                val queued = BackgroundWorkScheduler.ensureDeferredNotificationSuccessor(
                    applicationContext,
                    database,
                    accountHash,
                    expectedSessionEpoch,
                    currentWorkId = id.toString(),
                    claimToPreserve = existing?.toClaim(account.pendingSignalVersion),
                )
                if (existing != null && queued.confirmed) {
                    database.releaseNotificationAttempt(
                        existing.toClaim(account.pendingSignalVersion),
                    )
                }
                if (!queued.confirmed && !queued.notNeeded) {
                    Log.w(
                        TAG,
                        "deferred_notification_successor_not_confirmed:${queued.reasonCode}",
                    )
                    return Result.retry()
                }
                return Result.success()
            }
            // Claim before creating a FlutterEngine. Duplicate or stale work
            // exits without networking once this signal was attempted.
            val claimed = database.claimNotificationAttempt(
                accountHash,
                expectedSessionEpoch,
                ownerWorkId = id.toString(),
            )
            if (claimed == null) {
                val existing = database.notificationAttempt(accountHash)
                if (existing?.ownerWorkId == id.toString() &&
                    existing.phase == NotificationAttemptPhase.REMOTE_AUTHORIZED
                ) {
                    database.settleNotificationAttempt(
                        accountHash,
                        expectedSessionEpoch,
                        existing.claimToken,
                        ownerWorkId = id.toString(),
                    )
                }
                val followUp =
                    BackgroundWorkScheduler.scheduleNotificationFollowUpIfNeeded(
                        applicationContext,
                        database,
                        accountHash,
                        currentWorkId = id.toString(),
                    )
                return if (followUp.state == NotificationEnqueueState.FAILED) {
                    Result.retry()
                } else {
                    Result.success()
                }
            }
            claim = claimed
            activeClaim = claimed
            signalVersion = claimed.version
        }
        val startSignalVersion = if (reason == BackgroundWorkScheduler.REASON_DAYTIME) {
            account.pendingSignalVersion
        } else {
            signalVersion
        }

        if (reason == BackgroundWorkScheduler.REASON_DAYTIME &&
            ZonedDateTime.now().hour < 8
        ) {
            scheduleNextDaytime(accountHash, intervalMinutes, expectedSessionEpoch)
            return Result.success()
        }

        val latch = CountDownLatch(1)
        activeLatch = latch
        if (stopped) {
            latch.countDown()
        }
        val completed = AtomicBoolean(false)
        val workResult = AtomicReference<Map<*, *>?>(null)
        val payload = mapOf(
            "reason" to reason,
            "accountHash" to accountHash,
            "sessionEpoch" to account.sessionEpoch,
            "requestedAt" to Instant.ofEpochMilli(requestedAt).toString(),
            "intervalMinutes" to intervalMinutes,
            "signalVersion" to signalVersion,
            "leaseOwner" to owner,
            "workerId" to id.toString(),
            "claimToken" to claim?.token,
        )

        mainHandler.post {
            if (stopped) {
                latch.countDown()
                return@post
            }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                if (stopped) {
                    latch.countDown()
                    return@post
                }
                val flutterEngine = FlutterEngine(applicationContext)
                if (stopped || !engineRef.compareAndSet(null, flutterEngine)) {
                    flutterEngine.destroy()
                    latch.countDown()
                    return@post
                }
                GeneratedPluginRegistrant.registerWith(flutterEngine)
                BackgroundReminderBridge.attach(flutterEngine, applicationContext)
                val workerChannel = MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    CHANNEL,
                )
                channel = workerChannel
                workerChannel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ready" -> {
                            result.success(null)
                            if (!stopped) {
                                workerChannel.invokeMethod("run", payload)
                            } else {
                                latch.countDown()
                            }
                        }
                        "finished" -> {
                            if (completed.compareAndSet(false, true)) {
                                workResult.set(call.arguments as? Map<*, *>)
                            }
                            result.success(null)
                            latch.countDown()
                        }
                        else -> result.notImplemented()
                    }
                }
                flutterEngine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "backgroundMain",
                    ),
                )
            } catch (error: Exception) {
                Log.w(TAG, "flutter_engine_start_failed:${error.javaClass.simpleName}")
                completed.set(false)
                latch.countDown()
            }
        }

        val finished = latch.await(8, TimeUnit.MINUTES)
        activeLatch = null
        val received = finished && completed.get()
        if (!received) {
            requestDartCancellation()
            claim?.let { settleUnconfirmed(it) }
        }
        if (reason == BackgroundWorkScheduler.REASON_DAYTIME) {
            if (stopped) {
                cleanup()
                return Result.success()
            }
            val currentAccount = database.activeAccount()
            if (currentAccount != null && currentAccount.accountHash != accountHash) {
                val now = ZonedDateTime.now()
                val target = if (now.hour >= 8) {
                    System.currentTimeMillis()
                } else {
                    BackgroundWorkScheduler.nextWindowStart(now)
                }
                BackgroundWorkScheduler.scheduleDaytimeAfterRun(
                    applicationContext,
                    database,
                    currentAccount.accountHash,
                    target,
                    currentAccount.intervalMinutes,
                    currentAccount.sessionEpoch,
                )
                cleanup()
                return Result.success()
            }
            val latest = database.readAccount(accountHash)
            val effectiveInterval = latest?.intervalMinutes ?: intervalMinutes
            val target = (workResult.get()?.get("nextTargetAt") as? Number)?.toLong()
                ?: nextTarget(effectiveInterval)
            BackgroundWorkScheduler.scheduleDaytimeAfterRun(
                applicationContext,
                database,
                accountHash,
                target,
                effectiveInterval,
                expectedSessionEpoch,
            )
            if (workResult.get()?.get("success") == true &&
                startSignalVersion > 0 &&
                latest?.sessionEpoch == expectedSessionEpoch
            ) {
                database.consumeSignal(
                    accountHash,
                    startSignalVersion,
                    expectedSessionEpoch,
                )
            }
            cleanup()
            return Result.success()
        }

        val result = workResult.get()
        val resultSuccess = result?.get("success") == true
        val skipped = result?.get("skipped") == true
        val skipReason = result?.get("skipReason") as? String
        val remoteReadInvoked = result?.get("remoteReadInvoked") == true
        if (resultSuccess) {
            database.consumeSignal(
                accountHash,
                signalVersion,
                expectedSessionEpoch,
            )
            val followUp =
                BackgroundWorkScheduler.scheduleNotificationFollowUpIfNeeded(
                    applicationContext,
                    database,
                    accountHash,
                    currentWorkId = id.toString(),
                )
            cleanup()
            return if (followUp.state == NotificationEnqueueState.FAILED) {
                Result.retry()
            } else {
                Result.success()
            }
        }

        if (NotificationAttemptRollbackPolicy.shouldRollback(
                received = received,
                stopped = stopped,
                success = resultSuccess,
                skipped = skipped,
                skipReason = skipReason,
            )
        ) {
            val currentClaim = claim
            if (currentClaim == null ||
                currentClaim.sessionEpoch != expectedSessionEpoch
            ) {
                Log.w(TAG, "notification_claim_rollback_rejected")
            } else {
                if (!remoteReadInvoked) {
                    database.markNotificationAttemptPhase(
                        accountHash,
                        expectedSessionEpoch,
                        currentClaim.token,
                        NotificationAttemptPhase.WINDOW_DEFERRED,
                        ownerWorkId = id.toString(),
                        allowRemoteAuthorizedDowngrade = true,
                    )
                }
                val successor =
                    BackgroundWorkScheduler.ensureDeferredNotificationSuccessor(
                        applicationContext,
                        database,
                        accountHash,
                        expectedSessionEpoch,
                        currentWorkId = id.toString(),
                        claimToPreserve = currentClaim,
                    )
                val released = database.releaseNotificationAttempt(currentClaim)
                if (!released) {
                    val latest = database.readAccount(accountHash)
                    val lingering = database.notificationAttempt(accountHash)
                    val needsSuccessor = latest != null &&
                        latest.pendingSignalVersion >
                        maxOf(latest.consumedSignalVersion, latest.attemptedSignalVersion)
                    if (latest == null ||
                        !latest.active ||
                        lingering?.claimToken != currentClaim.token
                    ) {
                        cleanup()
                        return Result.success()
                    }
                    if (needsSuccessor &&
                        successor.state != NotificationEnqueueState.CONFIRMED
                    ) {
                        cleanup()
                        return Result.retry()
                    }
                    cleanup()
                    return Result.success()
                }
                cleanup()
                return if (successor.state == NotificationEnqueueState.FAILED) {
                    Result.retry()
                } else {
                    Result.success()
                }
            }
        }

        claim?.let { settleUnconfirmed(it) }
        val followUp =
            BackgroundWorkScheduler.scheduleNotificationFollowUpIfNeeded(
                applicationContext,
                database,
                accountHash,
                currentWorkId = id.toString(),
            )
        cleanup()
        return if (followUp.state == NotificationEnqueueState.FAILED) {
            Result.retry()
        } else {
            Result.success()
        }
    }

    override fun onStopped() {
        stopped = true
        activeLatch?.countDown()
        activeClaim?.let { settleUnconfirmed(it) }
        requestDartCancellation()
        cleanup()
        super.onStopped()
    }

    private fun requestDartCancellation() {
        mainHandler.post {
            try {
                channel?.invokeMethod("cancel", null)
            } catch (error: RuntimeException) {
                Log.w(TAG, "flutter_cancel_failed:${error.javaClass.simpleName}")
            }
        }
    }

    private fun settleUnconfirmed(claim: NotificationSignalClaim) {
        try {
            ReminderDatabase.get(applicationContext).settleNotificationAttempt(
                claim.accountHash,
                claim.sessionEpoch,
                claim.token,
                ownerWorkId = id.toString(),
            )
        } catch (error: RuntimeException) {
            Log.w(TAG, "notification_claim_settle_failed:${error.javaClass.simpleName}")
        }
    }

    private fun NotificationAttempt.toClaim(pendingVersion: Long) =
        NotificationSignalClaim(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            version = claimedVersion,
            token = claimToken,
            claimedAt = claimedAt,
            priorAttemptedVersion = priorAttemptedVersion,
            priorLastSignalCheckAt = priorLastSignalCheckAt,
            priorPendingVersion = pendingVersion,
            priorConsumedVersion = priorConsumedVersion,
            ownerWorkId = ownerWorkId,
        )

    private fun cleanup() {
        activeLatch = null
        val current = engineRef.getAndSet(null)
        channel = null
        mainHandler.post {
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
            current?.destroy()
        }
    }

    private fun scheduleNextDaytime(
        accountHash: String,
        intervalMinutes: Int,
        sessionEpoch: Long,
    ) {
        val database = ReminderDatabase.get(applicationContext)
        val effectiveInterval =
            database.readAccount(accountHash)?.intervalMinutes ?: intervalMinutes
        BackgroundWorkScheduler.scheduleDaytimeAfterRun(
            applicationContext,
            database,
            accountHash,
            BackgroundWorkScheduler.nextWindowStart(),
            effectiveInterval,
            sessionEpoch,
        )
    }

    private fun nextTarget(intervalMinutes: Int): Long {
        val now = ZonedDateTime.now()
        var target = now.plusMinutes(intervalMinutes.toLong())
        val nextMidnight = now.toLocalDate().plusDays(1).atStartOfDay(now.zone)
        if (!target.isBefore(nextMidnight)) {
            target = now.toLocalDate().plusDays(1).atStartOfDay(now.zone).plusHours(8)
        } else if (target.hour < 8) {
            target = target.toLocalDate().atStartOfDay(now.zone).plusHours(8)
        }
        return target.toInstant().toEpochMilli()
    }

    companion object {
        private const val TAG = "FlutterCheckWorker"
        const val SKIP_REASON_OUTSIDE_WINDOW =
            NotificationAttemptRollbackPolicy.OUTSIDE_WINDOW
        const val CHANNEL = "study_assistant/background_worker"
        const val KEY_REASON = "reason"
        const val KEY_ACCOUNT_HASH = "accountHash"
        const val KEY_REQUESTED_AT = "requestedAt"
        const val KEY_INTERVAL_MINUTES = "intervalMinutes"
        const val KEY_SIGNAL_VERSION = "signalVersion"
        const val KEY_SESSION_EPOCH = "sessionEpoch"
    }
}
