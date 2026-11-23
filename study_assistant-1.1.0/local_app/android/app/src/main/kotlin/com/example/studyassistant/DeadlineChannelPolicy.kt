package com.example.studyassistant

import android.app.NotificationManager
import android.content.Context

object DeadlineChannelPolicy {
    const val CHANNEL_DEADLINES = "assignment_deadlines"
    const val CHANNEL_DEADLINES_V2 = "assignment_deadlines_v2"
    const val CHANNEL_UPDATES = "assignment_updates"
    const val CHANNEL_SILENT = "assignment_silent"
    const val TEST_NOTIFICATION_ID = 1_900_000_008
    val DEFAULT_VIBRATION_PATTERN = longArrayOf(0L, 180L, 90L, 180L)

    fun normalizeChannelId(raw: String?): String? = when (raw?.trim()) {
        CHANNEL_DEADLINES -> CHANNEL_DEADLINES
        CHANNEL_DEADLINES_V2 -> CHANNEL_DEADLINES_V2
        else -> null
    }

    fun resolveDefaultChannelId(
        explicitSelection: String?,
        channelQuerySucceeded: Boolean,
        existingChannelIds: Set<String>,
    ): String {
        normalizeChannelId(explicitSelection)?.let { return it }
        if (!channelQuerySucceeded) return CHANNEL_DEADLINES
        if (CHANNEL_DEADLINES_V2 in existingChannelIds) return CHANNEL_DEADLINES_V2
        if (CHANNEL_DEADLINES in existingChannelIds) return CHANNEL_DEADLINES
        return CHANNEL_DEADLINES_V2
    }

    fun resolveFromSystem(
        context: Context,
        explicitSelection: String? = null,
    ): String {
        normalizeChannelId(explicitSelection)?.let { return it }
        val existing = runCatching {
            context.getSystemService(NotificationManager::class.java)
                ?.notificationChannels
                ?.map { it.id }
                ?.toSet()
        }.getOrNull()
        return resolveDefaultChannelId(
            explicitSelection = explicitSelection,
            channelQuerySucceeded = existing != null,
            existingChannelIds = existing ?: emptySet(),
        )
    }
}
