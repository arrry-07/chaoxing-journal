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
        load(cache, "tap", resonance(18, 260.0, 130.0, 0.24))
        load(cache, "pin",
            resonance(12, 220.0, 245.0, 0.22) + resonance(20, 270.0, 340.0, 0.27))
        load(cache, "unpin",
            resonance(12, 320.0, 275.0, 0.22) + resonance(20, 245.0, 200.0, 0.25))
        load(cache, "syncDone",
            resonance(42, 523.25, 523.25, 0.23, 0.08) +
                resonance(48, 659.25, 659.25, 0.24, 0.08))
        load(cache, "complete",
            resonance(23, 293.66, 293.66, 0.22) + resonance(32, 392.0, 392.0, 0.25))

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
        if (audioManager?.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
            audioManager.getStreamVolume(STREAM_MUSIC) <= 0 ||
            audioManager.isStreamMute(STREAM_MUSIC)) return
        val id = ids[kind] ?: return
        if (id in ready) pool.play(id, 0.9f, 0.9f, 1, 0, 1.0f)
    }

    @Suppress("DEPRECATION")
    private fun vibrate(kind: String?) {
        val (duration, amplitude) = when (kind) {
            "tap" -> 12L to 90
            "pin", "unpin", "syncDone" -> 18L to 125
            "complete" -> 23L to 150
            else -> return
        }
        val motor = vibrator
        val requested = runCatching {
            if (motor == null || !motor.hasVibrator()) return@runCatching false
            motor.vibrate(VibrationEffect.createOneShot(
                duration, if (motor.hasAmplitudeControl()) amplitude else VibrationEffect.DEFAULT_AMPLITUDE,
            ))
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

    private fun resonance(
        ms: Int,
        startHz: Double,
        endHz: Double,
        peak: Double,
        harmonic: Double = 0.0,
    ): ShortArray {
        val count = SAMPLE_RATE * ms / 1000
        val samples = DoubleArray(count)
        val lowPass = 1.0 - exp(-2.0 * PI * 850.0 / SAMPLE_RATE)
        var phase = 0.0
        var filtered = 0.0
        for (i in samples.indices) {
            val seconds = i.toDouble() / SAMPLE_RATE
            val progress = i.toDouble() / (count - 1)
            val frequency = startHz + (endHz - startHz) * progress
            phase += 2.0 * PI * frequency / SAMPLE_RATE
            val attack = minOf(seconds / 0.0015, 1.0)
            val tail = minOf((1.0 - progress) / 0.19, 1.0)
            val body = (sin(phase) + harmonic * sin(2.0 * phase)) *
                exp(-18.0 * seconds - 3.2 * progress)
            val contact = if (seconds < 0.004) {
                0.24 * sin(2.0 * PI * 320.0 * seconds) *
                    (1.0 - seconds / 0.004) * exp(-550.0 * seconds)
            } else 0.0
            filtered += lowPass * (attack * (body + contact) - filtered)
            samples[i] = filtered * tail
        }
        val scale = peak * Short.MAX_VALUE / samples.maxOf { abs(it) }
        return ShortArray(count) { (samples[it] * scale).toInt().toShort() }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pool.setOnLoadCompleteListener(null)
        pool.release()
    }

    companion object {
        private const val SAMPLE_RATE = 44_100
    }
}
