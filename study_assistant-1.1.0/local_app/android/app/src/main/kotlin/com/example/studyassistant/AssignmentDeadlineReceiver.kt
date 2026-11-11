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
        val database = ReminderDatabase.get(context)
        val event = database.event(eventId) ?: return
        val account = database.readAccount(accountHash) ?: return
        if (!account.active ||
            account.sessionEpoch != event.sessionEpoch ||
            event.status != ReminderDatabase.STATUS_PENDING
        ) {
            return
        }
        if (ZonedDateTime.now().hour < 8) {
            val deadline = event.deadlineAt
            if (deadline != null && deadline > System.currentTimeMillis()) {
                database.updateEventNotifyAt(
                    event.eventId,
                    BackgroundWorkScheduler.nextWindowStart(),
                )
                AssignmentAlarmScheduler.scheduleDeadline(
                    context,
                    event.copy(notifyAt = BackgroundWorkScheduler.nextWindowStart()),
                )
            } else {
                database.cancelEvent(event.eventId)
            }
            return
        }
        AssignmentNotificationPublisher.publishDeadline(context, database, event)
    }

    companion object {
        const val ACTION_DEADLINE =
            "com.example.studyassistant.action.ASSIGNMENT_DEADLINE"
        const val EXTRA_EVENT_ID = "eventId"
        const val EXTRA_ACCOUNT_HASH = "accountHash"
    }
}
