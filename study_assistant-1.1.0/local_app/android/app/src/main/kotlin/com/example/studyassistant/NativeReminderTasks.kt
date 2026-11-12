package com.example.studyassistant

import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

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
