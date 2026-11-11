package com.example.studyassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ReminderClickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CLICK) return
        ReminderClickRouter.launch(
            context,
            ReminderClickRouter.resolve(
                context,
                intent.getStringExtra(EXTRA_ACCOUNT_HASH),
                intent.getStringExtra(EXTRA_ASSIGNMENT_ID),
            ),
        )
    }

    companion object {
        const val ACTION_CLICK =
            "com.example.studyassistant.action.ASSIGNMENT_NOTIFICATION_CLICK"
        const val EXTRA_ACCOUNT_HASH = "accountHash"
        const val EXTRA_ASSIGNMENT_ID = "assignmentId"
    }
}
