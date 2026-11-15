package com.example.studyassistant

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderSnapshotPolicyTest {
    private val now = 1_000_000L
    private val snapshot = StoredReminderSnapshot(
        accountHash = "synthetic-account",
        assignmentId = "cx:activity:synthetic:class:35",
        sessionEpoch = 1L,
        courseName = "合成课程",
        title = "合成任务",
        deadlineAt = now + 3_600_000L,
        deadlineTrusted = true,
        deadlineReadFailed = false,
        status = "pending",
        completed = false,
        hidden = false,
        followed = true,
        formal = false,
        inAssignmentScope = true,
    )
    private val event = StoredReminderEvent(
        eventId = "synthetic-deadline",
        accountHash = snapshot.accountHash,
        sessionEpoch = snapshot.sessionEpoch,
        type = ReminderDatabase.EVENT_DEADLINE,
        assignmentId = snapshot.assignmentId,
        courseName = snapshot.courseName,
        title = snapshot.title,
        notifyAt = now + 60_000L,
        deadlineAt = snapshot.deadlineAt,
        offsets = listOf(1),
        batchId = null,
        status = ReminderDatabase.STATUS_PENDING,
        notificationId = 1,
    )

    @Test
    fun classroomScopeIsEligibleWithoutClaimingFormalSource() {
        assertTrue(snapshot.matchesEvent(event, now))
        assertTrue(snapshot.copy(status = "returned").matchesEvent(event, now))
        assertFalse(snapshot.formal)
    }

    @Test
    fun unknownFailedAndUntrustedSnapshotsCannotDeliver() {
        for (invalid in listOf(
            snapshot.copy(status = "unknown"),
            snapshot.copy(status = "submitted"),
            snapshot.copy(status = "overdue"),
            snapshot.copy(deadlineReadFailed = true),
            snapshot.copy(deadlineTrusted = false),
            snapshot.copy(inAssignmentScope = false),
            snapshot.copy(hidden = true),
            snapshot.copy(followed = false),
            snapshot.copy(completed = true),
        )) {
            assertFalse(invalid.matchesEvent(event, now))
        }
    }

    @Test
    fun deadlineMustMatchSnapshotAndRemainInFuture() {
        assertFalse(snapshot.matchesEvent(event.copy(deadlineAt = null), now))
        assertFalse(snapshot.matchesEvent(event.copy(deadlineAt = snapshot.deadlineAt!! + 1), now))
        assertFalse(snapshot.matchesEvent(event.copy(notifyAt = snapshot.deadlineAt!!), now))
        assertFalse(snapshot.matchesEvent(event, snapshot.deadlineAt!!))
        assertFalse(snapshot.copy(deadlineAt = null).matchesEvent(event.copy(deadlineAt = null), now))
    }

    @Test
    fun eventIdentityMustMatchAccountSessionAndAssignment() {
        assertFalse(snapshot.matchesEvent(event.copy(accountHash = "other"), now))
        assertFalse(snapshot.matchesEvent(event.copy(sessionEpoch = 2), now))
        assertFalse(snapshot.matchesEvent(event.copy(assignmentId = "other"), now))
        assertFalse(snapshot.matchesEvent(event.copy(type = "unsupported"), now))
    }

    @Test
    fun confirmedNoDeadlineAllowsNewEvent() {
        val noDeadline = snapshot.copy(deadlineAt = null)
        assertTrue(noDeadline.matchesEvent(event.copy(
            type = ReminderDatabase.EVENT_NEW, deadlineAt = null,
        ), now))
        assertFalse(noDeadline.copy(deadlineTrusted = false).matchesEvent(event.copy(
            type = ReminderDatabase.EVENT_NEW, deadlineAt = null,
        ), now))
    }
}
