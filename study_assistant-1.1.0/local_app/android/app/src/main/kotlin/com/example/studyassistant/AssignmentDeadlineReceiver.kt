package com.example.studyassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.ZonedDateTime

class AssignmentDeadlineReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_DEADLINE) return
        val eventId = intent.getStringExtra(EXTRA_EVENT_ID) ?: return
        val accountHash = intent.getStringExtra(EXTRA_ACCOUNT_HASH) ?: return
        val appContext = context.applicationContext ?: context
        NativeReceiverExecutor.dispatchReceiver(goAsync()) {
            handleDeadline(
                appContext = appContext,
                database = ReminderDatabase.get(appContext),
                eventId = eventId,
                accountHash = accountHash,
            )
        }
    }

    internal fun handleDeadline(
        appContext: Context,
        database: ReminderDatabase,
        eventId: String,
        accountHash: String,
        now: ZonedDateTime = ZonedDateTime.now(),
    ) {
        val event = database.event(eventId) ?: return
        val account = database.readAccount(accountHash) ?: return
        if (event.status != ReminderDatabase.STATUS_PENDING) return
        if (!account.active || account.sessionEpoch != event.sessionEpoch) {
            AssignmentNotificationPublisher.recordReceiverReason(
                appContext,
                database,
                listOf(event),
                "blocked",
                "staleSession",
            )
            return
        }
        if (now.hour < 8) {
            val windowStart = BackgroundWorkScheduler.nextWindowStart(now)
            val deadline = event.deadlineAt
            if (deadline != null && deadline > windowStart) {
                database.updateEventNotifyAt(event.eventId, windowStart)
                AssignmentAlarmScheduler.scheduleDeadline(
                    appContext,
                    event.copy(notifyAt = windowStart),
                )
                AssignmentNotificationPublisher.recordReceiverReason(
                    appContext,
                    database,
                    listOf(event),
                    "deferred",
                    "outsideWindow",
                    scheduledAtOverride = windowStart,
                )
            } else {
                database.cancelEvent(event.eventId)
                AssignmentNotificationPublisher.recordReceiverReason(
                    appContext,
                    database,
                    listOf(event),
                    "cancelled",
                    "deadlinePassed",
                )
            }
            return
        }
        AssignmentNotificationPublisher.publishDeadline(
            appContext,
            database,
            event,
            now.toInstant(),
        )
    }

    companion object {
        const val ACTION_DEADLINE =
            "com.example.studyassistant.action.ASSIGNMENT_DEADLINE"
        const val EXTRA_EVENT_ID = "eventId"
        const val EXTRA_ACCOUNT_HASH = "accountHash"
    }
}
