package com.example.studyassistant

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.net.URLConnection
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * User-selected document grants (`PersonalWork.files`) and private copies
 * (`manual_attachments/`) for manual todo/exam entries.
 */
class PersonalFileBridge(
    private val activity: Activity,
    private val channel: MethodChannel,
    private val attachmentChannel: MethodChannel,
) {
    private class FileTooLargeException : Exception()

    private class PendingOperation(
        val result: MethodChannel.Result,
        var captureFile: File? = null,
        val maxPickImages: Int = ManualAttachmentPathPolicy.MAX_IMAGES_PER_PICK,
        val generation: Long = 0L,
    )

    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var closed = false

    @Volatile
    private var storageGeneration = 0L

    private var pending: PendingOperation? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> startLegacyPick(result)
                "open" -> openLegacyUri(call.argument<String>("uri"), result)
                "releaseAll" -> result.success(releaseAll())
                else -> result.notImplemented()
            }
        }
        attachmentChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAttachmentRoot" -> {
                    val dir = File(activity.filesDir, ManualAttachmentPathPolicy.ATTACHMENTS_DIR)
                    dir.mkdirs()
                    result.success(dir.absolutePath)
                }
                "capturePhoto" -> startCapturePhoto(result)
                "pickImages" -> {
                    val requested = call.argument<Int>("maxCount")
                        ?: ManualAttachmentPathPolicy.MAX_IMAGES_PER_PICK
                    startPickImages(requested, result)
                }
                "pickAttachmentFile" -> startPickAttachmentFile(result)
                "openAttachment" -> {
                    val relativePath = call.argument<String>("relativePath")
                    val mimeType = call.argument<String>("mimeType")
                    result.success(openAttachment(relativePath, mimeType))
                }
                "deleteAttachmentFiles" -> {
                    val paths = call.argument<List<*>>("relativePaths")
                        ?.filterIsInstance<String>()
                        .orEmpty()
                    deleteAttachmentFilesAsync(paths, result)
                }
                "deleteAllAttachments" -> deleteAllAttachmentsAsync(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun startLegacyPick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("file_busy", "文件选择正在进行", null)
            return
        }
        val op = PendingOperation(result = result, generation = storageGeneration)
        pending = op
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                )
            activity.startActivityForResult(intent, REQUEST_CODE_LEGACY_PICK)
        } catch (_: Exception) {
            if (pending === op) pending = null
            result.error("file_picker", "无法打开系统文件选择器", null)
        }
    }

    private fun openLegacyUri(rawUri: String?, result: MethodChannel.Result) {
        val uri = Uri.parse(rawUri ?: "")
        if (uri.scheme != "content" || uri.authority.isNullOrBlank()) {
            result.success(false)
            return
        }
        try {
            // A restored URI or another account's URI is not a grant.
            val granted = activity.contentResolver.persistedUriPermissions
                .any { it.uri == uri && it.isReadPermission }
            if (!granted) {
                result.success(false)
                return
            }
            val type = activity.contentResolver.getType(uri)
                ?: "application/octet-stream"
            activity.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, type)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun startCapturePhoto(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("file_busy", "附件操作正在进行", null)
            return
        }
        val captureDir = File(activity.cacheDir, ManualAttachmentPathPolicy.CAMERA_CAPTURE_DIR)
        captureDir.mkdirs()
        val tempFile = File(
            captureDir,
            "cap_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.jpg",
        )
        val op = PendingOperation(
            result = result,
            captureFile = tempFile,
            generation = storageGeneration,
        )
        pending = op
        try {
            val outputUri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.update_file_provider",
                tempFile,
            )
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, outputUri)
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                clipData = ClipData.newUri(activity.contentResolver, "capture", outputUri)
            }
            activity.startActivityForResult(intent, REQUEST_CODE_CAPTURE_PHOTO)
        } catch (_: ActivityNotFoundException) {
            tempFile.delete()
            if (pending === op) pending = null
            result.error("no_camera", "未找到可用的相机应用", null)
        } catch (_: Exception) {
            tempFile.delete()
            if (pending === op) pending = null
            result.error("capture_failed", "无法启动相机拍照", null)
        }
    }

    private fun startPickImages(requestedMaxCount: Int, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("file_busy", "附件操作正在进行", null)
            return
        }
        val cappedMax = requestedMaxCount.coerceIn(1, ManualAttachmentPathPolicy.MAX_IMAGES_PER_PICK)
        val op = PendingOperation(
            result = result,
            maxPickImages = cappedMax,
            generation = storageGeneration,
        )
        pending = op

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                val photoPickerIntent = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                    type = "image/*"
                    // Android 13+ throws IllegalArgumentException when EXTRA_PICK_IMAGES_MAX < 2.
                    if (cappedMax >= 2) {
                        val systemLimit = MediaStore.getPickImagesMaxLimit().coerceAtLeast(2)
                        putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, minOf(cappedMax, systemLimit))
                    }
                }
                activity.startActivityForResult(photoPickerIntent, REQUEST_CODE_PICK_IMAGES)
                return
            } catch (_: ActivityNotFoundException) {
                // Fall back to ACTION_OPEN_DOCUMENT when Photo Picker is absent on custom ROMs.
            } catch (_: Exception) {
                if (pending === op) pending = null
                result.error("image_picker", "无法打开照片选择器", null)
                return
            }
        }

        try {
            val fallbackIntent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                if (cappedMax > 1) {
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivityForResult(fallbackIntent, REQUEST_CODE_PICK_IMAGES)
        } catch (_: Exception) {
            if (pending === op) pending = null
            result.error("image_picker", "无法打开图片选择器", null)
        }
    }

    private fun startPickAttachmentFile(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("file_busy", "附件操作正在进行", null)
            return
        }
        val op = PendingOperation(result = result, generation = storageGeneration)
        pending = op
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivityForResult(intent, REQUEST_CODE_PICK_ATTACHMENT_FILE)
        } catch (_: Exception) {
            if (pending === op) pending = null
            result.error("file_picker", "无法打开系统文件选择器", null)
        }
    }

    private fun openAttachment(relativePath: String?, mimeType: String?): String {
        val file = ManualAttachmentPathPolicy.resolveTargetFile(activity.filesDir, relativePath)
            ?: return "missing_file"
        if (!file.exists() || !file.isFile) return "missing_file"
        return try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.update_file_provider",
                file,
            )
            val ext = file.extension.lowercase(Locale.US)
            val guessedMime = guessMimeForExtension(ext, file.name)
            val preferredMime = if (isGenericMime(mimeType)) {
                guessedMime ?: mimeType
            } else {
                mimeType
            }
            val resolvedMime = ManualAttachmentPathPolicy.sanitizeMimeType(
                preferredMime,
                guessedMime ?: "application/octet-stream",
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, resolvedMime)
                clipData = ClipData.newUri(activity.contentResolver, file.name, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            "ok"
        } catch (_: ActivityNotFoundException) {
            "no_app"
        } catch (_: Exception) {
            "open_failed"
        }
    }

    private fun deleteAttachmentFilesAsync(
        relativePaths: List<String>,
        result: MethodChannel.Result,
    ) {
        if (closed) {
            result.error("file_closed", "附件操作已中止", null)
            return
        }
        if (relativePaths.isEmpty()) {
            result.success(0)
            return
        }
        val genSnapshot = storageGeneration
        try {
            ioExecutor.execute {
                val deleted = deleteRelativePaths(relativePaths)
                mainHandler.post {
                    if (!closed) {
                        result.success(if (storageGeneration == genSnapshot) deleted else 0)
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("file_closed", "附件操作已中止", null)
        }
    }

    private fun deleteAllAttachmentsAsync(result: MethodChannel.Result) {
        if (closed) {
            result.error("file_closed", "附件操作已中止", null)
            return
        }
        storageGeneration++
        try {
            ioExecutor.execute {
                val attachmentsRoot = File(activity.filesDir, ManualAttachmentPathPolicy.ATTACHMENTS_DIR)
                val captureRoot = File(activity.cacheDir, ManualAttachmentPathPolicy.CAMERA_CAPTURE_DIR)
                val deletedMain = !attachmentsRoot.exists() || attachmentsRoot.deleteRecursively()
                val deletedTemp = !captureRoot.exists() || captureRoot.deleteRecursively()
                val ok = deletedMain && deletedTemp
                mainHandler.post {
                    if (!closed) {
                        result.success(ok)
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("file_closed", "附件操作已中止", null)
        }
    }

    private fun deleteRelativePaths(relativePaths: List<String>): Int {
        var deleted = 0
        for (path in relativePaths) {
            val file = ManualAttachmentPathPolicy.resolveTargetFile(activity.filesDir, path)
                ?: continue
            if (file.exists() && file.delete()) {
                deleted++
            }
        }
        return deleted
    }

    private fun releaseAll(): Boolean {
        val resolver = activity.contentResolver
        val permissions = try {
            resolver.persistedUriPermissions.toList()
        } catch (error: Exception) {
            Log.w(TAG, "uri_grant_query_failed:${error.javaClass.simpleName}")
            return false
        }
        for (permission in permissions) {
            var flags = 0
            if (permission.isReadPermission) flags = flags or Intent.FLAG_GRANT_READ_URI_PERMISSION
            if (permission.isWritePermission) flags = flags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            if (flags == 0) continue
            try {
                resolver.releasePersistableUriPermission(permission.uri, flags)
            } catch (error: Exception) {
                Log.w(TAG, "uri_grant_release_failed:${error.javaClass.simpleName}")
            }
        }
        return true
    }

    fun onActivityResult(code: Int, status: Int, data: Intent?): Boolean {
        if (code != REQUEST_CODE_LEGACY_PICK &&
            code != REQUEST_CODE_CAPTURE_PHOTO &&
            code != REQUEST_CODE_PICK_IMAGES &&
            code != REQUEST_CODE_PICK_ATTACHMENT_FILE
        ) {
            return false
        }
        val op = pending ?: return true

        when (code) {
            REQUEST_CODE_LEGACY_PICK -> {
                pending = null
                handleLegacyPickResult(op.result, status, data)
            }
            REQUEST_CODE_CAPTURE_PHOTO -> handleCapturePhotoResult(op, status)
            REQUEST_CODE_PICK_IMAGES -> handlePickImagesResult(op, status, data)
            REQUEST_CODE_PICK_ATTACHMENT_FILE -> handlePickAttachmentFileResult(op, status, data)
        }
        return true
    }

    private fun handleLegacyPickResult(
        result: MethodChannel.Result,
        status: Int,
        data: Intent?,
    ) {
        if (status != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null || uri.scheme != "content" || uri.authority.isNullOrBlank()) {
            result.error("file_invalid", "文件无法关联", null)
            return
        }
        try {
            // Keep only read access, even when the picker also offers write access.
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            var name = "本地文件"
            activity.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    name = cursor.getString(0)?.take(200)?.takeIf { it.isNotBlank() } ?: name
                }
            }
            result.success(mapOf("label" to name, "url" to uri.toString()))
        } catch (_: Exception) {
            // Some document providers return a URI without a persistable grant.
            // Do not save a reference that will silently stop working on restart.
            result.error("file_access", "无法保留文件授权，请从内部存储重新选择本机文件", null)
        }
    }

    private fun handleCapturePhotoResult(
        op: PendingOperation,
        status: Int,
    ) {
        val tempFile = op.captureFile
        if (status != Activity.RESULT_OK || tempFile == null) {
            tempFile?.delete()
            op.captureFile = null
            if (pending === op) pending = null
            op.result.success(null)
            return
        }
        try {
            ioExecutor.execute {
                var copiedPath: String? = null
                try {
                    if (closed || op.generation != storageGeneration ||
                        !tempFile.exists() || tempFile.length() <= 0L
                    ) {
                        finishOperation(op) { res -> res.success(null) }
                        return@execute
                    }
                    if (!ManualAttachmentPathPolicy.isAllowedSize(tempFile.length())) {
                        finishOperation(op) { res ->
                            res.error("file_too_large", "照片超过 20 MB 上限，无法添加", null)
                        }
                        return@execute
                    }
                    val id = nextAttachmentId()
                    val relativePath = ManualAttachmentPathPolicy.buildUniqueRelativePath(id, "jpg")
                    val dest = ManualAttachmentPathPolicy.resolveTargetFile(activity.filesDir, relativePath)
                        ?: throw IllegalStateException("Invalid target path")
                    copiedPath = relativePath
                    dest.parentFile?.mkdirs()
                    val written = FileInputStream(tempFile).use { input ->
                        copyStreamBounded(input, dest, ManualAttachmentPathPolicy.MAX_FILE_BYTES)
                    }
                    if (closed || op.generation != storageGeneration) {
                        dest.delete()
                        finishOperation(op) { res -> res.success(null) }
                        return@execute
                    }
                    val payload = mapOf(
                        "id" to id,
                        "kind" to "image",
                        "name" to "拍照_$id.jpg",
                        "relativePath" to relativePath,
                        "mimeType" to "image/jpeg",
                        "sizeBytes" to written,
                        "addedAtMs" to System.currentTimeMillis(),
                    )
                    finishOperation(op, listOf(relativePath)) { res ->
                        res.success(payload)
                    }
                } catch (_: FileTooLargeException) {
                    copiedPath?.let { deleteRelativePaths(listOf(it)) }
                    finishOperation(op) { res ->
                        res.error("file_too_large", "照片超过 20 MB 上限，无法添加", null)
                    }
                } catch (_: Exception) {
                    copiedPath?.let { deleteRelativePaths(listOf(it)) }
                    finishOperation(op) { res ->
                        res.error("capture_failed", "照片保存失败，请重试", null)
                    }
                } finally {
                    tempFile.delete()
                }
            }
        } catch (_: RejectedExecutionException) {
            tempFile.delete()
            if (pending === op) {
                pending = null
                op.result.error("file_closed", "文件选择已中止", null)
            }
        }
    }

    private fun handlePickImagesResult(
        op: PendingOperation,
        status: Int,
        data: Intent?,
    ) {
        if (status != Activity.RESULT_OK || data == null) {
            if (pending === op) pending = null
            op.result.success(null)
            return
        }
        val uris = extractUris(data, op.maxPickImages)
        if (uris.isEmpty()) {
            if (pending === op) pending = null
            op.result.success(null)
            return
        }
        try {
            ioExecutor.execute {
                val items = mutableListOf<Map<String, Any>>()
                val createdPaths = mutableListOf<String>()
                var skippedTooLarge = 0
                var skippedFailed = 0
                for (uri in uris) {
                    if (closed || op.generation != storageGeneration) break
                    try {
                        val payload = copyContentUriIntoPrivateDir(uri, isImage = true)
                        items.add(payload)
                        (payload["relativePath"] as? String)?.let(createdPaths::add)
                    } catch (_: FileTooLargeException) {
                        skippedTooLarge++
                    } catch (_: Exception) {
                        skippedFailed++
                    }
                }
                if (closed || op.generation != storageGeneration) {
                    deleteRelativePaths(createdPaths)
                    finishOperation(op) { res -> res.success(null) }
                    return@execute
                }
                finishOperation(op, createdPaths) { res ->
                    res.success(
                        mapOf(
                            "items" to items,
                            "skippedTooLarge" to skippedTooLarge,
                            "skippedFailed" to skippedFailed,
                        ),
                    )
                }
            }
        } catch (_: RejectedExecutionException) {
            if (pending === op) {
                pending = null
                op.result.error("file_closed", "文件选择已中止", null)
            }
        }
    }

    private fun handlePickAttachmentFileResult(
        op: PendingOperation,
        status: Int,
        data: Intent?,
    ) {
        if (status != Activity.RESULT_OK || data == null) {
            if (pending === op) pending = null
            op.result.success(null)
            return
        }
        val uri = data.data
        if (uri == null || uri.scheme != "content" || uri.authority.isNullOrBlank()) {
            if (pending === op) pending = null
            op.result.error("file_invalid", "无法读取所选文件", null)
            return
        }
        try {
            ioExecutor.execute {
                try {
                    if (closed || op.generation != storageGeneration) {
                        finishOperation(op) { res -> res.success(null) }
                        return@execute
                    }
                    val payload = copyContentUriIntoPrivateDir(uri, isImage = false)
                    val rel = payload["relativePath"] as? String
                    if (closed || op.generation != storageGeneration) {
                        if (rel != null) deleteRelativePaths(listOf(rel))
                        finishOperation(op) { res -> res.success(null) }
                        return@execute
                    }
                    val created = if (rel == null) emptyList() else listOf(rel)
                    finishOperation(op, created) { res -> res.success(payload) }
                } catch (_: FileTooLargeException) {
                    finishOperation(op) { res ->
                        res.error("file_too_large", "单个文件不能超过 20 MB", null)
                    }
                } catch (_: Exception) {
                    finishOperation(op) { res ->
                        res.error("file_copy_failed", "无法复制文件，请重新选择", null)
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            if (pending === op) {
                pending = null
                op.result.error("file_closed", "文件选择已中止", null)
            }
        }
    }

    private fun extractUris(data: Intent, maxCount: Int): List<Uri> {
        val collected = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null && clip.itemCount > 0) {
            for (index in 0 until clip.itemCount) {
                val uri = clip.getItemAt(index)?.uri ?: continue
                if (uri.scheme == "content" && !uri.authority.isNullOrBlank()) {
                    collected.add(uri)
                    if (collected.size >= maxCount) break
                }
            }
        }
        if (collected.isEmpty()) {
            val single = data.data
            if (single != null && single.scheme == "content" && !single.authority.isNullOrBlank()) {
                collected.add(single)
            }
        }
        return collected
    }

    private fun copyContentUriIntoPrivateDir(
        uri: Uri,
        isImage: Boolean,
    ): Map<String, Any> {
        val resolver = activity.contentResolver
        var rawName: String? = null
        var reportedSize: Long? = null
        resolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    rawName = cursor.getString(nameIndex)
                }
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    reportedSize = cursor.getLong(sizeIndex)
                }
            }
        }
        val knownSize = reportedSize
        if (knownSize != null && knownSize > ManualAttachmentPathPolicy.MAX_FILE_BYTES) {
            throw FileTooLargeException()
        }
        val rawMime = resolver.getType(uri)
        val defaultMime = if (isImage) "image/jpeg" else "application/octet-stream"
        val rawExtHint = rawName?.substringAfterLast('/')?.substringAfterLast('\\')
        val displayName = ManualAttachmentPathPolicy.sanitizeDisplayName(
            rawName,
            fallback = if (isImage) "图片" else "本地文件",
        )
        val ext = ManualAttachmentPathPolicy.sanitizeExtension(
            rawExtHint,
            rawMime,
            fallback = if (isImage) "jpg" else "bin",
        )
        val guessedMime = guessMimeForExtension(ext, rawExtHint ?: displayName)
        val preferredMime = if (isGenericMime(rawMime)) {
            guessedMime ?: rawMime
        } else {
            rawMime
        }
        val mimeType = ManualAttachmentPathPolicy.sanitizeMimeType(preferredMime, defaultMime)
        val id = nextAttachmentId()
        val relativePath = ManualAttachmentPathPolicy.buildUniqueRelativePath(id, ext)
        val dest = ManualAttachmentPathPolicy.resolveTargetFile(activity.filesDir, relativePath)
            ?: throw IllegalStateException("Invalid target path")
        dest.parentFile?.mkdirs()
        var succeeded = false
        try {
            val written = resolver.openInputStream(uri)?.use { input ->
                copyStreamBounded(input, dest, ManualAttachmentPathPolicy.MAX_FILE_BYTES)
            } ?: throw IllegalStateException("Cannot open input stream")
            succeeded = true
            return mapOf(
                "id" to id,
                "kind" to if (isImage) "image" else "file",
                "name" to displayName,
                "relativePath" to relativePath,
                "mimeType" to mimeType,
                "sizeBytes" to written,
                "addedAtMs" to System.currentTimeMillis(),
            )
        } finally {
            if (!succeeded) {
                dest.delete()
            }
        }
    }

    private fun copyStreamBounded(
        input: InputStream,
        dest: File,
        maxBytes: Long,
    ): Long {
        val buffer = ByteArray(16 * 1024)
        var total = 0L
        FileOutputStream(dest).use { output ->
            while (true) {
                val read = input.read(buffer)
                if (read == -1) break
                total += read
                if (total > maxBytes) {
                    throw FileTooLargeException()
                }
                output.write(buffer, 0, read)
            }
            output.flush()
        }
        return total
    }

    private fun nextAttachmentId(): String =
        "att_${System.currentTimeMillis()}_${UUID.randomUUID().toString().replace("-", "").take(8)}"

    private fun isGenericMime(mime: String?): Boolean {
        val base = mime?.substringBefore(';')?.trim()?.lowercase(Locale.US)
        return base.isNullOrEmpty() || base == "*/*" || base == "application/octet-stream"
    }

    private fun guessMimeForExtension(ext: String, name: String): String? =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: URLConnection.guessContentTypeFromName(name)

    private fun finishOperation(
        op: PendingOperation,
        createdPaths: List<String> = emptyList(),
        deliver: (MethodChannel.Result) -> Unit,
    ) {
        mainHandler.post {
            if (closed || pending !== op) {
                deleteRelativePaths(createdPaths)
                return@post
            }
            pending = null
            op.captureFile = null
            if (op.generation != storageGeneration) {
                deleteRelativePaths(createdPaths)
                op.result.success(null)
                return@post
            }
            deliver(op.result)
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        attachmentChannel.setMethodCallHandler(null)
        val op = pending
        pending = null
        op?.captureFile?.delete()
        op?.captureFile = null
        op?.result?.error("file_closed", "文件选择已中止", null)
        // Let the single worker finish its finally block so temp/aborted files always delete.
        ioExecutor.shutdown()
    }

    companion object {
        private const val TAG = "PersonalFileBridge"
        private const val REQUEST_CODE_LEGACY_PICK = 6183
        private const val REQUEST_CODE_CAPTURE_PHOTO = 6184
        private const val REQUEST_CODE_PICK_IMAGES = 6185
        private const val REQUEST_CODE_PICK_ATTACHMENT_FILE = 6186
    }
}
