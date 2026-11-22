package com.example.studyassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.ZonedDateTime

class NewAssignmentWindowReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val accountHash = intent.getStringExtra(EXTRA_ACCOUNT_HASH) ?: return
        val appContext = context.applicationContext ?: context
        NativeReceiverExecutor.dispatchReceiver(goAsync()) {
            handleWindow(
                appContext = appContext,
                database = ReminderDatabase.get(appContext),
                accountHash = accountHash,
            )
        }
    }

    internal fun handleWindow(
        appContext: Context,
        database: ReminderDatabase,
        accountHash: String,
        now: ZonedDateTime = ZonedDateTime.now(),
    ) {
        val account = database.readAccount(accountHash) ?: return
        if (!account.active || !account.newAssignmentEnabled) return
        if (!DeadlineQuietHoursPolicy.isInAudibleNewWindow(now.toInstant(), now.zone)) {
            val windowStart = DeadlineQuietHoursPolicy
                .nextAudibleNewWindowStart(now.toInstant(), now.zone)
                .toEpochMilli()
            AssignmentAlarmScheduler.scheduleNewAssignmentWindow(
                appContext,
                accountHash,
                now.toInstant(),
                now.zone,
            )
            AssignmentNotificationPublisher.recordReceiverReason(
                appContext,
                database,
                database.pendingNewEvents(accountHash),
                "deferred",
                "outsideWindow",
                scheduledAtOverride = windowStart,
            )
            return
        }
        AssignmentNotificationPublisher.publishPendingNewAssignments(
            appContext,
            database,
            accountHash,
            now.toInstant(),
        )
    }

    companion object {
        const val EXTRA_ACCOUNT_HASH = "accountHash"
    }
}
