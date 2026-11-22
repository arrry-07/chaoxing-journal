package com.example.studyassistant

import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

object DeadlineQuietHoursPolicy {
    private const val QUIET_START_MINUTE = 23 * 60 + 30
    private const val QUIET_END_MINUTE = 7 * 60 + 30
    private const val PRE_NIGHT_HOUR = 22
    private const val PRE_NIGHT_MINUTE = 30
    const val URGENT_BREAKTHROUGH_MAX_MINUTES = 60L

    enum class DeliveryDecision {
        DELIVER,
        DEFER_TO_QUIET_END,
        SUPPRESS_LATE_QUIET,
        CANCEL_DEADLINE_PASSED,
        BLOCK_MISSING_SOURCE,
    }

    data class DeliveryEvaluation(
        val decision: DeliveryDecision,
        val deferredAt: Instant? = null,
    )

    fun isTrustedSource(source: String?): Boolean =
        source == "official" || source == "manual"

    fun isQuiet(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        val local = instant.atZone(zone)
        val minuteOfDay = local.hour * 60 + local.minute
        return minuteOfDay >= QUIET_START_MINUTE || minuteOfDay < QUIET_END_MINUTE
    }

    fun isInAudibleNewWindow(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean =
        NativeReminderPolicy.isInDaytimeWindow(instant, zone) && !isQuiet(instant, zone)

    fun nextAudibleNewWindowStart(now: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant =
        maxOf(NativeReminderPolicy.nextWindowStart(now, zone), nextQuietEnd(now, zone))

    fun nextQuietEnd(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant {
        val local = instant.atZone(zone)
        val minuteOfDay = local.hour * 60 + local.minute
        val awakeTime = LocalTime.of(7, 30)
        return when {
            minuteOfDay >= QUIET_START_MINUTE ->
                local.toLocalDate().plusDays(1).atTime(awakeTime).atZone(zone).toInstant()
            minuteOfDay < QUIET_END_MINUTE ->
                local.toLocalDate().atTime(awakeTime).atZone(zone).toInstant()
            else -> instant
        }
    }

    fun canBreakThroughQuiet(
        notifyAt: Instant,
        deadlineAt: Instant,
        deadlineSource: String?,
        allowUrgentNightBreakthrough: Boolean,
    ): Boolean {
        if (!allowUrgentNightBreakthrough || !isTrustedSource(deadlineSource)) {
            return false
        }
        val remaining = Duration.between(notifyAt, deadlineAt)
        return !remaining.isNegative &&
            !remaining.isZero &&
            remaining <= Duration.ofMinutes(URGENT_BREAKTHROUGH_MAX_MINUTES)
    }

    fun preNightWarningAt(
        deadlineAt: Instant,
        now: Instant,
        eventKind: String,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Instant? {
        if (eventKind != "deadline" || !isQuiet(deadlineAt, zone)) {
            return null
        }
        val local = deadlineAt.atZone(zone)
        val minuteOfDay = local.hour * 60 + local.minute
        val targetDate = if (minuteOfDay >= QUIET_START_MINUTE) {
            local.toLocalDate()
        } else {
            local.toLocalDate().minusDays(1)
        }
        val preNight = targetDate
            .atTime(LocalTime.of(PRE_NIGHT_HOUR, PRE_NIGHT_MINUTE))
            .atZone(zone)
            .toInstant()
        return if (preNight.isAfter(now) && preNight.isBefore(deadlineAt)) {
            preNight
        } else {
            null
        }
    }

    fun evaluateDeadlineDelivery(
        now: Instant,
        scheduledNotifyAt: Instant,
        deadlineAt: Instant?,
        deadlineSource: String?,
        allowUrgentNightBreakthrough: Boolean,
        zone: ZoneId = ZoneId.systemDefault(),
    ): DeliveryEvaluation {
        if (deadlineAt == null || !deadlineAt.isAfter(now)) {
            return DeliveryEvaluation(DeliveryDecision.CANCEL_DEADLINE_PASSED)
        }
        if (!isTrustedSource(deadlineSource)) {
            return DeliveryEvaluation(DeliveryDecision.BLOCK_MISSING_SOURCE)
        }
        if (!isQuiet(now, zone)) {
            return DeliveryEvaluation(DeliveryDecision.DELIVER)
        }
        if (canBreakThroughQuiet(now, deadlineAt, deadlineSource, allowUrgentNightBreakthrough)) {
            return DeliveryEvaluation(DeliveryDecision.DELIVER)
        }
        if (!isQuiet(scheduledNotifyAt, zone)) {
            return DeliveryEvaluation(DeliveryDecision.SUPPRESS_LATE_QUIET)
        }
        val nextAwake = nextQuietEnd(now, zone)
        return if (nextAwake.isBefore(deadlineAt)) {
            DeliveryEvaluation(DeliveryDecision.DEFER_TO_QUIET_END, deferredAt = nextAwake)
        } else {
            DeliveryEvaluation(DeliveryDecision.CANCEL_DEADLINE_PASSED)
        }
    }

    fun recomputeEarliestSlot(
        deadlineAt: Instant,
        now: Instant,
        offsets: List<Int>,
        deadlineSource: String?,
        eventKind: String,
        allowUrgentNightBreakthrough: Boolean,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Instant? {
        if (!isTrustedSource(deadlineSource) || !deadlineAt.isAfter(now)) {
            return null
        }
        val candidates = mutableListOf<Instant>()
        for (offset in offsets) {
            if (offset <= 0) continue
            val raw = deadlineAt.minusSeconds(offset.toLong() * 60L)
            val shifted = if (isQuiet(raw, zone) &&
                !canBreakThroughQuiet(raw, deadlineAt, deadlineSource, allowUrgentNightBreakthrough)
            ) {
                nextQuietEnd(raw, zone)
            } else {
                raw
            }
            if (shifted.isAfter(now) && shifted.isBefore(deadlineAt)) {
                candidates.add(shifted)
            }
        }
        preNightWarningAt(deadlineAt, now, eventKind, zone)?.let(candidates::add)
        return candidates.minOrNull()
    }
}
