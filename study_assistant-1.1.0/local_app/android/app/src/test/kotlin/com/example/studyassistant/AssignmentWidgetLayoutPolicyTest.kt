package com.example.studyassistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AssignmentWidgetLayoutPolicyTest {
    @Test
    fun effectiveHeightReadsMaxInPortraitAndMinInLandscapeWithFallback() {
        // Android AppWidgetManager stores portrait height in MAX_HEIGHT and landscape height in MIN_HEIGHT.
        assertEquals(
            240,
            AssignmentWidgetLayoutPolicy.effectiveHeightDp(
                isPortrait = true,
                minHeightDp = 120,
                maxHeightDp = 240,
            ),
        )
        assertEquals(
            120,
            AssignmentWidgetLayoutPolicy.effectiveHeightDp(
                isPortrait = false,
                minHeightDp = 120,
                maxHeightDp = 240,
            ),
        )
        assertEquals(
            110,
            AssignmentWidgetLayoutPolicy.effectiveHeightDp(
                isPortrait = true,
                minHeightDp = 110,
                maxHeightDp = 0,
            ),
        )
        assertEquals(
            0,
            AssignmentWidgetLayoutPolicy.effectiveHeightDp(
                isPortrait = false,
                minHeightDp = 0,
                maxHeightDp = 0,
            ),
        )
    }

    @Test
    fun tierForHeightDpSelectsCompactMediumAndLargeAtThresholds() {
        assertEquals(2, AssignmentWidgetLayoutPolicy.tierForHeightDp(0))
        assertEquals(2, AssignmentWidgetLayoutPolicy.tierForHeightDp(144))
        assertEquals(4, AssignmentWidgetLayoutPolicy.tierForHeightDp(145))
        assertEquals(4, AssignmentWidgetLayoutPolicy.tierForHeightDp(229))
        assertEquals(6, AssignmentWidgetLayoutPolicy.tierForHeightDp(230))
        assertEquals(6, AssignmentWidgetLayoutPolicy.tierForHeightDp(360))
    }

    @Test
    fun normalAndInvalidFontScalesKeepTheOriginalHeightTiers() {
        for ((height, expected) in listOf(0 to 2, 144 to 2, 145 to 4, 229 to 4, 230 to 6)) {
            for (scale in listOf(1.0f, Float.NaN, 0f, Float.POSITIVE_INFINITY)) {
                assertEquals(expected, AssignmentWidgetLayoutPolicy.visibleRowCount(height, scale))
            }
        }
    }

    @Test
    fun largerTextFitsFewerRowsAndKeepsAtLeastOneForPositiveHeight() {
        for ((height, moderate, large) in listOf(
            Triple(150, 1, 1),
            Triple(230, 2, 1),
            Triple(300, 3, 2),
        )) {
            assertEquals(moderate, AssignmentWidgetLayoutPolicy.visibleRowCount(height, 1.5f))
            assertEquals(large, AssignmentWidgetLayoutPolicy.visibleRowCount(height, 2.0f))
        }
    }

    @Test
    fun headerAndOverflowCopyReflectAuthRangeAndTotalCount() {
        assertEquals(
            "课业手记 · 未登录",
            AssignmentWidgetLayoutPolicy.headerText(
                authenticated = false,
                rangeLabel = "今日待办",
                totalCount = 4,
            ),
        )
        assertEquals(
            "7日待办 5 项",
            AssignmentWidgetLayoutPolicy.headerText(
                authenticated = true,
                rangeLabel = "7日待办",
                totalCount = 5,
            ),
        )
        assertEquals(
            "还有 3 项未展示 · 点击查看全部",
            AssignmentWidgetLayoutPolicy.overflowText(totalCount = 7, shownCount = 4),
        )
        assertNull(AssignmentWidgetLayoutPolicy.overflowText(totalCount = 4, shownCount = 4))
        assertNull(AssignmentWidgetLayoutPolicy.overflowText(totalCount = 0, shownCount = 0))
    }

    @Test
    fun isUrgentDetectsCriticalOrExpiredEntries() {
        assertTrue(AssignmentWidgetLayoutPolicy.isUrgent("critical", "2小时"))
        assertTrue(AssignmentWidgetLayoutPolicy.isUrgent("normal", "已逾期"))
        assertTrue(AssignmentWidgetLayoutPolicy.isUrgent("unknown", "已截止"))
        assertFalse(AssignmentWidgetLayoutPolicy.isUrgent("critical", "已开考"))
        assertFalse(AssignmentWidgetLayoutPolicy.isUrgent("normal", "已开考"))
        assertFalse(AssignmentWidgetLayoutPolicy.isUrgent("soon", "5小时"))
        assertFalse(AssignmentWidgetLayoutPolicy.isUrgent("normal", "2天"))
    }

    @Test
    fun formatItemMetaMarksManualDeadlinesAndKeepsLegacyCompatible() {
        assertEquals(
            "手动 11月20日 23:59 · 2天 · 高等数学",
            AssignmentWidgetLayoutPolicy.formatItemMeta(
                deadlineText = "11月20日 23:59",
                resolvedRemaining = "2天",
                courseName = "高等数学",
                deadlineSource = "manual",
            ),
        )
        assertEquals(
            "手动 · 2天 · 高等数学",
            AssignmentWidgetLayoutPolicy.formatItemMeta(
                deadlineText = "",
                resolvedRemaining = "2天",
                courseName = "高等数学",
                deadlineSource = "manual",
            ),
        )
        for (source in listOf("official", "", "unknown_future")) {
            assertEquals(
                "11月20日 23:59 · 2天 · 高等数学",
                AssignmentWidgetLayoutPolicy.formatItemMeta(
                    deadlineText = "11月20日 23:59",
                    resolvedRemaining = "2天",
                    courseName = "高等数学",
                    deadlineSource = source,
                ),
            )
        }
    }

    @Test
    fun normalizeDeepLinkStringPreservesAssignmentRouteAndFailSafesInvalidTargets() {
        assertEquals(
            "studyassistant:///assignments/cx%3Awork%3A1%3A2%3A3",
            AssignmentWidgetLayoutPolicy.normalizeDeepLinkString(
                "studyassistant://assignments/cx%3Awork%3A1%3A2%3A3",
            ),
        )
        assertEquals(
            "studyassistant:///assignments/cx%3Awork%3A1%3A2%3A3",
            AssignmentWidgetLayoutPolicy.normalizeDeepLinkString(
                "studyassistant:///assignments/cx%3Awork%3A1%3A2%3A3",
            ),
        )
        for (homeTarget in listOf(
            "studyassistant://assignments",
            "studyassistant:///assignments",
            "",
            "   ",
            "https://evil.invalid/steal",
            "studyassistant://assignments/..",
            "studyassistant:///assignments/a/b",
        )) {
            assertEquals(
                "studyassistant:///assignments",
                AssignmentWidgetLayoutPolicy.normalizeDeepLinkString(homeTarget),
            )
        }
    }

    @Test
    fun legacySnapshotDefaultsToAuthenticatedWaitCountAndDefaultRangeLabel() {
        val meta = AssignmentWidgetLayoutPolicy.resolveSnapshotMeta(
            hasAuthenticatedKey = false,
            rawAuthenticated = false,
            rawRangeLabel = null,
            hasTotalCountKey = false,
            rawTotalCount = null,
            snapshotLength = 3,
        )
        assertTrue(meta.authenticated)
        assertEquals("待完成", meta.rangeLabel)
        assertEquals(3, meta.totalCount)

        val explicit = AssignmentWidgetLayoutPolicy.resolveSnapshotMeta(
            hasAuthenticatedKey = true,
            rawAuthenticated = true,
            rawRangeLabel = "今日待办",
            hasTotalCountKey = true,
            rawTotalCount = 9L,
            snapshotLength = 6,
        )
        assertTrue(explicit.authenticated)
        assertEquals("今日待办", explicit.rangeLabel)
        assertEquals(9, explicit.totalCount)
    }
}
