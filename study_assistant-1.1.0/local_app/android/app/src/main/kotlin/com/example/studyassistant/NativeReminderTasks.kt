package com.example.studyassistant

import android.content.BroadcastReceiver
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Serializes broadcast receivers and notification listener DB work off the main thread. */
internal object NativeReceiverExecutor {
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "study-reminder-receiver").apply { isDaemon = true }
    }

    fun dispatchReceiver(
        pendingResult: BroadcastReceiver.PendingResult?,
        action: () -> Unit,
    ) {
        if (pendingResult == null) {
            action()
            return
        }
        try {
            worker.execute {
                try {
                    action()
                } catch (error: Throwable) {
                    runCatching {
                        Log.w("NativeReceiverExecutor", "receiver_work_failed", error)
                    }
                } finally {
                    pendingResult.finish()
                }
            }
        } catch (error: Throwable) {
            runCatching {
                Log.w("NativeReceiverExecutor", "receiver_dispatch_failed", error)
            }
            pendingResult.finish()
        }
    }

    fun executeAsync(action: () -> Unit) {
        worker.execute {
            try {
                action()
            } catch (error: Throwable) {
                runCatching {
                    Log.w("NativeReceiverExecutor", "listener_work_failed", error)
                }
            }
        }
    }

    fun awaitIdle(timeoutSeconds: Long = 5L) {
        worker.submit {}.get(timeoutSeconds, TimeUnit.SECONDS)
    }
}

/** Ordered heavy work is separate from lease waits and urgent privacy controls. */
internal class NativeReminderTasks(
    private val worker: Executor,
    private val dispatch: (() -> Unit) -> Unit,
) {
    fun execute(result: MethodChannel.Result, operation: (MethodChannel.Result) -> Unit) {
        val once = reply(result)
        try {
            worker.execute {
                try {
                    operation(once)
                } catch (error: ReminderHistoryException) {
                    once.error(error.code, error.message, null)
                } catch (error: Exception) {
                    once.error("background_reminder_error", error.message, null)
                }
            }
        } catch (error: Exception) {
            once.error("background_reminder_error", error.message, null)
        }
    }

    fun reply(result: MethodChannel.Result): MethodChannel.Result {
        val completed = AtomicBoolean(false)
        fun deliver(action: () -> Unit) {
            if (completed.compareAndSet(false, true)) dispatch(action)
        }
        return object : MethodChannel.Result {
            override fun success(value: Any?) = deliver { result.success(value) }
            override fun error(code: String, message: String?, details: Any?) =
                deliver { result.error(code, message, details) }
            override fun notImplemented() = deliver { result.notImplemented() }
        }
    }
}
