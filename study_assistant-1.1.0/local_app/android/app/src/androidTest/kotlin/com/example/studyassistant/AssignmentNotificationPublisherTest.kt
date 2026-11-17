package com.example.studyassistant

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
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
        val earlyNow = ZonedDateTime.of(2026, 11, 18, 3, 0, 0, 0, zone)
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

            val expectedWindowStart = ZonedDateTime.of(2026, 11, 18, 8, 0, 0, 0, zone)
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
            val now = ZonedDateTime.of(2026, 11, 18, 10, 0, 0, 0, ZoneId.of("Asia/Shanghai"))
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
        val preWindowNow = ZonedDateTime.of(2026, 11, 18, 2, 0, 0, 0, zone)
        val windowStart = BackgroundWorkScheduler.nextWindowStart(preWindowNow)

        val beforeWindowDeadlineAt = ZonedDateTime.of(2026, 11, 18, 6, 0, 0, 0, zone)
            .toInstant()
            .toEpochMilli()
        val futureDeadlineAt = ZonedDateTime.of(2026, 11, 18, 12, 0, 0, 0, zone)
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
            assertEquals("outsideWindow", lateHistory.first()["reasonCode"])
            assertEquals(windowStart, lateHistory.first()["scheduledAt"])
        } finally {
            AssignmentAlarmScheduler.cancelDeadline(context, earlyEvent)
            AssignmentAlarmScheduler.cancelDeadline(context, lateEvent)
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
}
