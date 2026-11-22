package com.example.studyassistant

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.content.IntentFilter
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ExternalUrlBoundaryTest {
    @Test
    fun nativeOpenUrlRejectsHttpBeforeDispatch() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val filter = IntentFilter(Intent.ACTION_VIEW).apply { addDataScheme("http") }
        val monitor = instrumentation.addMonitor(
            filter,
            Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null),
            true,
        )
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    val open = MainActivity::class.java
                        .getDeclaredMethod("openExternalUrl", String::class.java)
                        .apply { isAccessible = true }

                    val opened = open.invoke(activity, "http://example.invalid/")
                    assertFalse(opened as Boolean)
                    assertEquals(0, monitor.hits)
                }
            }
        } finally {
            instrumentation.removeMonitor(monitor)
        }
    }
}
