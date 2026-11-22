package com.example.studyassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.UserManager
import android.util.Log

class ReminderSystemReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val userUnlocked = try {
            context.getSystemService(UserManager::class.java)?.isUserUnlocked == true
        } catch (error: RuntimeException) {
            Log.w(TAG, "user_unlock_query_failed:${error.javaClass.simpleName}")
            return
        }
        if (!userUnlocked && action != Intent.ACTION_USER_UNLOCKED) return
        val appContext = context.applicationContext ?: context
        NativeReceiverExecutor.dispatchReceiver(goAsync()) {
            try {
                val database = ReminderDatabase.get(appContext)
                when (action) {
                    Intent.ACTION_TIMEZONE_CHANGED,
                    Intent.ACTION_TIME_CHANGED ->
                        AssignmentAlarmScheduler.rescheduleForTimeZoneChange(appContext, database)
                    Intent.ACTION_BOOT_COMPLETED,
                    Intent.ACTION_USER_UNLOCKED,
                    Intent.ACTION_MY_PACKAGE_REPLACED,
                    "android.intent.action.QUICKBOOT_POWERON",
                    "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                        try {
                            database.pruneStaleData(System.currentTimeMillis())
                        } catch (error: RuntimeException) {
                            Log.w(TAG, "startup_prune_failed:${error.javaClass.simpleName}")
                        }
                        AssignmentAlarmScheduler.reconcile(appContext, database)
                    }
                    else -> return@dispatchReceiver
                }
                BackgroundWorkScheduler.reconcileAfterSystemChange(appContext, database)
                AssignmentWidgetProvider.refreshAll(appContext)
            } catch (error: RuntimeException) {
                Log.w(TAG, "system_reconcile_failed:${error.javaClass.simpleName}")
            }
        }
    }

    companion object {
        private const val TAG = "ReminderSystemReceiver"
    }
}
