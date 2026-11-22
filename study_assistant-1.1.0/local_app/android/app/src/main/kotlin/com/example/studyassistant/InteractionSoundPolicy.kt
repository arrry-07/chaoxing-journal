package com.example.studyassistant

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

internal object InteractionSoundPolicy {
    const val SAMPLE_RATE = 48_000

    val PRESET_KINDS = listOf("tap", "pin", "unpin", "syncDone", "complete")

    sealed class VibrationSpec {
        data class OneShot(val durationMs: Long, val amplitude: Int) : VibrationSpec()

        data class Waveform(val timings: LongArray, val repeat: Int = -1) : VibrationSpec() {
            override fun equals(other: Any?): Boolean =
                other is Waveform && timings.contentEquals(other.timings) && repeat == other.repeat

            override fun hashCode(): Int = 31 * timings.contentHashCode() + repeat
        }
    }

    fun presetPcm(kind: String): ShortArray? = when (kind) {
        "tap" -> tone(60, 800.0, 760.0, 16.0, 0.28)
        "pin" -> tone(55, 660.0, 650.0, 18.0, 0.26) +
            tone(80, 880.0, 870.0, 24.0, 0.28)
        "unpin" -> tone(55, 880.0, 870.0, 18.0, 0.26) +
            tone(80, 660.0, 650.0, 24.0, 0.28)
        "syncDone" -> tone(90, 659.25, 659.25, 30.0, 0.24) +
            tone(160, 987.77, 987.77, 55.0, 0.26)
        "complete" -> tone(70, 523.25, 523.25, 22.0, 0.26) +
            tone(110, 784.0, 784.0, 34.0, 0.28)
        else -> null
    }

    fun tone(
        ms: Int,
        startHz: Double,
        endHz: Double,
        tauMs: Double,
        peak: Double,
        partial: Double = 0.04,
        attackMs: Double = 5.0,
    ): ShortArray {
        val count = SAMPLE_RATE * ms / 1000
        if (count <= 0) return ShortArray(0)
        val samples = DoubleArray(count)
        val fadeSamples = SAMPLE_RATE * 0.006
        var phase = 0.0
        for (i in samples.indices) {
            val tMs = i * 1000.0 / SAMPLE_RATE
            val progress = if (count > 1) i.toDouble() / (count - 1) else 0.0
            val hz = startHz + (endHz - startHz) * progress
            phase += 2.0 * PI * hz / SAMPLE_RATE
            val attack = if (attackMs > 0.0 && tMs < attackMs) {
                0.5 * (1.0 - cos(PI * tMs / attackMs))
            } else {
                1.0
            }
            val decay = exp(-tMs / tauMs)
            val release = minOf((count - 1 - i).toDouble() / fadeSamples, 1.0)
            samples[i] = (sin(phase) + partial * sin(2.0 * phase)) *
                attack * decay * release
        }
        val maxSample = samples.maxOf { abs(it) }
        if (maxSample <= 0.0) return ShortArray(count)
        val scale = peak * Short.MAX_VALUE / maxSample
        return ShortArray(count) { (samples[it] * scale).toInt().toShort() }
    }

    fun wav(pcm: ShortArray): ByteArray {
        val bytes = pcm.size * 2
        return ByteBuffer.allocate(44 + bytes).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray())
            putInt(36 + bytes)
            put("WAVEfmt ".toByteArray())
            putInt(16)
            putShort(1) // PCM
            putShort(1) // Mono
            putInt(SAMPLE_RATE)
            putInt(SAMPLE_RATE * 2)
            putShort(2)
            putShort(16)
            put("data".toByteArray())
            putInt(bytes)
            for (sample in pcm) putShort(sample)
        }.array()
    }

    const val RINGER_MODE_NORMAL = 2
    const val AUDIO_MODE_NORMAL = 0
    const val AUDIO_MODE_RINGTONE = 1
    const val AUDIO_MODE_IN_CALL = 2
    const val AUDIO_MODE_IN_COMMUNICATION = 3

    fun shouldPlay(
        hasAudioManager: Boolean,
        streamVolume: Int,
        isStreamMuted: Boolean,
        soundId: Int?,
        readyIds: Set<Int>,
        ringerMode: Int = RINGER_MODE_NORMAL,
        audioMode: Int = AUDIO_MODE_NORMAL,
    ): Boolean {
        if (!hasAudioManager || streamVolume <= 0 || isStreamMuted) return false
        if (ringerMode != RINGER_MODE_NORMAL) return false
        if (audioMode == AUDIO_MODE_RINGTONE ||
            audioMode == AUDIO_MODE_IN_CALL ||
            audioMode == AUDIO_MODE_IN_COMMUNICATION
        ) {
            return false
        }
        return soundId != null && soundId in readyIds
    }

    fun vibrationSpec(kind: String?): VibrationSpec? = when (kind) {
        "tap" -> VibrationSpec.OneShot(30L, 160)
        "pin", "unpin" -> VibrationSpec.OneShot(40L, 200)
        "complete" -> VibrationSpec.OneShot(50L, 200)
        "syncDone" -> VibrationSpec.Waveform(longArrayOf(0, 30, 60, 30), -1)
        else -> null
    }

    fun effectiveAmplitude(
        requested: Int,
        hasAmplitudeControl: Boolean,
        defaultAmplitude: Int,
    ): Int = if (hasAmplitudeControl) requested else defaultAmplitude
}
