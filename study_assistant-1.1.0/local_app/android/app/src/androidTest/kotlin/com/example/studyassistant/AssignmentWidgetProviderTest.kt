package com.example.studyassistant

import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.os.Process
import android.util.SizeF
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Locale
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        deadlineSource: String? = null,
        eventKind: String = "deadline",
    ): JSONObject = JSONObject().apply {
        put("assignmentId", id)
        put("title", title)
        put("courseName", "高等数学")
        put("deadlineText", "11月20日 23:59")
        put("remainingText", remaining)
        put("urgencyLevel", urgency)
        put("deepLinkUrl", "studyassistant:///assignments/$id")
        put("eventKind", eventKind)
        if (deadlineSource != null) {
            put("deadlineSource", deadlineSource)
        }
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
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                    Configuration.UI_MODE_NIGHT_NO
                fontScale = 1.0f
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
        assertEquals(android.graphics.Color.parseColor("#B5493A"), meta1.currentTextColor)
        assertEquals(android.graphics.Color.parseColor("#4E545C"), meta2.currentTextColor)
        assertEquals(android.graphics.Color.parseColor("#1F2328"), header.currentTextColor)
        assertEquals(View.VISIBLE, footer.visibility)
        assertEquals("还有 4 项未展示 · 点击查看全部", footer.text.toString())
    }

    @Test
    fun largerTextShowingOneRowKeepsTheOverflowCount() {
        val items = JSONArray().apply {
            repeat(6) { index -> put(sampleItem("w$index", "作业 $index")) }
        }
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("assignment_snapshot", items.toString())
            .putInt("assignment_total_count", 7)
            .commit()
        val largeTextContext = context.createConfigurationContext(
            Configuration(context.resources.configuration).apply {
                orientation = Configuration.ORIENTATION_PORTRAIT
                fontScale = 1.5f
            },
        )
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 150)
        }
        val inflated = AssignmentWidgetProvider().buildViews(largeTextContext, options)
            .apply(largeTextContext, FrameLayout(largeTextContext))

        assertEquals(View.VISIBLE, inflated.findViewById<View>(R.id.assignment_row_1).visibility)
        assertEquals(View.GONE, inflated.findViewById<View>(R.id.assignment_row_2).visibility)
        assertEquals("还有 6 项未展示 · 点击查看全部",
            inflated.findViewById<TextView>(R.id.widget_footer).text.toString())
    }

    @Test
    @SdkSuppress(minSdkVersion = 31)
    fun widgetKeepsOverflowVisibleWhenLauncherReportsMoreHeightThanItRenders() {
        val items = JSONArray().apply {
            repeat(6) { index -> put(sampleItem("w$index", "课堂知识点巩固练习 $index")) }
        }
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit().putString("assignment_snapshot", items.toString())
            .putInt("assignment_total_count", 13).commit()
        val provider = AppWidgetManager.getInstance(context)
            .getInstalledProvidersForPackage(context.packageName, Process.myUserHandle())
            .single { it.provider.className == AssignmentWidgetProvider::class.java.name }
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 128)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 323)
            putParcelableArrayList(
                AppWidgetManager.OPTION_APPWIDGET_SIZES,
                arrayListOf(SizeF(264f, 324f), SizeF(467f, 129f)),
            )
        }
        val hostSizes = listOf(320 to SizeF(202f, 247f), 246 to SizeF(264f, 323f))
        for ((dpi, size) in hostSizes) {
            for (scale in listOf(1.0f, 1.5f)) {
                val portrait = context.createConfigurationContext(
                    Configuration(context.resources.configuration).apply {
                        orientation = Configuration.ORIENTATION_PORTRAIT
                        densityDpi = dpi
                        fontScale = scale
                        setLocale(Locale.SIMPLIFIED_CHINESE)
                    },
                )
                val host = AppWidgetHostView(portrait)
                val density = portrait.resources.displayMetrics.density
                val width = (size.width * density).roundToInt()
                val height = (size.height * density).roundToInt()
                InstrumentationRegistry.getInstrumentation().runOnMainSync {
                    host.setAppWidget(5, provider)
                    host.setPadding(0, 0, 0, 0)
                    fun layoutHost() {
                        host.measure(
                            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
                        )
                        host.layout(0, 0, width, height)
                    }
                    layoutHost()
                    host.updateAppWidget(AssignmentWidgetProvider().buildViews(portrait, options))
                    layoutHost()
                }
                val root = host.findViewById<View>(R.id.assignment_widget_root)
                val footer = root.findViewById<TextView>(R.id.widget_footer)
                val visibleRows = listOf(
                    R.id.assignment_row_1, R.id.assignment_row_2, R.id.assignment_row_3,
                    R.id.assignment_row_4, R.id.assignment_row_5, R.id.assignment_row_6,
                ).count { root.findViewById<View>(it)?.visibility == View.VISIBLE }
                val scenario = "size $size, density $dpi, font scale $scale"
                val maxRows = if (scale == 1.0f) 5 else 3
                assertTrue("$scenario must show 1 to $maxRows complete rows", visibleRows in 1..maxRows)
                assertEquals("还有 ${13 - visibleRows} 项未展示 · 点击查看全部", footer.text.toString())
                assertTrue(
                    "$scenario clipped the overflow label at ${footer.bottom} in ${root.height}px",
                    footer.height > 0 && footer.bottom <= root.height - root.paddingBottom,
                )
            }
        }
    }

    @Test
    fun remoteViewsUsesNightPaletteForBaseAndUrgentText() {
        val items = JSONArray().apply {
            put(sampleItem("w1", "紧急作业", urgency = "critical"))
            put(sampleItem("w2", "普通作业"))
        }
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit().putString("assignment_snapshot", items.toString()).commit()
        val night = context.createConfigurationContext(
            Configuration(context.resources.configuration).apply {
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                    Configuration.UI_MODE_NIGHT_YES
                fontScale = 1.0f
            },
        )
        val view = AssignmentWidgetProvider().buildViews(night, Bundle())
            .apply(night, FrameLayout(night))

        assertEquals(android.graphics.Color.parseColor("#EAE6DF"),
            view.findViewById<TextView>(R.id.widget_header).currentTextColor)
        assertEquals(android.graphics.Color.parseColor("#E27D70"),
            view.findViewById<TextView>(R.id.assignment_meta_1).currentTextColor)
        assertEquals(android.graphics.Color.parseColor("#BAB5AC"),
            view.findViewById<TextView>(R.id.assignment_meta_2).currentTextColor)
    }

    @Test
    fun manualSourceLegacyItemsAndStartedExamRenderExpectedCopyAndUrgency() {
        val items = JSONArray().apply {
            put(sampleItem("m1", "手动改期作业", deadlineSource = "manual"))
            put(sampleItem("l1", "旧格式作业", deadlineSource = null))
            put(
                sampleItem(
                    "e1",
                    "跨天考试",
                    urgency = "critical",
                    remaining = "已开考",
                    eventKind = "examStart",
                ),
            )
        }
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit().putString("assignment_snapshot", items.toString()).commit()

        val portrait = context.createConfigurationContext(
            Configuration(context.resources.configuration).apply {
                orientation = Configuration.ORIENTATION_PORTRAIT
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                    Configuration.UI_MODE_NIGHT_NO
                fontScale = 1.0f
            },
        )
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 160)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 180)
        }
        val view = AssignmentWidgetProvider().buildViews(portrait, options)
            .apply(portrait, FrameLayout(portrait))

        assertEquals(
            "手动 11月20日 23:59 · 2天 · 高等数学",
            view.findViewById<TextView>(R.id.assignment_meta_1).text.toString(),
        )
        assertEquals(
            "11月20日 23:59 · 2天 · 高等数学",
            view.findViewById<TextView>(R.id.assignment_meta_2).text.toString(),
        )
        val examMeta = view.findViewById<TextView>(R.id.assignment_meta_3)
        assertEquals("11月20日 23:59 · 已开考 · 高等数学", examMeta.text.toString())
        assertEquals(android.graphics.Color.parseColor("#4E545C"), examMeta.currentTextColor)
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
