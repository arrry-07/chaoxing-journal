package com.example.studyassistant

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
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
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            runCatching {
                InstrumentationRegistry.getInstrumentation().uiAutomation
                    .grantRuntimePermission(
                        context.packageName,
                        Manifest.permission.POST_NOTIFICATIONS,
                    )
            }
        }
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
    fun bDisabledChannelKeepsClassroomActivityPending() {
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        notificationId = seedPendingNewAssignment(formal = false)
        notificationManager.createNotificationChannel(
            NotificationChannel(
                AssignmentNotificationPublisher.CHANNEL_UPDATES,
                "测试关闭通道",
                NotificationManager.IMPORTANCE_NONE,
            ),
        )
        val result = AssignmentNotificationPublisher.publishPendingNewAssignments(
            context, database, accountHash, Instant.now(),
        )
        assertFalse(result.submitted)
        assertEquals("对应通知通道已关闭，请在系统通知设置中重新开启", result.warning)
        val pending = database.pendingNewEvents(accountHash).single()
        val snapshot = database.snapshot(accountHash, pending.assignmentId)!!
        assertFalse(snapshot.formal)
        assertTrue(snapshot.inAssignmentScope)
        assertEquals("pending", snapshot.status)
    }

    @Test
    fun detailedDeadlineIsPrivateWithAnAnonymousPublicVersion() {
        val shanghai = ZoneId.of("Asia/Shanghai")
        val daytimeNow = ZonedDateTime.now(shanghai).plusDays(1)
            .withHour(10).withMinute(0).withSecond(0).withNano(0)
        val daytimeDeadline = daytimeNow.plusHours(1).toInstant().toEpochMilli()
        val event = seedPendingDeadlineAssignment(
            deadlineAtOverride = daytimeDeadline,
            notifyAtOverride = daytimeDeadline - 60_000L,
        )
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        assertTrue("Grant POST_NOTIFICATIONS on the isolated test app",
            notificationManager.areNotificationsEnabled())

        val result = AssignmentNotificationPublisher.publishDeadline(
            context, database, event, daytimeNow.toInstant(), shanghai,
        )

        assertTrue("Expected actual delivery: ${result.warning}", result.submitted)
        val notification = notificationManager.activeNotifications.single {
            it.id == event.notificationId && it.tag == null
        }.notification
        assertEquals(Notification.VISIBILITY_PRIVATE, notification.visibility)
        assertTrue(
            notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
                .contains(event.title),
        )
        assertTrue(AssignmentNotificationPublisher.matchesClickIntent(
            context, notification.contentIntent, event,
        ))
        val publicVersion = requireNotNull(notification.publicVersion)
        assertEquals(Notification.VISIBILITY_PUBLIC, publicVersion.visibility)
        assertEquals(
            "有作业即将截止，请打开课业手记查看",
            publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT).toString(),
        )
        assertEquals(notification.smallIcon.resId, publicVersion.smallIcon.resId)
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

    @Test
    fun reconcileInvalidatedEventsRecordsCancelledForPendingDeadlineWithoutActiveNotification() {
        val event = seedPendingDeadlineAssignment()
        val epoch = event.sessionEpoch
        ReminderHistoryStore.enableSession(context, database, accountHash, epoch, 1)
        val state = database.loadPlanState(accountHash, epoch)
        val application = database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(event.assignmentId),
            snapshots = emptyList(),
            events = emptyList(),
            completedAt = System.currentTimeMillis(),
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )
        assertEquals(1, application.invalidatedEvents.size)

        AssignmentNotificationPublisher.reconcileInvalidatedEvents(
            context,
            database,
            application.invalidatedEvents,
            Instant.now(),
        )

        val obsContext = ReminderHistoryStore.acquireObservationContext(
            context,
            database,
            accountHash,
            epoch,
        )
        @Suppress("UNCHECKED_CAST")
        val items = ReminderHistoryStore.listHistory(
            context,
            database,
            obsContext,
            snapshotMaxId = null,
            beforeId = null,
            category = null,
            subjectRefs = listOf("assignment" to event.assignmentId),
        )["items"] as List<Map<String, Any?>>
        assertTrue(
            items.any {
                it["logicalKey"] == event.eventId &&
                    it["stage"] == "cancelled" &&
                    it["reasonCode"] == "invalid"
            },
        )
    }

    @Test
    fun applyPlanAndRecordLogsScheduledOnceAndDefersNewAssignmentBeforeEight() {
        val epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = epoch,
            backgroundEnabled = true,
            intervalMinutes = 240,
            listenerEnabled = true,
            newAssignmentEnabled = true,
            showDetails = true,
        )
        ReminderHistoryStore.enableSession(context, database, accountHash, epoch, 1)

        val zone = ZoneId.of("Asia/Shanghai")
        val earlyNow = ZonedDateTime.now(zone).plusDays(7)
            .withHour(3).withMinute(0).withSecond(0).withNano(0)
        val deadlineAt = earlyNow.plusHours(12).toInstant().toEpochMilli()
        val deadlineAssignmentId = "cx:work:bridge:plan:deadline"
        val newAssignmentId = "cx:work:bridge:plan:new"
        val deadlineEventId = "$accountHash|$deadlineAssignmentId|deadline:$deadlineAt|60"
        val newEventId = "$accountHash|$newAssignmentId|new"
        val snapshots = listOf(
            StoredReminderSnapshot(
                accountHash = accountHash,
                assignmentId = deadlineAssignmentId,
                sessionEpoch = epoch,
                courseName = "桥接课程",
                title = "桥接截止作业",
                deadlineAt = deadlineAt,
                deadlineTrusted = true,
                deadlineReadFailed = false,
                status = "pending",
                completed = false,
                hidden = false,
                followed = true,
                formal = true,
                inAssignmentScope = true,
            ),
            StoredReminderSnapshot(
                accountHash = accountHash,
                assignmentId = newAssignmentId,
                sessionEpoch = epoch,
                courseName = "桥接课程",
                title = "桥接新增作业",
                deadlineAt = null,
                deadlineTrusted = true,
                deadlineReadFailed = false,
                status = "pending",
                completed = false,
                hidden = false,
                followed = true,
                formal = true,
                inAssignmentScope = true,
            ),
        )
        val deadlineEvent = StoredReminderEvent(
            eventId = deadlineEventId,
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = deadlineAssignmentId,
            courseName = "桥接课程",
            title = "桥接截止作业",
            notifyAt = deadlineAt - 3_600_000L,
            deadlineAt = deadlineAt,
            offsets = listOf(60),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId(deadlineEventId),
        )
        val newEvent = StoredReminderEvent(
            eventId = newEventId,
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_NEW,
            assignmentId = newAssignmentId,
            courseName = "桥接课程",
            title = "桥接新增作业",
            notifyAt = earlyNow.toInstant().toEpochMilli(),
            deadlineAt = null,
            offsets = emptyList(),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId(newEventId),
        )
        try {
            val state1 = database.loadPlanState(accountHash, epoch)
            BackgroundReminderBridge.applyPlanAndRecord(
                appContext = context,
                database = database,
                accountHash = accountHash,
                sessionEpoch = epoch,
                baselineCompleted = true,
                knownIds = setOf(deadlineAssignmentId, newAssignmentId),
                snapshots = snapshots,
                events = listOf(deadlineEvent, newEvent),
                completedAt = earlyNow.toInstant().toEpochMilli(),
                failure = null,
                syncCompleted = true,
                expectedMutationVersion = state1.mutationVersion,
                baselinedSources = setOf("courseWork"),
                now = earlyNow,
            )

            // Re-applying an identical plan must not duplicate 'scheduled' deadline history.
            val state2 = database.loadPlanState(accountHash, epoch)
            BackgroundReminderBridge.applyPlanAndRecord(
                appContext = context,
                database = database,
                accountHash = accountHash,
                sessionEpoch = epoch,
                baselineCompleted = true,
                knownIds = setOf(deadlineAssignmentId, newAssignmentId),
                snapshots = snapshots,
                events = listOf(deadlineEvent, newEvent),
                completedAt = earlyNow.plusMinutes(10).toInstant().toEpochMilli(),
                failure = null,
                syncCompleted = true,
                expectedMutationVersion = state2.mutationVersion,
                baselinedSources = setOf("courseWork"),
                now = earlyNow.plusMinutes(10),
            )

            val obsContext = ReminderHistoryStore.acquireObservationContext(
                context,
                database,
                accountHash,
                epoch,
            )
            @Suppress("UNCHECKED_CAST")
            val items = ReminderHistoryStore.listHistory(
                context,
                database,
                obsContext,
                snapshotMaxId = null,
                beforeId = null,
                category = null,
                subjectRefs = listOf(
                    "assignment" to deadlineAssignmentId,
                    "assignment" to newAssignmentId,
                ),
            )["items"] as List<Map<String, Any?>>
            val deadlineScheduled = items.filter {
                it["logicalKey"] == deadlineEventId && it["stage"] == "scheduled"
            }
            assertEquals(1, deadlineScheduled.size)
            assertEquals(deadlineEvent.notificationId, deadlineScheduled.single()["notificationId"])

            val expectedWindowStart = earlyNow.withHour(8).withMinute(0).withSecond(0).withNano(0)
                .toInstant()
                .toEpochMilli()
            val deferredNew = items.single {
                it["logicalKey"] == newEventId &&
                    it["stage"] == "deferred" &&
                    it["reasonCode"] == "outsideWindow"
            }
            assertEquals(expectedWindowStart, deferredNew["scheduledAt"])
        } finally {
            AssignmentAlarmScheduler.cancelDeadline(context, deadlineEvent)
            AssignmentAlarmScheduler.cancelNewAssignmentWindow(context, accountHash)
        }
    }

    @Test
    fun concurrentPublisherAndHistoryStoreOperationsDoNotDeadlock() {
        val event = seedPendingDeadlineAssignment()
        val epoch = event.sessionEpoch
        database.markPendingUpdate(accountHash, epoch)
        ReminderHistoryStore.enableSession(context, database, accountHash, epoch, 1)

        val executor = Executors.newFixedThreadPool(4)
        val startGate = CountDownLatch(1)
        val doneGate = CountDownLatch(4)
        val failure = AtomicReference<Throwable?>(null)
        try {
            repeat(4) { workerIndex ->
                executor.submit {
                    try {
                        startGate.await(5, TimeUnit.SECONDS)
                        for (iteration in 1..150) {
                            when ((workerIndex + iteration) % 4) {
                                0 -> AssignmentNotificationPublisher.publishDeadline(
                                    context,
                                    database,
                                    event,
                                    Instant.now(),
                                )
                                1 -> {
                                    val obs = ReminderHistoryStore.acquireObservationContext(
                                        context,
                                        database,
                                        accountHash,
                                        epoch,
                                    )
                                    ReminderHistoryStore.appendObservation(
                                        context,
                                        database,
                                        obs,
                                        ReminderHistoryObservationInput(
                                            observationId = "conc-$workerIndex-$iteration",
                                            ordinal = iteration,
                                            subjectKind = "assignment",
                                            subjectId = event.assignmentId,
                                            logicalKey = "conc:$workerIndex:$iteration",
                                            category = "deadline",
                                            stage = "scheduled",
                                            reasonCode = null,
                                            observedAt = System.currentTimeMillis(),
                                            scheduledAt = System.currentTimeMillis() + 60_000L,
                                            notificationId = event.notificationId,
                                            batchKey = null,
                                        ),
                                    )
                                }
                                2 -> {
                                    val obs = ReminderHistoryStore.acquireObservationContext(
                                        context,
                                        database,
                                        accountHash,
                                        epoch,
                                    )
                                    ReminderHistoryStore.inspectSubjects(
                                        context,
                                        database,
                                        obs,
                                        listOf("assignment" to event.assignmentId),
                                    )
                                }
                                else -> AssignmentNotificationPublisher.reconcileInvalidatedEvents(
                                    context,
                                    database,
                                    emptyList(),
                                    Instant.now(),
                                )
                            }
                        }
                    } catch (t: Throwable) {
                        failure.compareAndSet(null, t)
                    } finally {
                        doneGate.countDown()
                    }
                }
            }
            startGate.countDown()
            assertTrue("并发调度与历史操作疑似死锁", doneGate.await(20, TimeUnit.SECONDS))
            failure.get()?.let { throw AssertionError("并发执行失败", it) }
        } finally {
            executor.shutdownNow()
        }
    }

    private fun seedPendingNewAssignment(formal: Boolean = true): Int {
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
        val assignmentId = if (formal) {
            "cx:work:instrumentation:class:new"
        } else {
            "cx:activity:instrumentation:class:new"
        }
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
                    deadlineTrusted = true,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = formal,
                    inAssignmentScope = true,
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

    private fun seedPendingDeadlineAssignment(
        deadlineAtOverride: Long? = null,
        notifyAtOverride: Long? = null,
        deadlineSource: String = "official",
    ): StoredReminderEvent {
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
        val deadlineAt = deadlineAtOverride ?: (System.currentTimeMillis() + 3_600_000L)
        val notifyAt = notifyAtOverride ?: (deadlineAt - 60_000L)
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
                    deadlineSource = deadlineSource,
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
                    notifyAt = notifyAt,
                    deadlineAt = deadlineAt,
                    offsets = listOf(1),
                    batchId = null,
                    status = ReminderDatabase.STATUS_PENDING,
                    notificationId = stableId,
                    deadlineSource = deadlineSource,
                ),
            ),
            completedAt = now,
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )
        return database.pendingDeadlineEvents(accountHash).single()
    }

    @Test
    fun cancelDeliveryForPrivacyFollowedByApplyPlanReEmitsScheduledHistory() {
        val event = seedPendingDeadlineAssignment()
        try {
            val generation = (ReminderHistoryStore.enableSession(
                context,
                database,
                accountHash,
                event.sessionEpoch,
                1L,
            )["historyGeneration"] as Number).toLong()
            val obsContext = ReminderObservationContext(
                accountHash = accountHash,
                sessionEpoch = event.sessionEpoch,
                historyGeneration = generation,
                operationSequence = 1L,
            )
            AssignmentAlarmScheduler.scheduleDeadline(context, event)
            AssignmentNotificationPublisher.cancelDeliveryForPrivacy(
                context,
                database,
                accountHash,
            )
            assertFalse(AssignmentAlarmScheduler.hasDeadlineAlarm(context, event))

            val state = database.loadPlanState(accountHash, event.sessionEpoch)
            val snapshot = database.snapshot(accountHash, event.assignmentId)!!
            val now = ZonedDateTime.now(ZoneId.of("Asia/Shanghai"))
                .withHour(10).withMinute(0).withSecond(0).withNano(0)
            BackgroundReminderBridge.applyPlanAndRecord(
                appContext = context,
                database = database,
                accountHash = accountHash,
                sessionEpoch = event.sessionEpoch,
                baselineCompleted = true,
                knownIds = setOf(event.assignmentId),
                snapshots = listOf(snapshot),
                events = listOf(event),
                completedAt = now.toInstant().toEpochMilli(),
                failure = null,
                syncCompleted = true,
                expectedMutationVersion = state.mutationVersion,
                baselinedSources = setOf("courseWork"),
                now = now,
            )

            assertTrue(AssignmentAlarmScheduler.hasDeadlineAlarm(context, event))
            @Suppress("UNCHECKED_CAST")
            val items = ReminderHistoryStore.listHistory(
                context,
                database,
                obsContext,
                snapshotMaxId = null,
                beforeId = null,
                category = null,
                subjectRefs = listOf("assignment" to event.assignmentId),
            )["items"] as List<Map<String, Any?>>
            assertEquals("scheduled", items.first()["stage"])
        } finally {
            AssignmentAlarmScheduler.cancelDeadline(context, event)
        }
    }

    @Test
    fun deadlineReceiverPreWindowCancelsPassedDeadlineAndDefersFutureDeadlineWithWindowTime() {
        val epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        val generation = (ReminderHistoryStore.enableSession(
            context,
            database,
            accountHash,
            epoch,
            1L,
        )["historyGeneration"] as Number).toLong()
        val obsContext = ReminderObservationContext(
            accountHash = accountHash,
            sessionEpoch = epoch,
            historyGeneration = generation,
            operationSequence = 1L,
        )
        val zone = ZoneId.of("Asia/Shanghai")
        val futureDay = ZonedDateTime.now(zone).plusDays(7)
        val preWindowNow = futureDay.withHour(2).withMinute(0).withSecond(0).withNano(0)
        val windowStart = DeadlineQuietHoursPolicy.nextQuietEnd(preWindowNow.toInstant(), zone)
            .toEpochMilli()

        val beforeWindowDeadlineAt = futureDay.withHour(6).withMinute(0).withSecond(0).withNano(0)
            .toInstant()
            .toEpochMilli()
        val futureDeadlineAt = futureDay.withHour(12).withMinute(0).withSecond(0).withNano(0)
            .toInstant()
            .toEpochMilli()

        val earlyId = "cx:work:pre:early"
        val lateId = "cx:work:pre:late"
        val earlyEvent = StoredReminderEvent(
            eventId = "$accountHash|$earlyId|deadline:$beforeWindowDeadlineAt|60",
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = earlyId,
            courseName = "早截止课程",
            title = "八点前截止",
            notifyAt = preWindowNow.toInstant().toEpochMilli(),
            deadlineAt = beforeWindowDeadlineAt,
            offsets = listOf(60),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId("early"),
        )
        val lateEvent = StoredReminderEvent(
            eventId = "$accountHash|$lateId|deadline:$futureDeadlineAt|60",
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = lateId,
            courseName = "午后课程",
            title = "八点后截止",
            notifyAt = preWindowNow.toInstant().toEpochMilli(),
            deadlineAt = futureDeadlineAt,
            offsets = listOf(60),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId("late"),
        )
        val state = database.loadPlanState(accountHash, epoch)
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(earlyId, lateId),
            snapshots = listOf(
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = earlyId,
                    sessionEpoch = epoch,
                    courseName = "早截止课程",
                    title = "八点前截止",
                    deadlineAt = beforeWindowDeadlineAt,
                    deadlineTrusted = true,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = true,
                ),
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = lateId,
                    sessionEpoch = epoch,
                    courseName = "午后课程",
                    title = "八点后截止",
                    deadlineAt = futureDeadlineAt,
                    deadlineTrusted = true,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = true,
                ),
            ),
            events = listOf(earlyEvent, lateEvent),
            completedAt = preWindowNow.toInstant().toEpochMilli(),
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )

        val receiver = AssignmentDeadlineReceiver()
        try {
            receiver.handleDeadline(context, database, earlyEvent.eventId, accountHash, preWindowNow)
            receiver.handleDeadline(context, database, lateEvent.eventId, accountHash, preWindowNow)

            assertEquals(
                ReminderDatabase.STATUS_CANCELLED,
                database.event(earlyEvent.eventId)?.status,
            )
            assertEquals(windowStart, database.event(lateEvent.eventId)?.notifyAt)

            @Suppress("UNCHECKED_CAST")
            val earlyHistory = ReminderHistoryStore.listHistory(
                context,
                database,
                obsContext,
                snapshotMaxId = null,
                beforeId = null,
                category = null,
                subjectRefs = listOf("assignment" to earlyId),
            )["items"] as List<Map<String, Any?>>
            assertEquals("cancelled", earlyHistory.first()["stage"])
            assertEquals("deadlinePassed", earlyHistory.first()["reasonCode"])

            @Suppress("UNCHECKED_CAST")
            val lateHistory = ReminderHistoryStore.listHistory(
                context,
                database,
                obsContext,
                snapshotMaxId = null,
                beforeId = null,
                category = null,
                subjectRefs = listOf("assignment" to lateId),
            )["items"] as List<Map<String, Any?>>
            assertEquals("deferred", lateHistory.first()["stage"])
            assertEquals("quietHours", lateHistory.first()["reasonCode"])
            assertEquals(windowStart, lateHistory.first()["scheduledAt"])
        } finally {
            AssignmentAlarmScheduler.cancelDeadline(context, earlyEvent)
            AssignmentAlarmScheduler.cancelDeadline(context, lateEvent)
        }
    }

    @Test
    fun unknownTimeNewAssignmentPublishesSilentlyOnSilentChannel() {
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        val id = seedPendingNewAssignment()
        val result = AssignmentNotificationPublisher.publishPendingNewAssignments(
            context,
            database,
            accountHash,
            Instant.now(),
        )
        assertTrue("publish result: $result", result.submitted)
        val active = notificationManager.activeNotifications.single { it.id == id && it.tag == null }
        assertEquals(AssignmentNotificationPublisher.CHANNEL_SILENT, active.notification.channelId)
        notificationManager.cancel(id)
    }

    @Test
    fun deadlineReceiverBlocksMissingSourceSuppressesLateQuietAndAllowsUrgentBreakthrough() {
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        val zone = ZoneId.of("Asia/Shanghai")
        val futureDay = ZonedDateTime.now(zone).plusDays(7)
        val quietNow = futureDay.withHour(0).withMinute(15).withSecond(0).withNano(0)
        val urgentDeadline = futureDay.withHour(1).withMinute(0).withSecond(0).withNano(0)
            .toInstant().toEpochMilli()
        val epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = epoch,
            backgroundEnabled = true,
            intervalMinutes = 240,
            listenerEnabled = true,
            newAssignmentEnabled = true,
            showDetails = false,
            allowUrgentNightBreakthrough = true,
        )
        ReminderHistoryStore.enableSession(context, database, accountHash, epoch, 1)
        val lateId = "cx:work:4a:late"
        val urgentId = "cx:work:4a:urgent"
        val lateEvent = StoredReminderEvent(
            eventId = "$accountHash|$lateId|deadline:${urgentDeadline + 7_200_000L}|30",
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = lateId,
            courseName = "晚间到达测试课",
            title = "错峰迟到作业",
            notifyAt = quietNow.minusHours(2).toInstant().toEpochMilli(),
            deadlineAt = urgentDeadline + 7_200_000L,
            offsets = listOf(30),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId("late-quiet"),
            deadlineSource = "official",
        )
        val urgentEvent = StoredReminderEvent(
            eventId = "$accountHash|$urgentId|deadline:$urgentDeadline|45",
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = ReminderDatabase.EVENT_DEADLINE,
            assignmentId = urgentId,
            courseName = "紧急穿透测试课",
            title = "45分钟死线作业",
            notifyAt = quietNow.toInstant().toEpochMilli(),
            deadlineAt = urgentDeadline,
            offsets = listOf(45),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId("urgent-break"),
            deadlineSource = "manual",
        )
        val state = database.loadPlanState(accountHash, epoch)
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(lateId, urgentId),
            snapshots = listOf(
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = lateId,
                    sessionEpoch = epoch,
                    courseName = "晚间到达测试课",
                    title = "错峰迟到作业",
                    deadlineAt = urgentDeadline + 7_200_000L,
                    deadlineTrusted = true,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = true,
                    deadlineSource = "official",
                ),
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = urgentId,
                    sessionEpoch = epoch,
                    courseName = "紧急穿透测试课",
                    title = "45分钟死线作业",
                    deadlineAt = urgentDeadline,
                    deadlineTrusted = true,
                    deadlineReadFailed = false,
                    status = "pending",
                    completed = false,
                    hidden = false,
                    followed = true,
                    formal = true,
                    deadlineSource = "manual",
                ),
            ),
            events = listOf(lateEvent, urgentEvent),
            completedAt = quietNow.toInstant().toEpochMilli(),
            failure = null,
            syncCompleted = true,
            expectedMutationVersion = state.mutationVersion,
        )
        val receiver = AssignmentDeadlineReceiver()
        try {
            receiver.handleDeadline(context, database, lateEvent.eventId, accountHash, quietNow)
            assertEquals(ReminderDatabase.STATUS_CANCELLED, database.event(lateEvent.eventId)?.status)

            receiver.handleDeadline(context, database, urgentEvent.eventId, accountHash, quietNow)
            assertEquals(ReminderDatabase.STATUS_SUBMITTED, database.event(urgentEvent.eventId)?.status)
            assertTrue(notificationManager.activeNotifications.any { it.id == urgentEvent.notificationId })
        } finally {
            notificationManager.cancel(urgentEvent.notificationId)
            AssignmentAlarmScheduler.cancelDeadline(context, lateEvent)
            AssignmentAlarmScheduler.cancelDeadline(context, urgentEvent)
        }
    }

    @Test
    fun deadlineReceiverIgnoresNonPendingEventWithoutRecordingStaleSession() {
        val event = seedPendingDeadlineAssignment()
        val generation = (ReminderHistoryStore.enableSession(
            context,
            database,
            accountHash,
            event.sessionEpoch,
            1L,
        )["historyGeneration"] as Number).toLong()
        val obsContext = ReminderObservationContext(
            accountHash = accountHash,
            sessionEpoch = event.sessionEpoch,
            historyGeneration = generation,
            operationSequence = 1L,
        )
        database.cancelEvent(event.eventId)

        AssignmentDeadlineReceiver().handleDeadline(
            context,
            database,
            event.eventId,
            accountHash,
        )

        @Suppress("UNCHECKED_CAST")
        val items = ReminderHistoryStore.listHistory(
            context,
            database,
            obsContext,
            snapshotMaxId = null,
            beforeId = null,
            category = null,
            subjectRefs = listOf("assignment" to event.assignmentId),
        )["items"] as List<Map<String, Any?>>
        assertTrue(items.isEmpty())
    }

    @Test
    fun zCreatesV2DeadlineChannelWithoutOverwritingExistingChannel() {
        notificationManager.deleteNotificationChannel(
            AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
        )
        notificationManager.deleteNotificationChannel(
            AssignmentNotificationPublisher.CHANNEL_DEADLINES,
        )
        notificationManager.createNotificationChannel(
            NotificationChannel(
                AssignmentNotificationPublisher.CHANNEL_DEADLINES,
                "既有旧截止渠道",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )

        AssignmentNotificationPublisher.ensureChannels(
            context,
            AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
        )

        val v2 = notificationManager.getNotificationChannel(
            AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
        )
        assertEquals(NotificationManager.IMPORTANCE_HIGH, v2.importance)
        assertTrue(v2.sound != null)
        assertEquals(AudioAttributes.USAGE_NOTIFICATION, v2.audioAttributes?.usage)
        assertTrue(v2.shouldVibrate())
        // Some platforms normalize channel-level lock-screen visibility to
        // UNSPECIFIED; the privacy contract only requires it never be PUBLIC.
        assertTrue(v2.lockscreenVisibility != Notification.VISIBILITY_PUBLIC)

        val v1 = notificationManager.getNotificationChannel(
            AssignmentNotificationPublisher.CHANNEL_DEADLINES,
        )
        assertEquals(NotificationManager.IMPORTANCE_LOW, v1.importance)
        notificationManager.deleteNotificationChannel(
            AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
        )
        notificationManager.deleteNotificationChannel(
            AssignmentNotificationPublisher.CHANNEL_DEADLINES,
        )
    }

    @Test
    fun zTestDeadlineNotificationRespectsQuietHoursAndWritesNoHistory() {
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        val shanghai = ZoneId.of("Asia/Shanghai")
        val quietNow = ZonedDateTime.now(shanghai).plusDays(1)
            .withHour(23).withMinute(45).withSecond(0).withNano(0)
        val quietResult = AssignmentNotificationPublisher.publishTestDeadlineNotification(
            context = context,
            database = database,
            accountHash = accountHash,
            requestedChannelId = AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
            now = quietNow.toInstant(),
            zone = shanghai,
            delayMillis = 0L,
        )
        assertEquals("quietHours", quietResult.status)
        assertTrue(quietResult.retryAfterAt != null)
        assertFalse(
            notificationManager.activeNotifications.any {
                it.id == AssignmentNotificationPublisher.TEST_NOTIFICATION_ID
            },
        )

        val eventsBefore = database.eventsForAccount(accountHash).size
        val epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        val generation = (ReminderHistoryStore.enableSession(
            context,
            database,
            accountHash,
            epoch,
            1L,
        )["historyGeneration"] as Number).toLong()
        val obsContext = ReminderObservationContext(
            accountHash = accountHash,
            sessionEpoch = epoch,
            historyGeneration = generation,
            operationSequence = 1L,
        )
        val dayNow = ZonedDateTime.now(shanghai).plusDays(1)
            .withHour(10).withMinute(0).withSecond(0).withNano(0)
        try {
            val dayResult = AssignmentNotificationPublisher.publishTestDeadlineNotification(
                context = context,
                database = database,
                accountHash = accountHash,
                requestedChannelId = AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
                now = dayNow.toInstant(),
                zone = shanghai,
                delayMillis = 0L,
            )
            assertEquals("posted", dayResult.status)
            assertEquals(
                AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
                dayResult.channelId,
            )
            val active = notificationManager.activeNotifications.single {
                it.id == AssignmentNotificationPublisher.TEST_NOTIFICATION_ID
            }
            assertEquals(
                AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
                active.notification.channelId,
            )
            assertEquals(
                Notification.VISIBILITY_PRIVATE,
                active.notification.visibility,
            )
            assertEquals(eventsBefore, database.eventsForAccount(accountHash).size)
            @Suppress("UNCHECKED_CAST")
            val historyItems = ReminderHistoryStore.listHistory(
                context,
                database,
                obsContext,
                snapshotMaxId = null,
                beforeId = null,
                category = null,
                subjectRefs = emptyList(),
            )["items"] as List<Map<String, Any?>>
            assertTrue(historyItems.isEmpty())
        } finally {
            runCatching {
                notificationManager.cancel(
                    AssignmentNotificationPublisher.TEST_NOTIFICATION_ID,
                )
            }
        }
    }
}
