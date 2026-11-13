package com.example.studyassistant

import org.junit.Assert.assertEquals
import org.junit.Test

class FeedbackEmailCompositionTest {
    @Test
    fun uri_usesFixedRecipientAndEncodesChineseNewlinesAndSpecialCharacters() {
        val uri = FeedbackEmailComposition.buildUri(
            "反馈 & 1.7.52",
            "问题：中文换行\n特殊字符 &?%+#",
        )

        assertEquals(
            "mailto:397079535%40qq.com?subject=" +
                "%E5%8F%8D%E9%A6%88%20%26%201.7.52&body=" +
                "%E9%97%AE%E9%A2%98%EF%BC%9A%E4%B8%AD%E6%96%87%E6%8D%A2%E8%A1%8C" +
                "%0A%E7%89%B9%E6%AE%8A%E5%AD%97%E7%AC%A6%20%26%3F%25%2B%23",
            uri,
        )
    }
}
