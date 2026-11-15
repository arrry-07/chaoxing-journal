package com.example.studyassistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

@RunWith(AndroidJUnit4::class)
class ReminderAggregateNotificationTest {
    private lateinit var context: Context
    private lateinit var manager: NotificationManager
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private lateinit var channelId: String
    private var epoch = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        manager = context.getSystemService(NotificationManager::class.java)
        database = ReminderDatabase.get(context)
        accountHash = "synthetic-aggregate-${System.nanoTime()}"
        epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(accountHash, epoch, true, 240, false, true, true)
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        assertTrue("Grant POST_NOTIFICATIONS to the isolated QA app", manager.areNotificationsEnabled())
        // Other tests deliberately disable the production channel. Android
        // remembers that importance even after deleting/recreating a channel.
        channelId = "synthetic-aggregate-${System.nanoTime()}"
        manager.createNotificationChannel(NotificationChannel(
            channelId, "合成聚合提醒", NotificationManager.IMPORTANCE_DEFAULT,
        ))
    }

    @After
    fun tearDown() {
        if (::accountHash.isInitialized) {
            AssignmentNotificationPublisher.cancelForAccount(context, database, accountHash)
            database.clearActiveAccount(accountHash)
        }
        if (::channelId.isInitialized) manager.deleteNotificationChannel(channelId)
    }

    @Test
    fun unknownActivityKeepsSubmittedFormalNotificationAndDetailClick() {
        assertSurvivor(formalSurvives = true)
    }

    @Test
    fun unknownFormalKeepsSubmittedActivityNotificationAndDetailClick() {
        assertSurvivor(formalSurvives = false)
    }

    @Test
    fun remainingMembersStayAggregatedUnderOriginalNotificationId() {
        val formal = snapshot("formal-A", formal = true)
        val activity = snapshot("activity-B", formal = false)
        val otherFormal = snapshot("formal-C", formal = true)
        val originals = listOf(formal, activity, otherFormal)
        val sharedId = publishBatch(originals)

        val application = apply(listOf(formal, activity.copy(status = "unknown"), otherFormal))
        reconcile(application)

        val notification = awaitNotification(sharedId) {
            val text = it.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
            text.contains("共 2 项") && !text.contains(activity.title)
        }
        val text = notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
        assertTrue(text.contains("共 2 项"))
        assertTrue(text.contains(formal.title))
        assertTrue(text.contains(otherFormal.title))
        assertFalse(text.contains(activity.title))
        for (survivor in listOf(formal, otherFormal)) {
            assertEquals(ReminderDatabase.STATUS_SUBMITTED, database.event(event(survivor).eventId)!!.status)
            assertEquals(sharedId, database.event(event(survivor).eventId)!!.notificationId)
        }
        assertTrue(database.pendingNewEvents(accountHash).isEmpty())
    }

    @Test
    fun fullyInvalidatedBatchIsRemoved() {
        val originals = listOf(snapshot("formal-A", true), snapshot("activity-B", false))
        val sharedId = publishBatch(originals)
        reconcile(apply(originals.map { it.copy(status = "unknown") }))
        awaitAbsent(sharedId)
        assertTrue(database.eventsForAccount(accountHash).all {
            it.status == ReminderDatabase.STATUS_CANCELLED
        })
    }

    @Test
    fun dismissedBatchIsNotPostedAgainWhenOneMemberBecomesUnknown() {
        val formal = snapshot("formal-A", true)
        val activity = snapshot("activity-B", false)
        val sharedId = publishBatch(listOf(formal, activity))
        manager.cancel(sharedId)
        awaitAbsent(sharedId)

        reconcile(apply(listOf(formal, activity.copy(status = "unknown"))))
        assertFalse(AssignmentNotificationPublisher.publishPendingNewAssignments(
            context, database, accountHash, Instant.now(), channelId,
        ).submitted)
        assertFalse(manager.activeNotifications.any { it.id == sharedId })
        assertEquals(ReminderDatabase.STATUS_SUBMITTED, database.event(event(formal).eventId)!!.status)
    }

    private fun assertSurvivor(formalSurvives: Boolean) {
        val formal = snapshot("formal-A", true)
        val activity = snapshot("activity-B", false)
        val sharedId = publishBatch(listOf(formal, activity))
        val originalWhen = awaitNotification(sharedId).`when`
        val survivor = if (formalSurvives) formal else activity
        val invalid = if (formalSurvives) activity else formal
        val application = apply(listOf(survivor, invalid.copy(status = "unknown")))
        assertEquals(listOf(event(invalid).eventId), application.invalidatedEvents.map { it.eventId })

        reconcile(application)
        val notification = awaitNotification(sharedId) {
            val text = it.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
            text.contains(survivor.title) && !text.contains(invalid.title)
        }
        val text = notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
        assertTrue(text.contains(survivor.title))
        assertFalse(text.contains(invalid.title))
        assertEquals(originalWhen, notification.`when`)
        assertTrue(notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0)
        val stored = database.event(event(survivor).eventId)!!
        assertEquals(ReminderDatabase.STATUS_SUBMITTED, stored.status)
        assertEquals(sharedId, stored.notificationId)
        assertTrue(AssignmentNotificationPublisher.matchesClickIntent(context, notification.contentIntent, stored))
        assertEquals(ReminderDatabase.STATUS_CANCELLED, database.event(event(invalid).eventId)!!.status)
        assertTrue(database.pendingNewEvents(accountHash).isEmpty())
        assertEquals(setOf(formal.assignmentId, activity.assignmentId),
            database.loadPlanState(accountHash, epoch).sentNewAssignmentIds)

        // A pending-only pass cannot repair this regression. Reconciliation
        // must already have retained the submitted member, and is idempotent.
        reconcile(application)
        assertFalse(AssignmentNotificationPublisher.publishPendingNewAssignments(
            context, database, accountHash, Instant.now(), channelId,
        ).submitted)
        assertTrue(manager.activeNotifications.any { it.id == sharedId })
    }

    private fun publishBatch(snapshots: List<StoredReminderSnapshot>): Int {
        val events = snapshots.map(::event)
        apply(snapshots, events)
        val result = AssignmentNotificationPublisher.publishPendingNewAssignments(
            context, database, accountHash, Instant.now(), channelId,
        )
        assertTrue("Actual aggregate delivery failed: ${result.warning}", result.submitted)
        val id = result.notificationId!!
        assertEquals(ReminderDatabase.stableNotificationId(
            "new:$accountHash:${events.map { it.eventId }.sorted().joinToString("|")}",
        ), id)
        for (event in events) {
            val stored = database.event(event.eventId)!!
            assertEquals(ReminderDatabase.STATUS_SUBMITTED, stored.status)
            assertEquals(id, stored.notificationId)
        }
        awaitNotification(id)
        return id
    }

    private fun reconcile(application: ReminderDatabase.PlanApplication) {
        assertEquals(null, AssignmentNotificationPublisher.reconcileInvalidatedEvents(
            context, database, application.invalidatedEvents,
        ))
    }

    private fun snapshot(name: String, formal: Boolean) = StoredReminderSnapshot(
        accountHash = accountHash,
        assignmentId = "cx:${if (formal) "work" else "activity"}:synthetic:class:$name",
        sessionEpoch = epoch,
        courseName = "合成课程",
        title = name,
        deadlineAt = null,
        deadlineTrusted = true,
        deadlineReadFailed = false,
        status = "pending",
        completed = false,
        hidden = false,
        followed = true,
        formal = formal,
        inAssignmentScope = true,
    )

    private fun event(snapshot: StoredReminderSnapshot): StoredReminderEvent {
        val id = "$accountHash|${snapshot.assignmentId}|new"
        return StoredReminderEvent(
            id, accountHash, epoch, ReminderDatabase.EVENT_NEW, snapshot.assignmentId,
            snapshot.courseName, snapshot.title, System.currentTimeMillis(), null,
            emptyList(), "synthetic-batch", ReminderDatabase.STATUS_PENDING,
            ReminderDatabase.stableNotificationId(id),
        )
    }

    private fun apply(
        snapshots: List<StoredReminderSnapshot>,
        events: List<StoredReminderEvent> = emptyList(),
    ) = database.applyPlan(
        accountHash, epoch, true, snapshots.map { it.assignmentId }.toSet(),
        snapshots, events, System.currentTimeMillis(), null, true,
        database.loadPlanState(accountHash, epoch).mutationVersion,
        setOf("courseWork", "classroomActivity:35"),
    )

    private fun awaitNotification(
        id: Int,
        matches: (Notification) -> Boolean = { true },
    ): Notification {
        repeat(50) {
            manager.activeNotifications.firstOrNull { it.id == id }?.let {
                if (matches(it.notification)) return it.notification
            }
            SystemClock.sleep(20)
        }
        error("Expected notification $id")
    }

    private fun awaitAbsent(id: Int) {
        repeat(50) {
            if (manager.activeNotifications.none { it.id == id }) return
            SystemClock.sleep(20)
        }
        error("Unexpected notification $id")
    }
}
