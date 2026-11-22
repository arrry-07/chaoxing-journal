package com.example.studyassistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
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
    private const val TAG = "BackgroundReminderBridge"
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
            onCleanupFailure = { error ->
                Log.w(TAG, "lease_cleanup_failed:${error.javaClass.simpleName}")
            },
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
                    "ensureActiveAccount" -> tasks.execute(result) { reply ->
                        val accountHash = call.requiredString("accountHash")
                        BackgroundWorkScheduler.retireLegacyWork(appContext)
                        reply.success(database.ensureActiveAccount(accountHash).sessionEpoch)
                    }
                    "switchAccount" -> tasks.execute(result) { reply ->
                        val target = call.requiredString("accountHash")
                        val previous = database.activeAccount()?.accountHash?.takeIf { it != target }
                            ?: call.argument<String>("previousAccountHash")
                        val switchingFrom = previous?.takeIf { it.isNotBlank() && it != target }
                        val targetBefore = switchingFrom?.let { database.readAccount(target) }
                        if (switchingFrom != null) {
                            database.readAccount(switchingFrom)?.let { previousState ->
                                BackgroundWorkScheduler.cancelAllForAccount(
                                    appContext,
                                    switchingFrom,
                                    previousState.sessionEpoch,
                                )
                            }
                            AssignmentNotificationPublisher.cancelForAccount(
                                appContext,
                                database,
                                switchingFrom,
                            )
                            // Cancel the target's old notifications while the DB still has their IDs.
                            AssignmentNotificationPublisher.cancelForAccount(
                                appContext,
                                database,
                                target,
                            )
                        }
                        val state = database.switchAccount(previous, target)
                        if (switchingFrom != null) {
                            AssignmentWidgetProvider.clearForUnauthenticated(appContext)
                            if (targetBefore != null &&
                                targetBefore.sessionEpoch != state.sessionEpoch
                            ) {
                                BackgroundWorkScheduler.cancelAllForAccount(
                                    appContext,
                                    target,
                                    targetBefore.sessionEpoch,
                                )
                            }
                            BackgroundWorkScheduler.cancelAllForAccount(
                                appContext,
                                target,
                                state.sessionEpoch,
                            )
                        }
                        reply.success(state.sessionEpoch)
                    }
                    "rotateSessionEpoch" -> tasks.execute(result) { reply ->
                        val accountHash = call.requiredString("accountHash")
                        database.readAccount(accountHash)?.let { previous ->
                            BackgroundWorkScheduler.cancelAllForAccount(
                                appContext,
                                accountHash,
                                previous.sessionEpoch,
                            )
                        }
                        AssignmentNotificationPublisher.cancelForAccount(
                            appContext,
                            database,
                            accountHash,
                        )
                        val epoch = database.rotateSessionEpoch(accountHash)
                        BackgroundWorkScheduler.cancelAllForAccount(
                            appContext,
                            accountHash,
                            epoch,
                        )
                        reply.success(epoch)
                    }
                    "clearActiveAccount" -> tasks.execute(result) { reply ->
                        val accountHash = call.requiredString("accountHash")
                        database.readAccount(accountHash)?.let { previous ->
                            BackgroundWorkScheduler.cancelAllForAccount(
                                appContext,
                                accountHash,
                                previous.sessionEpoch,
                            )
                        } ?: BackgroundWorkScheduler.retireLegacyWork(appContext)
                        AssignmentNotificationPublisher.cancelForAccount(
                            appContext,
                            database,
                            accountHash,
                        )
                        val epoch = database.clearActiveAccount(accountHash)
                        if (database.activeAccount() == null) {
                            AssignmentWidgetProvider.clearForUnauthenticated(appContext)
                        }
                        reply.success(epoch)
                    }
                    "isSessionCurrent" -> tasks.execute(result) { reply ->
                        reply.success(
                            database.isSessionCurrent(
                                call.requiredString("accountHash"),
                                call.requiredLong("sessionEpoch"),
                            ),
                        )
                    }
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
                                val reconcileSchedules =
                                    call.argument<Boolean>("reconcileSchedules") != false
                                if (reconcileSchedules) {
                                    BackgroundWorkScheduler.reconcileDaytime(
                                        appContext,
                                        database,
                                        state.nextCheckAt,
                                        state.backgroundEnabled,
                                        state.intervalMinutes,
                                        state.accountHash,
                                        state.sessionEpoch,
                                    )
                                    BackgroundWorkScheduler.reconcileNotification(
                                        appContext,
                                        database,
                                        accountHash = state.accountHash,
                                        expectedSessionEpoch = state.sessionEpoch,
                                    )
                                } else {
                                    // A restored background engine only mirrors
                                    // settings. Disabled features still retire
                                    // work that is no longer permitted.
                                    if (!state.backgroundEnabled) {
                                        BackgroundWorkScheduler.reconcileDaytime(
                                            appContext,
                                            database,
                                            state.nextCheckAt,
                                            false,
                                            state.intervalMinutes,
                                            state.accountHash,
                                            state.sessionEpoch,
                                        )
                                    }
                                    if (!state.listenerEnabled) {
                                        BackgroundWorkScheduler.reconcileNotification(
                                            appContext,
                                            database,
                                            accountHash = state.accountHash,
                                            expectedSessionEpoch = state.sessionEpoch,
                                        )
                                    }
                                }
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
                    "markPendingUpdate" -> tasks.execute(result) { reply ->
                        database.markPendingUpdate(
                            call.requiredString("accountHash"),
                            call.requiredLong("sessionEpoch"),
                        )
                        reply.success(null)
                    }
                    "authorizeNotificationRemoteStart" -> tasks.execute(result) { reply ->
                        val authorization = database.authorizeNotificationRemoteStart(
                            accountHash = call.requiredString("accountHash"),
                            sessionEpoch = call.requiredLong("sessionEpoch"),
                            claimToken = call.requiredString("claimToken"),
                            ownerWorkId = call.requiredString("workerId"),
                        )
                        reply.success(
                            when (authorization) {
                                NotificationRemoteAuthorization.GRANTED -> "granted"
                                NotificationRemoteAuthorization.OUTSIDE_WINDOW ->
                                    "outsideWindow"
                                NotificationRemoteAuthorization.STALE -> "stale"
                            },
                        )
                    }
                    "loadPlanState" -> tasks.execute(result) { reply ->
                        val state = database.loadPlanState(
                            call.requiredString("accountHash"),
                            call.requiredLong("sessionEpoch"),
                        )
                        reply.success(
                            mapOf(
                                "baselineCompleted" to state.baselineCompleted,
                                "baselinedSources" to state.baselinedSources.toList(),
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
                        reply.success(
                            applyPlanAndRecord(
                                appContext = appContext,
                                database = database,
                                accountHash = accountHash,
                                sessionEpoch = sessionEpoch,
                                baselineCompleted =
                                    call.argument<Boolean>("baselineCompleted") == true,
                                knownIds = stringSet(call.argument("knownAssignmentIds")),
                                snapshots = snapshots,
                                events = events,
                                completedAt = ReminderDatabase.parseInstant(
                                    call.argument("completedAt"),
                                ) ?: System.currentTimeMillis(),
                                failure = call.argument<String>("failure"),
                                syncCompleted =
                                    call.argument<Boolean>("syncCompleted") == true,
                                expectedMutationVersion =
                                    call.requiredLong("expectedMutationVersion"),
                                baselinedSources =
                                    call.argument<List<String>>("baselinedSources")?.toSet(),
                            ),
                        )
                    }
                    "recordAttempt" -> tasks.execute(result) { reply ->
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
                        reply.success(null)
                    }
                    "inspectHealth" -> tasks.execute(result) { reply ->
                        val state = database.loadPlanState(
                            call.requiredString("accountHash"),
                            call.requiredLong("sessionEpoch"),
                        )
                        val counts = database.counts(state.accountHash)
                        val queryErrors = mutableListOf<String>()
                        val listenerGranted = try {
                            NotificationManagerCompat.getEnabledListenerPackages(appContext)
                                .contains(appContext.packageName)
                        } catch (error: RuntimeException) {
                            Log.w(TAG, "listener_permission_read_failed:${error.javaClass.simpleName}")
                            queryErrors.add("通知使用权状态读取失败")
                            false
                        }
                        reply.success(
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
                                "queryErrors" to queryErrors,
                            ),
                        )
                    }
                    "cancelAssignmentReminders" -> tasks.execute(result) { reply ->
                        AssignmentNotificationPublisher.cancelForAccount(
                            appContext,
                            database,
                            call.requiredString("accountHash"),
                        )
                        reply.success(null)
                    }
                    "cancelAssignmentDeliveryKeepEvents" -> tasks.execute(result) { reply ->
                        AssignmentNotificationPublisher.cancelDeliveryForPrivacy(
                            appContext,
                            database,
                            call.requiredString("accountHash"),
                        )
                        reply.success(null)
                    }
                    "consumeNotificationSignal" -> tasks.execute(result) { reply ->
                        database.consumeSignal(
                            call.requiredString("accountHash"),
                            call.requiredLong("version"),
                        )
                        reply.success(null)
                    }
                    "getReminderHistoryControl" -> tasks.execute(result) { reply ->
                        val snapshot = ReminderHistoryStore.controlSnapshot(
                            appContext,
                            call.argument<String>("accountHash"),
                            call.argument<Number>("sessionEpoch")?.toLong(),
                        )
                        reply.success(
                            mapOf(
                                "historyGeneration" to snapshot.historyGeneration,
                                "recordingEnabled" to snapshot.recordingEnabled,
                                "ownerMatches" to snapshot.ownerMatches,
                                "purgePending" to snapshot.purgePending,
                                "purgeToken" to snapshot.purgeToken,
                            ),
                        )
                    }
                    "acquireReminderObservationContext" -> tasks.execute(result) { reply ->
                        val context = ReminderHistoryStore.acquireObservationContext(
                            appContext,
                            database,
                            call.requiredString("accountHash"),
                            call.requiredLong("sessionEpoch"),
                        )
                        reply.success(context.toBridgeMap())
                    }
                    "appendReminderObservation" -> tasks.execute(result) { reply ->
                        val context = call.requiredObservationContext()
                        val observation = call.requiredObservation()
                        reply.success(
                            ReminderHistoryStore.appendObservation(
                                appContext,
                                database,
                                context,
                                observation,
                            ),
                        )
                    }
                    "recordReminderScheduleOutcome" -> tasks.execute(result) { reply ->
                        val context = call.requiredObservationContext()
                        val outcomes = jsonObjectList(call.argument("outcomes")).map {
                            ReminderScheduleOutcomeInput(
                                subjectKind = it.getString("subjectKind"),
                                subjectId = it.optString("subjectId")
                                    .takeIf { value -> value.isNotBlank() },
                                logicalKey = it.getString("logicalKey"),
                                category = it.getString("category"),
                                stage = it.getString("stage"),
                                reasonCode = it.optString("reasonCode")
                                    .takeIf { value -> value.isNotBlank() },
                                observedAt = ReminderDatabase.parseInstant(
                                    it.opt("observedAt"),
                                ),
                                scheduledAt = ReminderDatabase.parseInstant(
                                    it.opt("scheduledAt"),
                                ),
                                notificationId = if (it.has("notificationId") &&
                                    !it.isNull("notificationId")
                                ) {
                                    it.getInt("notificationId")
                                } else {
                                    null
                                },
                                expectedPayload = it.optString("expectedPayload")
                                    .takeIf { value -> value.isNotBlank() },
                                evidenceState = it.optString("evidenceState")
                                    .takeIf { value -> value.isNotBlank() },
                                batchKey = it.optString("batchKey")
                                    .takeIf { value -> value.isNotBlank() },
                            )
                        }
                        reply.success(
                            ReminderHistoryStore.recordScheduleOutcome(
                                appContext,
                                database,
                                context,
                                outcomes,
                            ),
                        )
                    }
                    "listReminderHistory" -> tasks.execute(result) { reply ->
                        val context = call.requiredObservationContext()
                        reply.success(
                            ReminderHistoryStore.listHistory(
                                appContext,
                                database,
                                context,
                                snapshotMaxId = call.argument<Number>("snapshotMaxId")
                                    ?.toLong(),
                                beforeId = call.argument<Number>("beforeId")?.toLong(),
                                category = call.argument<String>("category"),
                                subjectRefs = call.subjectRefPairs(),
                            ),
                        )
                    }
                    "inspectReminderSubjects" -> tasks.execute(result) { reply ->
                        val context = call.requiredObservationContext()
                        val refs = jsonObjectList(call.argument("subjectRefs")).map {
                            it.getString("kind") to
                                it.optString("id").takeIf { value -> value.isNotBlank() }
                        }
                        reply.success(
                            ReminderHistoryStore.inspectSubjects(
                                appContext,
                                database,
                                context,
                                refs,
                            ),
                        )
                    }
                    "beginReminderHistoryLogout" -> tasks.execute(result) { reply ->
                        reply.success(
                            ReminderHistoryStore.beginLogout(
                                appContext,
                                call.requiredLong("expectedHistoryGeneration"),
                                call.requiredString("requestId"),
                            ),
                        )
                    }
                    "finishReminderHistoryLogout" -> tasks.execute(result) { reply ->
                        reply.success(
                            ReminderHistoryStore.finishLogout(
                                appContext,
                                database,
                                call.requiredString("purgeToken"),
                            ),
                        )
                    }
                    "enableReminderHistorySession" -> tasks.execute(result) { reply ->
                        reply.success(
                            ReminderHistoryStore.enableSession(
                                appContext,
                                database,
                                call.requiredString("accountHash"),
                                call.requiredLong("sessionEpoch"),
                                call.requiredLong("expectedHistoryGeneration"),
                            ),
                        )
                    }
                    else -> result.notImplemented()
                }
            } catch (error: ReminderHistoryException) {
                result.error(error.code, error.message, null)
            } catch (error: Exception) {
                result.error("background_reminder_error", error.message, null)
            }
        }
    }

    internal fun applyPlanAndRecord(
        appContext: Context,
        database: ReminderDatabase,
        accountHash: String,
        sessionEpoch: Long,
        baselineCompleted: Boolean,
        knownIds: Set<String>,
        snapshots: List<StoredReminderSnapshot>,
        events: List<StoredReminderEvent>,
        completedAt: Long,
        failure: String?,
        syncCompleted: Boolean,
        expectedMutationVersion: Long,
        baselinedSources: Set<String>?,
        now: ZonedDateTime = ZonedDateTime.now(),
    ): Map<String, Any?> {
        val application = database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            baselineCompleted = baselineCompleted,
            knownIds = knownIds,
            snapshots = snapshots,
            events = events,
            completedAt = completedAt,
            failure = failure,
            syncCompleted = syncCompleted,
            expectedMutationVersion = expectedMutationVersion,
            baselinedSources = baselinedSources,
        )
        val warnings = mutableListOf<String>()
        AssignmentNotificationPublisher.reconcileInvalidatedEvents(
            appContext,
            database,
            application.invalidatedEvents,
            now.toInstant(),
        )?.let(warnings::add)
        val missingAlarmEvents = application.desiredDeadlineEvents.filter { event ->
            !AssignmentAlarmScheduler.hasDeadlineAlarm(appContext, event)
        }
        application.desiredDeadlineEvents.forEach {
            AssignmentAlarmScheduler.scheduleDeadline(appContext, it)
        }
        val scheduledEvents = (application.scheduledDeadlineEvents + missingAlarmEvents)
            .distinctBy { it.eventId }
        val observedAtMillis = now.toInstant().toEpochMilli()
        if (scheduledEvents.isNotEmpty()) {
            AssignmentNotificationPublisher.recordEventObservations(
                context = appContext,
                database = database,
                events = scheduledEvents,
                stage = "scheduled",
                reasonCode = null,
                notificationId = null,
                observedAt = observedAtMillis,
                useEventNotificationId = true,
            )?.let(warnings::add)
        }
        if (application.pendingNewCount == 0) {
            AssignmentAlarmScheduler.cancelNewAssignmentWindow(appContext, accountHash)
        }
        if (NativeReminderPolicy.isInDaytimeWindow(now.toInstant(), now.zone)) {
            val published = AssignmentNotificationPublisher.publishPendingNewAssignments(
                appContext,
                database,
                accountHash,
                now.toInstant(),
            )
            published.warning?.let(warnings::add)
            published.historyWarning?.let(warnings::add)
        } else if (application.pendingNewCount > 0) {
            AssignmentAlarmScheduler.scheduleNewAssignmentWindow(
                appContext,
                accountHash,
                now.toInstant(),
                now.zone,
            )
            if (application.newEvents.isNotEmpty()) {
                val windowStart = NativeReminderPolicy
                    .nextWindowStart(now.toInstant(), now.zone)
                    .toEpochMilli()
                AssignmentNotificationPublisher.recordEventObservations(
                    context = appContext,
                    database = database,
                    events = application.newEvents,
                    stage = "deferred",
                    reasonCode = "outsideWindow",
                    notificationId = null,
                    observedAt = observedAtMillis,
                    scheduledAtOverride = windowStart,
                )?.let(warnings::add)
            }
        }
        val warning = warnings.distinct().takeIf { it.isNotEmpty() }?.joinToString("；")
        return mapOf(
            "scheduledDeadlineCount" to application.desiredDeadlineEvents.size,
            "pendingNewCount" to application.pendingNewCount,
            "warning" to warning,
        )
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

    private fun io.flutter.plugin.common.MethodCall.requiredObservationContext():
        ReminderObservationContext {
        val value = argument<Map<*, *>>("context")
            ?: throw IllegalArgumentException("缺少参数 context")
        fun requiredString(key: String): String =
            (value[key] as? String)?.takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("缺少参数 context.$key")
        fun requiredLong(key: String): Long =
            (value[key] as? Number)?.toLong()
                ?: throw IllegalArgumentException("缺少参数 context.$key")
        return ReminderObservationContext(
            accountHash = requiredString("accountHash"),
            sessionEpoch = requiredLong("sessionEpoch"),
            historyGeneration = requiredLong("historyGeneration"),
            operationSequence = requiredLong("operationSequence"),
        )
    }

    private fun io.flutter.plugin.common.MethodCall.requiredObservation():
        ReminderHistoryObservationInput {
        val value = argument<Map<*, *>>("observation")
            ?: throw IllegalArgumentException("缺少参数 observation")
        fun requiredString(key: String): String =
            (value[key] as? String)?.takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("缺少参数 observation.$key")
        fun optionalString(key: String): String? =
            (value[key] as? String)?.takeIf { it.isNotBlank() }
        return ReminderHistoryObservationInput(
            observationId = optionalString("observationId"),
            ordinal = (value["ordinal"] as? Number)?.toInt() ?: 0,
            subjectKind = requiredString("subjectKind"),
            subjectId = optionalString("subjectId"),
            logicalKey = requiredString("logicalKey"),
            category = requiredString("category"),
            stage = requiredString("stage"),
            reasonCode = optionalString("reasonCode"),
            observedAt = ReminderDatabase.parseInstant(value["observedAt"]),
            scheduledAt = ReminderDatabase.parseInstant(value["scheduledAt"]),
            notificationId = (value["notificationId"] as? Number)?.toInt(),
            batchKey = optionalString("batchKey"),
        )
    }

    private fun io.flutter.plugin.common.MethodCall.subjectRefPairs():
        List<Pair<String, String?>> = jsonObjectList(argument("subjectRefs")).map {
            val kind = it.getString("kind")
            val id = it.optString("id").takeIf { value -> value.isNotBlank() }
            kind to id
        }

    private fun ReminderObservationContext.toBridgeMap() = mapOf(
        "accountHash" to accountHash,
        "sessionEpoch" to sessionEpoch,
        "historyGeneration" to historyGeneration,
        "operationSequence" to operationSequence,
    )

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
