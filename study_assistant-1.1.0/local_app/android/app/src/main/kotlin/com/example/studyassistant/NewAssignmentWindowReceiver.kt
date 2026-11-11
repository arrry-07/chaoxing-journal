package com.example.studyassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.ZonedDateTime

class NewAssignmentWindowReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val accountHash = intent.getStringExtra(EXTRA_ACCOUNT_HASH) ?: return
        val database = ReminderDatabase.get(context)
        val account = database.readAccount(accountHash) ?: return
        if (!account.active || !account.newAssignmentEnabled) return
        if (ZonedDateTime.now().hour < 8) {
            AssignmentAlarmScheduler.scheduleNewAssignmentWindow(context, accountHash)
            return
        }
        AssignmentNotificationPublisher.publishPendingNewAssignments(
            context,
            database,
            accountHash,
        )
    }

    companion object {
        const val EXTRA_ACCOUNT_HASH = "accountHash"
    }
}
