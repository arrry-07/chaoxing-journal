package com.example.studyassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.Instant
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
        val snapshot = database.snapshot(accountHash, event.assignmentId)
        val verifiedSource = if (snapshot != null && snapshot.deadlineSource == event.deadlineSource) {
            snapshot.deadlineSource
        } else {
            "unknown"
        }
        val evaluation = DeadlineQuietHoursPolicy.evaluateDeadlineDelivery(
            now = now.toInstant(),
            scheduledNotifyAt = Instant.ofEpochMilli(event.notifyAt),
            deadlineAt = event.deadlineAt?.let(Instant::ofEpochMilli),
            deadlineSource = verifiedSource,
            allowUrgentNightBreakthrough = account.allowUrgentNightBreakthrough,
            zone = now.zone,
        )
        when (evaluation.decision) {
            DeadlineQuietHoursPolicy.DeliveryDecision.DELIVER -> {
                AssignmentNotificationPublisher.publishDeadline(
                    appContext,
                    database,
                    event,
                    now.toInstant(),
                    now.zone,
                )
            }
            DeadlineQuietHoursPolicy.DeliveryDecision.DEFER_TO_QUIET_END -> {
                val nextAt = evaluation.deferredAt!!.toEpochMilli()
                database.updateEventNotifyAt(event.eventId, nextAt)
                AssignmentAlarmScheduler.scheduleDeadline(
                    appContext,
                    event.copy(notifyAt = nextAt),
                )
                AssignmentNotificationPublisher.recordReceiverReason(
                    appContext,
                    database,
                    listOf(event),
                    "deferred",
                    "quietHours",
                    scheduledAtOverride = nextAt,
                )
            }
            DeadlineQuietHoursPolicy.DeliveryDecision.SUPPRESS_LATE_QUIET -> {
                database.cancelEvent(event.eventId)
                AssignmentNotificationPublisher.recordReceiverReason(
                    appContext,
                    database,
                    listOf(event),
                    "cancelled",
                    "lateQuietSuppressed",
                )
            }
            DeadlineQuietHoursPolicy.DeliveryDecision.CANCEL_DEADLINE_PASSED -> {
                database.cancelEvent(event.eventId)
                AssignmentNotificationPublisher.recordReceiverReason(
                    appContext,
                    database,
                    listOf(event),
                    "cancelled",
                    "deadlinePassed",
                )
            }
            DeadlineQuietHoursPolicy.DeliveryDecision.BLOCK_MISSING_SOURCE -> {
                database.cancelEvent(event.eventId)
                AssignmentNotificationPublisher.recordReceiverReason(
                    appContext,
                    database,
                    listOf(event),
                    "blocked",
                    "missingDeadlineSource",
                )
            }
        }
    }

    companion object {
        const val ACTION_DEADLINE =
            "com.example.studyassistant.action.ASSIGNMENT_DEADLINE"
        const val EXTRA_EVENT_ID = "eventId"
        const val EXTRA_ACCOUNT_HASH = "accountHash"
    }
}
