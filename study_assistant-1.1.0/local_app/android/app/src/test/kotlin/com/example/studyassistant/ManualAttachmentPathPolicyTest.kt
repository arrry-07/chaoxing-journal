package com.example.studyassistant

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class ManualAttachmentPathPolicyTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun relativePath_acceptsSafePathsAndRejectsTraversal() {
        assertTrue(ManualAttachmentPathPolicy.isValidRelativePath("manual_attachments/att_1.jpg"))
        assertTrue(ManualAttachmentPathPolicy.isValidRelativePath("manual_attachments/sub_dir/report-2026.pdf"))

        val invalidPaths = listOf(
            null,
            "",
            "manual_attachments/",
            "/manual_attachments/a.jpg",
            "updates/a.apk",
            "manual_attachments/../secret.jpg",
            "manual_attachments\\a.jpg",
            "manual_attachments//a.jpg",
            "manual_attachments/./a.jpg",
            "manual_attachments/中文.jpg",
            "manual_attachments/" + "a".repeat(250) + ".jpg",
        )
        for (path in invalidPaths) {
            assertFalse("Expected invalid path: $path", ManualAttachmentPathPolicy.isValidRelativePath(path))
        }
    }

    @Test
    fun resolveTargetFile_staysInsideAttachmentsRoot() {
        val filesDir = tempFolder.newFolder("files")
        val resolved = ManualAttachmentPathPolicy.resolveTargetFile(
            filesDir,
            "manual_attachments/photo_1.jpg",
        )
        assertNotNull(resolved)
        assertEquals(
            File(File(filesDir, "manual_attachments"), "photo_1.jpg").canonicalPath,
            resolved!!.canonicalPath,
        )

        assertNull(
            ManualAttachmentPathPolicy.resolveTargetFile(
                filesDir,
                "manual_attachments/../other.txt",
            ),
        )
        assertNull(
            ManualAttachmentPathPolicy.resolveTargetFile(
                filesDir,
                "updates/evil.apk",
            ),
        )
    }

    @Test
    fun sizeBoundary_enforces20MbCap() {
        assertTrue(ManualAttachmentPathPolicy.isAllowedSize(0L))
        assertTrue(ManualAttachmentPathPolicy.isAllowedSize(ManualAttachmentPathPolicy.MAX_FILE_BYTES))
        assertFalse(ManualAttachmentPathPolicy.isAllowedSize(-1L))
        assertFalse(ManualAttachmentPathPolicy.isAllowedSize(ManualAttachmentPathPolicy.MAX_FILE_BYTES + 1L))
    }

    @Test
    fun displayNameExtensionAndRelativePathBuilders_sanitizeInputs() {
        assertEquals("实验 报告.pdf", ManualAttachmentPathPolicy.sanitizeDisplayName("实验/报告\n.pdf"))
        assertEquals("本地文件", ManualAttachmentPathPolicy.sanitizeDisplayName("  /\\  "))
        assertEquals("pdf", ManualAttachmentPathPolicy.sanitizeExtension("notes.PDF", "application/octet-stream"))
        assertEquals("jpg", ManualAttachmentPathPolicy.sanitizeExtension("photo", "image/jpeg"))
        assertEquals("image/jpeg", ManualAttachmentPathPolicy.sanitizeMimeType("image/jpeg; charset=utf-8", "application/octet-stream"))
        assertEquals(
            "manual_attachments/att_123.jpg",
            ManualAttachmentPathPolicy.buildUniqueRelativePath("att:123", "jpg"),
        )
    }
}
