package com.example.studyassistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.time.Duration
import java.time.Instant

object AssignmentNotificationPublisher {
    const val CHANNEL_DEADLINES = "assignment_deadlines"
    const val CHANNEL_UPDATES = "assignment_updates"

    data class PublishResult(
        val submitted: Boolean,
        val notificationId: Int?,
        val warning: String?,
    )

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_DEADLINES,
                "作业截止提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "学习通作业截止前提醒"
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_UPDATES,
                "作业变化提醒",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "学习通正式作业新增提醒"
            },
        )
    }

    fun publishDeadline(
        context: Context,
        database: ReminderDatabase,
        event: StoredReminderEvent,
        now: Instant = Instant.now(),
    ): PublishResult {
        ensureChannels(context)
        val account = database.readAccount(event.accountHash)
            ?: return PublishResult(false, null, "账号提醒状态不存在")
        if (account.pendingUpdate) {
            return PublishResult(false, null, "提醒快照正在恢复，已暂停自动投递")
        }
        val snapshot = database.snapshot(event.accountHash, event.assignmentId)
            ?: return cancelInvalid(database, event, "作业快照不存在")
        if (!account.active ||
            account.sessionEpoch != event.sessionEpoch ||
            event.status != ReminderDatabase.STATUS_PENDING ||
            !snapshot.formal ||
            !snapshot.followed ||
            snapshot.completed ||
            snapshot.hidden
        ) {
            return cancelInvalid(database, event, null)
        }
        val deadline = event.deadlineAt
            ?: return cancelInvalid(database, event, "截止时间不存在")
        if (deadline <= now.toEpochMilli()) {
            return cancelInvalid(database, event, null)
        }
        notificationWarning(context, CHANNEL_DEADLINES)?.let {
            return PublishResult(false, null, it)
        }

        val remaining = formatRemaining(
            Duration.ofMillis(deadline - now.toEpochMilli()).toMinutes(),
        )
        val title = "作业即将截止"
        val body = if (account.showDetails) {
            "${event.courseName} · ${event.title}，$remaining"
        } else {
            "有作业即将截止，请打开课业手记查看"
        }
        val click = clickIntent(
            context = context,
            accountHash = event.accountHash,
            assignmentId = event.assignmentId,
            eventId = event.eventId,
        )
        val notification = baseBuilder(
            context,
            CHANNEL_DEADLINES,
            title,
            body,
            account.showDetails,
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
            CHANNEL_DEADLINES,
        )
    }

    fun publishPendingNewAssignments(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
        now: Instant = Instant.now(),
    ): PublishResult {
        ensureChannels(context)
        val account = database.readAccount(accountHash)
            ?: return PublishResult(false, null, "账号提醒状态不存在")
        if (!account.active || !account.newAssignmentEnabled) {
            return PublishResult(false, null, null)
        }
        if (account.pendingUpdate) {
            return PublishResult(false, null, "提醒快照正在恢复，已暂停自动投递")
        }
        val pending = database.pendingNewEvents(accountHash).filter { event ->
            val snapshot = database.snapshot(accountHash, event.assignmentId)
            snapshot != null &&
                snapshot.formal &&
                snapshot.followed &&
                !snapshot.completed &&
                !snapshot.hidden &&
                event.sessionEpoch == account.sessionEpoch
        }
        if (pending.isEmpty()) return PublishResult(false, null, null)
        notificationWarning(context, CHANNEL_UPDATES)?.let {
            return PublishResult(false, null, it)
        }
        val todo = pending
            .filter { event ->
                event.deadlineAt?.let { it > now.toEpochMilli() } ?: true
            }
        pending.filter { it !in todo }.forEach { database.cancelEvent(it.eventId) }
        if (todo.isEmpty()) return PublishResult(false, null, null)

        val single = todo.singleOrNull()
        val title = if (single == null) "发现新的学习通作业" else "发现新的学习通作业"
        val body = if (!account.showDetails) {
            if (single == null) {
                "有 ${todo.size} 项正式作业有新变化，请打开课业手记查看"
            } else {
                "有正式作业有新变化，请打开课业手记查看"
            }
        } else if (single == null) {
            val names = todo.take(3).joinToString("、") { it.title }
            "共 ${todo.size} 项：$names${if (todo.size > 3) "等" else ""}"
        } else {
            val deadlineText = single.deadlineAt?.let {
                val minutes = Duration.ofMillis(it - now.toEpochMilli()).toMinutes()
                "，${formatRemaining(minutes)}"
            } ?: "，截止时间待确认"
            "${single.courseName} · ${single.title}$deadlineText"
        }
        val notificationId = if (single != null) {
            single.notificationId
        } else {
            ReminderDatabase.stableNotificationId(
                "new:${accountHash}:${todo.map { it.eventId }.sorted().joinToString("|")}",
            )
        }
        val assignmentId = single?.assignmentId
        val click = clickIntent(
            context = context,
            accountHash = accountHash,
            assignmentId = assignmentId,
            eventId = single?.eventId,
        )
        val notification = baseBuilder(
            context,
            CHANNEL_UPDATES,
            title,
            body,
            account.showDetails,
        )
            .setContentIntent(click)
            .build()
        return submit(
            context,
            database,
            todo,
            notificationId,
            notification,
            account.showDetails,
            CHANNEL_UPDATES,
        )
    }

    fun cancelForAccount(context: Context, database: ReminderDatabase, accountHash: String) {
        synchronized(LegacyAssignmentNotificationMigrator.deliveryLock) {
            AssignmentAlarmScheduler.cancelNewAssignmentWindow(context, accountHash)
            val manager = NotificationManagerCompat.from(context)
            val events = database.cancelAssignmentReminders(accountHash)
            events.forEach {
                if (it.type == ReminderDatabase.EVENT_DEADLINE) {
                    AssignmentAlarmScheduler.cancelDeadline(context, it)
                }
                manager.cancel(it.notificationId)
            }
        }
    }

    fun cancelDeliveryForPrivacy(
        context: Context,
        database: ReminderDatabase,
        accountHash: String,
    ) {
        synchronized(LegacyAssignmentNotificationMigrator.deliveryLock) {
            AssignmentAlarmScheduler.cancelNewAssignmentWindow(context, accountHash)
            val manager = NotificationManagerCompat.from(context)
            database.eventsForAccount(accountHash)
                .filter {
                    it.status == ReminderDatabase.STATUS_PENDING ||
                        it.status == ReminderDatabase.STATUS_SUBMITTED
                }
                .forEach {
                    if (it.type == ReminderDatabase.EVENT_DEADLINE) {
                        AssignmentAlarmScheduler.cancelDeadline(context, it)
                    }
                    manager.cancel(it.notificationId)
                }
        }
    }

    private fun submit(
        context: Context,
        database: ReminderDatabase,
        events: List<StoredReminderEvent>,
        notificationId: Int,
        notification: Notification,
        showDetails: Boolean,
        channelId: String,
    ): PublishResult {
        return synchronized(LegacyAssignmentNotificationMigrator.deliveryLock) {
            try {
                if (!showDetails) {
                    notification.visibility = Notification.VISIBILITY_PRIVATE
                }
                val manager = NotificationManagerCompat.from(context)
                manager.notify(notificationId, notification)
                if (!isActive(manager, notificationId)) {
                    return@synchronized PublishResult(
                        false, null, "系统未接受通知，请检查通知通道设置",
                    )
                }
                events.forEach {
                    database.markEventSubmitted(
                        it.eventId,
                        notificationId,
                        it.accountHash,
                        it.assignmentId,
                        it.type,
                    )
                }
                PublishResult(true, notificationId, null)
            } catch (error: SecurityException) {
                PublishResult(false, null, "系统通知权限未开启：${error.message.orEmpty()}")
            } catch (error: Exception) {
                PublishResult(false, null, "通知提交失败：${error.message.orEmpty()}")
            }
        }
    }

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

    private fun isActive(
        manager: NotificationManagerCompat,
        notificationId: Int,
    ): Boolean {
        repeat(10) { attempt ->
            if (manager.activeNotifications.any { it.id == notificationId }) {
                return true
            }
            if (attempt < 9) SystemClock.sleep(50)
        }
        return false
    }

    private fun cancelInvalid(
        database: ReminderDatabase,
        event: StoredReminderEvent,
        warning: String?,
    ): PublishResult {
        database.cancelEvent(event.eventId)
        return PublishResult(false, null, warning)
    }

    private fun baseBuilder(
        context: Context,
        channel: String,
        title: String,
        body: String,
        showDetails: Boolean,
    ): NotificationCompat.Builder =
        NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.app_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setVisibility(
                if (showDetails) NotificationCompat.VISIBILITY_PUBLIC
                else NotificationCompat.VISIBILITY_PRIVATE,
            )

    private fun clickIntent(
        context: Context,
        accountHash: String,
        assignmentId: String?,
        eventId: String?,
    ): PendingIntent {
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
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun formatRemaining(minutes: Long): String {
        val safe = minutes.coerceAtLeast(1)
        if (safe < 60) return "还剩 $safe 分钟截止"
        if (safe < 24 * 60) {
            val hours = safe / 60
            val rest = safe % 60
            return if (rest == 0L) "还剩 $hours 小时截止" else "还剩 $hours 小时 $rest 分钟截止"
        }
        val days = safe / (24 * 60)
        val hours = (safe % (24 * 60)) / 60
        return if (hours == 0L) "还剩 $days 天截止" else "还剩 $days 天 $hours 小时截止"
    }
}
