package com.example.studyassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.UserManager

class ReminderSystemReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val userUnlocked = context.getSystemService(UserManager::class.java).isUserUnlocked
        if (!userUnlocked && intent.action != Intent.ACTION_USER_UNLOCKED) return
        val database = ReminderDatabase.get(context)
        when (intent.action) {
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED -> {
                AssignmentAlarmScheduler.rescheduleForTimeZoneChange(context, database)
                BackgroundWorkScheduler.reconcileAfterSystemChange(context, database)
            }
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_USER_UNLOCKED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                AssignmentAlarmScheduler.reconcile(context, database)
                BackgroundWorkScheduler.reconcileAfterSystemChange(context, database)
            }
        }
    }
}
