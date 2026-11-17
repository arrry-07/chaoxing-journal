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
    @Volatile private var engine: FlutterEngine? = null
    @Volatile private var channel: MethodChannel? = null
    @Volatile private var stopped = false

    override fun doWork(): Result {
        val reason = inputData.getString(KEY_REASON) ?: return Result.success()
        val accountHash = inputData.getString(KEY_ACCOUNT_HASH) ?: return Result.success()
        val requestedAt = inputData.getLong(KEY_REQUESTED_AT, System.currentTimeMillis())
        val intervalMinutes = inputData.getInt(KEY_INTERVAL_MINUTES, 240)
        var signalVersion = inputData.getLong(KEY_SIGNAL_VERSION, 0L)
        var claim: NotificationSignalClaim? = null
        val expectedSessionEpoch = inputData.getLong(KEY_SESSION_EPOCH, -1L)
        val database = ReminderDatabase.get(applicationContext)
        val account = database.readAccount(accountHash)
        if (account == null ||
            !account.active ||
            (reason == BackgroundWorkScheduler.REASON_DAYTIME && !account.backgroundEnabled) ||
            (reason == BackgroundWorkScheduler.REASON_NOTIFICATION && !account.listenerEnabled)
        ) {
            return Result.success()
        }
        if (reason == BackgroundWorkScheduler.REASON_NOTIFICATION) {
            if (expectedSessionEpoch <= 0L ||
                account.sessionEpoch != expectedSessionEpoch
            ) {
                return Result.success()
            }
            val now = Instant.now()
            if (!NotificationCheckSchedulerPolicy.canClaimNow(
                    now,
                    database.lastSignalCheckAt(accountHash),
                    ZoneId.systemDefault(),
                )
            ) {
                val queued = BackgroundWorkScheduler.ensureDeferredNotificationSuccessor(
                    applicationContext,
                    database,
                    accountHash,
                    expectedSessionEpoch,
                )
                if (!queued) {
                    Log.w(TAG, "deferred_notification_successor_not_confirmed")
                }
                return Result.success()
            }
            // Claim before creating a FlutterEngine. Duplicate or stale work
            // exits without networking once this signal was attempted.
            val claimed = database.claimNotificationAttempt(
                accountHash,
                expectedSessionEpoch,
            ) ?: return Result.success()
            claim = claimed
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
            scheduleNextDaytime(accountHash, intervalMinutes)
            return Result.success()
        }

        val latch = CountDownLatch(1)
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
        )

        mainHandler.post {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val flutterEngine = FlutterEngine(applicationContext)
                engine = flutterEngine
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
                            if (!stopped) workerChannel.invokeMethod("run", payload)
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
                completed.set(false)
                latch.countDown()
            }
        }

        val finished = latch.await(8, TimeUnit.MINUTES)
        if (!finished || !completed.get()) {
            mainHandler.post {
                runCatching { channel?.invokeMethod("cancel", null) }
            }
        }
        if (reason == BackgroundWorkScheduler.REASON_DAYTIME) {
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
            )
            if (workResult.get()?.get("success") == true && startSignalVersion > 0) {
                database.consumeSignal(
                    accountHash,
                    startSignalVersion,
                    account.sessionEpoch,
                )
            }
        } else if (reason == BackgroundWorkScheduler.REASON_NOTIFICATION) {
            val result = workResult.get()
            val resultSuccess = result?.get("success") == true
            val skipped = result?.get("skipped") == true
            val skipReason = result?.get("skipReason") as? String
            if (resultSuccess) {
                database.consumeSignal(
                    accountHash,
                    signalVersion,
                    expectedSessionEpoch,
                )
            } else if (NotificationAttemptRollbackPolicy.shouldRollback(
                    received = finished && completed.get(),
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
                    val successor =
                        BackgroundWorkScheduler.ensureDeferredNotificationSuccessor(
                            applicationContext,
                            database,
                            accountHash,
                            expectedSessionEpoch,
                        )
                    if (successor) {
                        if (!database.rollbackUnstartedNotificationAttempt(
                                currentClaim,
                            )
                        ) {
                            Log.w(TAG, "notification_claim_rollback_not_applied")
                        }
                    } else {
                        Log.w(TAG, "notification_claim_kept_without_successor")
                    }
                }
            }
            BackgroundWorkScheduler.scheduleNotificationFollowUpIfNeeded(
                applicationContext,
                database,
                accountHash,
            )
        }
        cleanup()
        return Result.success()
    }

    override fun onStopped() {
        stopped = true
        mainHandler.post { runCatching { channel?.invokeMethod("cancel", null) } }
        cleanup()
        super.onStopped()
    }

    private fun cleanup() {
        val current = engine ?: return
        engine = null
        channel = null
        mainHandler.post {
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
            current.destroy()
        }
    }

    private fun scheduleNextDaytime(accountHash: String, intervalMinutes: Int) {
        val database = ReminderDatabase.get(applicationContext)
        val effectiveInterval =
            database.readAccount(accountHash)?.intervalMinutes ?: intervalMinutes
        BackgroundWorkScheduler.scheduleDaytimeAfterRun(
            applicationContext,
            database,
            accountHash,
            BackgroundWorkScheduler.nextWindowStart(),
            effectiveInterval,
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
