package com.example.studyassistant

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
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
        listOf(item.optString("deadlineText"), item.optString("remainingText"), item.optString("courseName"))
            .filter { it.isNotEmpty() }
            .joinToString(" · ")

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
