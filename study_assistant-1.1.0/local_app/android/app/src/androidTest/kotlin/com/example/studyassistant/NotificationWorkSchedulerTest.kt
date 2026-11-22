package com.example.studyassistant

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class NotificationWorkSchedulerTest {
    private lateinit var context: Context
    private lateinit var database: ReminderDatabase
    private lateinit var workManager: WorkManager
    private lateinit var accountHash: String
    private var epoch = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = ReminderDatabase.get(context)
        workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork(BackgroundWorkScheduler.LEGACY_NOTIFICATION_WORK)
            .getResult()
            .get(5, TimeUnit.SECONDS)
        accountHash = "instrumentation-signal-${System.nanoTime()}"
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
    }

    @After
    fun tearDown() {
        workManager.cancelUniqueWork(workName())
            .getResult()
            .get(5, TimeUnit.SECONDS)
        workManager.cancelUniqueWork(daytimeWorkName())
            .getResult()
            .get(5, TimeUnit.SECONDS)
        workManager.cancelUniqueWork(BackgroundWorkScheduler.LEGACY_NOTIFICATION_WORK)
            .getResult()
            .get(5, TimeUnit.SECONDS)
        runCatching { database.clearActiveAccount(accountHash) }
    }

    @Test
    fun notificationCheckRequestRequiresNetwork() {
        val signal = database.recordSignal(
            accountHash,
            epoch,
            "signal-requires-network",
            System.currentTimeMillis(),
        )
        val enqueue = BackgroundWorkScheduler.scheduleNotificationCheck(
            context,
            database,
            accountHash,
            signal,
        )

        assertTrue("notification check request was not enqueued", enqueue.confirmed)
        assertEquals(NetworkType.CONNECTED, liveWork().single().constraints.requiredNetworkType)
    }

    @Test
    fun daytimeCheckRequestRequiresNetwork() {
        BackgroundWorkScheduler.reconcileDaytime(
            context,
            database,
            targetAt = System.currentTimeMillis() + TimeUnit.MINUTES.toMillis(10),
            enabled = true,
            intervalMinutes = 240,
            accountHash = accountHash,
            sessionEpoch = epoch,
        )

        val work = liveWorks(daytimeWorkName()).single()
        assertEquals(NetworkType.CONNECTED, work.constraints.requiredNetworkType)
    }

    @Test
    fun queuedNotificationSignalKeepsTheExistingWorkAndClaimsLatest() {
        val first = database.recordSignal(
            accountHash,
            epoch,
            "signal-one",
            System.currentTimeMillis(),
        )
        BackgroundWorkScheduler.scheduleNotificationCheck(
            context,
            database,
            accountHash,
            first,
        )
        val firstWork = liveWork().single()

        val second = database.recordSignal(
            accountHash,
            epoch,
            "signal-two",
            System.currentTimeMillis() + 1_000L,
        )
        BackgroundWorkScheduler.scheduleNotificationCheck(
            context,
            database,
            accountHash,
            second,
        )
        val secondWork = liveWork().single()

        assertEquals(firstWork.id, secondWork.id)
        assertEquals(
            second,
            database.claimNotificationSignal(accountHash, epoch),
        )
    }

    @Test
    fun attemptedSignalDoesNotScheduleAnotherEngine() {
        val version = database.recordSignal(
            accountHash,
            epoch,
            "signal-attempted",
            System.currentTimeMillis(),
        )
        assertEquals(version, database.claimNotificationSignal(accountHash, epoch))

        BackgroundWorkScheduler.scheduleNotificationCheck(
            context,
            database,
            accountHash,
            version,
        )

        assertTrue(liveWorks().isEmpty())
    }

    @Test
    fun higherSignalAfterFailedAttemptSchedulesOneSuccessor() {
        val first = database.recordSignal(
            accountHash,
            epoch,
            "signal-first",
            System.currentTimeMillis(),
        )
        database.claimNotificationSignal(accountHash, epoch)
        val second = database.recordSignal(
            accountHash,
            epoch,
            "signal-second",
            System.currentTimeMillis() + 1_000L,
        )
        assertTrue(second > first)

        BackgroundWorkScheduler.scheduleNotificationCheck(
            context,
            database,
            accountHash,
            second,
        )

        liveWork()
    }

    @Test
    fun deferredSuccessorIsEnqueuedOnceAndReused() {
        database.recordSignal(
            accountHash,
            epoch,
            "signal-deferred",
            System.currentTimeMillis(),
        )

        assertTrue(
            BackgroundWorkScheduler.ensureDeferredNotificationSuccessor(
                context,
                database,
                accountHash,
                epoch,
                currentWorkId = null,
            ).confirmed,
        )
        val first = liveWork().single()
        assertTrue(
            BackgroundWorkScheduler.ensureDeferredNotificationSuccessor(
                context,
                database,
                accountHash,
                epoch,
                currentWorkId = null,
            ).confirmed,
        )
        val second = liveWork().single()

        assertEquals(first.id, second.id)
    }

    private fun liveWork(): List<WorkInfo> =
        liveWorks().also {
            assertEquals(1, it.size)
        }

    private fun workName(): String =
        BackgroundWorkScheduler.notificationWorkName(accountHash, epoch)

    private fun daytimeWorkName(): String =
        BackgroundWorkScheduler.daytimeWorkName(accountHash, epoch)

    private fun liveWorks(name: String = workName()): List<WorkInfo> =
        workManager.getWorkInfosForUniqueWork(
            name,
        ).get(5, TimeUnit.SECONDS)
            .filter {
                it.state == WorkInfo.State.ENQUEUED ||
                    it.state == WorkInfo.State.RUNNING ||
                    it.state == WorkInfo.State.BLOCKED
            }
}
