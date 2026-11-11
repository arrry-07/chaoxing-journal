package com.example.studyassistant

import android.app.NotificationManager

object NotificationDeliveryPolicy {
    fun warning(
        notificationsEnabled: Boolean,
        channelExists: Boolean,
        channelImportance: Int?,
    ): String? {
        if (!notificationsEnabled) {
            return "系统通知权限未开启"
        }
        if (!channelExists || channelImportance == null) {
            return "通知通道不存在，请重新打开提醒设置"
        }
        if (channelImportance == NotificationManager.IMPORTANCE_NONE) {
            return "对应通知通道已关闭，请在系统通知设置中重新开启"
        }
        return null
    }
}
