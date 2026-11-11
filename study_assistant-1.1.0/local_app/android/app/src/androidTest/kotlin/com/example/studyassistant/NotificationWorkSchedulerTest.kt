package com.example.studyassistant

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.WorkInfo
import androidx.work.WorkManager
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
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

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = ReminderDatabase.get(context)
        workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork(BackgroundWorkScheduler.NOTIFICATION_WORK)
            .getResult()
            .get(5, TimeUnit.SECONDS)
        accountHash = "instrumentation-signal-${System.nanoTime()}"
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
    }

    @After
    fun tearDown() {
        workManager.cancelUniqueWork(BackgroundWorkScheduler.NOTIFICATION_WORK)
            .getResult()
            .get(5, TimeUnit.SECONDS)
        runCatching { database.clearActiveAccount(accountHash) }
    }

    @Test
    fun queuedNotificationSignalIsReplacedWithoutGrowingQueue() {
        val epoch = database.readAccount(accountHash)!!.sessionEpoch
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

        assertNotEquals(firstWork.id, secondWork.id)
    }

    private fun liveWork(): List<WorkInfo> =
        workManager.getWorkInfosForUniqueWork(
            BackgroundWorkScheduler.NOTIFICATION_WORK,
        ).get(5, TimeUnit.SECONDS)
            .filter {
                it.state == WorkInfo.State.ENQUEUED ||
                    it.state == WorkInfo.State.RUNNING ||
                    it.state == WorkInfo.State.BLOCKED
            }
            .also {
                assertEquals(1, it.size)
            }
}
