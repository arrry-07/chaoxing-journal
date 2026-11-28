package com.example.studyassistant

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import kotlin.math.ceil
import org.json.JSONArray
import org.json.JSONException
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
        val configuration = context.resources.configuration
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
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
        } catch (error: DateTimeException) {
            Log.w(TAG, "snapshot_time_parse_failed:${error.javaClass.simpleName}")
            null
        }
        val availableRows = minOf(rowSlots.size, items.length())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            options?.containsKey(AppWidgetManager.OPTION_APPWIDGET_SIZES) == true &&
            meta.authenticated && availableRows > 1
        ) {
            // Some launchers report grid sizes larger than the area they render.
            // Let the host choose a layout using its measured content size.
            val variants = (1..availableRows).associate { rows ->
                val height = if (rows == 1) 0f else {
                    AssignmentWidgetLayoutPolicy.minimumHeightDp(rows, configuration.fontScale)
                }
                SizeF(0f, height) to renderViews(context, rows, items, meta, stamp)
            }
            return RemoteViews(variants)
        }
        val effectiveHeight = AssignmentWidgetLayoutPolicy.effectiveHeightDp(
            isPortrait = configuration.orientation != Configuration.ORIENTATION_LANDSCAPE,
            minHeightDp = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0,
            maxHeightDp = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0) ?: 0,
        )
        val maxRows = AssignmentWidgetLayoutPolicy.visibleRowCount(
            effectiveHeight, configuration.fontScale,
        )
        return renderViews(context, maxRows, items, meta, stamp)
    }

    private fun renderViews(
        context: Context,
        maxRows: Int,
        items: JSONArray,
        meta: WidgetSnapshotMeta,
        stamp: String?,
    ): RemoteViews {
        val tier = when {
            maxRows <= 2 -> 2
            maxRows <= 4 -> 4
            else -> 6
        }
        val layoutId = when (tier) {
            6 -> R.layout.assignment_widget_large
            4 -> R.layout.assignment_widget_medium
            else -> R.layout.assignment_widget
        }
        val views = RemoteViews(context.packageName, layoutId)
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
            applyTextColorRes(context, views, first.metaId, R.color.widget_muted)
            views.setOnClickPendingIntent(first.containerId, homePendingIntent)
            for (index in 1 until slots.size) {
                views.setViewVisibility(slots[index].containerId, View.GONE)
            }
            views.setViewVisibility(R.id.widget_footer, View.GONE)
            return views
        }

        val shownCount = minOf(maxRows, items.length())
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
            applyTextColorRes(
                context,
                views,
                slot.metaId,
                if (urgent) R.color.widget_urgent else R.color.widget_muted,
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

    private fun applyTextColorRes(context: Context, views: RemoteViews, id: Int, color: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColor(id, "setTextColor", color)
        } else {
            views.setTextColor(id, context.getColor(color))
        }
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
        AssignmentWidgetLayoutPolicy.formatItemMeta(
            deadlineText = item.optString("deadlineText"),
            resolvedRemaining = resolvedRemaining,
            courseName = item.optString("courseName"),
            deadlineSource = item.optString("deadlineSource"),
        )

    private fun remainingText(item: JSONObject): String {
        val fallback = item.optString("remainingText")
        val raw = item.optString("deadlineAt")
        if (raw.isEmpty() || raw == "null") return fallback
        val anchorAt = try {
            val instant = try {
                OffsetDateTime.parse(raw).toInstant()
            } catch (_: DateTimeParseException) {
                LocalDateTime.parse(raw).atZone(ZoneId.systemDefault()).toInstant()
            }
            instant.toEpochMilli()
        } catch (error: DateTimeException) {
            Log.w(TAG, "anchor_time_parse_failed:${error.javaClass.simpleName}")
            return fallback
        } catch (error: ArithmeticException) {
            Log.w(TAG, "anchor_time_out_of_range:${error.javaClass.simpleName}")
            return fallback
        }
        return AssignmentWidgetTimeText.remainingText(
            anchorAtMillis = anchorAt,
            eventKind = item.optString("eventKind", "deadline"),
            nowMillis = System.currentTimeMillis(),
            fallback = fallback,
        )
    }

    private fun normalizeDeepLink(target: String): Uri =
        Uri.parse(AssignmentWidgetLayoutPolicy.normalizeDeepLinkString(target))

    private fun loadItems(prefs: android.content.SharedPreferences): JSONArray {
        val raw = prefs.getString("assignment_snapshot", "[]") ?: "[]"
        return try {
            JSONArray(raw)
        } catch (error: JSONException) {
            Log.w(TAG, "snapshot_parse_failed:${error.javaClass.simpleName}")
            JSONArray()
        }
    }

    companion object {
        private const val TAG = "AssignmentWidgetProvider"
        private const val PREFS_NAME = "HomeWidgetPreferences"

        fun clearForUnauthenticated(context: Context) {
            val saved = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putString("assignment_snapshot", "[]")
                .putBoolean("assignment_authenticated", false)
                .putInt("assignment_total_count", 0)
                .remove("assignment_snapshot_at")
                .commit()
            refreshAll(context)
            check(saved) { "小组件隐私状态保存失败" }
        }

        /**
         * Refreshes every active home-screen instance from saved preferences after
         * package replacement, boot reconciliation, or system time changes.
         */
        fun refreshAll(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context) ?: return
                val ids = manager.getAppWidgetIds(
                    ComponentName(context, AssignmentWidgetProvider::class.java),
                )
                if (ids.isNotEmpty()) {
                    AssignmentWidgetProvider().onUpdate(context, manager, ids)
                }
            } catch (error: RuntimeException) {
                Log.w(TAG, "refresh_failed:${error.javaClass.simpleName}")
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

    fun visibleRowCount(heightDp: Int, fontScale: Float): Int {
        val baseTier = tierForHeightDp(heightDp)
        val safeScale = safeFontScale(fontScale)
        if (safeScale <= 1.05f || heightDp <= 0) return baseTier

        return (baseTier downTo 2).firstOrNull {
            heightDp >= minimumHeightDp(it, safeScale)
        } ?: 1
    }

    fun minimumHeightDp(rows: Int, fontScale: Float): Float {
        val safeScale = safeFontScale(fontScale)
        // Include CJK font padding for both lines and keep the footer clear
        // even when the launcher's density rounds each child's size separately.
        val chromeDp = 35f + 34f * safeScale
        val rowDp = 10f + 40f * safeScale
        return ceil(chromeDp + rows * rowDp)
    }

    private fun safeFontScale(fontScale: Float): Float =
        fontScale.takeIf { it.isFinite() && it > 0f } ?: 1.0f

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
        if (remainingText == "已开考") return false
        return urgencyLevel == "critical" ||
            remainingText.contains("已逾期") ||
            remainingText.contains("已截止")
    }

    fun formatItemMeta(
        deadlineText: String,
        resolvedRemaining: String,
        courseName: String,
        deadlineSource: String = "official",
    ): String {
        val formattedDeadline = if (deadlineSource == "manual") {
            if (deadlineText.isNotEmpty()) "手动 $deadlineText" else "手动"
        } else {
            deadlineText
        }
        return listOf(formattedDeadline, resolvedRemaining, courseName)
            .filter { it.isNotEmpty() }
            .joinToString(" · ")
    }

    fun normalizeDeepLinkString(target: String): String {
        val trimmed = target.trim()
        if (trimmed.isEmpty() || trimmed.any { it.isISOControl() || it.isWhitespace() }) {
            return "studyassistant:///assignments"
        }
        if (trimmed == "studyassistant://assignments" ||
            trimmed == "studyassistant:///assignments"
        ) {
            return "studyassistant:///assignments"
        }
        val twoSlashPrefix = "studyassistant://assignments/"
        if (trimmed.startsWith(twoSlashPrefix)) {
            val suffix = trimmed.removePrefix(twoSlashPrefix)
            if (suffix.isNotEmpty() && suffix != "." && suffix != ".." && !suffix.contains('/')) {
                return "studyassistant:///assignments/$suffix"
            }
            return "studyassistant:///assignments"
        }
        val threeSlashPrefix = "studyassistant:///assignments/"
        if (trimmed.startsWith(threeSlashPrefix)) {
            val suffix = trimmed.removePrefix(threeSlashPrefix)
            if (suffix.isNotEmpty() && suffix != "." && suffix != ".." && !suffix.contains('/')) {
                return trimmed
            }
            return "studyassistant:///assignments"
        }
        return "studyassistant:///assignments"
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
    private const val MILLIS_PER_DAY = 86_400_000L
    private val beijing = ZoneId.of("Asia/Shanghai")

    fun remainingText(
        anchorAtMillis: Long?,
        eventKind: String,
        nowMillis: Long,
        fallback: String,
    ): String {
        if (anchorAtMillis == null) return fallback
        val examStart = eventKind == "examStart"
        val remainingMillis = anchorAtMillis - nowMillis
        if (remainingMillis <= 0) return if (examStart) "已开考" else "已截止"
        val minutes = ceil(remainingMillis / 60000.0).toLong()
        val label = when {
            minutes < 60 -> "${minutes}分钟"
            remainingMillis < MILLIS_PER_DAY -> "${ceil(minutes / 60.0).toLong()}小时"
            else -> {
                val start = Instant.ofEpochMilli(nowMillis).atZone(beijing).toLocalDate()
                val end = Instant.ofEpochMilli(anchorAtMillis).atZone(beijing).toLocalDate()
                "${ChronoUnit.DAYS.between(start, end).coerceAtLeast(1)}天"
            }
        }
        return if (examStart) "距开考 $label" else label
    }
}
