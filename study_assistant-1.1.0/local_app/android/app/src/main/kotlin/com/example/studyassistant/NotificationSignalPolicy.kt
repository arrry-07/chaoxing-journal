package com.example.studyassistant

import android.app.Notification

object NotificationSignalPolicy {
    const val CHAOXING_PACKAGE = "com.chaoxing.mobile"
    private val ignoredCategories = setOf(
        Notification.CATEGORY_MESSAGE,
        Notification.CATEGORY_EMAIL,
        Notification.CATEGORY_CALL,
        "missed_call",
    )

    fun shouldIgnore(
        packageName: String,
        isOngoing: Boolean,
        isClearable: Boolean,
        flags: Int,
        category: String?,
    ): Boolean =
        packageName != CHAOXING_PACKAGE ||
            isOngoing ||
            !isClearable ||
            flags and Notification.FLAG_GROUP_SUMMARY != 0 ||
            ignoredCategories.contains(category)
}
