package com.example.studyassistant

import android.content.Intent
import android.net.Uri

object FeedbackEmailComposition {
    private const val RECIPIENT = "397079535@qq.com"
    private const val HEX = "0123456789ABCDEF"

    fun buildUri(subject: String, body: String): String =
        "mailto:${encode(RECIPIENT)}?subject=${encode(subject)}&body=${encode(body)}"

    fun intent(subject: String, body: String): Intent =
        Intent(Intent.ACTION_SENDTO, Uri.parse(buildUri(subject, body)))

    private fun encode(value: String): String = buildString {
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val code = byte.toInt() and 0xff
            if (code in 'A'.code..'Z'.code ||
                code in 'a'.code..'z'.code ||
                code in '0'.code..'9'.code ||
                code == '-'.code ||
                code == '.'.code ||
                code == '_'.code ||
                code == '~'.code
            ) {
                append(code.toChar())
            } else {
                append('%')
                append(HEX[code ushr 4])
                append(HEX[code and 0x0f])
            }
        }
    }
}
