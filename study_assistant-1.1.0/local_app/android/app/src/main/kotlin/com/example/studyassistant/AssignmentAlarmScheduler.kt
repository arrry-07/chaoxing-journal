package com.example.studyassistant

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import java.time.Instant
import java.time.ZoneId

object AssignmentAlarmScheduler {
    private const val TAG = "AssignmentAlarmScheduler"
    private const val NEW_WINDOW_ACTION =
        "com.example.studyassistant.action.NEW_ASSIGNMENT_WINDOW"

    fun scheduleDeadline(context: Context, event: StoredReminderEvent) {
        val triggerAt = event.notifyAt.coerceAtLeast(System.currentTimeMillis() + 100L)
        val intent = Intent(context, AssignmentDeadlineReceiver::class.java)
            .setAction(AssignmentDeadlineReceiver.ACTION_DEADLINE)
            .setData(Uri.parse("studyassistant://deadline/${Uri.encode(event.eventId)}"))
            .putExtra(AssignmentDeadlineReceiver.EXTRA_EVENT_ID, event.eventId)
            .putExtra(AssignmentDeadlineReceiver.EXTRA_ACCOUNT_HASH, event.accountHash)
        val pending = PendingIntent.getBroadcast(
            context,
            event.notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        setAlarm(context, triggerAt, pending)
    }

    fun cancelDeadline(context: Context, event: StoredReminderEvent) {
        val intent = Intent(context, AssignmentDeadlineReceiver::class.java)
            .setAction(AssignmentDeadlineReceiver.ACTION_DEADLINE)
            .setData(Uri.parse("studyassistant://deadline/${Uri.encode(event.eventId)}"))
        val pending = PendingIntent.getBroadcast(
            context,
            event.notificationId,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(pending)
        pending.cancel()
    }

    fun hasDeadlineAlarm(context: Context, event: StoredReminderEvent): Boolean {
        val intent = Intent(context, AssignmentDeadlineReceiver::class.java)
            .setAction(AssignmentDeadlineReceiver.ACTION_DEADLINE)
            .setData(Uri.parse("studyassistant://deadline/${Uri.encode(event.eventId)}"))
        return PendingIntent.getBroadcast(
            context,
            event.notificationId,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) != null
    }

    fun scheduleNewAssignmentWindow(
        context: Context,
        accountHash: String,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ) {
        val triggerAt = NativeReminderPolicy.nextWindowStart(now, zone).toEpochMilli()
        val requestCode = stableRequestCode("new-window:$accountHash")
        val intent = Intent(context, NewAssignmentWindowReceiver::class.java)
            .setAction(NEW_WINDOW_ACTION)
            .setData(Uri.parse("studyassistant://new-window/${Uri.encode(accountHash)}"))
            .putExtra(NewAssignmentWindowReceiver.EXTRA_ACCOUNT_HASH, accountHash)
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        setAlarm(context, triggerAt, pending)
    }

    fun cancelNewAssignmentWindow(context: Context, accountHash: String) {
        val intent = Intent(context, NewAssignmentWindowReceiver::class.java)
            .setAction(NEW_WINDOW_ACTION)
            .setData(Uri.parse("studyassistant://new-window/${Uri.encode(accountHash)}"))
        val pending = PendingIntent.getBroadcast(
            context,
            stableRequestCode("new-window:$accountHash"),
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(pending)
        pending.cancel()
    }

    fun hasNewAssignmentWindowAlarm(context: Context, accountHash: String): Boolean {
        val intent = Intent(context, NewAssignmentWindowReceiver::class.java)
            .setAction(NEW_WINDOW_ACTION)
            .setData(Uri.parse("studyassistant://new-window/${Uri.encode(accountHash)}"))
        return PendingIntent.getBroadcast(
            context,
            stableRequestCode("new-window:$accountHash"),
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) != null
    }

    fun reconcile(
        context: Context,
        database: ReminderDatabase,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ) {
        val account = database.activeAccount() ?: return
        if (!database.isSessionCurrent(account.accountHash, account.sessionEpoch)) return
        database.pendingDeadlineEvents(account.accountHash).forEach {
            scheduleDeadline(context, it)
        }
        reconcilePendingNewAssignments(context, database, account, now, zone)
    }

    fun rescheduleForTimeZoneChange(
        context: Context,
        database: ReminderDatabase,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ) {
        val account = database.activeAccount() ?: return
        if (!database.isSessionCurrent(account.accountHash, account.sessionEpoch)) return
        database.pendingDeadlineEvents(account.accountHash).forEach { event ->
            val deadline = event.deadlineAt?.let(Instant::ofEpochMilli) ?: return@forEach
            if (!deadline.isAfter(now)) {
                database.cancelEvent(event.eventId)
                cancelDeadline(context, event)
                return@forEach
            }
            val earliest = event.offsets.asSequence()
                .map { deadline.minusSeconds(it.toLong() * 60) }
                .map { NativeReminderPolicy.moveToDaytime(it, zone) }
                .filter { it.isAfter(now) && it.isBefore(deadline) }
                .minOrNull()
            if (earliest == null) {
                database.cancelEvent(event.eventId)
                cancelDeadline(context, event)
            } else {
                val updated = event.copy(notifyAt = earliest.toEpochMilli())
                database.updateEventNotifyAt(updated.eventId, updated.notifyAt)
                scheduleDeadline(context, updated)
            }
        }
        reconcilePendingNewAssignments(context, database, account, now, zone)
    }

    private fun reconcilePendingNewAssignments(
        context: Context,
        database: ReminderDatabase,
        account: ReminderAccountState,
        now: Instant,
        zone: ZoneId,
    ) {
        val accountHash = account.accountHash
        if (!account.newAssignmentEnabled || database.pendingNewEvents(accountHash).isEmpty()) {
            cancelNewAssignmentWindow(context, accountHash)
        } else if (NativeReminderPolicy.isInDaytimeWindow(now, zone)) {
            cancelNewAssignmentWindow(context, accountHash)
            AssignmentNotificationPublisher.publishPendingNewAssignments(
                context,
                database,
                accountHash,
                now,
            )
        } else {
            scheduleNewAssignmentWindow(context, accountHash, now, zone)
        }
    }

    private fun setAlarm(context: Context, triggerAt: Long, pending: PendingIntent) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
                return
            }
        } catch (error: SecurityException) {
            // Exact alarm permission can be revoked between check and schedule.
            Log.w(TAG, "exact_alarm_denied:${error.javaClass.simpleName}")
        } catch (error: RuntimeException) {
            // Alarm quota or OEM restrictions must not abort remaining schedules.
            Log.w(TAG, "exact_alarm_failed:${error.javaClass.simpleName}")
            return
        }
        try {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        } catch (error: RuntimeException) {
            Log.w(TAG, "inexact_alarm_failed:${error.javaClass.simpleName}")
        }
    }

    private fun stableRequestCode(value: String): Int =
        1_600_000_000 + (value.hashCode() and 0x0fffffff)
}
