package com.example.studyassistant

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FeedbackEmailLaunchTest {
    @Test
    fun systemCanOpenTheFixedMailtoDraftWhenAHandlerExists() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val intent = FeedbackEmailComposition.intent(
            "学习通课业手记 1.7.53 (60) 反馈",
            "问题：系统邮件草稿启动测试\n复现步骤：不发送邮件",
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val launched = try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
        assumeTrue("No mailto handler on this device", launched)
        instrumentation.waitForIdleSync()
    }
}
