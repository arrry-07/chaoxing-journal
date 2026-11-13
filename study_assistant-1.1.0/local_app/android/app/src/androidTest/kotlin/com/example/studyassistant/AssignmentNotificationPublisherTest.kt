package com.example.studyassistant

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.time.Instant

@RunWith(AndroidJUnit4::class)
// Android preserves a deleted channel's settings when it is recreated. On a
// fresh test install, create the disabled channel before tests that create it.
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AssignmentNotificationPublisherTest {
    private lateinit var context: Context
    private lateinit var notificationManager: NotificationManager
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private var notificationId = 0

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        notificationManager = context.getSystemService(NotificationManager::class.java)
        database = ReminderDatabase.get(context)
        accountHash = "instrumentation-disabled-channel-${System.nanoTime()}"
        notificationManager.deleteNotificationChannel(
            AssignmentNotificationPublisher.CHANNEL_UPDATES,
        )
        notificationId = seedPendingNewAssignment()
    }

    @After
    fun tearDown() {
        runCatching { notificationManager.cancel(notificationId) }
        runCatching {
            AssignmentNotificationPublisher.cancelForAccount(
                context,
                database,
                accountHash,
            )
        }
        runCatching { database.clearActiveAccount(accountHash) }
        notificationManager.deleteNotificationChannel(
            AssignmentNotificationPublisher.CHANNEL_UPDATES,
        )
    }

    @Test
    fun aDisabledChannelKeepsNewAssignmentPending() {
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        notificationManager.createNotificationChannel(
            NotificationChannel(
                AssignmentNotificationPublisher.CHANNEL_UPDATES,
                "测试关闭通道",
                NotificationManager.IMPORTANCE_NONE,
            ),
        )
        assertEquals(
            "测试前置条件：系统渠道必须处于关闭状态",
            NotificationManager.IMPORTANCE_NONE,
            notificationManager.getNotificationChannel(
                AssignmentNotificationPublisher.CHANNEL_UPDATES,
            ).importance,
        )
        val result = AssignmentNotificationPublisher.publishPendingNewAssignments(
            context,
            database,
            accountHash,
            Instant.now(),
        )

        assertFalse(result.submitted)
        assertEquals("对应通知通道已关闭，请在系统通知设置中重新开启", result.warning)
        assertEquals(
            ReminderDatabase.STATUS_PENDING,
            database.eventsForAccount(accountHash).single().status,
        )
        assertFalse(
            notificationManager.activeNotifications.any {
                it.id == notificationId
            },
        )
    }

    @Test
    fun pendingUpdateKeepsDeadlineEventPending() {
        val event = seedPendingDeadlineAssignment()
        database.markPendingUpdate(accountHash, event.sessionEpoch)

        val result = AssignmentNotificationPublisher.publishDeadline(
            context,
            database,
            event,
            Instant.now(),
        )

        assertFalse(result.submitted)
        assertEquals(
            ReminderDatabase.STATUS_PENDING,
            database.eventsForAccount(accountHash)
                .single { it.eventId == event.eventId }
                .status,
        )
    }

    private fun seedPendingNewAssignment(): Int {
        val sessionEpoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            backgroundEnabled = true,
            intervalMinutes = 240,
            listenerEnabled = true,
            newAssignmentEnabled = true,
            showDetails = true,
        )
        val state = database.loadPlanState(accountHash, sessionEpoch)
        val assignmentId = "cx:work:instrumentation:class:new"
        val eventId = "$accountHash|$assignmentId|new"
        val stableId = ReminderDatabase.stableNotificationId(eventId)
        val now = System.currentTimeMillis()
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            baselineCompleted = true,
            knownIds = setOf(assignmentId),
            snapshots = listOf(
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = assignmentId,
                    sessionEpoch = sessionEpoch,
                    courseName = "合成课程",
                    title = "合成新增作业",
                    deadlineAt = null,
                    deadlineTrusted = false,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = true,
                ),
            ),
            events = listOf(
                StoredReminderEvent(
                    eventId = eventId,
                    accountHash = accountHash,
                    sessionEpoch = sessionEpoch,
                    type = ReminderDatabase.EVENT_NEW,
                    assignmentId = assignmentId,
                    courseName = "合成课程",
                    title = "合成新增作业",
                    notifyAt = now,
                    deadlineAt = null,
                    offsets = emptyList(),
                    batchId = null,
                    status = ReminderDatabase.STATUS_PENDING,
                    notificationId = stableId,
                ),
            ),
            completedAt = now,
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )
        return stableId
    }

    private fun seedPendingDeadlineAssignment(): StoredReminderEvent {
        val sessionEpoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            backgroundEnabled = true,
            intervalMinutes = 240,
            listenerEnabled = true,
            newAssignmentEnabled = true,
            showDetails = true,
        )
        val state = database.loadPlanState(accountHash, sessionEpoch)
        val assignmentId = "cx:work:instrumentation:class:deadline"
        val deadlineAt = System.currentTimeMillis() + 3_600_000L
        val eventId = "$accountHash|$assignmentId|deadline:$deadlineAt|60"
        val stableId = ReminderDatabase.stableNotificationId(eventId)
        val now = System.currentTimeMillis()
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = sessionEpoch,
            baselineCompleted = true,
            knownIds = setOf(assignmentId),
            snapshots = listOf(
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = assignmentId,
                    sessionEpoch = sessionEpoch,
                    courseName = "合成课程",
                    title = "合成截止作业",
                    deadlineAt = deadlineAt,
                    deadlineTrusted = true,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = true,
                ),
            ),
            events = listOf(
                StoredReminderEvent(
                    eventId = eventId,
                    accountHash = accountHash,
                    sessionEpoch = sessionEpoch,
                    type = ReminderDatabase.EVENT_DEADLINE,
                    assignmentId = assignmentId,
                    courseName = "合成课程",
                    title = "合成截止作业",
                    notifyAt = deadlineAt - 60_000L,
                    deadlineAt = deadlineAt,
                    offsets = listOf(1),
                    batchId = null,
                    status = ReminderDatabase.STATUS_PENDING,
                    notificationId = stableId,
                ),
            ),
            completedAt = now,
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )
        return database.pendingDeadlineEvents(accountHash).single()
    }
}
