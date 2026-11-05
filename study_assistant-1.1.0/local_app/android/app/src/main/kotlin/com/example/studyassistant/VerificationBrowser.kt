package com.example.studyassistant

import android.app.Dialog
import android.graphics.Color
import android.net.Uri
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebSettings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream

/** Transient first-party browser. No JS bridge, credential logging, or external navigation. */
class VerificationBrowser(private val activity: MainActivity) {
    private var closeAction: (() -> Unit)? = null
    fun close() { closeAction?.invoke() }
    private fun trusted(url: String): Boolean {
        val u = Uri.parse(url)
        return u.scheme == "https" && (u.host == "chaoxing.com" || u.host?.endsWith(".chaoxing.com") == true)
    }
    fun open(url: String?, cookies: List<Map<String, String>>, userAgent: String?, result: MethodChannel.Result) {
        if (url == null || !trusted(url)) { result.error("invalid_origin", "验证地址不可用", null); return }
        val manager = CookieManager.getInstance()
        val dialog = Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar)
        val layout = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.rgb(247,245,236)) }
        val status = TextView(activity).apply { text = "学习通访问验证\n请在网页内完成验证，再点继续。登录信息仅用于学习通。"; textSize = 16f; setPadding(20,20,20,12) }
        val browser = WebView(activity)
        if (!userAgent.isNullOrBlank()) browser.settings.userAgentString = userAgent
        browser.settings.javaScriptEnabled = true
        browser.settings.domStorageEnabled = true
        browser.settings.allowFileAccess = false
        browser.settings.allowContentAccess = false
        browser.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        manager.setAcceptThirdPartyCookies(browser, false)
        val origins = mutableSetOf("https://mooc1.chaoxing.com/", "https://mooc1-api.chaoxing.com/")
        origins.add(Uri.parse(url).buildUpon().clearQuery().fragment(null).build().toString())
        cookies.mapNotNull { it["url"] }.filter { trusted(it) }.forEach { origins.add(it) }
        browser.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val target = request.url
                if (target.scheme == "http" && target.host?.endsWith(".chaoxing.com") == true) {
                    view.loadUrl(target.buildUpon().scheme("https").build().toString())
                    return true
                }
                return !trusted(target.toString())
            }
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                return if (trusted(request.url.toString())) null else WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
            }
            override fun onPageFinished(view: WebView, loaded: String) {
                if (trusted(loaded)) { val u=Uri.parse(loaded); origins.add("https://${u.host}/"); origins.add(u.buildUpon().clearQuery().fragment(null).build().toString()) }
            }
        }
        val actions = LinearLayout(activity)
        var finished = false
        fun finish(collect: Boolean) {
            if (finished) return
            finished = true
            closeAction = null
            val exported = if (collect) origins.mapNotNull { origin -> manager.getCookie(origin)?.let { mapOf("url" to origin, "cookies" to it) } } else emptyList()
            val agent = browser.settings.userAgentString
            browser.stopLoading()
            browser.destroy()
            // This jar belongs only to this new verification browser; journal and secure storage are untouched.
            manager.removeAllCookies(null)
            dialog.dismiss()
            result.success(if (collect) exported + mapOf("userAgent" to agent) else null)
        }
        closeAction = { finish(false) }
        dialog.setOnDismissListener { finish(false) }
        actions.addView(Button(activity).apply { text="返回"; setOnClickListener { finish(false) } }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT,1f))
        actions.addView(Button(activity).apply { text="刷新网页"; setOnClickListener { browser.reload() } }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT,1f))
        actions.addView(Button(activity).apply { text="继续同步"; setOnClickListener { finish(true) } }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT,1f))
        layout.addView(status)
        layout.addView(actions)
        layout.addView(browser, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,0,1f))
        dialog.setContentView(layout)
        dialog.setOnCancelListener { finish(false) }
        dialog.show()
        // Seed only this app's in-memory authenticated session after clearing stale browser sessions.
        manager.removeAllCookies {
            fun seed(index: Int) {
                if (finished) return
                if (index == cookies.size) { browser.loadUrl(url); return }
                val entry=cookies[index]; val origin=entry["url"]; val value=entry["value"]
                if (origin == null || value == null || !trusted(origin)) seed(index+1)
                else manager.setCookie(origin,value) { seed(index+1) }
            }
            seed(0)
        }
    }
}
