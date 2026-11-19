package com.example.studyassistant

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.security.MessageDigest

class ChaoxingNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val posted = sbn ?: return
        val notification = posted.notification ?: return
        if (NotificationSignalPolicy.shouldIgnore(
                posted.packageName,
                posted.isOngoing,
                posted.isClearable,
                notification.flags,
                notification.category,
            )
        ) return

        val appContext = applicationContext ?: this
        val signalKey = sha256(posted.key)
        val postTime = posted.postTime
        NativeReceiverExecutor.executeAsync {
            val database = ReminderDatabase.get(appContext)
            val account = database.activeAccount() ?: return@executeAsync
            if (!account.active || !account.listenerEnabled) return@executeAsync
            val version = runCatching {
                database.recordSignal(
                    account.accountHash,
                    account.sessionEpoch,
                    signalKey,
                    postTime,
                )
            }.getOrNull() ?: return@executeAsync
            if (version <= account.pendingSignalVersion) return@executeAsync
            val enqueue = BackgroundWorkScheduler.scheduleNotificationCheck(
                appContext,
                database,
                account.accountHash,
                version,
            )
            if (enqueue.state == NotificationEnqueueState.FAILED) {
                Log.w(
                    "ChaoxingNotificationListener",
                    "notification_signal_enqueue_failed:${enqueue.reasonCode}",
                )
            }
        }
    }

    private fun sha256(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

}
