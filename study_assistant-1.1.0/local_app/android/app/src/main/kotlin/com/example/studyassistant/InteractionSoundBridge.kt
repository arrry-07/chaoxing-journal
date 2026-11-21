package com.example.studyassistant

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

internal class InteractionSoundBridge(context: Context, messenger: BinaryMessenger) {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val channel = MethodChannel(messenger, "study_assistant/interaction_sound")
    private val pool = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
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
        val cache = context.cacheDir
        load(cache, "tap", chirp(28, 2100.0, 900.0, 0.38))
        load(cache, "pin", chirp(42, 1600.0, 2400.0, 0.44))
        load(cache, "unpin", chirp(42, 2200.0, 1500.0, 0.36))
        load(cache, "syncDone",
            chirp(37, 1046.5, 1046.5, 0.30) + chirp(38, 1318.5, 1318.5, 0.34))
        load(cache, "complete", chirp(55, 1100.0, 1700.0, 0.36))

        channel.setMethodCallHandler { call, result ->
            if (call.method == "play") {
                play(call.argument<String>("kind"))
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun play(kind: String?) {
        if (audioManager?.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val id = ids[kind] ?: return
        if (id in ready) pool.play(id, 0.45f, 0.45f, 1, 0, 1.0f)
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

    private fun chirp(ms: Int, startHz: Double, endHz: Double, amplitude: Double): ShortArray {
        val count = SAMPLE_RATE * ms / 1000
        var phase = 0.0
        return ShortArray(count) { i ->
            val t = i.toDouble() / count
            val frequency = startHz + (endHz - startHz) * t
            phase += 2 * PI * frequency / SAMPLE_RATE
            val envelope = minOf(t / 0.08, (1 - t) / 0.08, 1.0) * exp(-5.2 * t)
            (sin(phase) * envelope * amplitude * Short.MAX_VALUE).toInt().toShort()
        }
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
