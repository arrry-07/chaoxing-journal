package com.example.studyassistant

import android.app.NotificationManager
import android.content.Context
import android.net.Uri

object DeadlineChannelPolicy {
    const val CHANNEL_DEADLINES = "assignment_deadlines"
    const val CHANNEL_DEADLINES_V2 = "assignment_deadlines_v2"
    const val CHANNEL_DEADLINES_V3 = "assignment_deadlines_v3"
    const val CHANNEL_UPDATES = "assignment_updates"
    const val CHANNEL_UPDATES_V2 = "assignment_updates_v2"
    const val CHANNEL_UPDATES_V3 = "assignment_updates_v3"
    const val CHANNEL_SUMMARY_V2 = "daily_summary_v2"
    const val CHANNEL_SUMMARY_V3 = "daily_summary_v3"
    const val CHANNEL_MANUAL_V2 = "personal_schedule_v2"
    const val CHANNEL_MANUAL_V3 = "personal_schedule_v3"
    const val CHANNEL_SILENT = "assignment_silent"
    const val CHIME_RAW_NAME = "journal_chime"
    const val TEST_NOTIFICATION_ID = 1_900_000_008
    val DEFAULT_VIBRATION_PATTERN = longArrayOf(0L, 180L, 90L, 180L)

    fun chimeUri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/raw/$CHIME_RAW_NAME")

    fun isCustomSoundUri(
        channelSound: String?,
        defaultSound: String?,
        builtinChime: String?,
    ): Boolean {
        if (channelSound == null || defaultSound == null) return false
        if (channelSound == defaultSound) return false
        if (builtinChime != null && channelSound == builtinChime) return false
        return true
    }

    fun normalizeChannelId(raw: String?): String? = when (raw?.trim()) {
        CHANNEL_DEADLINES -> CHANNEL_DEADLINES
        CHANNEL_DEADLINES_V2 -> CHANNEL_DEADLINES_V2
        CHANNEL_DEADLINES_V3 -> CHANNEL_DEADLINES_V3
        else -> null
    }

    fun resolveDefaultChannelId(
        explicitSelection: String?,
        channelQuerySucceeded: Boolean,
        existingChannelIds: Set<String>,
    ): String {
        normalizeChannelId(explicitSelection)?.let { return it }
        return CHANNEL_DEADLINES_V3
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
