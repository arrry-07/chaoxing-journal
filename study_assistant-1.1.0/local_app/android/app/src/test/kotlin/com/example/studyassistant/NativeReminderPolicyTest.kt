package com.example.studyassistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

class NativeReminderPolicyTest {
    private val zone = ZoneId.of("Asia/Shanghai")

    @Test
    fun windowUsesInclusiveEightAndExclusiveMidnight() {
        assertFalse(NativeReminderPolicy.isInDaytimeWindow(
            ZonedDateTime.of(2026, 11, 11, 7, 59, 59, 0, zone).toInstant(),
            zone,
        ))
        assertTrue(NativeReminderPolicy.isInDaytimeWindow(
            ZonedDateTime.of(2026, 11, 11, 8, 0, 0, 0, zone).toInstant(),
            zone,
        ))
        assertTrue(NativeReminderPolicy.isInDaytimeWindow(
            ZonedDateTime.of(2026, 11, 11, 23, 59, 59, 0, zone).toInstant(),
            zone,
        ))
        assertFalse(NativeReminderPolicy.isInDaytimeWindow(
            ZonedDateTime.of(2026, 11, 12, 0, 0, 0, 0, zone).toInstant(),
            zone,
        ))
    }

    @Test
    fun zoneDeterminesWhetherTheSameInstantIsInTheDaytimeWindow() {
        val utc = ZoneId.of("UTC")
        val beforeEight = Instant.parse("2026-11-10T23:59:00Z")
        val atEight = Instant.parse("2026-11-11T00:00:00Z")
        val lateEvening = Instant.parse("2026-11-11T15:59:00Z")

        assertFalse(NativeReminderPolicy.isInDaytimeWindow(beforeEight, zone))
        assertTrue(NativeReminderPolicy.isInDaytimeWindow(beforeEight, utc))
        assertTrue(NativeReminderPolicy.isInDaytimeWindow(atEight, zone))
        assertFalse(NativeReminderPolicy.isInDaytimeWindow(atEight, utc))
        assertTrue(NativeReminderPolicy.isInDaytimeWindow(lateEvening, zone))
    }

    @Test
    fun earlyAlarmMovesToEightOnTheSameLocalDate() {
        val input = ZonedDateTime.of(2026, 11, 12, 3, 15, 0, 0, zone).toInstant()
        val result = NativeReminderPolicy.moveToDaytime(input, zone)
        assertEquals(
            ZonedDateTime.of(2026, 11, 12, 8, 0, 0, 0, zone).toInstant(),
            result,
        )
    }

    @Test
    fun daytimeAlarmIsUnchanged() {
        val input = ZonedDateTime.of(2026, 11, 12, 8, 30, 0, 0, zone).toInstant()
        assertEquals(input, NativeReminderPolicy.moveToDaytime(input, zone))
    }

    @Test
    fun nextWindowStartHandlesBeforeAndAfterEight() {
        assertEquals(
            ZonedDateTime.of(2026, 11, 11, 8, 0, 0, 0, zone).toInstant(),
            NativeReminderPolicy.nextWindowStart(
                ZonedDateTime.of(2026, 11, 11, 3, 0, 0, 0, zone).toInstant(),
                zone,
            ),
        )
        assertEquals(
            ZonedDateTime.of(2026, 11, 12, 8, 0, 0, 0, zone).toInstant(),
            NativeReminderPolicy.nextWindowStart(
                Instant.parse("2026-11-11T15:00:00Z"),
                zone,
            ),
        )
    }

    @Test
    fun notificationSignalAtNightWaitsForNextDaytimeWindow() {
        val now = ZonedDateTime.of(2026, 11, 12, 3, 0, 0, 0, zone).toInstant()
        val cooldown = now.plusSeconds(5 * 60)

        assertEquals(
            ZonedDateTime.of(2026, 11, 12, 8, 0, 0, 0, zone).toInstant(),
            NativeReminderPolicy.notificationTargetAt(now, cooldown, zone),
        )
    }

    @Test
    fun notificationSignalPastMidnightWaitsForFollowingWindow() {
        val now = ZonedDateTime.of(2026, 11, 11, 23, 59, 0, 0, zone).toInstant()
        val cooldown = now.plusSeconds(2 * 60)

        assertEquals(
            ZonedDateTime.of(2026, 11, 12, 8, 0, 0, 0, zone).toInstant(),
            NativeReminderPolicy.notificationTargetAt(now, cooldown, zone),
        )
    }

    @Test
    fun daytimeNotificationSignalKeepsMergeDelay() {
        val now = ZonedDateTime.of(2026, 11, 12, 14, 0, 0, 0, zone).toInstant()
        val cooldown = now.plusSeconds(60)

        assertEquals(
            now.plusSeconds(60),
            NativeReminderPolicy.notificationTargetAt(now, cooldown, zone),
        )
    }

    @Test
    fun notificationIdentityIsStableAndAppScoped() {
        assertEquals(
            NativeReminderPolicy.notificationId("account|assignment|new"),
            NativeReminderPolicy.notificationId("account|assignment|new"),
        )
        assertTrue(
            NativeReminderPolicy.notificationId("account|assignment|new") >=
                1_100_000_000,
        )
    }

    @Test
    fun quietHoursExactBoundariesAcrossUtcShanghaiAndLosAngelesDst() {
        for (zoneId in listOf("UTC", "Asia/Shanghai", "America/Los_Angeles")) {
            val z = ZoneId.of(zoneId)
            for (date in listOf(
                java.time.LocalDate.of(2026, 3, 8),
                java.time.LocalDate.of(2026, 11, 1),
            )) {
                assertFalse(
                    DeadlineQuietHoursPolicy.isQuiet(
                        ZonedDateTime.of(date.year, date.monthValue, date.dayOfMonth, 23, 29, 0, 0, z).toInstant(),
                        z,
                    ),
                )
                assertTrue(
                    DeadlineQuietHoursPolicy.isQuiet(
                        ZonedDateTime.of(date.year, date.monthValue, date.dayOfMonth, 23, 30, 0, 0, z).toInstant(),
                        z,
                    ),
                )
                assertTrue(
                    DeadlineQuietHoursPolicy.isQuiet(
                        ZonedDateTime.of(date.year, date.monthValue, date.dayOfMonth, 7, 29, 0, 0, z).toInstant(),
                        z,
                    ),
                )
                assertFalse(
                    DeadlineQuietHoursPolicy.isQuiet(
                        ZonedDateTime.of(date.year, date.monthValue, date.dayOfMonth, 7, 30, 0, 0, z).toInstant(),
                        z,
                    ),
                )
                assertEquals(
                    ZonedDateTime.of(date.plusDays(1), java.time.LocalTime.of(7, 30), z).toInstant(),
                    DeadlineQuietHoursPolicy.nextQuietEnd(
                        ZonedDateTime.of(date, java.time.LocalTime.of(23, 30), z).toInstant(),
                        z,
                    ),
                )
                assertEquals(
                    ZonedDateTime.of(date, java.time.LocalTime.of(7, 30), z).toInstant(),
                    DeadlineQuietHoursPolicy.nextQuietEnd(
                        ZonedDateTime.of(date, java.time.LocalTime.of(7, 29), z).toInstant(),
                        z,
                    ),
                )
            }
        }
    }

    @Test
    fun deadlineDeliveryReCheckSuppressesLateQuietBlocksUnknownAndHonorsBreakthrough() {
        val shanghai = ZoneId.of("Asia/Shanghai")
        val deadline = ZonedDateTime.of(2026, 11, 21, 0, 30, 0, 0, shanghai).toInstant()
        val quietNow = ZonedDateTime.of(2026, 11, 21, 0, 0, 0, 0, shanghai).toInstant()
        val lateScheduledDaytime = ZonedDateTime.of(2026, 11, 20, 22, 30, 0, 0, shanghai).toInstant()

        assertEquals(
            DeadlineQuietHoursPolicy.DeliveryDecision.BLOCK_MISSING_SOURCE,
            DeadlineQuietHoursPolicy.evaluateDeadlineDelivery(
                now = quietNow,
                scheduledNotifyAt = quietNow,
                deadlineAt = deadline,
                deadlineSource = "unknown",
                allowUrgentNightBreakthrough = true,
                zone = shanghai,
            ).decision,
        )

        assertEquals(
            DeadlineQuietHoursPolicy.DeliveryDecision.SUPPRESS_LATE_QUIET,
            DeadlineQuietHoursPolicy.evaluateDeadlineDelivery(
                now = quietNow,
                scheduledNotifyAt = lateScheduledDaytime,
                deadlineAt = deadline,
                deadlineSource = "official",
                allowUrgentNightBreakthrough = false,
                zone = shanghai,
            ).decision,
        )

        assertEquals(
            DeadlineQuietHoursPolicy.DeliveryDecision.DELIVER,
            DeadlineQuietHoursPolicy.evaluateDeadlineDelivery(
                now = quietNow,
                scheduledNotifyAt = lateScheduledDaytime,
                deadlineAt = deadline,
                deadlineSource = "manual",
                allowUrgentNightBreakthrough = true,
                zone = shanghai,
            ).decision,
        )

        val quietNotify = ZonedDateTime.of(2026, 11, 20, 23, 34, 0, 0, shanghai)
        assertTrue(
            DeadlineQuietHoursPolicy.canBreakThroughQuiet(
                notifyAt = quietNotify.toInstant(),
                deadlineAt = quietNotify.plusMinutes(60).toInstant(),
                deadlineSource = "official",
                allowUrgentNightBreakthrough = true,
            ),
        )
        assertFalse(
            DeadlineQuietHoursPolicy.canBreakThroughQuiet(
                notifyAt = quietNotify.toInstant(),
                deadlineAt = quietNotify.plusMinutes(61).toInstant(),
                deadlineSource = "official",
                allowUrgentNightBreakthrough = true,
            ),
        )

        val quietScheduled = ZonedDateTime.of(2026, 11, 21, 2, 0, 0, 0, shanghai).toInstant()
        val noonDeadline = ZonedDateTime.of(2026, 11, 21, 12, 0, 0, 0, shanghai).toInstant()
        val deferred = DeadlineQuietHoursPolicy.evaluateDeadlineDelivery(
            now = quietScheduled,
            scheduledNotifyAt = quietScheduled,
            deadlineAt = noonDeadline,
            deadlineSource = "official",
            allowUrgentNightBreakthrough = false,
            zone = shanghai,
        )
        assertEquals(DeadlineQuietHoursPolicy.DeliveryDecision.DEFER_TO_QUIET_END, deferred.decision)
        assertEquals(
            ZonedDateTime.of(2026, 11, 21, 7, 30, 0, 0, shanghai).toInstant(),
            deferred.deferredAt,
        )
    }

    @Test
    fun recomputeForTimezoneChangeAppliesQuietShiftAndPreNight() {
        val la = ZoneId.of("America/Los_Angeles")
        val now = ZonedDateTime.of(2026, 11, 1, 18, 0, 0, 0, la).toInstant()
        val earlyNextDay = ZonedDateTime.of(2026, 11, 2, 1, 0, 0, 0, la).toInstant()

        val earliest = DeadlineQuietHoursPolicy.recomputeEarliestSlot(
            deadlineAt = earlyNextDay,
            now = now,
            offsets = listOf(30),
            deadlineSource = "official",
            eventKind = "deadline",
            allowUrgentNightBreakthrough = false,
            zone = la,
        )
        assertEquals(
            ZonedDateTime.of(2026, 11, 1, 22, 30, 0, 0, la).toInstant(),
            earliest,
        )
    }
}
