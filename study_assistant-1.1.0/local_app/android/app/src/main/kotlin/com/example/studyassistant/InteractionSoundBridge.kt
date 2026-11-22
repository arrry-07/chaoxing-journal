package com.example.studyassistant

import android.app.Activity
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioManager.STREAM_MUSIC
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class InteractionSoundBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val audioManager = activity.getSystemService(AudioManager::class.java)
    private val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        activity.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        activity.getSystemService(Vibrator::class.java)
    }
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
    private val ids = ConcurrentHashMap<String, Int>()
    private val ready: MutableSet<Int> =
        Collections.newSetFromMap(ConcurrentHashMap<Int, Boolean>())
    private val closed = AtomicBoolean(false)
    private val loaderExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "journal-sfx-loader").apply { isDaemon = true }
    }

    init {
        pool.setOnLoadCompleteListener { _, id, status ->
            if (!closed.get() && status == 0) ready.add(id)
        }
        val cache = activity.cacheDir
        loaderExecutor.execute {
            for (kind in InteractionSoundPolicy.PRESET_KINDS) {
                if (closed.get()) return@execute
                val pcm = InteractionSoundPolicy.presetPcm(kind) ?: continue
                load(cache, kind, pcm)
            }
        }

        channel.setMethodCallHandler { call, result ->
            if (call.method == "feedback") {
                val kind = call.argument<String>("kind")
                if (call.argument<Boolean>("sound") == true) runCatching { play(kind) }
                if (call.argument<Boolean>("haptics") == true) runCatching { vibrate(kind) }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun play(kind: String?) {
        if (closed.get()) return
        val manager = audioManager
        val id = if (kind == null) null else ids[kind]
        if (!InteractionSoundPolicy.shouldPlay(
                hasAudioManager = manager != null,
                streamVolume = manager?.getStreamVolume(STREAM_MUSIC) ?: 0,
                isStreamMuted = manager?.isStreamMute(STREAM_MUSIC) ?: false,
                soundId = id,
                readyIds = ready,
                ringerMode = manager?.ringerMode ?: AudioManager.RINGER_MODE_SILENT,
                audioMode = manager?.mode ?: AudioManager.MODE_NORMAL,
            )
        ) {
            return
        }
        pool.play(id!!, 0.55f, 0.55f, 1, 0, 1.0f)
    }

    @Suppress("DEPRECATION")
    private fun vibrate(kind: String?) {
        val spec = InteractionSoundPolicy.vibrationSpec(kind) ?: return
        val motor = vibrator
        val requested = runCatching {
            if (motor == null || !motor.hasVibrator()) return@runCatching false
            val effect = when (spec) {
                is InteractionSoundPolicy.VibrationSpec.Waveform ->
                    VibrationEffect.createWaveform(spec.timings, spec.repeat)
                is InteractionSoundPolicy.VibrationSpec.OneShot ->
                    VibrationEffect.createOneShot(
                        spec.durationMs,
                        InteractionSoundPolicy.effectiveAmplitude(
                            spec.amplitude,
                            motor.hasAmplitudeControl(),
                            VibrationEffect.DEFAULT_AMPLITUDE,
                        ),
                    )
            }
            motor.vibrate(effect)
            true
        }.getOrDefault(false)
        if (!requested) {
            runCatching {
                activity.window?.decorView?.performHapticFeedback(
                    HapticFeedbackConstants.KEYBOARD_TAP,
                )
            }
        }
    }

    private fun load(cache: File, kind: String, pcm: ShortArray) {
        if (closed.get()) return
        // SoundPool opens the file when load is called and decodes it asynchronously.
        // Keep no bundled audio assets or persistent files.
        runCatching {
            val file = File.createTempFile("journal-sfx-", ".wav", cache)
            try {
                file.writeBytes(InteractionSoundPolicy.wav(pcm))
                if (closed.get()) return@runCatching
                val id = pool.load(file.absolutePath, 1)
                if (id != 0 && !closed.get()) ids[kind] = id
            } finally {
                file.delete()
            }
        }
    }

    fun onPause() {
        if (!closed.get()) {
            runCatching { pool.autoPause() }
        }
    }

    fun onResume() {
        if (!closed.get()) {
            runCatching { pool.autoResume() }
        }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        loaderExecutor.shutdownNow()
        ids.clear()
        ready.clear()
        runCatching {
            pool.setOnLoadCompleteListener(null)
            pool.release()
        }
    }
}
