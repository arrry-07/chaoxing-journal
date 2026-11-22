package com.example.studyassistant

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

object NativeReminderPolicy {
    const val DAYTIME_START_HOUR = 8

    fun isInDaytimeWindow(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean =
        instant.atZone(zone).hour >= DAYTIME_START_HOUR

    fun nextWindowStart(
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Instant {
        val local = now.atZone(zone)
        val date = local.toLocalDate()
        val today = date.atTime(DAYTIME_START_HOUR, 0).atZone(zone)
        return if (local.isBefore(today)) {
            today.toInstant()
        } else {
            date.plusDays(1).atTime(DAYTIME_START_HOUR, 0).atZone(zone).toInstant()
        }
    }

    /**
     * Moves 00:00–07:59 to 08:00 on the same local date. The caller still has
     * to reject the result if it is at or after the assignment deadline.
     */
    fun moveToDaytime(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant {
        val local = instant.atZone(zone)
        if (local.hour >= DAYTIME_START_HOUR) return instant
        return local.toLocalDate().atTime(DAYTIME_START_HOUR, 0).atZone(zone)
            .toInstant()
    }

    fun notificationTargetAt(
        now: Instant,
        cooldownAt: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Instant {
        val earliest = maxOf(now.plusSeconds(60), cooldownAt)
        return if (isInDaytimeWindow(earliest, zone)) {
            earliest
        } else {
            nextWindowStart(now, zone)
        }
    }

    fun notificationId(eventId: String): Int =
        1_100_000_000 + (eventId.hashCode() and 0x1fffffff)
}
