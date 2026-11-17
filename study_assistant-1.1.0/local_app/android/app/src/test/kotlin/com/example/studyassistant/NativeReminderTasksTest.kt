package com.example.studyassistant

import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeReminderTasksTest {
    @Test
    fun executePreservesReminderHistoryExceptionErrorCode() {
        val tasks = NativeReminderTasks(
            worker = { runnable -> runnable.run() },
            dispatch = { action -> action() },
        )
        var capturedCode: String? = null
        var capturedMessage: String? = null
        tasks.execute(
            object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    capturedCode = errorCode
                    capturedMessage = errorMessage
                }

                override fun notImplemented() {}
            },
        ) {
            throw ReminderHistoryException("stale_history_generation", "提醒历史代数已变更")
        }

        assertEquals("stale_history_generation", capturedCode)
        assertEquals("提醒历史代数已变更", capturedMessage)
    }

    @Test
    fun executeMapsGenericExceptionToBackgroundReminderError() {
        val tasks = NativeReminderTasks(
            worker = { runnable -> runnable.run() },
            dispatch = { action -> action() },
        )
        var capturedCode: String? = null
        var capturedDetails: Any? = "unexpected"
        tasks.execute(
            object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    capturedCode = errorCode
                    capturedDetails = errorDetails
                }

                override fun notImplemented() {}
            },
        ) {
            throw IllegalStateException("boom")
        }

        assertEquals("background_reminder_error", capturedCode)
        assertNull(capturedDetails)
    }
}
