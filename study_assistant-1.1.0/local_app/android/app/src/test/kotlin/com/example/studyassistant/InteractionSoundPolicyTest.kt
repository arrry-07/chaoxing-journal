package com.example.studyassistant

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

class InteractionSoundPolicyTest {
    @Test
    fun presetPcmGeneratesExpectedSampleCountsZeroEdgesAndBoundedPeaks() {
        val expectedCounts = mapOf(
            "tap" to 2_880,
            "pin" to 6_480,
            "unpin" to 6_480,
            "syncDone" to 12_000,
            "complete" to 8_640,
        )
        assertEquals(expectedCounts.keys.toList(), InteractionSoundPolicy.PRESET_KINDS)

        for ((kind, count) in expectedCounts) {
            val pcm = InteractionSoundPolicy.presetPcm(kind)!!
            assertEquals("sample count for $kind", count, pcm.size)
            assertEquals("zero-cross start for $kind", 0, pcm.first().toInt())
            assertEquals("zero-cross end for $kind", 0, pcm.last().toInt())
            val maxAmplitude = pcm.maxOf { abs(it.toInt()) }
            assertTrue("audible signal for $kind", maxAmplitude > 5_000)
            assertTrue("bounded peak for $kind", maxAmplitude <= 9_200)
        }

        assertNull(InteractionSoundPolicy.presetPcm("unknown"))
        assertEquals(0, InteractionSoundPolicy.tone(0, 440.0, 440.0, 10.0, 0.25).size)
        assertEquals(0, InteractionSoundPolicy.tone(-5, 440.0, 440.0, 10.0, 0.25).size)
    }

    @Test
    fun wavEncodesValidLittleEndian48kMono16BitPcmHeaderAndPayload() {
        val pcm = shortArrayOf(0, 1234, -5678, 32767, -32768)
        val wav = InteractionSoundPolicy.wav(pcm)

        assertEquals(44 + pcm.size * 2, wav.size)
        assertEquals("RIFF", String(wav.copyOfRange(0, 4), Charsets.US_ASCII))
        assertEquals("WAVEfmt ", String(wav.copyOfRange(8, 16), Charsets.US_ASCII))
        assertEquals("data", String(wav.copyOfRange(36, 40), Charsets.US_ASCII))

        val buf = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(36 + pcm.size * 2, buf.getInt(4))
        assertEquals(16, buf.getInt(16)) // PCM subchunk size
        assertEquals(1.toShort(), buf.getShort(20)) // PCM format
        assertEquals(1.toShort(), buf.getShort(22)) // Mono
        assertEquals(48_000, buf.getInt(24))
        assertEquals(96_000, buf.getInt(28)) // Byte rate
        assertEquals(2.toShort(), buf.getShort(32)) // Block align
        assertEquals(16.toShort(), buf.getShort(34)) // Bits per sample
        assertEquals(pcm.size * 2, buf.getInt(40))

        val decoded = ShortArray(pcm.size) { buf.getShort(44 + it * 2) }
        assertArrayEquals(pcm, decoded)
    }

    @Test
    fun shouldPlayRequiresUnmutedPositiveStreamVolumeAndLoadedSoundId() {
        assertFalse(InteractionSoundPolicy.shouldPlay(false, 10, false, 1, setOf(1)))
        assertFalse(InteractionSoundPolicy.shouldPlay(true, 0, false, 1, setOf(1)))
        assertFalse(InteractionSoundPolicy.shouldPlay(true, -1, false, 1, setOf(1)))
        assertFalse(InteractionSoundPolicy.shouldPlay(true, 5, true, 1, setOf(1)))
        assertFalse(InteractionSoundPolicy.shouldPlay(true, 5, false, null, setOf(1)))
        assertFalse(InteractionSoundPolicy.shouldPlay(true, 5, false, 2, setOf(1)))
        assertTrue(InteractionSoundPolicy.shouldPlay(true, 5, false, 1, setOf(1)))
    }

    @Test
    fun vibrationSpecAndAmplitudeControlMatchAllSupportedKinds() {
        assertEquals(
            InteractionSoundPolicy.VibrationSpec.OneShot(30L, 160),
            InteractionSoundPolicy.vibrationSpec("tap"),
        )
        assertEquals(
            InteractionSoundPolicy.VibrationSpec.OneShot(40L, 200),
            InteractionSoundPolicy.vibrationSpec("pin"),
        )
        assertEquals(
            InteractionSoundPolicy.VibrationSpec.OneShot(40L, 200),
            InteractionSoundPolicy.vibrationSpec("unpin"),
        )
        assertEquals(
            InteractionSoundPolicy.VibrationSpec.OneShot(50L, 200),
            InteractionSoundPolicy.vibrationSpec("complete"),
        )
        assertEquals(
            InteractionSoundPolicy.VibrationSpec.Waveform(longArrayOf(0, 30, 60, 30), -1),
            InteractionSoundPolicy.vibrationSpec("syncDone"),
        )
        assertNull(InteractionSoundPolicy.vibrationSpec("unknown"))
        assertNull(InteractionSoundPolicy.vibrationSpec(null))

        assertEquals(160, InteractionSoundPolicy.effectiveAmplitude(160, true, -1))
        assertEquals(-1, InteractionSoundPolicy.effectiveAmplitude(160, false, -1))
    }
}
