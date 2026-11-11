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
}
