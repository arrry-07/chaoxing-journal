package com.example.studyassistant

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Owns a single native operation, including its picker and background I/O lifetime. */
class BackupBridge(private val activity: Activity, private val channel: MethodChannel) {
    private class Operation(val result: MethodChannel.Result, val kind: String) {
        var content: ByteArray? = null
    }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Operation? = null
    private var destroyed = false

    init { channel.setMethodCallHandler(::handle) }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("encrypt", "decrypt", "save", "pick")) {
            result.notImplemented()
            return
        }
        if (destroyed) {
            result.error("backup_closed", "备份页面已关闭，请重试", null)
            return
        }
        if (pending != null) {
            result.error("backup_busy", "另一个备份操作正在进行", null)
            return
        }
        val operation = Operation(result, call.method)
        pending = operation
        try {
            when (call.method) {
                "encrypt", "decrypt" -> {
                    val content = requiredString(call, if (call.method == "encrypt") "plaintext" else "envelope")
                    val passwordText = requiredString(call, "password")
                    require(passwordText.length in 1..1024)
                    val password = passwordText.toCharArray()
                    background(operation) {
                        // BackupCrypto clears this mutable copy even if validation or authentication fails.
                        val output = if (operation.kind == "encrypt") BackupCrypto.encrypt(content, password)
                            else BackupCrypto.decrypt(content, password)
                        succeed(operation, output)
                    }
                }
                "save" -> {
                    val content = requiredString(call, "content")
                    require(content.length in 1..BackupCrypto.MAX_ENVELOPE_BYTES)
                    val suggestedName = (call.argument<String>("suggestedName") ?: "学习通备份.xxtbackup")
                        .substringAfterLast('/').substringAfterLast('\\').take(120)
                        .ifBlank { "学习通备份.xxtbackup" }
                    background(operation) {
                        val bytes = content.toByteArray(Charsets.UTF_8)
                        require(bytes.size <= BackupCrypto.MAX_ENVELOPE_BYTES)
                        main.post {
                            if (pending === operation && !destroyed) {
                                operation.content = bytes
                                launchPicker(operation, Intent(Intent.ACTION_CREATE_DOCUMENT)
                                    .addCategory(Intent.CATEGORY_OPENABLE).setType("application/octet-stream")
                                    .putExtra(Intent.EXTRA_TITLE, suggestedName), SAVE_REQUEST)
                            }
                        }
                    }
                }
                "pick" -> launchPicker(operation, Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"), PICK_REQUEST)
            }
        } catch (_: Exception) {
            fail(operation)
        }
    }

    private fun requiredString(call: MethodCall, name: String): String =
        call.argument<String>(name) ?: throw IllegalArgumentException("Missing argument")

    @Suppress("DEPRECATION")
    private fun launchPicker(operation: Operation, intent: Intent, request: Int) {
        try { activity.startActivityForResult(intent, request) }
        catch (_: Exception) { fail(operation) }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAVE_REQUEST && requestCode != PICK_REQUEST) return false
        val operation = pending ?: return true
        if ((requestCode == SAVE_REQUEST && operation.kind != "save") ||
            (requestCode == PICK_REQUEST && operation.kind != "pick")) return true
        if (resultCode != Activity.RESULT_OK) {
            succeed(operation, if (operation.kind == "save") false else null)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            fail(operation)
            return true
        }
        background(operation) {
            if (operation.kind == "save") {
                val bytes = operation.content ?: throw IllegalStateException("Missing content")
                val output = activity.contentResolver.openOutputStream(uri, "w")
                    ?: throw java.io.IOException("Cannot open document")
                // A successful result requires write, flush AND close to succeed.
                output.use { it.write(bytes); it.flush() }
                succeed(operation, true)
            } else {
                val input = activity.contentResolver.openInputStream(uri)
                    ?: throw java.io.IOException("Cannot open document")
                val bytes = input.use { BackupCrypto.readBounded(it) }
                succeed(operation, BackupCrypto.decodeUtf8(bytes))
            }
        }
        return true
    }

    private fun background(operation: Operation, action: () -> Unit) {
        worker.execute {
            try { action() }
            catch (_: Exception) { fail(operation) }
        }
    }

    private fun succeed(operation: Operation, value: Any?) {
        main.post {
            if (pending === operation && !destroyed) {
                pending = null
                operation.content = null
                operation.result.success(value)
            }
        }
    }

    private fun fail(operation: Operation) {
        main.post {
            if (pending === operation && !destroyed) {
                pending = null
                operation.content = null
                // Never return provider exceptions, passwords, paths or backup data to logs/UI.
                operation.result.error("backup_error", "备份操作失败，请检查文件、口令或存储位置后重试", null)
            }
        }
    }

    fun close() {
        destroyed = true
        channel.setMethodCallHandler(null)
        val operation = pending
        pending = null
        operation?.content = null
        operation?.result?.error("backup_closed", "备份操作已中止，请重试", null)
        // Let the one running task finish its finally block and clear its password copy.
        worker.shutdown()
    }

    private companion object {
        const val SAVE_REQUEST = 48210
        const val PICK_REQUEST = 48211
    }
}
