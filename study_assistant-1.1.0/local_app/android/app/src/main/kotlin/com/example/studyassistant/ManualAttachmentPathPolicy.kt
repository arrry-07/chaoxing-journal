package com.example.studyassistant

import java.io.File
import java.util.Locale

internal object ManualAttachmentPathPolicy {
    const val ATTACHMENTS_DIR = "manual_attachments"
    const val CAMERA_CAPTURE_DIR = "camera_captures"
    const val STORAGE_PREFIX = "$ATTACHMENTS_DIR/"
    const val MAX_FILE_BYTES = 20L * 1024L * 1024L
    const val MAX_RELATIVE_PATH_LENGTH = 260
    const val MAX_IMAGES_PER_PICK = 9
    const val MAX_DISPLAY_NAME_LENGTH = 200

    private val segmentPattern = Regex("^[A-Za-z0-9._-]+$")
    private val extensionPattern = Regex("^[a-z0-9]{1,12}$")

    fun isValidRelativePath(relativePath: String?): Boolean {
        if (relativePath.isNullOrEmpty() ||
            relativePath.length > MAX_RELATIVE_PATH_LENGTH ||
            !relativePath.startsWith(STORAGE_PREFIX) ||
            relativePath.contains('\\') ||
            relativePath.contains("..") ||
            relativePath.contains("//") ||
            relativePath.endsWith('/')
        ) {
            return false
        }
        val tail = relativePath.substring(STORAGE_PREFIX.length)
        if (tail.isEmpty() || tail.startsWith('/')) return false
        val segments = tail.split('/')
        for (segment in segments) {
            if (segment.isEmpty() ||
                segment == "." ||
                segment == ".." ||
                !segmentPattern.matches(segment)
            ) {
                return false
            }
        }
        return true
    }

    fun resolveTargetFile(filesDir: File, relativePath: String?): File? {
        if (!isValidRelativePath(relativePath)) return null
        return try {
            val root = File(filesDir, ATTACHMENTS_DIR)
            val rootPrefix = root.canonicalPath.let {
                if (it.endsWith(File.separator)) it else it + File.separator
            }
            val candidate = File(filesDir, relativePath!!)
            val candidatePath = candidate.canonicalPath
            if (!candidatePath.startsWith(rootPrefix)) null else candidate
        } catch (_: Exception) {
            null
        }
    }

    fun isAllowedSize(sizeBytes: Long): Boolean = sizeBytes in 0L..MAX_FILE_BYTES

    fun sanitizeDisplayName(raw: String?, fallback: String = "本地文件"): String {
        val cleaned = raw
            .orEmpty()
            .replace(Regex("[\\r\\n\\u0000-\\u0008\\u000B-\\u001F]+"), "")
            .replace(Regex("[\\t/\\\\]+"), " ")
            .replace(Regex(" {2,}"), " ")
            .trim { it.isWhitespace() }
        if (cleaned.isEmpty()) return fallback
        if (cleaned.length <= MAX_DISPLAY_NAME_LENGTH) {
            return cleaned
        }
        var cut = cleaned.substring(0, MAX_DISPLAY_NAME_LENGTH)
        if (cut.isNotEmpty() && Character.isHighSurrogate(cut.last())) {
            cut = cut.dropLast(1)
        }
        return cut.trim { it.isWhitespace() }.ifEmpty { fallback }
    }

    fun sanitizeExtension(
        displayName: String?,
        mimeType: String?,
        fallback: String = "bin",
    ): String {
        val fromName = displayName
            ?.substringAfterLast('.', "")
            ?.lowercase(Locale.US)
            ?.takeIf { extensionPattern.matches(it) }
        if (fromName != null) return fromName

        val normalizedMime = mimeType
            ?.substringBefore(';')
            ?.trim()
            ?.lowercase(Locale.US)
        val mapped = when (normalizedMime) {
            "image/jpeg", "image/jpg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            "image/heic" -> "heic"
            "image/heif" -> "heif"
            "application/pdf" -> "pdf"
            "text/plain" -> "txt"
            "application/zip" -> "zip"
            "application/msword" -> "doc"
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> "docx"
            "application/vnd.ms-excel" -> "xls"
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xlsx"
            "application/vnd.ms-powerpoint" -> "ppt"
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" -> "pptx"
            else -> null
        }
        if (mapped != null) return mapped
        return if (extensionPattern.matches(fallback.lowercase(Locale.US))) {
            fallback.lowercase(Locale.US)
        } else {
            "bin"
        }
    }

    fun sanitizeMimeType(raw: String?, fallback: String): String {
        val base = raw?.substringBefore(';')?.trim()
        if (base.isNullOrEmpty() || base.length > 120) return fallback
        val mimePattern = Regex("^[A-Za-z0-9!#\$&^_.+-]+/[A-Za-z0-9!#\$&^_.+-]+\$")
        return if (mimePattern.matches(base)) base else fallback
    }

    fun buildUniqueRelativePath(id: String, extension: String): String {
        val safeId = id.replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trim('.')
            .ifEmpty { "att" }
            .take(100)
        val safeExt = extension.lowercase(Locale.US)
            .takeIf { extensionPattern.matches(it) }
            ?: "bin"
        val relativePath = "$STORAGE_PREFIX$safeId.$safeExt"
        require(isValidRelativePath(relativePath)) { "Invalid attachment path" }
        return relativePath
    }
}
