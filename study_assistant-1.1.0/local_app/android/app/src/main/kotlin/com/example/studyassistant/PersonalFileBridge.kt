package com.example.studyassistant

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel

/** User-selected read-only document grants, never filesystem paths. */
class PersonalFileBridge(
    private val activity: Activity,
    private val channel: MethodChannel
) {
    private var pending: MethodChannel.Result? = null
    private val requestCode = 6183

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    if (pending != null) {
                        result.error("file_busy", "文件选择正在进行", null)
                        return@setMethodCallHandler
                    }
                    pending = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("*/*")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        activity.startActivityForResult(intent, requestCode)
                    } catch (_: Exception) {
                        pending = null
                        result.error("file_picker", "无法打开系统文件选择器", null)
                    }
                }
                "open" -> {
                    val uri = Uri.parse(call.argument<String>("uri") ?: "")
                    if (uri.scheme != "content" || uri.authority.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        // A restored URI or another account's URI is not a grant.
                        val granted = activity.contentResolver.persistedUriPermissions
                            .any { it.uri == uri && it.isReadPermission }
                        if (!granted) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val type = activity.contentResolver.getType(uri)
                            ?: "application/octet-stream"
                        activity.startActivity(Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, type)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(code: Int, status: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val result = pending ?: return true
        pending = null
        if (status != Activity.RESULT_OK) {
            result.success(null)
            return true
        }
        val uri = data?.data
        if (uri == null || uri.scheme != "content" || uri.authority.isNullOrBlank()) {
            result.error("file_invalid", "文件无法关联", null)
            return true
        }
        try {
            // Keep only read access, even when the picker also offers write access.
            activity.contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            var name = "本地文件"
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
                null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    name = cursor.getString(0)?.take(200)?.takeIf { it.isNotBlank() }
                        ?: name
                }
            }
            result.success(mapOf("label" to name, "url" to uri.toString()))
        } catch (_: Exception) {
            // Some document providers return a URI without a persistable grant.
            // Do not save a reference that will silently stop working on restart.
            result.error("file_access", "无法保留文件授权，请从内部存储重新选择本机文件", null)
        }
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.error("file_closed", "文件选择已中止", null)
        pending = null
    }
}
