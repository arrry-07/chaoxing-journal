package com.example.studyassistant

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AssignmentWidgetProviderTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        clearWidgetPrefs()
    }

    @After
    fun tearDown() {
        clearWidgetPrefs()
    }

    private fun clearWidgetPrefs() {
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    private fun sampleItem(
        id: String,
        title: String,
        urgency: String = "normal",
        remaining: String = "2天",
    ): JSONObject = JSONObject().apply {
        put("assignmentId", id)
        put("title", title)
        put("courseName", "高等数学")
        put("deadlineText", "11月20日 23:59")
        put("remainingText", remaining)
        put("urgencyLevel", urgency)
        put("deepLinkUrl", "studyassistant:///assignments/$id")
        put("eventKind", "deadline")
    }

    @Test
    fun legacy1810SnapshotDefaultsToAuthenticatedWithoutFlashingLoggedOut() {
        val items = JSONArray().apply {
            put(sampleItem("w1", "微积分作业1"))
            put(sampleItem("w2", "微积分作业2"))
            put(sampleItem("w3", "微积分作业3"))
        }
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("assignment_snapshot", items.toString())
            .putString("assignment_snapshot_at", "2026-11-18T00:00:00Z")
            .commit()

        val portraitCtx = context.createConfigurationContext(
            Configuration(context.resources.configuration).apply {
                orientation = Configuration.ORIENTATION_PORTRAIT
            },
        )
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 120)
        }
        val views = AssignmentWidgetProvider().buildViews(portraitCtx, options)
        val parent = FrameLayout(portraitCtx)
        val inflated = views.apply(portraitCtx, parent)

        val header = inflated.findViewById<TextView>(R.id.widget_header)
        val footer = inflated.findViewById<TextView>(R.id.widget_footer)
        val row1 = inflated.findViewById<View>(R.id.assignment_row_1)
        val row2 = inflated.findViewById<View>(R.id.assignment_row_2)
        assertNull(inflated.findViewById<View>(R.id.assignment_row_3))

        assertEquals("待完成 3 项", header.text.toString())
        assertEquals(View.VISIBLE, row1.visibility)
        assertEquals(View.VISIBLE, row2.visibility)
        assertEquals(View.VISIBLE, footer.visibility)
        assertEquals("还有 1 项未展示 · 点击查看全部", footer.text.toString())
    }

    @Test
    fun mediumAndLargeTiersInflateCleanlyAndColorUrgentEntriesBerryRed() {
        val items = JSONArray().apply {
            put(sampleItem("w1", "紧急作业", urgency = "critical", remaining = "1小时"))
            put(sampleItem("w2", "普通作业", urgency = "normal", remaining = "3天"))
            put(sampleItem("w3", "已逾期作业", urgency = "normal", remaining = "已逾期"))
        }
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("assignment_snapshot", items.toString())
            .putString("assignment_snapshot_at", "2026-11-18T00:00:00Z")
            .putBoolean("assignment_authenticated", true)
            .putInt("assignment_total_count", 7)
            .putString("assignment_range_label", "7日待办")
            .commit()

        val portraitCtx = context.createConfigurationContext(
            Configuration(context.resources.configuration).apply {
                orientation = Configuration.ORIENTATION_PORTRAIT
            },
        )
        val mediumOptions = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 160)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 180)
        }
        val mediumViews = AssignmentWidgetProvider().buildViews(portraitCtx, mediumOptions)
        val mediumInflated = mediumViews.apply(portraitCtx, FrameLayout(portraitCtx))
        assertNotNull(mediumInflated.findViewById<View>(R.id.assignment_row_4))
        assertNull(mediumInflated.findViewById<View>(R.id.assignment_row_5))
        assertEquals(View.VISIBLE, mediumInflated.findViewById<View>(R.id.assignment_row_3).visibility)
        assertEquals(View.GONE, mediumInflated.findViewById<View>(R.id.assignment_row_4).visibility)
        assertEquals(
            "还有 4 项未展示 · 点击查看全部",
            mediumInflated.findViewById<TextView>(R.id.widget_footer).text.toString(),
        )

        val largeOptions = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 260)
        }
        val views = AssignmentWidgetProvider().buildViews(portraitCtx, largeOptions)
        val inflated = views.apply(portraitCtx, FrameLayout(portraitCtx))

        val header = inflated.findViewById<TextView>(R.id.widget_header)
        val footer = inflated.findViewById<TextView>(R.id.widget_footer)
        val row3 = inflated.findViewById<View>(R.id.assignment_row_3)
        val row4 = inflated.findViewById<View>(R.id.assignment_row_4)
        val row6 = inflated.findViewById<View>(R.id.assignment_row_6)
        val meta1 = inflated.findViewById<TextView>(R.id.assignment_meta_1)
        val meta2 = inflated.findViewById<TextView>(R.id.assignment_meta_2)

        assertNotNull(row6)
        assertEquals("7日待办 7 项", header.text.toString())
        assertEquals(View.VISIBLE, row3.visibility)
        assertEquals(View.GONE, row4.visibility)
        assertEquals(View.GONE, row6.visibility)
        assertEquals(android.graphics.Color.parseColor("#813E53"), meta1.currentTextColor)
        assertEquals(android.graphics.Color.parseColor("#53645A"), meta2.currentTextColor)
        assertEquals(View.VISIBLE, footer.visibility)
        assertEquals("还有 4 项未展示 · 点击查看全部", footer.text.toString())
    }

    @Test
    fun unauthenticatedSnapshotDisplaysLoggedOutGuidanceAndHidesOverflow() {
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("assignment_snapshot", "[]")
            .putBoolean("assignment_authenticated", false)
            .putInt("assignment_total_count", 0)
            .putString("assignment_range_label", "待完成")
            .commit()

        val views = AssignmentWidgetProvider().buildViews(context, Bundle())
        val inflated = views.apply(context, FrameLayout(context))
        assertEquals("课业手记 · 未登录", inflated.findViewById<TextView>(R.id.widget_header).text.toString())
        assertEquals("尚未登录学习通", inflated.findViewById<TextView>(R.id.assignment_title_1).text.toString())
        assertEquals(View.GONE, inflated.findViewById<View>(R.id.assignment_row_2).visibility)
        assertEquals(View.GONE, inflated.findViewById<View>(R.id.widget_footer).visibility)
        AssignmentWidgetProvider.refreshAll(context)
    }
}
