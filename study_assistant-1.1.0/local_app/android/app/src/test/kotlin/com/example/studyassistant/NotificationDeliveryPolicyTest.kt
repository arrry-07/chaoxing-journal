package com.example.studyassistant

import android.app.NotificationManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationDeliveryPolicyTest {
    @Test
    fun disabledAppNotificationsKeepDeliveryPending() {
        assertEquals(
            "系统通知权限未开启",
            NotificationDeliveryPolicy.warning(
                notificationsEnabled = false,
                channelExists = true,
                channelImportance = NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    @Test
    fun missingChannelKeepsDeliveryPending() {
        assertEquals(
            "通知通道不存在，请重新打开提醒设置",
            NotificationDeliveryPolicy.warning(
                notificationsEnabled = true,
                channelExists = false,
                channelImportance = null,
            ),
        )
    }

    @Test
    fun disabledChannelKeepsDeliveryPending() {
        assertEquals(
            "对应通知通道已关闭，请在系统通知设置中重新开启",
            NotificationDeliveryPolicy.warning(
                notificationsEnabled = true,
                channelExists = true,
                channelImportance = NotificationManager.IMPORTANCE_NONE,
            ),
        )
    }

    @Test
    fun enabledChannelAllowsDelivery() {
        assertNull(
            NotificationDeliveryPolicy.warning(
                notificationsEnabled = true,
                channelExists = true,
                channelImportance = NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }
}
