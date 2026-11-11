package com.example.studyassistant

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.time.Instant
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

object AssignmentAlarmScheduler {
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

    fun scheduleNewAssignmentWindow(context: Context, accountHash: String) {
        val triggerAt = NativeReminderPolicy.nextWindowStart(Instant.now()).toEpochMilli()
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

    fun reconcile(context: Context, database: ReminderDatabase) {
        val account = database.activeAccount() ?: return
        if (!database.isSessionCurrent(account.accountHash, account.sessionEpoch)) return
        database.pendingDeadlineEvents(account.accountHash).forEach {
            scheduleDeadline(context, it)
        }
        if (database.pendingNewEvents(account.accountHash).isNotEmpty()) {
            scheduleNewAssignmentWindow(context, account.accountHash)
        }
    }

    fun rescheduleForTimeZoneChange(context: Context, database: ReminderDatabase) {
        val account = database.activeAccount() ?: return
        val now = Instant.now()
        database.pendingDeadlineEvents(account.accountHash).forEach { event ->
            val deadline = event.deadlineAt ?: return@forEach
            if (deadline <= now.toEpochMilli()) {
                database.cancelEvent(event.eventId)
                cancelDeadline(context, event)
                return@forEach
            }
            val deadlineTime = Instant.ofEpochMilli(deadline).atZone(ZonedDateTime.now().zone)
            var earliest: ZonedDateTime? = null
            event.offsets.forEach { offset ->
                var candidate = deadlineTime.minusMinutes(offset.toLong())
                candidate = NativeReminderPolicy.moveToDaytime(
                    candidate.toInstant(),
                    ZonedDateTime.now().zone,
                ).atZone(ZonedDateTime.now().zone)
                if (candidate.toInstant().isAfter(now) &&
                    candidate.toInstant().isBefore(Instant.ofEpochMilli(deadline))
                ) {
                    if (earliest == null || candidate.isBefore(earliest)) earliest = candidate
                }
            }
            if (earliest == null) {
                database.cancelEvent(event.eventId)
                cancelDeadline(context, event)
            } else {
                val updated = event.copy(notifyAt = earliest!!.toInstant().toEpochMilli())
                database.updateEventNotifyAt(updated.eventId, updated.notifyAt)
                scheduleDeadline(context, updated)
            }
        }
        if (database.pendingNewEvents(account.accountHash).isNotEmpty()) {
            scheduleNewAssignmentWindow(context, account.accountHash)
        }
    }

    private fun setAlarm(context: Context, triggerAt: Long, pending: PendingIntent) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarms.canScheduleExactAlarms()
        ) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        } else {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }
    }

    private fun stableRequestCode(value: String): Int =
        1_600_000_000 + (value.hashCode() and 0x0fffffff)
}
