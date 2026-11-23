package com.example.studyassistant

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Device-level checks for legacy ownership proofs. The Dart seam only mocks the
 * channel result, so these exercise the real PendingIntent comparison the
 * migration relies on before recording its one-time marker.
 */
@RunWith(AndroidJUnit4::class)
class LegacyAssignmentNotificationMigratorTest {
    private lateinit var context: Context
    private lateinit var manager: NotificationManager
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private val postedIds = mutableSetOf<Int>()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        manager = context.getSystemService(NotificationManager::class.java)
        database = ReminderDatabase.get(context)
        accountHash = "instrumentation-migration-${System.nanoTime()}"
        if (Build.VERSION.SDK_INT >= 33) {
            InstrumentationRegistry.getInstrumentation().uiAutomation
                .grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        }
        NotificationManagerCompat.from(context).cancelAll()
        manager.createNotificationChannel(
            NotificationChannel(
                AssignmentNotificationPublisher.CHANNEL_DEADLINES,
                "迁移测试",
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }

    @After
    fun tearDown() {
        postedIds.forEach { runCatching { manager.cancel(it) } }
        runCatching { database.clearActiveAccount(accountHash) }
    }

    @Test
    fun retiresPluginDeliveredNotificationAndPreservesNativeCollision() {
        val nativeId = ReminderDatabase.stableNotificationId("native:$accountHash")
        val nativeEventId = seedNativeEvent(nativeId)
        postNative(nativeId, nativeEventId)

        val legacyId = ReminderDatabase.stableNotificationId("legacy:$accountHash")
        postPlugin(legacyId)
        val legacyOwned = database.notificationIds() + legacyId

        val outcome = LegacyAssignmentNotificationMigrator.retireNow(
            context,
            database,
            legacyOwned,
        )

        assertTrue(outcome.completed)
        assertEquals(listOf(legacyId), outcome.retiredIds)
        assertTrue(outcome.preservedUnknownIds.isEmpty())
        // The notification service dispatches cancel requests asynchronously.
        val deadline = SystemClock.elapsedRealtime() + 3_000
        while (legacyId in activeIds() && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(50)
        }
        assertFalse("已退休的旧通知仍在系统通知列表中", activeIds().contains(legacyId))
        assertTrue(activeIds().contains(nativeId))
    }

    @Test
    fun staleDatabaseIdCannotProveOwnershipOfAnUnrelatedClickToken() {
        val id = ReminderDatabase.stableNotificationId("stale-owner:$accountHash")
        seedNativeEvent(id)
        postNative(id, "different-event-$id")

        // The legacy cache makes this id a cancellation candidate, so the
        // PendingIntent check must still hold during the main-thread re-read.
        val cacheName = "legacy-ownership-$accountHash"
        val cache = context.getSharedPreferences(cacheName, Context.MODE_PRIVATE)
        val raw = """[{"id":$id,"payload":"a:synthetic","channelId":"assignment_deadlines"}]"""
        val isolatedCacheContext = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                if (name == "scheduled_notifications") cache else super.getSharedPreferences(name, mode)
        }
        try {
            assertTrue(cache.edit().putString("scheduled_notifications", raw).commit())
            val outcome = LegacyAssignmentNotificationMigrator.retireNow(
                isolatedCacheContext, database, setOf(id),
            )

            assertFalse(outcome.completed)
            assertEquals(listOf(id), outcome.preservedUnknownIds)
            assertTrue(outcome.retiredIds.isEmpty())
            assertTrue(id in activeIds())
            assertEquals(raw, cache.getString("scheduled_notifications", null))
        } finally {
            context.deleteSharedPreferences(cacheName)
        }
    }

    @Test
    fun unknownOwnershipIsPreservedAndReported() {
        val unknownId = ReminderDatabase.stableNotificationId("unknown:$accountHash")
        postNative(unknownId, "unknown-event-$unknownId")

        val outcome = LegacyAssignmentNotificationMigrator.retireNow(
            context,
            database,
            emptySet(),
        )

        assertFalse(outcome.completed)
        assertTrue(outcome.preservedUnknownIds.contains(unknownId))
        assertTrue(activeIds().contains(unknownId))
    }

    @Test
    fun retiresPluginDeliveredNotificationOnV2Channel() {
        manager.createNotificationChannel(
            NotificationChannel(
                AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
                "迁移测试v2",
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        val legacyV2Id = ReminderDatabase.stableNotificationId("legacy-v2:$accountHash")
        postPlugin(
            legacyV2Id,
            channelId = AssignmentNotificationPublisher.CHANNEL_DEADLINES_V2,
        )

        val outcome = LegacyAssignmentNotificationMigrator.retireNow(
            context,
            database,
            database.notificationIds() + legacyV2Id,
        )

        assertTrue(outcome.completed)
        assertEquals(listOf(legacyV2Id), outcome.retiredIds)
        val deadline = SystemClock.elapsedRealtime() + 3_000
        while (legacyV2Id in activeIds() && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(50)
        }
        assertFalse(activeIds().contains(legacyV2Id))
    }

    private fun activeIds(): Set<Int> =
        NotificationManagerCompat.from(context).activeNotifications.map { it.id }.toSet()

    private fun postPlugin(
        id: Int,
        channelId: String = AssignmentNotificationPublisher.CHANNEL_DEADLINES,
    ) {
        val launcher = requireNotNull(
            context.packageManager.getLaunchIntentForPackage(context.packageName),
        )
        launcher.action = "SELECT_NOTIFICATION"
        launcher.putExtra("notificationId", id)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val click = PendingIntent.getActivity(context, id, launcher, flags)
        post(id, click, channelId = channelId)
    }

    private fun postNative(id: Int, eventId: String) {
        val click = PendingIntent.getActivity(
            context,
            ReminderDatabase.stableNotificationId("click:$eventId"),
            Intent(context, ReminderClickActivity::class.java)
                .setAction(ReminderClickReceiver.ACTION_CLICK)
                .setData(
                    android.net.Uri.parse(
                        "studyassistant://notification-click/${android.net.Uri.encode(eventId)}",
                    ),
                ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        post(id, click)
    }

    private fun post(
        id: Int,
        click: PendingIntent,
        channelId: String = AssignmentNotificationPublisher.CHANNEL_DEADLINES,
    ) {
        val notification = NotificationCompat.Builder(
            context,
            channelId,
        )
            .setSmallIcon(R.drawable.app_icon)
            .setContentTitle("合成通知")
            .setContentText("合成通知正文")
            .setContentIntent(click)
            .build()
        NotificationManagerCompat.from(context).notify(id, notification)
        postedIds.add(id)
        val deadline = SystemClock.elapsedRealtime() + 3_000
        while (id !in activeIds() && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(50)
        }
        assertTrue("测试通知未出现在系统通知列表中", id in activeIds())
    }

    private fun seedNativeEvent(notificationId: Int): String {
        val state = database.ensureActiveAccount(accountHash)
        val assignmentId = "cx:work:instrumentation:class:migration"
        val deadlineAt = System.currentTimeMillis() + 3_600_000L
        val eventId = "$accountHash|$assignmentId|deadline:$deadlineAt|60"
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = state.sessionEpoch,
            baselineCompleted = true,
            knownIds = setOf(assignmentId),
            snapshots = listOf(
                StoredReminderSnapshot(
                    accountHash = accountHash,
                    assignmentId = assignmentId,
                    sessionEpoch = state.sessionEpoch,
                    courseName = "合成课程",
                    title = "合成迁移作业",
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
                    sessionEpoch = state.sessionEpoch,
                    type = ReminderDatabase.EVENT_DEADLINE,
                    assignmentId = assignmentId,
                    courseName = "合成课程",
                    title = "合成迁移作业",
                    notifyAt = System.currentTimeMillis() + 60_000L,
                    deadlineAt = deadlineAt,
                    offsets = listOf(60),
                    batchId = null,
                    status = ReminderDatabase.STATUS_PENDING,
                    notificationId = notificationId,
                ),
            ),
            completedAt = System.currentTimeMillis(),
            failure = null,
            syncCompleted = false,
            expectedMutationVersion = state.mutationVersion,
        )
        return eventId
    }
}
