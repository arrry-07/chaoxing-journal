package com.example.studyassistant

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sin

internal object InteractionSoundPolicy {
    const val SAMPLE_RATE = 48_000

    enum class ChipWave {
        SQUARE,
        TRIANGLE,
    }

    val PRESET_KINDS = listOf(
        "tap",
        "pin",
        "unpin",
        "syncDone",
        "complete",
        "clawdJump",
        "clawdCombo2",
        "clawdCombo3",
        "clawdPet",
        "clawdGrab",
        "clawdLand",
        "clawdCheer",
        "clawdSyncTick",
    )

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
        "clawdJump" -> chipNote(
            ms = 75,
            startHz = 440.0,
            endHz = 880.0,
            peak = 0.24,
            wave = ChipWave.SQUARE,
            duty = 0.25,
            exponentialSlide = true,
        )
        "clawdCombo2" -> chipNote(
            ms = 55,
            startHz = 523.25,
            endHz = 523.25,
            peak = 0.23,
            wave = ChipWave.SQUARE,
            duty = 0.25,
        ) + chipNote(
            ms = 55,
            startHz = 659.25,
            endHz = 659.25,
            peak = 0.25,
            wave = ChipWave.SQUARE,
            duty = 0.25,
        )
        "clawdCombo3" -> chipNote(
            ms = 50,
            startHz = 523.25,
            endHz = 523.25,
            peak = 0.22,
            wave = ChipWave.SQUARE,
            duty = 0.25,
        ) + chipNote(
            ms = 50,
            startHz = 659.25,
            endHz = 659.25,
            peak = 0.24,
            wave = ChipWave.SQUARE,
            duty = 0.25,
        ) + chipNote(
            ms = 55,
            startHz = 880.0,
            endHz = 880.0,
            peak = 0.26,
            wave = ChipWave.SQUARE,
            duty = 0.25,
        )
        "clawdPet" -> chipNote(
            ms = 75,
            startHz = 440.0,
            endHz = 493.88,
            peak = 0.21,
            wave = ChipWave.TRIANGLE,
        ) + chipNote(
            ms = 75,
            startHz = 587.33,
            endHz = 659.25,
            peak = 0.23,
            wave = ChipWave.TRIANGLE,
        )
        "clawdGrab" -> chipNote(
            ms = 85,
            startHz = 392.0,
            endHz = 932.33,
            peak = 0.24,
            wave = ChipWave.SQUARE,
            duty = 0.25,
            exponentialSlide = true,
        )
        "clawdLand" -> chipNote(
            ms = 70,
            startHz = 329.63,
            endHz = 130.81,
            peak = 0.25,
            wave = ChipWave.TRIANGLE,
            exponentialSlide = true,
        )
        "clawdCheer" -> chipNote(
            ms = 60,
            startHz = 523.25,
            endHz = 523.25,
            peak = 0.23,
            wave = ChipWave.SQUARE,
            duty = 0.25,
        ) + chipNote(
            ms = 65,
            startHz = 659.25,
            endHz = 659.25,
            peak = 0.24,
            wave = ChipWave.SQUARE,
            duty = 0.25,
        ) + chipNote(
            ms = 85,
            startHz = 783.99,
            endHz = 1046.50,
            peak = 0.26,
            wave = ChipWave.TRIANGLE,
            exponentialSlide = true,
        )
        "clawdSyncTick" -> chipNote(
            ms = 28,
            startHz = 740.0,
            endHz = 620.0,
            peak = 0.14,
            wave = ChipWave.TRIANGLE,
            fadeMs = 4.0,
        )
        else -> null
    }

    fun chipNote(
        ms: Int,
        startHz: Double,
        endHz: Double,
        peak: Double,
        wave: ChipWave = ChipWave.SQUARE,
        duty: Double = 0.25,
        exponentialSlide: Boolean = false,
        fadeMs: Double = 5.0,
    ): ShortArray {
        val count = SAMPLE_RATE * ms / 1000
        if (count <= 0) return ShortArray(0)
        if (count <= 2) return ShortArray(count)
        val samples = DoubleArray(count)
        val clampedFadeMs = fadeMs.coerceIn(4.0, 6.0)
        val fadeSamples = minOf(SAMPLE_RATE * clampedFadeMs / 1000.0, (count - 1) / 2.0)
        val clampedDuty = duty.coerceIn(0.05, 0.95)
        var phase = 0.0
        for (i in 1 until count - 1) {
            val progress = i.toDouble() / (count - 1)
            val hz = if (exponentialSlide && startHz > 0.0 && endHz > 0.0) {
                startHz * (endHz / startHz).pow(progress)
            } else {
                startHz + (endHz - startHz) * progress
            }
            phase = (phase + hz / SAMPLE_RATE) % 1.0
            val raw = when (wave) {
                ChipWave.SQUARE -> if (phase < clampedDuty) 1.0 else -1.0
                ChipWave.TRIANGLE -> if (phase < 0.5) 4.0 * phase - 1.0 else 3.0 - 4.0 * phase
            }
            val attack = if (fadeSamples > 0.0 && i < fadeSamples) {
                0.5 * (1.0 - cos(PI * i / fadeSamples))
            } else {
                1.0
            }
            val distFromEnd = count - 1 - i
            val release = if (fadeSamples > 0.0 && distFromEnd < fadeSamples) {
                0.5 * (1.0 - cos(PI * distFromEnd / fadeSamples))
            } else {
                1.0
            }
            samples[i] = raw * attack * release
        }
        val maxSample = samples.maxOf { abs(it) }
        if (maxSample <= 0.0) return ShortArray(count)
        val scale = peak * Short.MAX_VALUE / maxSample
        return ShortArray(count) { idx ->
            if (idx == 0 || idx == count - 1) 0 else (samples[idx] * scale).toInt().toShort()
        }
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

    fun playVolume(kind: String?): Float = when (kind) {
        "clawdSyncTick" -> 0.22f
        "clawdJump",
        "clawdCombo2",
        "clawdCombo3",
        "clawdPet",
        "clawdGrab",
        "clawdLand",
        "clawdCheer",
        -> 0.48f
        else -> 0.55f
    }

    fun vibrationSpec(kind: String?): VibrationSpec? = when (kind) {
        "tap" -> VibrationSpec.OneShot(30L, 160)
        "pin", "unpin" -> VibrationSpec.OneShot(40L, 200)
        "complete" -> VibrationSpec.OneShot(50L, 200)
        "syncDone" -> VibrationSpec.Waveform(longArrayOf(0, 30, 60, 30), -1)
        "clawdJump" -> VibrationSpec.OneShot(22L, 130)
        "clawdCombo2" -> VibrationSpec.OneShot(26L, 150)
        "clawdCombo3" -> VibrationSpec.Waveform(longArrayOf(0, 20, 35, 28), -1)
        "clawdPet" -> VibrationSpec.OneShot(32L, 110)
        "clawdGrab" -> VibrationSpec.OneShot(28L, 160)
        "clawdLand" -> VibrationSpec.OneShot(30L, 175)
        "clawdCheer" -> VibrationSpec.OneShot(40L, 185)
        "clawdSyncTick" -> null
        else -> null
    }

    fun effectiveAmplitude(
        requested: Int,
        hasAmplitudeControl: Boolean,
        defaultAmplitude: Int,
    ): Int = if (hasAmplitudeControl) requested else defaultAmplitude
}
