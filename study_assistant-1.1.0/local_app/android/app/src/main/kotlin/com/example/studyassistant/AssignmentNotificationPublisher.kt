package com.example.studyassistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object AssignmentNotificationPublisher {
    const val CHANNEL_DEADLINES = DeadlineChannelPolicy.CHANNEL_DEADLINES
    const val CHANNEL_DEADLINES_V2 = DeadlineChannelPolicy.CHANNEL_DEADLINES_V2
    const val CHANNEL_UPDATES = DeadlineChannelPolicy.CHANNEL_UPDATES
    const val CHANNEL_UPDATES_V2 = DeadlineChannelPolicy.CHANNEL_UPDATES_V2
    const val CHANNEL_SUMMARY_V2 = DeadlineChannelPolicy.CHANNEL_SUMMARY_V2
    const val CHANNEL_MANUAL_V2 = DeadlineChannelPolicy.CHANNEL_MANUAL_V2
    const val CHANNEL_SILENT = DeadlineChannelPolicy.CHANNEL_SILENT
    const val TEST_NOTIFICATION_ID = DeadlineChannelPolicy.TEST_NOTIFICATION_ID
    private const val EXTRA_DELIVERY_TOKEN = "com.example.studyassistant.DELIVERY_TOKEN"
    private val testDelayExecutor = Executors.newSingleThreadScheduledExecutor { action ->
        Thread(action, "test-notification-delay").apply { isDaemon = true }
    }

    // Guarded by deliveryLock, including cleanup and the visibility check.
    private val inFlightDeliveries = mutableMapOf<Int, InFlightDelivery>()

    private class InFlightDelivery(
        val events: List<StoredReminderEvent>,
        val token: String = UUID.randomUUID().toString(),
        var cancelled: Boolean = false,
    )

    data class PublishResult(
        val submitted: Boolean,
        val notificationId: Int?,
        val warning: String?,
        val historyWarning: String? = null,
    )

    data class TestPublishResult(
        val status: String,
        val channelId: String?,
        val warning: String?,
        val retryAfterAt: Long? = null,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "status" to status,
            "channelId" to channelId,
            "warning" to warning,
            "retryAfterAt" to retryAfterAt,
        )
    }

    private fun buildAudibleChannel(
        context: Context,
        channelId: String,
        name: String,
        channelDescription: String,
    ): NotificationChannel = NotificationChannel(
        channelId,
        name,
        NotificationManager.IMPORTANCE_HIGH,
    ).apply {
        description = channelDescription
        setSound(
            DeadlineChannelPolicy.chimeUri(context),
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        enableVibration(true)
        vibrationPattern = DeadlineChannelPolicy.DEFAULT_VIBRATION_PATTERN
        lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        setShowBadge(true)
    }

    fun ensureDeadlineChannel(context: Context, channelId: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val normalized = DeadlineChannelPolicy.normalizeChannelId(channelId) ?: CHANNEL_DEADLINES_V2
        if (manager.getNotificationChannel(normalized) != null) return
        if (normalized == CHANNEL_DEADLINES_V2) {
            manager.createNotificationChannel(
                buildAudibleChannel(
                    context = context,
                    channelId = CHANNEL_DEADLINES_V2,
                    name = "作业截止提醒",
                    channelDescription = "学习通作业截止与考试开考提醒",
                ),
            )
        } else {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_DEADLINES,
                    "作业截止提醒",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "学习通作业截止前提醒"
                },
            )
        }
    }

    fun ensureChannels(context: Context, activeDeadlineChannelId: String? = null) {
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureDeadlineChannel(context, CHANNEL_DEADLINES_V2)
        val deadlineChannel = DeadlineChannelPolicy.normalizeChannelId(activeDeadlineChannelId)
            ?: DeadlineChannelPolicy.resolveFromSystem(context)
        if (deadlineChannel != CHANNEL_DEADLINES_V2) {
            ensureDeadlineChannel(context, deadlineChannel)
        }
        if (manager.getNotificationChannel(CHANNEL_UPDATES_V2) == null) {
            manager.createNotificationChannel(
                buildAudibleChannel(
                    context = context,
                    channelId = CHANNEL_UPDATES_V2,
                    name = "新增作业提醒",
                    channelDescription = "学习通新增作业与考试有声提醒",
                ),
            )
        }
        if (manager.getNotificationChannel(CHANNEL_SUMMARY_V2) == null) {
            manager.createNotificationChannel(
                buildAudibleChannel(
                    context = context,
                    channelId = CHANNEL_SUMMARY_V2,
                    name = "每日课业摘要",
                    channelDescription = "基于最近一次本机快照的课业摘要",
                ),
            )
        }
        if (manager.getNotificationChannel(CHANNEL_MANUAL_V2) == null) {
            manager.createNotificationChannel(
                buildAudibleChannel(
                    context = context,
                    channelId = CHANNEL_MANUAL_V2,
                    name = "待办与考试提醒",
                    channelDescription = "待办和考试开始前提醒",
                ),
            )
        }
    }

    fun publishDeadline(
        context: Context,
        database: ReminderDatabase,
        event: StoredReminderEvent,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): PublishResult {
        if (!LegacyAssignmentMigrationState.isComplete(context)) {
            return blocked(
                context,
                database,
                listOf(event),
                event.eventKind,
                "旧提醒迁移尚未完成，已暂缓自动投递",
                "legacyMigrationPending",
            )
        }
        val account = database.readAccount(event.accountHash)
            ?: return PublishResult(false, null, "账号提醒状态不存在")
        ensureChannels(context, account.deadlineChannelId)
        if (account.pendingUpdate) {
            return blocked(
                context,
                database,
                listOf(event),
                event.eventKind,
                "提醒快照正在恢复，已暂停自动投递",
                "snapshotPending",
            )
        }
        val snapshot = database.snapshot(event.accountHash, event.assignmentId)
            ?: return cancelInvalid(context, database, event, "作业快照不存在", now.toEpochMilli())
        val stored = database.event(event.eventId)
        if (stored?.status != ReminderDatabase.STATUS_PENDING ||
            stored.sessionEpoch != event.sessionEpoch
        ) {
            return PublishResult(false, null, null)
        }
        if (!account.active ||
            account.sessionEpoch != event.sessionEpoch ||
            event.status != ReminderDatabase.STATUS_PENDING ||
            !snapshot.matchesEvent(event, now.toEpochMilli())
        ) {
            return cancelInvalid(context, database, event, null, now.toEpochMilli())
        }
        val deadline = event.deadlineAt
            ?: return cancelInvalid(context, database, event, "截止时间不存在", now.toEpochMilli())
        if (deadline <= now.toEpochMilli()) {
            return cancelInvalid(context, database, event, null, now.toEpochMilli())
        }
        val evaluation = DeadlineQuietHoursPolicy.evaluateDeadlineDelivery(
            now = now,
            scheduledNotifyAt = Instant.ofEpochMilli(event.notifyAt),
            deadlineAt = Instant.ofEpochMilli(deadline),
            deadlineSource = snapshot.deadlineSource,
            allowUrgentNightBreakthrough = account.allowUrgentNightBreakthrough,
            zone = zone,
        )
        when (evaluation.decision) {
            DeadlineQuietHoursPolicy.DeliveryDecision.DELIVER -> Unit
            DeadlineQuietHoursPolicy.DeliveryDecision.BLOCK_MISSING_SOURCE -> {
                database.cancelEvent(event.eventId)
                return PublishResult(
                    false,
                    null,
                    "旧版提醒缺少时间来源，等待重新规划",
                    recordObservations(
                        context,
                        database,
                        listOf(event),
                        "blocked",
                        "missingDeadlineSource",
                        null,
                        now.toEpochMilli(),
                        useEventNotificationId = true,
                    ),
                )
            }
            DeadlineQuietHoursPolicy.DeliveryDecision.SUPPRESS_LATE_QUIET -> {
                database.cancelEvent(event.eventId)
                return PublishResult(
                    false,
                    null,
                    null,
                    recordObservations(
                        context,
                        database,
                        listOf(event),
                        "cancelled",
                        "lateQuietSuppressed",
                        null,
                        now.toEpochMilli(),
                        useEventNotificationId = true,
                    ),
                )
            }
            DeadlineQuietHoursPolicy.DeliveryDecision.CANCEL_DEADLINE_PASSED -> {
                database.cancelEvent(event.eventId)
                return PublishResult(
                    false,
                    null,
                    null,
                    recordObservations(
                        context,
                        database,
                        listOf(event),
                        "cancelled",
                        "deadlinePassed",
                        null,
                        now.toEpochMilli(),
                        useEventNotificationId = true,
                    ),
                )
            }
            DeadlineQuietHoursPolicy.DeliveryDecision.DEFER_TO_QUIET_END -> {
                val nextAt = evaluation.deferredAt!!.toEpochMilli()
                database.updateEventNotifyAt(event.eventId, nextAt)
                AssignmentAlarmScheduler.scheduleDeadline(
                    context,
                    event.copy(notifyAt = nextAt),
                )
                return PublishResult(
                    false,
                    null,
                    "当前处于夜间静音时段，提醒已顺延",
                    recordObservations(
                        context,
                        database,
                        listOf(event),
                        "deferred",
                        "quietHours",
                        null,
                        now.toEpochMilli(),
                        scheduledAtOverride = nextAt,
                    ),
                )
            }
        }
        val activeChannel = DeadlineChannelPolicy.normalizeChannelId(account.deadlineChannelId)
            ?: CHANNEL_DEADLINES_V2
        ensureDeadlineChannel(context, activeChannel)
        notificationWarning(context, activeChannel)?.let {
            return blocked(
                context,
                database,
                listOf(event),
                event.eventKind,
                it,
                channelIdOverride = activeChannel,
            )
        }

        val remaining = formatRemaining(
            Duration.ofMillis(deadline - now.toEpochMilli()).toMinutes(),
            event.eventKind,
        )
        val title = if (event.eventKind == "examStart") "考试即将开考" else "作业即将截止"
        val anonymousBody = if (event.eventKind == "examStart") {
            "有考试即将开考，请打开课业手记查看"
        } else {
            "有作业即将截止，请打开课业手记查看"
        }
        val body = if (account.showDetails) {
            "${event.courseName} · ${event.title}，$remaining"
        } else {
            anonymousBody
        }
        val click = clickIntent(
            context = context,
            accountHash = event.accountHash,
            assignmentId = event.assignmentId,
            eventId = event.eventId,
        )
        val notification = baseBuilder(
            context,
            activeChannel,
            title,
            body,
            anonymousBody.takeIf { account.showDetails },
        )
            .setContentIntent(click)
            .build()
        return submit(
            context,
            database,
            listOf(event),
            event.notificationId,
            notification,
            account.showDetails,
            now.toEpochMilli(),
        )
    }

    fun publishPendingNewAssignments(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        now: Instant = Instant.now(),
    ): PublishResult = publishPendingNewAssignments(context, database, accountHash, now, CHANNEL_UPDATES_V2)

    internal fun publishPendingNewAssignments(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        now: Instant,
        channelId: String,
    ): PublishResult {
        ensureChannels(context)
        if (!LegacyAssignmentMigrationState.isComplete(context)) {
            return blocked(
                context,
                database,
                database.pendingNewEvents(accountHash),
                "newAssignment",
                "旧提醒迁移尚未完成，已暂缓自动投递",
                "legacyMigrationPending",
            )
        }
        val account = database.readAccount(accountHash)
            ?: return PublishResult(false, null, "账号提醒状态不存在")
        if (!account.active || !account.newAssignmentEnabled) {
            return PublishResult(false, null, null)
        }
        if (account.pendingUpdate) {
            return blocked(
                context,
                database,
                database.pendingNewEvents(accountHash),
                "newAssignment",
                "提醒快照正在恢复，已暂停自动投递",
                "snapshotPending",
            )
        }
        val pending = database.pendingNewEvents(accountHash)
        val todo = pending.filter { event ->
            val snapshot = database.snapshot(accountHash, event.assignmentId)
            snapshot?.matchesEvent(event, now.toEpochMilli()) == true &&
                event.sessionEpoch == account.sessionEpoch
        }
        pending.filter { it !in todo }.forEach {
            cancelInvalid(context, database, it, null, now.toEpochMilli())
        }
        if (todo.isEmpty()) {
            AssignmentAlarmScheduler.cancelNewAssignmentWindow(context, accountHash)
            return PublishResult(false, null, null)
        }
        notificationWarning(context, channelId)?.let {
            return blocked(
                context,
                database,
                todo,
                "newAssignment",
                it,
            )
        }
        val single = todo.singleOrNull()
        val notificationId = if (single != null) {
            single.notificationId
        } else {
            ReminderDatabase.stableNotificationId(
                "new:${accountHash}:${todo.map { it.eventId }.sorted().joinToString("|")}",
            )
        }
        val notification = newAssignmentNotification(
            context,
            todo,
            account.showDetails,
            now,
            channelId,
        ).build()
        return submit(
            context,
            database,
            todo,
            notificationId,
            notification,
            account.showDetails,
            now.toEpochMilli(),
        )
    }

    private fun newAssignmentNotification(
        context: Context,
        events: List<StoredReminderEvent>,
        showDetails: Boolean,
        now: Instant,
        channelId: String,
    ): NotificationCompat.Builder {
        val single = events.singleOrNull()
        val hasExams = events.any { it.eventKind == "examStart" }
        val subject = if (hasExams) "课业" else "作业"
        val anonymousBody = if (single == null) {
            "有 ${events.size} 项${subject}有新变化，请打开课业手记查看"
        } else {
            "有${subject}有新变化，请打开课业手记查看"
        }
        val body = if (!showDetails) {
            anonymousBody
        } else if (single == null) {
            val names = events.take(3).joinToString("、") { it.title }
            "共 ${events.size} 项：$names${if (events.size > 3) "等" else ""}"
        } else {
            val deadlineText = single.deadlineAt?.let {
                val minutes = Duration.ofMillis(it - now.toEpochMilli()).toMinutes()
                "，${formatRemaining(minutes, single.eventKind)}"
            } ?: if (single.eventKind == "examStart") "，开考时间待确认" else "，截止时间待确认"
            "${single.courseName} · ${single.title}$deadlineText"
        }
        val click = clickIntent(
            context = context,
            accountHash = events.first().accountHash,
            assignmentId = single?.assignmentId,
            eventId = single?.eventId,
        )
        return baseBuilder(
            context,
            channelId,
            if (hasExams) "发现新的学习通课业" else "发现新的学习通作业",
            body,
            anonymousBody.takeIf { showDetails },
        )
            .setContentIntent(click)
    }

    private data class PendingHistoryBatch(
        val events: List<StoredReminderEvent>,
        val stage: String,
        val reasonCode: String? = null,
        val notificationId: Int? = null,
        val categoryOverride: String? = null,
        val useEventNotificationId: Boolean = false,
    )

    private fun reconcileInvalidatedEventsLocked(
        context: Context,
        database: ReminderDatabase,
        invalidatedEvents: List<StoredReminderEvent>,
        now: Instant,
    ): Pair<String?, List<StoredReminderEvent>> {
        invalidatedEvents.filter { it.type == ReminderDatabase.EVENT_DEADLINE }.forEach {
            AssignmentAlarmScheduler.cancelDeadline(context, it)
        }
        val manager = NotificationManagerCompat.from(context)
        val warnings = mutableSetOf<String>()
        val cancelledEvents = invalidatedEvents
            .filter { it.status == ReminderDatabase.STATUS_PENDING }
            .toMutableList()
        for (id in invalidatedEvents.map { it.notificationId }.toSet()) {
            // Submitted history includes notifications the user has already
            // dismissed. Only update a notification that is still visible.
            val active = manager.activeNotifications.firstOrNull { it.id == id } ?: continue
            if (database.eventsForNotification(id).any {
                    it.status == ReminderDatabase.STATUS_SUBMITTED &&
                        database.readAccount(it.accountHash)?.pendingUpdate == true
                }
            ) {
                warnings.add("提醒快照正在恢复，已暂停自动投递")
                continue
            }
            val members = database.submittedNotificationMembers(id, now.toEpochMilli())
            if (members.isEmpty()) {
                manager.cancel(id)
                cancelledEvents.addAll(invalidatedEvents.filter { it.notificationId == id })
                continue
            }
            // Only new-assignment events share a batch notification. Keep
            // any valid deadline owner if its numeric id happens to collide.
            if (members.any { it.type != ReminderDatabase.EVENT_NEW }) continue
            val account = database.readAccount(members.first().accountHash)!!
            val channelWarning = notificationWarning(context, active.notification.channelId)
            if (channelWarning != null) {
                warnings.add(channelWarning)
                continue
            }
            try {
                val notification = newAssignmentNotification(
                    context, members, account.showDetails, now, active.notification.channelId,
                )
                    .setWhen(active.notification.`when`)
                    .setSilent(true)
                    .setOnlyAlertOnce(true)
                    .build()
                // Preserve both the notification id and SUBMITTED history;
                // this is a silent content update, not another new event.
                manager.notify(id, notification)
            } catch (_: SecurityException) {
                warnings.add("系统通知权限未开启，提醒内容未能更新")
            } catch (error: Exception) {
                warnings.add("通知更新失败：${error.message.orEmpty()}")
            }
        }
        return Pair(
            warnings.takeIf { it.isNotEmpty() }?.joinToString("；"),
            cancelledEvents.distinctBy { it.eventId },
        )
    }

    /** Invalidating one member must not remove its submitted batch siblings. */
    fun reconcileInvalidatedEvents(
        context: Context,
        database: ReminderDatabase,
        invalidatedEvents: List<StoredReminderEvent>,
        now: Instant = Instant.now(),
    ): String? {
        val (warning, cancelledEvents) = synchronized(LegacyAssignmentNotificationMigrator.deliveryLock) {
            synchronized(database) {
                reconcileInvalidatedEventsLocked(context, database, invalidatedEvents, now)
            }
        }
        val historyWarning = if (cancelledEvents.isNotEmpty()) {
            recordObservations(
                context,
                database,
                cancelledEvents,
                "cancelled",
                "invalid",
                null,
                now.toEpochMilli(),
                useEventNotificationId = true,
            )
        } else {
            null
        }
        return listOfNotNull(warning, historyWarning)
            .distinct()
            .takeIf { it.isNotEmpty() }
            ?.joinToString("；")
    }

    fun cancelForAccount(context: Context, database: ReminderDatabase, accountHash: String) {
        val events = synchronized(LegacyAssignmentNotificationMigrator.deliveryLock) {
            AssignmentAlarmScheduler.cancelNewAssignmentWindow(context, accountHash)
            val manager = NotificationManagerCompat.from(context)
            val cancelled = database.cancelAssignmentReminders(accountHash)
            cancelInFlightForAccountLocked(manager, accountHash)
            cancelled.forEach {
                if (it.type == ReminderDatabase.EVENT_DEADLINE) {
                    AssignmentAlarmScheduler.cancelDeadline(context, it)
                }
                manager.cancel(it.notificationId)
            }
            cancelled
        }
        recordObservations(
            context,
            database,
            events,
            "cancelled",
            "accountChanged",
            null,
            System.currentTimeMillis(),
        )
    }

    fun cancelDeadlineReminders(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
    ) {
        val events = synchronized(LegacyAssignmentNotificationMigrator.deliveryLock) {
            val manager = NotificationManagerCompat.from(context)
            val cancelled = database.cancelDeadlineReminders(accountHash)
            cancelInFlightForAccountLocked(manager, accountHash)
            cancelled.forEach {
                AssignmentAlarmScheduler.cancelDeadline(context, it)
                manager.cancel(it.notificationId)
            }
            cancelled
        }
        if (events.isNotEmpty()) {
            recordObservations(
                context,
                database,
                events,
                "cancelled",
                "scheduleReplaced",
                null,
                System.currentTimeMillis(),
                useEventNotificationId = true,
            )
        }
    }

    fun publishTestDeadlineNotification(
        context: Context,
        database: ReminderDatabase,
        accountHash: String? = null,
        requestedChannelId: String? = null,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
        delayMillis: Long = 3_000L,
    ): TestPublishResult {
        if (DeadlineQuietHoursPolicy.isQuiet(now, zone)) {
            val retryAt = DeadlineQuietHoursPolicy.nextQuietEnd(now, zone).toEpochMilli()
            return TestPublishResult(
                status = "quietHours",
                channelId = null,
                warning = "当前处于夜间静音时段（23:30–07:30），测试提醒不会穿透静音；请在 07:30 后重试。",
                retryAfterAt = retryAt,
            )
        }
        val targetChannel = DeadlineChannelPolicy.normalizeChannelId(requestedChannelId)
            ?: accountHash?.let { database.readAccount(it)?.deadlineChannelId }
                ?.let(DeadlineChannelPolicy::normalizeChannelId)
            ?: DeadlineChannelPolicy.resolveFromSystem(context)
        ensureChannels(context, targetChannel)
        notificationWarning(context, targetChannel)?.let { warning ->
            return TestPublishResult(
                status = "blocked",
                channelId = targetChannel,
                warning = warning,
            )
        }
        val appContext = context.applicationContext ?: context
        val launchIntent = appContext.packageManager
            .getLaunchIntentForPackage(appContext.packageName)
            ?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        val click = launchIntent?.let {
            PendingIntent.getActivity(
                appContext,
                TEST_NOTIFICATION_ID,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val body = "这是一条无隐私内容的测试提醒，用于核对声音、短振与锁屏横幅（实际效果取决于系统与渠道设置）。"
        val notification = baseBuilder(
            appContext,
            targetChannel,
            "课业手记测试有声提醒",
            body,
            "课业手记有声提醒测试",
        )
            .setOnlyAlertOnce(false)
            .apply { if (click != null) setContentIntent(click) }
            .build()
        val postAction = {
            try {
                NotificationManagerCompat.from(appContext)
                    .notify(TEST_NOTIFICATION_ID, notification)
            } catch (_: SecurityException) {
            } catch (_: RuntimeException) {
            }
        }
        val boundedDelay = delayMillis.coerceIn(0L, 10_000L)
        if (boundedDelay == 0L) {
            return try {
                NotificationManagerCompat.from(appContext)
                    .notify(TEST_NOTIFICATION_ID, notification)
                TestPublishResult(status = "posted", channelId = targetChannel, warning = null)
            } catch (error: SecurityException) {
                TestPublishResult(
                    status = "blocked",
                    channelId = targetChannel,
                    warning = "系统通知权限未开启：${error.message.orEmpty()}",
                )
            }
        }
        testDelayExecutor.schedule(postAction, boundedDelay, TimeUnit.MILLISECONDS)
        return TestPublishResult(status = "scheduled", channelId = targetChannel, warning = null)
    }

    fun cancelDeliveryForPrivacy(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
    ) {
        val events = synchronized(LegacyAssignmentNotificationMigrator.deliveryLock) {
            AssignmentAlarmScheduler.cancelNewAssignmentWindow(context, accountHash)
            val manager = NotificationManagerCompat.from(context)
            cancelInFlightForAccountLocked(manager, accountHash)
            val activeEvents = database.eventsForAccount(accountHash)
                .filter {
                    it.status == ReminderDatabase.STATUS_PENDING ||
                        it.status == ReminderDatabase.STATUS_SUBMITTED
                }
            activeEvents.forEach {
                if (it.type == ReminderDatabase.EVENT_DEADLINE) {
                    AssignmentAlarmScheduler.cancelDeadline(context, it)
                }
                manager.cancel(it.notificationId)
            }
            activeEvents
        }
        recordObservations(
            context,
            database,
            events,
            "cancelled",
            "privacyCleanup",
            null,
            System.currentTimeMillis(),
        )
    }

    private fun cancelInFlightForAccountLocked(
        manager: NotificationManagerCompat,
        accountHash: String,
    ) {
        for ((id, delivery) in inFlightDeliveries) {
            if (delivery.events.first().accountHash != accountHash) continue
            delivery.cancelled = true
            // A pending aggregate still has per-event IDs in the database.
            cancelUnconfirmedNotification(manager, id, delivery)
        }
    }

    private fun submit(
        context: Context,
        database: ReminderDatabase,
        events: List<StoredReminderEvent>,
        notificationId: Int,
        notification: Notification,
        showDetails: Boolean,
        now: Long,
    ): PublishResult {
        val lock = LegacyAssignmentNotificationMigrator.deliveryLock
        val manager = NotificationManagerCompat.from(context)
        val delivery = InFlightDelivery(events)
        val eventIds = events.map { it.eventId }.toSet()
        val initial = synchronized(lock) {
            synchronized(database) start@ {
                if (notificationId in inFlightDeliveries || inFlightDeliveries.values.any {
                        it.events.any { pending -> pending.eventId in eventIds }
                    }
                ) {
                    return@start Pair(PublishResult(false, null, null), null)
                }
                validateEventsForSubmitLocked(context, database, events, showDetails, now)?.let {
                    return@start it
                }
                try {
                    notification.visibility = Notification.VISIBILITY_PRIVATE
                    notification.extras.putString(EXTRA_DELIVERY_TOKEN, delivery.token)
                    manager.notify(notificationId, notification)
                    if (activeNotification(manager, notificationId).matchesDelivery(delivery)) {
                        return@start markSubmittedLocked(database, events, notificationId)
                    }
                    inFlightDeliveries[notificationId] = delivery
                    null
                } catch (error: SecurityException) {
                    blockedPermissionResult(events, error)
                } catch (error: Exception) {
                    blockedFailureResult(events, error)
                }
            }
        }
        val (result, pendingHistory) = initial ?: try {
            // Android can take several hundred milliseconds to expose a post.
            // Let account, privacy and plan changes proceed during this wait.
            val visible = waitUntilActive(manager, notificationId, delivery)
            synchronized(lock) {
                synchronized(database) confirm@ {
                    if (delivery.cancelled) {
                        return@confirm Pair(PublishResult(false, null, null), null)
                    }
                    validateEventsForSubmitLocked(context, database, events, showDetails, now)?.let {
                        cancelUnconfirmedNotification(manager, notificationId, delivery)
                        return@confirm it
                    }
                    if (visible) {
                        if (activeNotification(manager, notificationId).matchesDelivery(delivery)) {
                            return@confirm markSubmittedLocked(database, events, notificationId)
                        }
                        // The system showed the post, then it was removed or replaced.
                        return@confirm Pair(PublishResult(false, null, null), null)
                    }
                    cancelUnconfirmedNotification(manager, notificationId, delivery)
                    Pair(
                        PublishResult(false, null, "系统未接受通知，请检查通知通道设置"),
                        PendingHistoryBatch(
                            events = events,
                            stage = "blocked",
                            reasonCode = "notificationNotVisible",
                            categoryOverride = categoryFor(events),
                        ),
                    )
                }
            }
        } catch (error: SecurityException) {
            blockedPermissionResult(events, error)
        } catch (error: Exception) {
            blockedFailureResult(events, error)
        } finally {
            synchronized(lock) {
                inFlightDeliveries.remove(notificationId)
            }
        }
        val historyWarning = pendingHistory?.let { batch ->
            recordObservations(
                context,
                database,
                batch.events,
                batch.stage,
                batch.reasonCode,
                batch.notificationId,
                now,
                categoryOverride = batch.categoryOverride,
                useEventNotificationId = batch.useEventNotificationId,
            )
        }
        return result.copy(historyWarning = historyWarning)
    }

    private fun validateEventsForSubmitLocked(
        context: Context,
        database: ReminderDatabase,
        events: List<StoredReminderEvent>,
        showDetails: Boolean,
        now: Long,
    ): Pair<PublishResult, PendingHistoryBatch?>? {
        if (!LegacyAssignmentMigrationState.isComplete(context)) {
            return Pair(
                PublishResult(false, null, "旧提醒迁移尚未完成，已暂缓自动投递"),
                PendingHistoryBatch(
                    events = events,
                    stage = "blocked",
                    reasonCode = "legacyMigrationPending",
                    categoryOverride = categoryFor(events),
                ),
            )
        }
        val account = database.readAccount(events.first().accountHash)
        if (account?.pendingUpdate == true) {
            return Pair(
                PublishResult(false, null, "提醒快照正在恢复，已暂停自动投递"),
                PendingHistoryBatch(
                    events = events,
                    stage = "blocked",
                    reasonCode = "snapshotPending",
                    categoryOverride = categoryFor(events),
                ),
            )
        }
        val stale = events.any { event ->
            val stored = database.event(event.eventId)
            account?.active != true || account.sessionEpoch != event.sessionEpoch ||
                (event.type == ReminderDatabase.EVENT_NEW && !account.newAssignmentEnabled) ||
                stored?.status != ReminderDatabase.STATUS_PENDING ||
                stored.sessionEpoch != event.sessionEpoch ||
                stored.notificationId != event.notificationId ||
                stored.notifyAt != event.notifyAt
        }
        if (stale) return Pair(PublishResult(false, null, null), null)
        if (showDetails && account?.showDetails != true) {
            return Pair(
                PublishResult(false, null, null),
                PendingHistoryBatch(events, stage = "cancelled", reasonCode = "privacyCleanup"),
            )
        }
        val invalid = events.filter { event ->
            database.snapshot(event.accountHash, event.assignmentId)
                ?.matchesEvent(event, now) != true
        }
        if (invalid.isEmpty()) return null
        val cancelledInvalid = mutableListOf<StoredReminderEvent>()
        val repairWarnings = mutableListOf<String>()
        invalid.forEach { event ->
            val stored = database.event(event.eventId)
            if (stored != null && stored.sessionEpoch == event.sessionEpoch &&
                database.snapshot(stored.accountHash, stored.assignmentId)
                    ?.matchesEvent(stored, now) != true
            ) {
                database.cancelEvent(stored.eventId)
                cancelledInvalid.add(stored)
                reconcileInvalidatedEventsLocked(
                    context,
                    database,
                    listOf(stored),
                    Instant.ofEpochMilli(now),
                ).first?.let(repairWarnings::add)
            }
        }
        return Pair(
            PublishResult(
                false,
                null,
                repairWarnings.distinct().takeIf { it.isNotEmpty() }?.joinToString("；"),
            ),
            cancelledInvalid.takeIf { it.isNotEmpty() }?.let {
                PendingHistoryBatch(
                    events = it,
                    stage = "cancelled",
                    reasonCode = "invalid",
                    useEventNotificationId = true,
                )
            },
        )
    }

    private fun markSubmittedLocked(
        database: ReminderDatabase,
        events: List<StoredReminderEvent>,
        notificationId: Int,
    ): Pair<PublishResult, PendingHistoryBatch?> {
        events.forEach {
            database.markEventSubmitted(
                it.eventId,
                notificationId,
                it.accountHash,
                it.assignmentId,
                it.type,
            )
        }
        return Pair(
            PublishResult(true, notificationId, null),
            PendingHistoryBatch(
                events = events,
                stage = "submitted",
                notificationId = notificationId,
            ),
        )
    }

    private fun blockedPermissionResult(
        events: List<StoredReminderEvent>,
        error: SecurityException,
    ) = Pair(
        PublishResult(
            false,
            null,
            "系统通知权限未开启：${error.message.orEmpty()}",
        ),
        PendingHistoryBatch(
            events = events,
            stage = "blocked",
            reasonCode = "notificationPermissionOff",
            categoryOverride = categoryFor(events),
        ),
    )

    private fun blockedFailureResult(
        events: List<StoredReminderEvent>,
        error: Exception,
    ) = Pair(
        PublishResult(
            false,
            null,
            "通知提交失败：${error.message.orEmpty()}",
        ),
        PendingHistoryBatch(
            events = events,
            stage = "blocked",
            reasonCode = "notificationFailure",
            categoryOverride = categoryFor(events),
        ),
    )

    private fun notificationWarning(context: Context, channelId: String): String? {
        val channel = context.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(channelId)
        return NotificationDeliveryPolicy.warning(
            notificationsEnabled =
                NotificationManagerCompat.from(context).areNotificationsEnabled(),
            channelExists = channel != null,
            channelImportance = channel?.importance,
        )
    }

    private fun waitUntilActive(
        manager: NotificationManagerCompat,
        notificationId: Int,
        delivery: InFlightDelivery,
    ): Boolean {
        repeat(9) {
            SystemClock.sleep(50)
            if (activeNotification(manager, notificationId).matchesDelivery(delivery)) {
                return true
            }
        }
        return false
    }

    private fun activeNotification(
        manager: NotificationManagerCompat,
        notificationId: Int,
    ): StatusBarNotification? =
        manager.activeNotifications.firstOrNull { it.id == notificationId && it.tag == null }

    private fun StatusBarNotification?.matchesDelivery(delivery: InFlightDelivery): Boolean =
        this?.notification?.extras?.getString(EXTRA_DELIVERY_TOKEN) == delivery.token

    private fun cancelUnconfirmedNotification(
        manager: NotificationManagerCompat,
        notificationId: Int,
        delivery: InFlightDelivery,
    ) {
        val current = activeNotification(manager, notificationId)
        // Also cancel an enqueue that Android hasn't exposed in its list yet.
        if (current == null || current.matchesDelivery(delivery)) manager.cancel(notificationId)
    }

    private fun cancelInvalid(
        context: Context,
        database: ReminderDatabase,
        event: StoredReminderEvent,
        warning: String?,
        now: Long,
    ): PublishResult {
        val (resultWarning, cancelled) = synchronized(LegacyAssignmentNotificationMigrator.deliveryLock) {
            synchronized(database) cancellation@ {
                val stored = database.event(event.eventId)
                // A caller can still hold an event from an earlier plan or session.
                // Cancel only the currently invalid persisted event.
                if (stored != null && stored.sessionEpoch == event.sessionEpoch &&
                    database.snapshot(stored.accountHash, stored.assignmentId)
                        ?.matchesEvent(stored, now) != true
                ) {
                    database.cancelEvent(stored.eventId)
                    val (repairWarning, _) = reconcileInvalidatedEventsLocked(
                        context,
                        database,
                        listOf(stored),
                        Instant.ofEpochMilli(now),
                    )
                    return@cancellation Pair(warning ?: repairWarning, stored)
                }
                Pair(warning, null)
            }
        }
        val historyWarning = cancelled?.let {
            recordObservations(
                context,
                database,
                listOf(it),
                "cancelled",
                "invalid",
                it.notificationId,
                now,
            )
        }
        return PublishResult(false, null, resultWarning, historyWarning)
    }

    private fun blocked(
        context: Context,
        database: ReminderDatabase,
        events: List<StoredReminderEvent>,
        category: String,
        warning: String,
        reasonCode: String? = null,
        channelIdOverride: String? = null,
    ): PublishResult = PublishResult(
        false,
        null,
        warning,
        recordObservations(
            context,
            database,
            events,
            "blocked",
            reasonCode ?: blockReasonCode(context, category, channelIdOverride),
            null,
            System.currentTimeMillis(),
            categoryOverride = category,
        ),
    )

    private fun categoryFor(events: List<StoredReminderEvent>): String =
        if (events.any { it.type == ReminderDatabase.EVENT_NEW }) {
            "newAssignment"
        } else {
            events.firstOrNull()?.eventKind ?: "deadline"
        }

    private fun blockReasonCode(
        context: Context,
        category: String,
        channelIdOverride: String? = null,
    ): String {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return "notificationPermissionOff"
        val channelId = channelIdOverride ?: if (category == "newAssignment") {
            CHANNEL_UPDATES_V2
        } else {
            CHANNEL_DEADLINES_V2
        }
        val channel = context.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(channelId)
            ?: return "notificationChannelMissing"
        return if (channel.importance == NotificationManager.IMPORTANCE_NONE) {
            "notificationChannelOff"
        } else {
            "notificationUnknown"
        }
    }

    private fun recordObservations(
        context: Context,
        database: ReminderDatabase,
        events: List<StoredReminderEvent>,
        stage: String,
        reasonCode: String?,
        notificationId: Int?,
        observedAt: Long,
        categoryOverride: String? = null,
        scheduledAtOverride: Long? = null,
        useEventNotificationId: Boolean = false,
    ): String? {
        val accountHash = events.firstOrNull()?.accountHash ?: return null
        val observations = events.mapIndexed { index, event ->
            ReminderHistoryObservationInput(
                observationId = null,
                ordinal = index,
                subjectKind = "assignment",
                subjectId = event.assignmentId,
                logicalKey = event.eventId,
                category = categoryOverride ?: if (
                    event.type == ReminderDatabase.EVENT_NEW
                ) {
                    "newAssignment"
                } else {
                    event.eventKind
                },
                stage = stage,
                reasonCode = reasonCode,
                observedAt = observedAt,
                scheduledAt = scheduledAtOverride ?: event.notifyAt,
                notificationId =
                    if (useEventNotificationId) event.notificationId else notificationId,
                batchKey = event.batchId,
            )
        }
        return ReminderHistoryStore.recordNativeObservations(
            context,
            database,
            accountHash,
            observations,
        )
    }

    internal fun recordEventObservations(
        context: Context,
        database: ReminderDatabase,
        events: List<StoredReminderEvent>,
        stage: String,
        reasonCode: String?,
        notificationId: Int?,
        observedAt: Long,
        scheduledAtOverride: Long? = null,
        useEventNotificationId: Boolean = false,
    ): String? = recordObservations(
        context,
        database,
        events,
        stage,
        reasonCode,
        notificationId,
        observedAt,
        scheduledAtOverride = scheduledAtOverride,
        useEventNotificationId = useEventNotificationId,
    )

    internal fun recordReceiverReason(
        context: Context,
        database: ReminderDatabase,
        events: List<StoredReminderEvent>,
        stage: String,
        reasonCode: String,
        scheduledAtOverride: Long? = null,
    ): String? = recordObservations(
        context,
        database,
        events,
        stage,
        reasonCode,
        null,
        System.currentTimeMillis(),
        scheduledAtOverride = scheduledAtOverride,
    )

    private fun baseBuilder(
        context: Context,
        channel: String,
        title: String,
        body: String,
        anonymousBody: String?,
    ): NotificationCompat.Builder =
        notificationContent(context, channel, title, body)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .apply {
                if (anonymousBody != null) {
                    setPublicVersion(
                        notificationContent(context, channel, title, anonymousBody)
                            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                            .build(),
                    )
                }
            }

    private fun notificationContent(
        context: Context,
        channel: String,
        title: String,
        body: String,
    ): NotificationCompat.Builder =
        NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.app_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setSound(DeadlineChannelPolicy.chimeUri(context))
            .setVibrate(DeadlineChannelPolicy.DEFAULT_VIBRATION_PATTERN)
            .setDefaults(NotificationCompat.DEFAULT_LIGHTS)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)

    private fun clickIntent(
        context: Context,
        accountHash: String,
        assignmentId: String?,
        eventId: String?,
    ): PendingIntent = clickOperation(
        context,
        accountHash,
        assignmentId,
        eventId,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    ) ?: error("notification click operation unavailable")

    /** Compares the stored event's own click operation without creating it. */
    internal fun matchesClickIntent(
        context: Context,
        contentIntent: PendingIntent?,
        event: StoredReminderEvent,
    ): Boolean {
        if (contentIntent == null) return false
        val expected = clickOperation(
            context,
            event.accountHash,
            event.assignmentId,
            event.eventId,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return false
        return expected == contentIntent
    }

    private fun clickOperation(
        context: Context,
        accountHash: String,
        assignmentId: String?,
        eventId: String?,
        flags: Int,
    ): PendingIntent? {
        val intent = Intent(context, ReminderClickActivity::class.java)
            .setAction(ReminderClickReceiver.ACTION_CLICK)
            .setData(
                Uri.parse(
                    "studyassistant://notification-click/" +
                        Uri.encode(eventId ?: accountHash),
                ),
            )
            .putExtra(ReminderClickReceiver.EXTRA_ACCOUNT_HASH, accountHash)
            .putExtra(ReminderClickReceiver.EXTRA_ASSIGNMENT_ID, assignmentId)
        val requestCode = ReminderDatabase.stableNotificationId(
            "click:${eventId ?: accountHash}",
        )
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private fun formatRemaining(minutes: Long, eventKind: String = "deadline"): String {
        val action = if (eventKind == "examStart") "开考" else "截止"
        val safe = minutes.coerceAtLeast(1)
        if (safe < 60) return "还剩 $safe 分钟$action"
        if (safe < 24 * 60) {
            val hours = safe / 60
            val rest = safe % 60
            return if (rest == 0L) "还剩 $hours 小时$action" else "还剩 $hours 小时 $rest 分钟$action"
        }
        val days = safe / (24 * 60)
        val hours = (safe % (24 * 60)) / 60
        return if (hours == 0L) "还剩 $days 天$action" else "还剩 $days 天 $hours 小时$action"
    }
}
