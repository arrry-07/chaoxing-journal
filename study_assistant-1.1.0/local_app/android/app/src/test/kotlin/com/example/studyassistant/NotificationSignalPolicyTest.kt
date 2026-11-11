package com.example.studyassistant

import android.app.Notification
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationSignalPolicyTest {
    @Test
    fun acceptsOnlyClearableChaoxingNotifications() {
        assertFalse(policy(packageName = "com.chaoxing.mobile"))
        assertTrue(policy(packageName = "com.example.lookalike"))
        assertTrue(policy(isClearable = false))
        assertTrue(policy(isOngoing = true))
    }

    @Test
    fun filtersGroupSummariesAndChatCategories() {
        assertTrue(policy(flags = Notification.FLAG_GROUP_SUMMARY))
        assertTrue(policy(category = Notification.CATEGORY_MESSAGE))
        assertTrue(policy(category = Notification.CATEGORY_EMAIL))
    }

    @Test
    fun ordinaryHomeworkNotificationRemainsEligible() {
        assertFalse(policy(flags = Notification.FLAG_AUTO_CANCEL))
    }

    private fun policy(
        packageName: String = "com.chaoxing.mobile",
        isOngoing: Boolean = false,
        isClearable: Boolean = true,
        flags: Int = 0,
        category: String? = null,
    ): Boolean = NotificationSignalPolicy.shouldIgnore(
        packageName,
        isOngoing,
        isClearable,
        flags,
        category,
    )
}
