package com.example.studyassistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterJNI
import io.flutter.embedding.engine.dart.PlatformMessageHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.nio.ByteBuffer
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class BackgroundReminderBridgeTest {
    private val main = Handler(Looper.getMainLooper())
    private val transport = BridgeTestTransport()
    private lateinit var context: Context
    private lateinit var database: ReminderDatabase
    private lateinit var engine: FlutterEngine
    private lateinit var accountHash: String
    private lateinit var targetHash: String
    private var epoch = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = ReminderDatabase.get(context)
        accountHash = "instrumentation-bridge-${System.nanoTime()}"
        targetHash = "$accountHash-target"
        epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            engine = FlutterEngine(context, null, transport, null, false)
            BackgroundReminderBridge.attach(engine, context)
        }
    }

    @After
    fun tearDown() {
        if (::engine.isInitialized) {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { engine.destroy() }
        }
        database.activeAccount()?.takeIf { it.accountHash in setOf(accountHash, targetHash) }
            ?.let { database.clearActiveAccount(it.accountHash) }
        widgetPrefs().edit()
            .remove("assignment_snapshot")
            .remove("assignment_authenticated")
            .remove("assignment_total_count")
            .remove("assignment_snapshot_at")
            .remove("batch2b_test_unrelated")
            .commit()
    }

    @Test
    fun sessionCheckLeavesMainLooperResponsiveWhileDatabaseIsBusy() {
        val mainMarker = CountDownLatch(1)
        val call = MethodCall("isSessionCurrent", mapOf(
            "accountHash" to accountHash,
            "sessionEpoch" to epoch,
        ))
        lateinit var reply: CompletableFuture<Any?>
        val mainRemainedResponsive = synchronized(database) {
            reply = callBridge(call, mainMarker)
            mainMarker.await(2, TimeUnit.SECONDS)
        }

        assertEquals(true, reply.get(5, TimeUnit.SECONDS))
        assertTrue("the DB monitor blocked the MethodChannel's main looper", mainRemainedResponsive)
    }

    @Test
    fun realAccountSwitchClearsWidgetSnapshotBeforeReply() {
        seedWidgetSnapshot()
        val sameAccountEpoch = switchAccount(accountHash)
        assertEquals(epoch, sameAccountEpoch)
        assertTrue(widgetPrefs().getBoolean("assignment_authenticated", false))
        assertTrue(widgetPrefs().contains("assignment_snapshot_at"))

        switchAccount(targetHash)

        assertEquals(targetHash, database.activeAccount()?.accountHash)
        assertWidgetSnapshotCleared()
    }

    @Test
    fun logoutClearsWidgetSnapshotBeforeReply() {
        seedWidgetSnapshot()
        val call = MethodCall("clearActiveAccount", mapOf("accountHash" to accountHash))

        assertEquals(epoch + 1, callBridge(call).get(5, TimeUnit.SECONDS))
        assertWidgetSnapshotCleared()
    }

    @Test
    fun retryingOldLogoutKeepsTheCurrentlyActiveAccountAndWidget() {
        val activeEpoch = switchAccount(targetHash)
        seedWidgetSnapshot()
        val call = MethodCall("clearActiveAccount", mapOf("accountHash" to accountHash))
        callBridge(call).get(5, TimeUnit.SECONDS)

        assertEquals(targetHash, database.activeAccount()?.accountHash)
        assertTrue(database.isSessionCurrent(targetHash, activeEpoch))
        assertTrue(widgetPrefs().getBoolean("assignment_authenticated", false))
        assertTrue(widgetPrefs().contains("assignment_snapshot_at"))
        assertEquals(1, widgetPrefs().getInt("assignment_total_count", 0))
    }

    private fun switchAccount(target: String): Long {
        val call = MethodCall("switchAccount", mapOf(
            "previousAccountHash" to accountHash,
            "accountHash" to target,
        ))
        return (callBridge(call).get(5, TimeUnit.SECONDS) as Number).toLong()
    }

    private fun widgetPrefs() =
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

    private fun seedWidgetSnapshot() {
        assertTrue(widgetPrefs().edit()
            .putString("assignment_snapshot", """[{"title":"Synthetic assignment"}]""")
            .putBoolean("assignment_authenticated", true)
            .putInt("assignment_total_count", 1)
            .putString("assignment_snapshot_at", "2026-11-22T08:00:00Z")
            .putString("batch2b_test_unrelated", "keep")
            .commit())
    }

    private fun assertWidgetSnapshotCleared() {
        val prefs = widgetPrefs()
        assertEquals("[]", prefs.getString("assignment_snapshot", null))
        assertFalse(prefs.getBoolean("assignment_authenticated", true))
        assertEquals(0, prefs.getInt("assignment_total_count", -1))
        assertFalse(prefs.contains("assignment_snapshot_at"))
        assertEquals("keep", prefs.getString("batch2b_test_unrelated", null))
    }

    private fun callBridge(
        call: MethodCall,
        mainMarker: CountDownLatch? = null,
    ): CompletableFuture<Any?> {
        val replyId = transport.nextReplyId.incrementAndGet()
        val reply = CompletableFuture<Any?>()
        transport.replies[replyId] = reply
        main.post {
            try {
                transport.send(call, replyId)
                if (mainMarker != null) main.post { mainMarker.countDown() }
            } catch (error: Exception) {
                reply.completeExceptionally(error)
            }
        }
        return reply
    }

    // Deliver Dart-format bytes through Flutter's real MethodChannel messenger
    // without starting a Dart isolate or making a remote check.
    private class BridgeTestTransport : FlutterJNI() {
        private val codec = StandardMethodCodec.INSTANCE
        private var handler: PlatformMessageHandler? = null
        val nextReplyId = AtomicInteger()
        val replies = ConcurrentHashMap<Int, CompletableFuture<Any?>>()

        override fun setPlatformMessageHandler(platformMessageHandler: PlatformMessageHandler?) {
            super.setPlatformMessageHandler(platformMessageHandler)
            handler = platformMessageHandler
        }

        fun send(call: MethodCall, replyId: Int) {
            val message = codec.encodeMethodCall(call).apply { flip() }
            checkNotNull(handler).handleMessageFromDart(
                BackgroundReminderBridge.CHANNEL, message, replyId, 0L,
            )
        }

        override fun cleanupMessageData(messageData: Long) {
            if (messageData != 0L) super.cleanupMessageData(messageData)
        }

        override fun invokePlatformMessageResponseCallback(
            replyId: Int,
            message: ByteBuffer,
            position: Int,
        ) {
            val reply = replies.remove(replyId) ?: return
            try {
                val envelope = message.duplicate().apply {
                    position(0)
                    limit(position)
                }
                reply.complete(codec.decodeEnvelope(envelope))
            } catch (error: Exception) {
                reply.completeExceptionally(error)
            }
        }

        override fun invokePlatformMessageEmptyResponseCallback(replyId: Int) {
            replies.remove(replyId)?.completeExceptionally(AssertionError("method not implemented"))
        }
    }
}
