package com.example.studyassistant

import android.app.Activity
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView

/** Application-wide WebView state, serialized with cookie callbacks before seeding. */
object WebSessionCleaner {
    private val pending = java.util.ArrayDeque<() -> Unit>()
    private var running = false

    fun clear(activity: Activity, browser: WebView? = null, onComplete: (Boolean) -> Unit) {
        pending.addLast {
            var view = browser
            var completed = false
            fun complete(ok: Boolean) {
                if (completed) return
                completed = true
                runCatching { view?.destroy() }
                try { onComplete(ok) } finally {
                    running = false
                    next()
                }
            }
            try {
                // CookieManager and WebStorage belong to this app's shared WebView
                // profile, not an individual View or another installed browser.
                view = view ?: WebView(activity)
                view?.stopLoading()
                view?.clearCache(true)
                view?.clearHistory()
                view?.clearFormData()
                WebStorage.getInstance().deleteAllData()
                val cookies = CookieManager.getInstance()
                cookies.removeAllCookies {
                    val flushed = runCatching { cookies.flush() }.isSuccess
                    complete(flushed)
                }
            } catch (_: Exception) {
                complete(false)
            }
        }
        next()
    }

    private fun next() {
        if (running || pending.isEmpty()) return
        running = true
        pending.removeFirst().invoke()
    }
}
