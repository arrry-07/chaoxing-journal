package com.example.studyassistant

import org.junit.Assert.assertEquals
import org.junit.Test

class AssignmentWidgetTimeTextTest {
    private val now = 1_000_000_000L
    private val minute = 60_000L
    private val hour = 60 * minute

    @Test
    fun examBeforeOpeningShowsOpeningCountdown() {
        assertEquals(
            "距开考 2小时",
            AssignmentWidgetTimeText.remainingText(
                anchorAtMillis = now + 90 * minute,
                eventKind = "examStart",
                nowMillis = now,
                fallback = "考试时间未知",
            ),
        )
    }

    @Test
    fun examAtAndAfterOpeningShowsOpened() {
        for (anchor in listOf(now, now - minute)) {
            assertEquals(
                "已开考",
                AssignmentWidgetTimeText.remainingText(
                    anchorAtMillis = anchor,
                    eventKind = "examStart",
                    nowMillis = now,
                    fallback = "考试时间未知",
                ),
            )
        }
    }

    @Test
    fun assignmentKeepsDeadlineCountdownAndExpiredText() {
        assertEquals(
            "30分钟",
            AssignmentWidgetTimeText.remainingText(
                anchorAtMillis = now + 30 * minute,
                eventKind = "deadline",
                nowMillis = now,
                fallback = "截止时间待确认",
            ),
        )
        assertEquals(
            "已截止",
            AssignmentWidgetTimeText.remainingText(
                anchorAtMillis = now,
                eventKind = "deadline",
                nowMillis = now,
                fallback = "截止时间待确认",
            ),
        )
    }

    @Test
    fun missingOrUnknownKindUsesExistingFallbackAndDeadlineSemantics() {
        assertEquals(
            "考试时间未知",
            AssignmentWidgetTimeText.remainingText(
                anchorAtMillis = null,
                eventKind = "examStart",
                nowMillis = now,
                fallback = "考试时间未知",
            ),
        )
        assertEquals(
            "2小时",
            AssignmentWidgetTimeText.remainingText(
                anchorAtMillis = now + 2 * hour,
                eventKind = "unsupported",
                nowMillis = now,
                fallback = "截止时间待确认",
            ),
        )
    }

    @Test
    fun crossDayInProgressExamAndDeadlineBoundaryTransitionCleanly() {
        assertEquals(
            "已开考",
            AssignmentWidgetTimeText.remainingText(
                anchorAtMillis = now - 3 * hour,
                eventKind = "examStart",
                nowMillis = now,
                fallback = "考试时间未知",
            ),
        )
        assertEquals(
            "30分钟",
            AssignmentWidgetTimeText.remainingText(
                anchorAtMillis = now + 30 * minute,
                eventKind = "deadline",
                nowMillis = now,
                fallback = "截止时间待确认",
            ),
        )
        assertEquals(
            "已截止",
            AssignmentWidgetTimeText.remainingText(
                anchorAtMillis = now - 5 * minute,
                eventKind = "deadline",
                nowMillis = now,
                fallback = "截止时间待确认",
            ),
        )
    }
}
