package com.example.studyassistant

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class ReminderApiMatrixTest {
    private lateinit var context: Context
    private lateinit var manager: NotificationManager
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private var epoch = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        manager = context.getSystemService(NotificationManager::class.java)
        database = ReminderDatabase.get(context)
        accountHash = "instrumentation-matrix-${System.nanoTime()}"
        epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = epoch,
            backgroundEnabled = true,
            intervalMinutes = 240,
            listenerEnabled = true,
            newAssignmentEnabled = true,
            showDetails = false,
        )
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
    }

    @After
    fun tearDown() {
        if (::accountHash.isInitialized) {
            runCatching {
                AssignmentNotificationPublisher.cancelForAccount(
                    context,
                    database,
                    accountHash,
                )
            }
            runCatching {
                AssignmentAlarmScheduler.cancelNewAssignmentWindow(context, accountHash)
                database.pendingDeadlineEvents(accountHash).forEach {
                    AssignmentAlarmScheduler.cancelDeadline(context, it)
                }
            }
            runCatching {
                WorkManager.getInstance(context).cancelUniqueWork(
                    BackgroundWorkScheduler.daytimeWorkName(accountHash, epoch),
                ).result.get(5, TimeUnit.SECONDS)
            }
            runCatching { database.clearActiveAccount(accountHash) }
        }
    }

    @Test
    fun aFreshInstallApi33NotificationDeniedBlocksAndPreservesPending() {
        assumeTrue(
            "Requires API 33+ fresh install",
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
        )
        assertFalse(
            "Requires a fresh install with POST_NOTIFICATIONS denied; " +
                "run this class in an isolated new-install batch",
            manager.areNotificationsEnabled(),
        )
        val control = ReminderHistoryStore.controlSnapshot(context, accountHash, epoch)
        ReminderHistoryStore.enableSession(
            context,
            database,
            accountHash,
            epoch,
            control.historyGeneration,
        )
        val shanghai = ZoneId.of("Asia/Shanghai")
        val daytimeNow = ZonedDateTime.now(shanghai).plusDays(1)
            .withHour(10).withMinute(0).withSecond(0).withNano(0)
        val deadline = daytimeNow.plusHours(1).toInstant().toEpochMilli()
        val deadlineEvent = seedDeadline(
            assignmentId = "cx:work:matrix:deadline",
            deadlineAt = deadline,
            notifyAt = deadline - 60_000L,
        )
        val newEvent = seedNew(
            assignmentId = "cx:work:matrix:new",
        )
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(newEvent.assignmentId, deadlineEvent.assignmentId),
            snapshots = listOf(
                snapshot(
                    deadlineEvent.assignmentId,
                    deadlineAt = deadline,
                ),
                snapshot(newEvent.assignmentId),
            ),
            events = listOf(deadlineEvent, newEvent),
            completedAt = System.currentTimeMillis(),
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = database.loadPlanState(accountHash, epoch)
                .mutationVersion,
        )

        val deadlineResult = AssignmentNotificationPublisher.publishDeadline(
            context,
            database,
            deadlineEvent,
            daytimeNow.toInstant(),
            shanghai,
        )
        val newResult = AssignmentNotificationPublisher.publishPendingNewAssignments(
            context,
            database,
            accountHash,
            daytimeNow.toInstant(),
            AssignmentNotificationPublisher.CHANNEL_UPDATES,
        )
        assertFalse(deadlineResult.submitted)
        assertFalse(newResult.submitted)
        assertEquals(
            ReminderDatabase.STATUS_PENDING,
            database.event(deadlineEvent.eventId)!!.status,
        )
        assertEquals(
            ReminderDatabase.STATUS_PENDING,
            database.event(newEvent.eventId)!!.status,
        )
        assertFalse(manager.activeNotifications.any {
            it.id == deadlineEvent.notificationId || it.id == newEvent.notificationId
        })

        val observationContext = ReminderHistoryStore.acquireObservationContext(
            context,
            database,
            accountHash,
            epoch,
        )
        val history = ReminderHistoryStore.listHistory(
            context,
            database,
            observationContext,
            snapshotMaxId = null,
            beforeId = null,
            category = null,
            subjectRefs = emptyList(),
        )
        val items = history["items"] as List<*>
        assertEquals(2, items.size)
        for (raw in items) {
            val item = raw as Map<*, *>
            assertEquals("blocked", item["stage"])
            assertEquals("notificationPermissionOff", item["reasonCode"])
        }
    }

    @Test
    fun bGrantingNotificationPermissionUnblocksPendingDelivery() {
        assumeTrue(
            "Requires API 33+",
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
        )
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .grantRuntimePermission(
                context.packageName,
                Manifest.permission.POST_NOTIFICATIONS,
            )
        assertTrue(manager.areNotificationsEnabled())
        val shanghai = ZoneId.of("Asia/Shanghai")
        val daytimeNow = ZonedDateTime.now(shanghai).plusDays(1)
            .withHour(10).withMinute(0).withSecond(0).withNano(0)
        val deadline = daytimeNow.plusHours(1).toInstant().toEpochMilli()
        val event = seedDeadline(
            assignmentId = "cx:work:matrix:granted",
            deadlineAt = deadline,
            notifyAt = deadline - 60_000L,
        )
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(event.assignmentId),
            snapshots = listOf(snapshot(event.assignmentId, deadlineAt = deadline)),
            events = listOf(event),
            completedAt = System.currentTimeMillis(),
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = database.loadPlanState(accountHash, epoch)
                .mutationVersion,
        )
        val result = AssignmentNotificationPublisher.publishDeadline(
            context,
            database,
            event,
            daytimeNow.toInstant(),
            shanghai,
        )
        assertTrue("Expected delivery: ${result.warning}", result.submitted)
        assertEquals(
            ReminderDatabase.STATUS_SUBMITTED,
            database.event(event.eventId)!!.status,
        )
        assertTrue(waitForNotification(event.notificationId))
    }

    @Test
    fun cFreshInstallApi34ExactAlarmDeniedFallsBackToInexactWithoutCrashing() {
        assumeTrue(
            "Requires API 34+ default-denied exact alarm",
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE,
        )
        val alarms = context.getSystemService(AlarmManager::class.java)
        assertFalse(
            "Fresh install on API 34+ must start without exact alarm access",
            alarms.canScheduleExactAlarms(),
        )
        val event = seedDeadline(
            assignmentId = "cx:work:matrix:inexact",
            deadlineAt = System.currentTimeMillis() + 2 * 60 * 60 * 1000L,
            notifyAt = System.currentTimeMillis() + 60 * 60 * 1000L,
        )
        AssignmentAlarmScheduler.scheduleDeadline(context, event)
        assertTrue(AssignmentAlarmScheduler.hasDeadlineAlarm(context, event))
    }

    @Test
    fun dExactAlarmPermissionGrantedBroadcastReconcilesAlarmsAndWorkConstraints() {
        assumeTrue(
            "Requires API 31+",
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S,
        )
        if (!context.getSystemService(AlarmManager::class.java)
                .canScheduleExactAlarms()
        ) {
            val descriptor = InstrumentationRegistry.getInstrumentation()
                .uiAutomation.executeShellCommand(
                    "appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow",
                )
            ParcelFileDescriptor.AutoCloseInputStream(descriptor)
                .bufferedReader()
                .use { it.readText() }
        }
        val alarms = context.getSystemService(AlarmManager::class.java)
        assertTrue(alarms.canScheduleExactAlarms())

        val event = seedDeadline(
            assignmentId = "cx:work:matrix:exact",
            deadlineAt = System.currentTimeMillis() + 2 * 60 * 60 * 1000L,
            notifyAt = System.currentTimeMillis() + 60 * 60 * 1000L,
        )
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(event.assignmentId),
            snapshots = listOf(
                snapshot(
                    event.assignmentId,
                    deadlineAt = event.deadlineAt,
                ),
            ),
            events = listOf(event),
            completedAt = System.currentTimeMillis(),
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = database.loadPlanState(accountHash, epoch)
                .mutationVersion,
        )
        AssignmentAlarmScheduler.reconcile(context, database)
        BackgroundWorkScheduler.reconcileAfterSystemChange(context, database)
        ReminderSystemReceiver().onReceive(
            context,
            Intent("android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"),
        )

        assertTrue(AssignmentAlarmScheduler.hasDeadlineAlarm(context, event))
        val name = BackgroundWorkScheduler.daytimeWorkName(accountHash, epoch)
        val work = waitForEnqueuedWork(name)
        assertTrue(
            work.constraints.requiredNetworkType == NetworkType.CONNECTED,
        )
    }

    private fun snapshot(
        assignmentId: String,
        deadlineAt: Long? = null,
    ) = StoredReminderSnapshot(
        accountHash = accountHash,
        assignmentId = assignmentId,
        sessionEpoch = epoch,
        courseName = "合成课程",
        title = "合成提醒",
        deadlineAt = deadlineAt,
        deadlineTrusted = true,
        deadlineReadFailed = false,
        status = "pending",
        completed = false,
        hidden = false,
        followed = true,
        formal = true,
    )

    private fun seedDeadline(
        assignmentId: String,
        deadlineAt: Long,
        notifyAt: Long,
    ): StoredReminderEvent {
        val eventId = "$accountHash|$assignmentId|deadline:$deadlineAt|60"
        return StoredReminderEvent(
            eventId = eventId,
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = assignmentId,
            courseName = "合成课程",
            title = "合成提醒",
            notifyAt = notifyAt,
            deadlineAt = deadlineAt,
            offsets = listOf(1),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId(eventId),
            deadlineSource = "official",
        )
    }

    private fun seedNew(assignmentId: String): StoredReminderEvent {
        val eventId = "$accountHash|$assignmentId|new"
        return StoredReminderEvent(
            eventId = eventId,
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_NEW,
            assignmentId = assignmentId,
            courseName = "合成课程",
            title = "合成新作业",
            notifyAt = System.currentTimeMillis(),
            deadlineAt = null,
            offsets = emptyList(),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId(eventId),
        )
    }

    private fun waitForNotification(id: Int): Boolean {
        repeat(100) {
            if (manager.activeNotifications.any { it.id == id }) return true
            SystemClock.sleep(20)
        }
        return false
    }

    private fun waitForEnqueuedWork(name: String): WorkInfo {
        repeat(100) {
            val infos = WorkManager.getInstance(context)
                .getWorkInfosForUniqueWork(name)
                .get(5, TimeUnit.SECONDS)
            infos.firstOrNull { it.state == WorkInfo.State.ENQUEUED }?.let {
                return it
            }
            SystemClock.sleep(20)
        }
        error("Expected unique work $name to be ENQUEUED")
    }
}
