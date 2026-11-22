package com.example.studyassistant

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.time.ZoneId
import java.util.TimeZone

// Run this class alone in a disposable Android test install with fresh channels.
@RunWith(AndroidJUnit4::class)
class Batch2BAlarmReconcileTest {
    @Test
    fun bootReconcileDeliversPendingNewAssignmentDuringDaytime() {
        assertDaytimeDelivery { context, database ->
            AssignmentAlarmScheduler.reconcile(context, database)
        }
    }

    @Test
    fun timeZoneReconcileDeliversPendingNewAssignmentDuringDaytime() {
        assertDaytimeDelivery { context, database ->
            AssignmentAlarmScheduler.rescheduleForTimeZoneChange(context, database)
        }
    }

    private fun assertDaytimeDelivery(reconcile: (Context, ReminderDatabase) -> Unit) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = ReminderDatabase.get(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        val accountHash = "instrumentation-reconcile-${System.nanoTime()}"
        val assignmentId = "cx:work:synthetic:class:new"
        val eventId = "$accountHash|$assignmentId|new"
        val notificationId = ReminderDatabase.stableNotificationId(eventId)
        val originalTimeZone = TimeZone.getDefault()

        val now = Instant.now()
        val zone = listOf("Etc/UTC", "Asia/Shanghai", "Pacific/Honolulu")
            .map(ZoneId::of)
            .first { now.atZone(it).hour in 10..20 }

        try {
            // The baseline entry points read the process clock. Choose a daytime
            // process zone without adjusting the Android device clock.
            TimeZone.setDefault(TimeZone.getTimeZone(zone.id))
            assertTrue(
                NativeReminderPolicy.isInDaytimeWindow(Instant.now(), ZoneId.systemDefault()),
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(
                    context.packageName,
                    Manifest.permission.POST_NOTIFICATIONS,
                )
            }
            assertTrue("notification permission must be enabled", manager.areNotificationsEnabled())
            assertTrue(
                "synthetic migration prerequisite",
                LegacyAssignmentMigrationState.confirm(context),
            )
            val channel =
                manager.getNotificationChannel(AssignmentNotificationPublisher.CHANNEL_UPDATES)
            assertTrue(
                "the test install needs a fresh or enabled updates channel",
                channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE,
            )
            seedPending(database, accountHash, assignmentId, eventId, notificationId)
            assertEquals(ReminderDatabase.STATUS_PENDING, database.event(eventId)?.status)
            assertFalse(AssignmentAlarmScheduler.hasNewAssignmentWindowAlarm(context, accountHash))

            reconcile(context, database)

            val scheduled = AssignmentAlarmScheduler.hasNewAssignmentWindowAlarm(context, accountHash)
            assertEquals(
                "daytime reconcile must submit immediately (window alarm present=$scheduled)",
                ReminderDatabase.STATUS_SUBMITTED,
                database.event(eventId)?.status,
            )
            assertFalse("daytime reconcile must not defer to the window alarm", scheduled)
            assertTrue(manager.activeNotifications.any { it.id == notificationId })
        } finally {
            TimeZone.setDefault(originalTimeZone)
            AssignmentAlarmScheduler.cancelNewAssignmentWindow(context, accountHash)
            manager.cancel(notificationId)
            if (database.readAccount(accountHash) != null) database.clearActiveAccount(accountHash)
        }
    }

    private fun seedPending(
        database: ReminderDatabase,
        accountHash: String,
        assignmentId: String,
        eventId: String,
        notificationId: Int,
    ) {
        val epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = epoch,
            backgroundEnabled = true,
            intervalMinutes = 240,
            listenerEnabled = true,
            newAssignmentEnabled = true,
            showDetails = false,
        )
        val now = System.currentTimeMillis()
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(assignmentId),
            snapshots = listOf(
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = assignmentId,
                    sessionEpoch = epoch,
                    courseName = "Synthetic course",
                    title = "Synthetic new assignment",
                    deadlineAt = null,
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
                    sessionEpoch = epoch,
                    type = ReminderDatabase.EVENT_NEW,
                    assignmentId = assignmentId,
                    courseName = "Synthetic course",
                    title = "Synthetic new assignment",
                    notifyAt = now,
                    deadlineAt = null,
                    offsets = emptyList(),
                    batchId = null,
                    status = ReminderDatabase.STATUS_PENDING,
                    notificationId = notificationId,
                ),
            ),
            completedAt = now,
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = database.loadPlanState(accountHash, epoch).mutationVersion,
        )
    }
}
