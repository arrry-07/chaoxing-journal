package com.example.studyassistant

import android.app.Activity
import android.media.AudioManager.STREAM_MUSIC
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

internal class InteractionSoundBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val audioManager = activity.getSystemService(AudioManager::class.java)
    private val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        activity.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        activity.getSystemService(Vibrator::class.java)
    }
    private val channel = MethodChannel(messenger, "study_assistant/interaction_sound")
    private val pool = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()
    private val ids = mutableMapOf<String, Int>()
    private val ready = mutableSetOf<Int>()

    init {
        pool.setOnLoadCompleteListener { _, id, status ->
            if (status == 0) ready.add(id)
        }
        val cache = activity.cacheDir
        load(cache, "tap", tone(60, 800.0, 760.0, 16.0, 0.28))
        load(
            cache,
            "pin",
            tone(55, 660.0, 650.0, 18.0, 0.26) +
                tone(80, 880.0, 870.0, 24.0, 0.28),
        )
        load(
            cache,
            "unpin",
            tone(55, 880.0, 870.0, 18.0, 0.26) +
                tone(80, 660.0, 650.0, 24.0, 0.28),
        )
        load(
            cache,
            "syncDone",
            tone(90, 659.25, 659.25, 30.0, 0.24) +
                tone(160, 987.77, 987.77, 55.0, 0.26),
        )
        load(
            cache,
            "complete",
            tone(70, 523.25, 523.25, 22.0, 0.26) +
                tone(110, 784.0, 784.0, 34.0, 0.28),
        )

        channel.setMethodCallHandler { call, result ->
            if (call.method == "feedback") {
                val kind = call.argument<String>("kind")
                if (call.argument<Boolean>("sound") == true) runCatching { play(kind) }
                if (call.argument<Boolean>("haptics") == true) vibrate(kind)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun play(kind: String?) {
        if (audioManager == null ||
            audioManager.getStreamVolume(STREAM_MUSIC) <= 0 ||
            audioManager.isStreamMute(STREAM_MUSIC)) return
        val id = ids[kind] ?: return
        if (id in ready) pool.play(id, 0.55f, 0.55f, 1, 0, 1.0f)
    }

    @Suppress("DEPRECATION")
    private fun vibrate(kind: String?) {
        val (duration, amplitude) = when (kind) {
            "tap" -> 30L to 160
            "pin", "unpin" -> 40L to 200
            "complete" -> 50L to 200
            "syncDone" -> 0L to 0
            else -> return
        }
        val motor = vibrator
        val requested = runCatching {
            if (motor == null || !motor.hasVibrator()) return@runCatching false
            val effect = if (kind == "syncDone") {
                VibrationEffect.createWaveform(longArrayOf(0, 30, 60, 30), -1)
            } else {
                VibrationEffect.createOneShot(
                    duration,
                    if (motor.hasAmplitudeControl()) amplitude else VibrationEffect.DEFAULT_AMPLITUDE,
                )
            }
            motor.vibrate(effect)
            true
        }.getOrDefault(false)
        if (!requested) {
            activity.window.decorView.performHapticFeedback(
                HapticFeedbackConstants.KEYBOARD_TAP,
                HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING,
            )
        }
    }

    private fun load(cache: File, kind: String, pcm: ShortArray) {
        // SoundPool opens the file when load is called and decodes it asynchronously.
        // Keep no bundled audio assets or persistent files.
        runCatching {
            val file = File.createTempFile("journal-sfx-", ".wav", cache)
            try {
                file.writeBytes(wav(pcm))
                val id = pool.load(file.absolutePath, 1)
                if (id != 0) ids[kind] = id
            } finally {
                file.delete()
            }
        }
    }

    private fun wav(pcm: ShortArray): ByteArray {
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

    private fun tone(
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

    fun close() {
        channel.setMethodCallHandler(null)
        pool.setOnLoadCompleteListener(null)
        pool.release()
    }

    companion object {
        private const val SAMPLE_RATE = 48_000
    }
}
