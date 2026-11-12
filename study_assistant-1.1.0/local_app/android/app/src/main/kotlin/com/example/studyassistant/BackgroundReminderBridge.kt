package com.example.studyassistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZonedDateTime
import java.util.concurrent.Executors

object BackgroundReminderBridge {
    const val CHANNEL = "study_assistant/background_reminders"
    private const val CONFIRMATION_TIMEOUT_SECONDS = 10L
    private val leaseExecutor = Executors.newCachedThreadPool()
    // Database, alarm and notification publishing run here, never on the
    // platform main thread. Lease waits stay on their own executor so a busy
    // plan cannot block confirmation/release callbacks.
    private val reminderExecutor = Executors.newSingleThreadExecutor()
    private val confirmationExecutor =
        Executors.newSingleThreadScheduledExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        val database = ReminderDatabase.get(appContext)
        val leaseRequests = BackgroundLeaseRequests(
            waitExecutor = leaseExecutor,
            dispatch = { action -> mainHandler.post(action) },
            scheduleConfirmationTimeout = { action ->
                val future = confirmationExecutor.schedule(
                    action,
                    CONFIRMATION_TIMEOUT_SECONDS,
                    java.util.concurrent.TimeUnit.SECONDS,
                )
                val cancel: () -> Unit = { future.cancel(false) }
                cancel
            },
            onCleanupFailure = { /* best effort; the lease is still released */ },
        )
        engine.addEngineLifecycleListener(
            object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {
                    leaseRequests.destroy()
                }

                override fun onEngineWillDestroy() {
                    leaseRequests.destroy()
                }
            },
        )
        LegacyAssignmentNotificationMigrator.attach(engine, appContext)
        val tasks = NativeReminderTasks(reminderExecutor) { action ->
            mainHandler.post(action)
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ping" -> result.success(true)
                    "ensureActiveAccount" -> {
                        val accountHash = call.requiredString("accountHash")
                        result.success(database.ensureActiveAccount(accountHash).sessionEpoch)
                    }
                    "switchAccount" -> {
                        val previous = call.argument<String>("previousAccountHash")
                        val target = call.requiredString("accountHash")
                        val switchingAccount =
                            !previous.isNullOrBlank() && previous != target
                        if (switchingAccount) {
                            AssignmentNotificationPublisher.cancelForAccount(
                                appContext,
                                database,
                                previous!!,
                            )
                        }
                        val state = database.switchAccount(previous, target)
                        if (switchingAccount) {
                            AssignmentNotificationPublisher.cancelForAccount(
                                appContext,
                                database,
                                target,
                            )
                        }
                        result.success(state.sessionEpoch)
                    }
                    "rotateSessionEpoch" -> {
                        val accountHash = call.requiredString("accountHash")
                        AssignmentNotificationPublisher.cancelForAccount(
                            appContext,
                            database,
                            accountHash,
                        )
                        result.success(database.rotateSessionEpoch(accountHash))
                    }
                    "clearActiveAccount" -> {
                        val accountHash = call.requiredString("accountHash")
                        BackgroundWorkScheduler.cancelAllForAccount(appContext)
                        AssignmentNotificationPublisher.cancelForAccount(
                            appContext,
                            database,
                            accountHash,
                        )
                        result.success(database.clearActiveAccount(accountHash))
                    }
                    "isSessionCurrent" -> result.success(
                        database.isSessionCurrent(
                            call.requiredString("accountHash"),
                            call.requiredLong("sessionEpoch"),
                        ),
                    )
                    "updateSettings" -> {
                        leaseExecutor.execute {
                            runCatching {
                                val state = database.updateSettings(
                                    accountHash = call.requiredString("accountHash"),
                                    sessionEpoch = call.requiredLong("sessionEpoch"),
                                    backgroundEnabled =
                                        call.argument<Boolean>("enabled") == true,
                                    intervalMinutes =
                                        call.argument<Int>("intervalMinutes") ?: 240,
                                    listenerEnabled =
                                        call.argument<Boolean>(
                                            "notificationListenerEnabled",
                                        ) == true,
                                    newAssignmentEnabled =
                                        call.argument<Boolean>(
                                            "newAssignmentReminderEnabled",
                                        ) == true,
                                    showDetails =
                                        call.argument<Boolean>("showDetails") == true,
                                )
                                BackgroundWorkScheduler.reconcileDaytime(
                                    appContext,
                                    database,
                                    state.nextCheckAt,
                                    state.backgroundEnabled,
                                    state.intervalMinutes,
                                )
                                BackgroundWorkScheduler.reconcileNotification(
                                    appContext,
                                    database,
                                    accountHash = state.accountHash,
                                )
                            }.onSuccess {
                                mainHandler.post { result.success(null) }
                            }.onFailure {
                                mainHandler.post {
                                    result.error(
                                        "background_reminder_error",
                                        it.message,
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    "reconcileDaytimeSchedule" -> {
                        leaseExecutor.execute {
                            runCatching {
                                val target =
                                    ReminderDatabase.parseInstant(call.argument("targetAt"))
                                BackgroundWorkScheduler.reconcileDaytime(
                                    appContext,
                                    database,
                                    target,
                                    call.argument<Boolean>("enabled") == true,
                                    call.argument<Int>("intervalMinutes") ?: 240,
                                )
                            }.onSuccess {
                                mainHandler.post { result.success(null) }
                            }.onFailure {
                                mainHandler.post {
                                    result.error(
                                        "background_reminder_error",
                                        it.message,
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    "acquireSyncLease" -> {
                        val accountHash = call.requiredString("accountHash")
                        leaseRequests.acquireSync(
                            accountHash,
                            call.requiredString("requestId"),
                            {
                                val state = database.readAccount(accountHash)
                                mapOf(
                                    "lastAttemptAt" to state?.lastAttemptAt?.toIsoUtc(),
                                    "lastFullSuccessAt" to
                                        state?.lastFullSuccessAt?.toIsoUtc(),
                                )
                            },
                            result.toLeaseReply(),
                        )
                    }
                    "confirmSyncLease" -> result.success(
                        leaseRequests.confirmSync(
                            call.requiredString("accountHash"),
                            call.requiredString("requestId"),
                        ),
                    )
                    "cancelSyncLeaseAcquisition" -> {
                        leaseRequests.cancelSync(
                            call.requiredString("accountHash"),
                            call.requiredString("requestId"),
                        )
                        result.success(null)
                    }
                    "releaseSyncLease" -> {
                        leaseRequests.releaseSync(
                            call.requiredString("accountHash"),
                            call.requiredString("requestId"),
                        )
                        result.success(null)
                    }
                    "acquireWriteLease" -> {
                        leaseRequests.acquireWrite(
                            call.requiredString("owner"),
                            call.requiredString("requestId"),
                            result.toLeaseReply(),
                        )
                    }
                    "confirmWriteLease" -> result.success(
                        leaseRequests.confirmWrite(
                            call.requiredString("owner"),
                            call.requiredString("requestId"),
                        ),
                    )
                    "cancelWriteLeaseAcquisition" -> {
                        leaseRequests.cancelWrite(
                            call.requiredString("owner"),
                            call.requiredString("requestId"),
                        )
                        result.success(null)
                    }
                    "releaseWriteLease" -> {
                        leaseRequests.releaseWrite(
                            call.requiredString("owner"),
                            call.requiredString("requestId"),
                        )
                        result.success(null)
                    }
                    "markPendingUpdate" -> {
                        database.markPendingUpdate(
                            call.requiredString("accountHash"),
                            call.requiredLong("sessionEpoch"),
                        )
                        result.success(null)
                    }
                    "loadPlanState" -> {
                        val state = database.loadPlanState(
                            call.requiredString("accountHash"),
                            call.requiredLong("sessionEpoch"),
                        )
                        result.success(
                            mapOf(
                                "baselineCompleted" to state.baselineCompleted,
                                "knownAssignmentIds" to state.knownAssignmentIds.toList(),
                                "sentNewAssignmentIds" to state.sentNewAssignmentIds.toList(),
                                "lastAttemptAt" to state.lastAttemptAt?.toIsoUtc(),
                                "lastFullSuccessAt" to state.lastFullSuccessAt?.toIsoUtc(),
                                "pendingUpdate" to state.pendingUpdate,
                                "mutationVersion" to state.mutationVersion,
                            ),
                        )
                    }
                    "applyPlan" -> tasks.execute(result) { reply ->
                        val accountHash = call.requiredString("accountHash")
                        val sessionEpoch = call.requiredLong("sessionEpoch")
                        val snapshots = jsonObjectList(call.argument("snapshots"))
                            .map {
                                ReminderDatabase.snapshotFromJson(
                                    accountHash,
                                    sessionEpoch,
                                    it,
                                )
                            }
                        val events = jsonObjectList(call.argument("events"))
                            .map {
                                ReminderDatabase.eventFromJson(
                                    accountHash,
                                    sessionEpoch,
                                    it,
                                )
                            }
                        val application = database.applyPlan(
                            accountHash = accountHash,
                            sessionEpoch = sessionEpoch,
                            baselineCompleted = call.argument<Boolean>("baselineCompleted") == true,
                            knownIds = stringSet(call.argument("knownAssignmentIds")),
                            snapshots = snapshots,
                            events = events,
                            completedAt = ReminderDatabase.parseInstant(
                                call.argument("completedAt"),
                            ) ?: System.currentTimeMillis(),
                            failure = call.argument<String>("failure"),
                            syncCompleted = call.argument<Boolean>("syncCompleted") == true,
                            expectedMutationVersion =
                                call.requiredLong("expectedMutationVersion"),
                        )
                        application.invalidatedEvents.forEach {
                            AssignmentAlarmScheduler.cancelDeadline(appContext, it)
                            NotificationManagerCompat.from(appContext).cancel(it.notificationId)
                        }
                        application.desiredDeadlineEvents.forEach {
                            AssignmentAlarmScheduler.scheduleDeadline(appContext, it)
                        }
                        var warning: String? = null
                        val now = ZonedDateTime.now()
                        if (now.hour >= 8) {
                            val published = AssignmentNotificationPublisher.publishPendingNewAssignments(
                                appContext,
                                database,
                                accountHash,
                                now.toInstant(),
                            )
                            warning = published.warning
                        } else if (application.pendingNewCount > 0) {
                            AssignmentAlarmScheduler.scheduleNewAssignmentWindow(
                                appContext,
                                accountHash,
                            )
                        }
                        reply.success(
                            mapOf(
                                "scheduledDeadlineCount" to
                                    application.desiredDeadlineEvents.size,
                                "pendingNewCount" to application.pendingNewCount,
                                "warning" to warning,
                            ),
                        )
                    }
                    "recordAttempt" -> {
                        database.recordAttempt(
                            accountHash = call.requiredString("accountHash"),
                            sessionEpoch = call.requiredLong("sessionEpoch"),
                            attemptedAt = ReminderDatabase.parseInstant(
                                call.argument("attemptedAt"),
                            ) ?: System.currentTimeMillis(),
                            dataSucceeded = call.argument<Boolean>("dataSucceeded") == true,
                            fullSucceeded = call.argument<Boolean>("fullSucceeded") == true,
                            failure = call.argument<String>("failure"),
                        )
                        result.success(null)
                    }
                    "inspectHealth" -> {
                        val state = database.loadPlanState(
                            call.requiredString("accountHash"),
                            call.requiredLong("sessionEpoch"),
                        )
                        val counts = database.counts(state.accountHash)
                        val listenerGranted = NotificationManagerCompat
                            .getEnabledListenerPackages(appContext)
                            .contains(appContext.packageName)
                        result.success(
                            mapOf(
                                "backgroundEnabled" to state.backgroundEnabled,
                                "intervalMinutes" to state.intervalMinutes,
                                "newAssignmentReminderEnabled" to state.newAssignmentEnabled,
                                "notificationListenerEnabled" to state.listenerEnabled,
                                "notificationListenerGranted" to listenerGranted,
                                "nextCheckAt" to state.nextCheckAt?.toIsoUtc(),
                                "pendingNewCount" to counts.first,
                                "pendingDeadlineCount" to counts.second,
                                "baselineCompleted" to state.baselineCompleted,
                                "pendingSignalCount" to counts.third,
                                "migrationPending" to
                                    (state.migrationState != "native_active" || state.pendingUpdate),
                                "lastFailure" to state.lastFailure,
                            ),
                        )
                    }
                    "cancelAssignmentReminders" -> {
                        AssignmentNotificationPublisher.cancelForAccount(
                            appContext,
                            database,
                            call.requiredString("accountHash"),
                        )
                        result.success(null)
                    }
                    "cancelAssignmentDeliveryKeepEvents" -> {
                        AssignmentNotificationPublisher.cancelDeliveryForPrivacy(
                            appContext,
                            database,
                            call.requiredString("accountHash"),
                        )
                        result.success(null)
                    }
                    "consumeNotificationSignal" -> {
                        database.consumeSignal(
                            call.requiredString("accountHash"),
                            call.requiredLong("version"),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("background_reminder_error", error.message, null)
            }
        }
    }

    private fun io.flutter.plugin.common.MethodCall.requiredString(key: String): String =
        argument<String>(key)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("缺少参数 $key")

    private fun MethodChannel.Result.toLeaseReply(): BackgroundLeaseRequests.Reply =
        object : BackgroundLeaseRequests.Reply {
            override fun success(value: Any?) {
                this@toLeaseReply.success(value)
            }

            override fun error(error: Exception) {
                this@toLeaseReply.error(
                    "background_reminder_error",
                    error.message ?: error.javaClass.simpleName,
                    null,
                )
            }
        }

    private fun io.flutter.plugin.common.MethodCall.requiredLong(key: String): Long =
        (argument<Number>(key) ?: throw IllegalArgumentException("缺少参数 $key")).toLong()

    private fun jsonObjectList(value: Any?): List<JSONObject> {
        val list = value as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            when (item) {
                is JSONObject -> item
                is Map<*, *> -> JSONObject(item)
                else -> null
            }
        }
    }

    private fun stringSet(value: Any?): Set<String> =
        (value as? List<*>)?.mapNotNull { it as? String }?.toSet().orEmpty()

    private fun Long.toIsoUtc(): String = Instant.ofEpochMilli(this).toString()
}
