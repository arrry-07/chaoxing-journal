package com.example.studyassistant

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
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

        val database = ReminderDatabase.get(this)
        val account = database.activeAccount() ?: return
        if (!account.active || !account.listenerEnabled) return
        val signalKey = sha256(posted.key)
        val version = runCatching {
            database.recordSignal(
                account.accountHash,
                account.sessionEpoch,
                signalKey,
                posted.postTime,
            )
        }.getOrNull() ?: return
        if (version <= account.pendingSignalVersion) return
        BackgroundWorkScheduler.scheduleNotificationCheck(
            this,
            database,
            account.accountHash,
            version,
        )
    }

    private fun sha256(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

}
