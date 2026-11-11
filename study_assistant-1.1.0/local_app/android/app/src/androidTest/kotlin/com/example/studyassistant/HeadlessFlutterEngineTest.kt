package com.example.studyassistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class HeadlessFlutterEngineTest {
    @Test
    fun backgroundEntryReadsPluginsWithoutAnActivity() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val setup = CountDownLatch(1)
        val ready = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val result = AtomicReference<Map<*, *>?>()
        val setupError = AtomicReference<Throwable?>()
        val engineRef = AtomicReference<FlutterEngine?>()
        val handler = Handler(Looper.getMainLooper())
        handler.post {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(context)
                loader.ensureInitializationComplete(context, null)
                val engine = FlutterEngine(context)
                engineRef.set(engine)
                GeneratedPluginRegistrant.registerWith(engine)
                BackgroundReminderBridge.attach(engine, context)
                val channel = MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    FlutterCheckWorker.CHANNEL,
                )
                channel.setMethodCallHandler { call, reply ->
                    when (call.method) {
                        "ready" -> {
                            reply.success(null)
                            ready.countDown()
                            channel.invokeMethod(
                                "run",
                                mapOf(
                                    "reason" to BackgroundWorkScheduler.REASON_DAYTIME,
                                    "accountHash" to "instrumentation-missing-account",
                                    "sessionEpoch" to 1,
                                    "requestedAt" to Instant.now().toString(),
                                    "intervalMinutes" to 240,
                                    "signalVersion" to 0,
                                    "leaseOwner" to "instrumentation-headless",
                                ),
                            )
                        }
                        "finished" -> {
                            result.set(call.arguments as? Map<*, *>)
                            reply.success(null)
                            finished.countDown()
                        }
                        else -> reply.notImplemented()
                    }
                }
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "backgroundMain",
                    ),
                )
            } catch (error: Throwable) {
                setupError.set(error)
            }
            setup.countDown()
        }
        try {
            assertTrue("headless setup did not start", setup.await(30, TimeUnit.SECONDS))
            setupError.get()?.let { throw AssertionError("headless setup failed", it) }
            assertTrue("backgroundMain did not become ready", ready.await(30, TimeUnit.SECONDS))
            assertTrue("backgroundMain did not finish", finished.await(30, TimeUnit.SECONDS))
            assertNotNull(result.get())
        } finally {
            handler.post { engineRef.get()?.destroy() }
        }
    }
}
