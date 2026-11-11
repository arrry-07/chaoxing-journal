package com.example.studyassistant

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class RealAccountHeadlessEntryTest {
    @Test
    fun realSessionRunsDaytimeBackgroundCheck() {
        assumeTrue(
            InstrumentationRegistry.getArguments()
                .getString("realAccount") == "true",
        )
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = ReminderDatabase.get(context)
        val account = database.activeAccount()
        assumeTrue(account != null)
        val before = account!!.lastAttemptAt
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        val oldAttempt = prefs.getString("flutter.sync_attempt_at", null)
        val oldData = prefs.getString("flutter.sync_data_at", null)
        val oldReport = prefs.getString("flutter.sync_report_v1", null)
        val oldJournal = prefs.getString("flutter.chaoxing_journal_v2", null)
        val oldTime = Instant.now().minusSeconds(48 * 60 * 60).toString()
        val oldJournalJson = oldJournal?.let(::JSONObject)
        oldJournalJson?.put("lastSync", oldTime)
        var restorePreferences = true
        prefs.edit()
            .putString("flutter.sync_attempt_at", oldTime)
            .putString("flutter.sync_data_at", oldTime)
            .remove("flutter.sync_report_v1")
            .putString(
                "flutter.chaoxing_journal_v2",
                oldJournalJson?.toString() ?: oldJournal,
            )
            .commit()
        val ready = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val result = AtomicReference<Map<*, *>?>()
        val engineRef = AtomicReference<FlutterEngine?>()
        val handler = Handler(Looper.getMainLooper())
        handler.post {
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
                                "accountHash" to account.accountHash,
                                "sessionEpoch" to account.sessionEpoch,
                                "requestedAt" to Instant.now().toString(),
                                "intervalMinutes" to account.intervalMinutes,
                                "signalVersion" to 0L,
                                "leaseOwner" to "instrumentation-real-account",
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
        }
        try {
            assertTrue("headless entry did not become ready", ready.await(30, TimeUnit.SECONDS))
            assertTrue("headless check did not finish", finished.await(120, TimeUnit.SECONDS))
            val output = result.get()
            assertNotNull(output)
            assertTrue("background result: $output", output!!["success"] == true)
            assertFalse("background result: $output", output["skipped"] == true)
            restorePreferences = false
            val after = database.readAccount(account.accountHash)
            assertNotNull(after)
            assertNotNull("lastAttemptAt was not recorded: $output", after!!.lastAttemptAt)
            assertTrue(
                before == null || after.lastAttemptAt!! > before,
            )
        } finally {
            handler.post { engineRef.get()?.destroy() }
            if (restorePreferences) {
                prefs.edit().apply {
                    restoreString(this, "flutter.sync_attempt_at", oldAttempt)
                    restoreString(this, "flutter.sync_data_at", oldData)
                    restoreString(this, "flutter.sync_report_v1", oldReport)
                    restoreString(this, "flutter.chaoxing_journal_v2", oldJournal)
                }.commit()
            }
        }
    }

    private fun restoreString(
        editor: SharedPreferences.Editor,
        key: String,
        value: String?,
    ) {
        if (value == null) {
            editor.remove(key)
        } else {
            editor.putString(key, value)
        }
    }
}
