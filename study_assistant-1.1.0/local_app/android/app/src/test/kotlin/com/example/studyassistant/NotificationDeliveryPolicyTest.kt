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

    @Test
    fun deadlineChannelPolicyNormalizesAndResolvesUpgradeVsFreshInstall() {
        assertEquals(
            DeadlineChannelPolicy.CHANNEL_DEADLINES,
            DeadlineChannelPolicy.normalizeChannelId(" assignment_deadlines "),
        )
        assertEquals(
            DeadlineChannelPolicy.CHANNEL_DEADLINES_V2,
            DeadlineChannelPolicy.normalizeChannelId("assignment_deadlines_v2"),
        )
        assertNull(DeadlineChannelPolicy.normalizeChannelId("assignment_updates"))
        assertNull(DeadlineChannelPolicy.normalizeChannelId(null))

        assertEquals(
            DeadlineChannelPolicy.CHANNEL_DEADLINES_V2,
            DeadlineChannelPolicy.resolveDefaultChannelId(
                explicitSelection = null,
                channelQuerySucceeded = true,
                existingChannelIds = emptySet(),
            ),
        )
        assertEquals(
            DeadlineChannelPolicy.CHANNEL_DEADLINES,
            DeadlineChannelPolicy.resolveDefaultChannelId(
                explicitSelection = null,
                channelQuerySucceeded = true,
                existingChannelIds = setOf(DeadlineChannelPolicy.CHANNEL_DEADLINES),
            ),
        )
        assertEquals(
            DeadlineChannelPolicy.CHANNEL_DEADLINES_V2,
            DeadlineChannelPolicy.resolveDefaultChannelId(
                explicitSelection = null,
                channelQuerySucceeded = true,
                existingChannelIds = setOf(
                    DeadlineChannelPolicy.CHANNEL_DEADLINES,
                    DeadlineChannelPolicy.CHANNEL_DEADLINES_V2,
                ),
            ),
        )
        assertEquals(
            DeadlineChannelPolicy.CHANNEL_DEADLINES,
            DeadlineChannelPolicy.resolveDefaultChannelId(
                explicitSelection = null,
                channelQuerySucceeded = false,
                existingChannelIds = emptySet(),
            ),
        )
        assertEquals(
            DeadlineChannelPolicy.CHANNEL_DEADLINES_V2,
            DeadlineChannelPolicy.resolveDefaultChannelId(
                explicitSelection = DeadlineChannelPolicy.CHANNEL_DEADLINES_V2,
                channelQuerySucceeded = false,
                existingChannelIds = setOf(DeadlineChannelPolicy.CHANNEL_DEADLINES),
            ),
        )
        assertEquals(
            DeadlineChannelPolicy.CHANNEL_DEADLINES,
            DeadlineChannelPolicy.resolveDefaultChannelId(
                explicitSelection = DeadlineChannelPolicy.CHANNEL_DEADLINES,
                channelQuerySucceeded = true,
                existingChannelIds = setOf(DeadlineChannelPolicy.CHANNEL_DEADLINES_V2),
            ),
        )
    }
}
