package com.example.studyassistant

import android.content.Intent
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FeedbackEmailIntentTest {
    @Test
    fun intent_isSendToWithFixedMailtoRecipientAndDecodedFields() {
        val intent = FeedbackEmailComposition.intent(
            "主题 & 版本",
            "正文：中文\n特殊字符 &?%+#",
        )

        assertEquals(Intent.ACTION_SENDTO, intent.action)
        assertEquals("mailto", intent.data?.scheme)
        assertEquals(
            "397079535@qq.com",
            intent.data?.schemeSpecificPart?.substringBefore('?'),
        )
        val query = requireNotNull(intent.data)
            .encodedSchemeSpecificPart
            .substringAfter('?')
            .split('&')
            .associate { field ->
                val (encodedName, encodedValue) = field.split('=', limit = 2)
                Uri.decode(encodedName) to Uri.decode(encodedValue)
            }
        assertEquals("主题 & 版本", query["subject"])
        assertEquals("正文：中文\n特殊字符 &?%+#", query["body"])
    }
}
