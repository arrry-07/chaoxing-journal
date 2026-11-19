package com.example.studyassistant

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.ceil
import org.json.JSONArray
import org.json.JSONObject

class AssignmentWidgetProvider : AppWidgetProvider() {
    private data class WidgetRowIds(
        val containerId: Int,
        val titleId: Int,
        val metaId: Int,
    )

    private val rowSlots = listOf(
        WidgetRowIds(R.id.assignment_row_1, R.id.assignment_title_1, R.id.assignment_meta_1),
        WidgetRowIds(R.id.assignment_row_2, R.id.assignment_title_2, R.id.assignment_meta_2),
        WidgetRowIds(R.id.assignment_row_3, R.id.assignment_title_3, R.id.assignment_meta_3),
        WidgetRowIds(R.id.assignment_row_4, R.id.assignment_title_4, R.id.assignment_meta_4),
        WidgetRowIds(R.id.assignment_row_5, R.id.assignment_title_5, R.id.assignment_meta_5),
        WidgetRowIds(R.id.assignment_row_6, R.id.assignment_title_6, R.id.assignment_meta_6),
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, options))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, newOptions))
    }

    internal fun buildViews(context: Context, options: Bundle?): RemoteViews {
        val isPortrait =
            context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        val minHeightDp = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
        val maxHeightDp = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0) ?: 0
        val effectiveHeight =
            AssignmentWidgetLayoutPolicy.effectiveHeightDp(isPortrait, minHeightDp, maxHeightDp)
        val tier = AssignmentWidgetLayoutPolicy.tierForHeightDp(effectiveHeight)
        val layoutId = when (tier) {
            6 -> R.layout.assignment_widget_large
            4 -> R.layout.assignment_widget_medium
            else -> R.layout.assignment_widget
        }

        val views = RemoteViews(context.packageName, layoutId)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val items = loadItems(prefs)
        val meta = AssignmentWidgetLayoutPolicy.resolveSnapshotMeta(
            hasAuthenticatedKey = prefs.contains("assignment_authenticated"),
            rawAuthenticated = prefs.getBoolean("assignment_authenticated", true),
            rawRangeLabel = prefs.getString("assignment_range_label", null),
            hasTotalCountKey = prefs.contains("assignment_total_count"),
            rawTotalCount = prefs.all["assignment_total_count"] as? Number,
            snapshotLength = items.length(),
        )
        val savedAt = prefs.getString("assignment_snapshot_at", null)
        val stamp = try {
            savedAt?.let {
                OffsetDateTime.parse(it)
                    .atZoneSameInstant(ZoneId.of("Asia/Shanghai"))
                    .format(DateTimeFormatter.ofPattern("M/d HH:mm"))
            }
        } catch (_: Exception) {
            null
        }

        views.setTextViewText(
            R.id.widget_header,
            AssignmentWidgetLayoutPolicy.headerText(
                authenticated = meta.authenticated,
                rangeLabel = meta.rangeLabel,
                totalCount = meta.totalCount,
            ),
        )
        views.setTextViewText(R.id.widget_updated_at, stamp ?: "待同步")

        val homePendingIntent = createPendingIntent(
            context = context,
            requestCode = 0,
            deepLink = "studyassistant://assignments",
        )
        views.setOnClickPendingIntent(R.id.assignment_widget_root, homePendingIntent)
        views.setOnClickPendingIntent(R.id.widget_header_row, homePendingIntent)
        views.setOnClickPendingIntent(R.id.widget_footer, homePendingIntent)

        val slots = rowSlots.take(tier)
        if (!meta.authenticated || items.length() == 0) {
            val first = slots[0]
            views.setViewVisibility(first.containerId, View.VISIBLE)
            views.setTextViewText(
                first.titleId,
                if (!meta.authenticated) "尚未登录学习通" else "当前范围暂无作业",
            )
            views.setTextViewText(
                first.metaId,
                if (!meta.authenticated) "打开 App 登录并同步学习通" else "打开 App 同步学习通",
            )
            views.setTextColor(first.metaId, Color.parseColor(COLOR_MUTED))
            views.setOnClickPendingIntent(first.containerId, homePendingIntent)
            for (index in 1 until slots.size) {
                views.setViewVisibility(slots[index].containerId, View.GONE)
            }
            views.setViewVisibility(R.id.widget_footer, View.GONE)
            return views
        }

        val shownCount = minOf(tier, items.length())
        for (index in slots.indices) {
            val slot = slots[index]
            if (index >= shownCount) {
                views.setViewVisibility(slot.containerId, View.GONE)
                continue
            }
            val item = items.getJSONObject(index)
            val resolvedRemaining = remainingText(item)
            val urgent = AssignmentWidgetLayoutPolicy.isUrgent(
                urgencyLevel = item.optString("urgencyLevel"),
                remainingText = resolvedRemaining,
            )
            views.setViewVisibility(slot.containerId, View.VISIBLE)
            views.setTextViewText(slot.titleId, item.optString("title"))
            views.setTextViewText(slot.metaId, itemMeta(item, resolvedRemaining))
            views.setTextColor(
                slot.metaId,
                Color.parseColor(if (urgent) COLOR_BERRY else COLOR_MUTED),
            )
            val rowPendingIntent = createPendingIntent(
                context = context,
                requestCode = index + 1,
                deepLink = item.optString("deepLinkUrl", "studyassistant://assignments"),
            )
            views.setOnClickPendingIntent(slot.containerId, rowPendingIntent)
        }

        val overflow = AssignmentWidgetLayoutPolicy.overflowText(
            totalCount = meta.totalCount,
            shownCount = shownCount,
        )
        if (overflow != null) {
            views.setTextViewText(R.id.widget_footer, overflow)
            views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_footer, View.GONE)
        }
        return views
    }

    private fun createPendingIntent(
        context: Context,
        requestCode: Int,
        deepLink: String,
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, normalizeDeepLink(deepLink))
            .setPackage(context.packageName)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun itemMeta(item: JSONObject, resolvedRemaining: String): String =
        listOf(item.optString("deadlineText"), resolvedRemaining, item.optString("courseName"))
            .filter { it.isNotEmpty() }
            .joinToString(" · ")

    private fun remainingText(item: JSONObject): String {
        val fallback = item.optString("remainingText")
        val raw = item.optString("deadlineAt")
        if (raw.isEmpty() || raw == "null") return fallback
        val anchorAt = try {
            val instant = try {
                OffsetDateTime.parse(raw).toInstant()
            } catch (_: Exception) {
                LocalDateTime.parse(raw).atZone(ZoneId.systemDefault()).toInstant()
            }
            instant.toEpochMilli()
        } catch (_: Exception) {
            return fallback
        }
        return AssignmentWidgetTimeText.remainingText(
            anchorAtMillis = anchorAt,
            eventKind = item.optString("eventKind", "deadline"),
            nowMillis = System.currentTimeMillis(),
            fallback = fallback,
        )
    }

    private fun normalizeDeepLink(target: String): Uri {
        if (target.startsWith("studyassistant://assignments/")) {
            return Uri.parse(
                target.replaceFirst(
                    "studyassistant://assignments/",
                    "studyassistant:///assignments/",
                ),
            )
        }
        if (target == "studyassistant://assignments") {
            return Uri.parse("studyassistant:///assignments")
        }
        return Uri.parse(target)
    }

    private fun loadItems(prefs: android.content.SharedPreferences): JSONArray {
        val raw = prefs.getString("assignment_snapshot", "[]") ?: "[]"
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    companion object {
        private const val COLOR_MUTED = "#53645A"
        private const val COLOR_BERRY = "#813E53"

        /**
         * Refreshes every active home-screen instance from saved preferences after
         * package replacement, boot reconciliation, or system time changes.
         */
        fun refreshAll(context: Context) {
            runCatching {
                val manager = AppWidgetManager.getInstance(context) ?: return
                val ids = manager.getAppWidgetIds(
                    ComponentName(context, AssignmentWidgetProvider::class.java),
                )
                if (ids.isNotEmpty()) {
                    AssignmentWidgetProvider().onUpdate(context, manager, ids)
                }
            }
        }
    }
}

internal data class WidgetSnapshotMeta(
    val authenticated: Boolean,
    val rangeLabel: String,
    val totalCount: Int,
)

internal object AssignmentWidgetLayoutPolicy {
    fun effectiveHeightDp(isPortrait: Boolean, minHeightDp: Int, maxHeightDp: Int): Int {
        return if (isPortrait) {
            when {
                maxHeightDp > 0 -> maxHeightDp
                minHeightDp > 0 -> minHeightDp
                else -> 0
            }
        } else {
            when {
                minHeightDp > 0 -> minHeightDp
                maxHeightDp > 0 -> maxHeightDp
                else -> 0
            }
        }
    }

    fun tierForHeightDp(heightDp: Int): Int = when {
        heightDp <= 0 || heightDp < 145 -> 2
        heightDp < 230 -> 4
        else -> 6
    }

    fun headerText(authenticated: Boolean, rangeLabel: String, totalCount: Int): String {
        if (!authenticated) return "课业手记 · 未登录"
        val label = rangeLabel.ifBlank { "待完成" }
        return "$label $totalCount 项"
    }

    fun overflowText(totalCount: Int, shownCount: Int): String? {
        val hidden = totalCount - shownCount
        return if (hidden > 0) "还有 $hidden 项未展示 · 点击查看全部" else null
    }

    fun isUrgent(urgencyLevel: String, remainingText: String): Boolean {
        return urgencyLevel == "critical" ||
            remainingText.contains("已逾期") ||
            remainingText.contains("已截止")
    }

    fun resolveSnapshotMeta(
        hasAuthenticatedKey: Boolean,
        rawAuthenticated: Boolean,
        rawRangeLabel: String?,
        hasTotalCountKey: Boolean,
        rawTotalCount: Number?,
        snapshotLength: Int,
    ): WidgetSnapshotMeta {
        val authenticated = if (hasAuthenticatedKey) rawAuthenticated else true
        val rangeLabel = rawRangeLabel?.takeIf { it.isNotBlank() } ?: "待完成"
        val totalCount = if (!authenticated) {
            0
        } else if (hasTotalCountKey && rawTotalCount != null) {
            maxOf(rawTotalCount.toInt(), snapshotLength)
        } else {
            snapshotLength
        }
        return WidgetSnapshotMeta(
            authenticated = authenticated,
            rangeLabel = rangeLabel,
            totalCount = totalCount,
        )
    }
}

internal object AssignmentWidgetTimeText {
    fun remainingText(
        anchorAtMillis: Long?,
        eventKind: String,
        nowMillis: Long,
        fallback: String,
    ): String {
        if (anchorAtMillis == null) return fallback
        val minutes = ceil((anchorAtMillis - nowMillis) / 60000.0).toLong()
        if (eventKind == "examStart") {
            if (minutes <= 0) return "已开考"
            return "距开考 ${remainingLabel(minutes)}"
        }
        return if (minutes <= 0) "已截止" else remainingLabel(minutes)
    }

    private fun remainingLabel(minutes: Long): String = when {
        minutes < 60 -> "${minutes}分钟"
        minutes < 1440 -> "${ceil(minutes / 60.0).toLong()}小时"
        else -> "${ceil(minutes / 1440.0).toLong()}天"
    }
}
