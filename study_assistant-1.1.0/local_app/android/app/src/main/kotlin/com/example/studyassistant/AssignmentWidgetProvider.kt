package com.example.studyassistant

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import kotlin.math.ceil
import org.json.JSONArray
import org.json.JSONObject

class AssignmentWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(appWidgetId, buildViews(context))
        }
    }

    private fun buildViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.assignment_widget)
        val items = loadItems(context)
        if (items.length() == 0) {
            views.setTextViewText(R.id.assignment_title_1, "暂无作业")
            views.setTextViewText(R.id.assignment_meta_1, "打开 App 同步学习通")
            views.setTextViewText(R.id.assignment_title_2, "")
            views.setTextViewText(R.id.assignment_meta_2, "")
        } else {
            val first = items.getJSONObject(0)
            views.setTextViewText(R.id.assignment_title_1, first.optString("title"))
            views.setTextViewText(R.id.assignment_meta_1, itemMeta(first))
            if (items.length() > 1) {
                val second = items.getJSONObject(1)
                views.setTextViewText(R.id.assignment_title_2, second.optString("title"))
                views.setTextViewText(R.id.assignment_meta_2, itemMeta(second))
            } else {
                views.setTextViewText(R.id.assignment_title_2, "")
                views.setTextViewText(R.id.assignment_meta_2, "")
            }
        }

        val target = if (items.length() > 0) {
            items.getJSONObject(0).optString("deepLinkUrl", "studyassistant://assignments")
        } else {
            "studyassistant://assignments"
        }
        val intent = Intent(Intent.ACTION_VIEW, normalizeDeepLink(target)).setPackage(context.packageName)
        val pendingIntent = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.assignment_widget_root, pendingIntent)
        return views
    }

    private fun itemMeta(item: JSONObject): String =
        listOf(item.optString("deadlineText"), remainingText(item), item.optString("courseName"))
            .filter { it.isNotEmpty() }
            .joinToString(" · ")

    private fun remainingText(item: JSONObject): String {
        val raw = item.optString("deadlineAt")
        if (raw.isEmpty() || raw == "null") return item.optString("remainingText")
        return try {
            val instant = try { OffsetDateTime.parse(raw).toInstant() }
                catch (_: Exception) { LocalDateTime.parse(raw).atZone(ZoneId.systemDefault()).toInstant() }
            val minutes = ceil((instant.toEpochMilli() - System.currentTimeMillis()) / 60000.0).toLong()
            when {
                minutes <= 0 -> "已截止"
                minutes < 60 -> "${minutes}分钟"
                minutes < 1440 -> "${ceil(minutes / 60.0).toLong()}小时"
                else -> "${ceil(minutes / 1440.0).toLong()}天"
            }
        } catch (_: Exception) { "截止时间读取失败" }
    }

    private fun normalizeDeepLink(target: String): Uri {
        if (target.startsWith("studyassistant://assignments/")) {
            return Uri.parse(target.replaceFirst("studyassistant://assignments/", "studyassistant:///assignments/"))
        }
        if (target == "studyassistant://assignments") {
            return Uri.parse("studyassistant:///assignments")
        }
        return Uri.parse(target)
    }

    private fun loadItems(context: Context): JSONArray {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("assignment_snapshot", "[]") ?: "[]"
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }
}
