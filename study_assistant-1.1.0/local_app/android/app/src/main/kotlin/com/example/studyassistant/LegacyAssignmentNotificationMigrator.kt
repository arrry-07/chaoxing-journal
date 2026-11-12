package com.example.studyassistant

import android.app.AlarmManager
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Retire only proven plugin assignment operations. IDs and DB rows are hints,
 * never ownership. Cache RMW follows the plugin's main-thread boundary; disk
 * barriers and notification scans run off main without holding deliveryLock. */
object LegacyAssignmentNotificationMigrator {
    const val CHANNEL = "study_assistant/legacy_assignment_migration"
    val deliveryLock = Any()
    private const val PLUGIN_PREFS = "scheduled_notifications"
    private const val PLUGIN_CACHE_KEY = "scheduled_notifications"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    data class Outcome(
        val completed: Boolean,
        val retiredIds: List<Int>,
        val preservedUnknownIds: List<Int>,
        val cacheChanged: Boolean,
        val warning: String?,
    )

    fun isMigrationComplete(context: Context): Boolean =
        LegacyAssignmentMigrationState.isComplete(context)

    fun attach(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        val database = ReminderDatabase.get(appContext)
        val tasks = NativeReminderTasks(worker) { action -> mainHandler.post(action) }
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isMigrationComplete" -> tasks.execute(result) {
                    it.success(isMigrationComplete(appContext))
                }
                "retireLegacyAssignments" -> {
                    val owned = (call.argument<List<*>>("ownedIds") ?: emptyList<Any>())
                        .mapNotNull { (it as? Number)?.toInt() }.toSet()
                    val excluded = (call.argument<List<*>>("excludeIds") ?: emptyList<Any>())
                        .mapNotNull { (it as? Number)?.toInt() }.toSet()
                    tasks.execute(result) {
                        it.success(retireAndConfirm(appContext, database, owned, excluded).toMap())
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Public protocol's durable outcome, also exercised by instrumented tests. */
    internal fun retireAndConfirm(
        context: Context,
        database: ReminderDatabase,
        ownedIds: Set<Int>,
        excludeIds: Set<Int> = emptySet(),
        commitCache: () -> Boolean = {
            context.getSharedPreferences(PLUGIN_PREFS, Context.MODE_PRIVATE).edit().commit()
        },
    ): Outcome {
        check(Looper.myLooper() != Looper.getMainLooper()) { "迁移磁盘屏障不能在主线程运行" }
        if (!LegacyAssignmentMigrationState.begin(context)) {
            return Outcome(false, emptyList(), emptyList(), false, "迁移待处理状态未能写入磁盘")
        }
        val outcome = retireNow(context, database, ownedIds, excludeIds)
        // Always execute the barrier, including retries after a previous failed
        // commit whose removal is already visible in SharedPreferences memory.
        val committed = runCatching(commitCache).getOrDefault(false)
        if (!committed) return outcome.copy(completed = false, warning = "旧提醒调度缓存未能写入磁盘")
        if (!outcome.completed) return outcome
        if (!LegacyAssignmentMigrationState.confirm(context)) {
            return outcome.copy(completed = false, warning = "迁移完成状态未能写入磁盘")
        }
        return outcome
    }

    internal fun retireNow(
        context: Context,
        database: ReminderDatabase,
        ownedIds: Set<Int>,
        excludeIds: Set<Int> = emptySet(),
    ): Outcome {
        val prefs = context.getSharedPreferences(PLUGIN_PREFS, Context.MODE_PRIVATE)
        fun readCache() = LegacyAssignmentCache.parse(prefs.getString(PLUGIN_CACHE_KEY, null))
        val initial = try {
            onMain { readCache() }
        } catch (_: Exception) {
            return Outcome(false, emptyList(), emptyList(), false, "旧提醒调度缓存无法解析")
        }
        val manager = NotificationManagerCompat.from(context)
        val active = manager.activeNotifications.toList()
        val unknown = linkedSetOf<Int>()
        val failures = mutableListOf<String>()
        if (initial.hasUnknown) failures.add("旧提醒调度缓存含未知记录，已原样保留")
        val foreignActive = active.filter {
            it.tag != null || it.notification.channelId !in assignmentChannels
        }.map { it.id }.toSet()
        val blocked = excludeIds + initial.foreignIds + foreignActive
        val candidates = initial.assignmentIds.toMutableSet()
        for (entry in active) {
            if (entry.tag != null || entry.notification.channelId !in assignmentChannels) continue
            if (entry.id in excludeIds) continue
            when {
                entry.id in blocked -> unknown.add(entry.id)
                isPluginOwned(context, entry.notification, entry.id) -> candidates.add(entry.id)
                isNativeOwned(context, database, entry.notification, entry.id) -> Unit
                else -> unknown.add(entry.id)
            }
        }
        unknown.addAll(initial.assignmentIds.intersect(initial.foreignIds + foreignActive) - excludeIds)
        val retired = linkedSetOf<Int>()
        for (id in candidates - blocked) {
            try {
                // One short main operation at a time. Re-read the CURRENT cache
                // before cancellation, so a concurrent personal reschedule is not
                // overwritten/cancelled from our stale initial snapshot.
                val cancelled = onMain {
                    val current = readCache()
                    if (id in current.foreignIds || id in excludeIds) return@onMain false
                    synchronized(deliveryLock) {
                        val visible = manager.activeNotifications.filter { it.id == id }
                        if (visible.any { it.tag != null || it.notification.channelId !in assignmentChannels }) {
                            return@synchronized false
                        }
                        for (entry in visible) {
                            if (isPluginOwned(context, entry.notification, id)) manager.cancel(id)
                            else if (!isNativeOwned(context, database, entry.notification, id)) {
                                return@synchronized false
                            }
                        }
                        cancelPluginAlarm(context, id)
                        true
                    }
                }
                if (cancelled) retired.add(id) else unknown.add(id)
            } catch (error: Exception) {
                failures.add("取消旧提醒失败：${error.javaClass.simpleName}")
                unknown.add(id)
            }
        }
        var cacheChanged = false
        try {
            onMain {
                val raw = prefs.getString(PLUGIN_CACHE_KEY, null)
                val current = LegacyAssignmentCache.parse(raw)
                if (current.hasUnknown && !initial.hasUnknown) failures.add("旧提醒调度缓存含未知记录")
                unknown.addAll(retired.intersect(current.foreignIds))
                val kept = current.without(retired - unknown, excludeIds)
                if (raw != null && kept != raw) {
                    prefs.edit().putString(PLUGIN_CACHE_KEY, kept).apply()
                    cacheChanged = true
                }
            }
        } catch (_: Exception) {
            failures.add("旧提醒调度缓存写入失败")
        }
        // Manifest-only ids carry no proof. Absence of an operation is harmless;
        // presence of an unknown token was reported above, never cancelled.
        @Suppress("UNUSED_VARIABLE") val manifestHints = ownedIds
        return Outcome(
            completed = unknown.isEmpty() && failures.isEmpty(),
            retiredIds = (retired - unknown).sorted(),
            preservedUnknownIds = unknown.sorted(),
            cacheChanged = cacheChanged,
            warning = failures.takeIf { it.isNotEmpty() }?.joinToString("；"),
        )
    }

    private val assignmentChannels = setOf("assignment_deadlines", "assignment_updates")

    private fun Outcome.toMap(): Map<String, Any?> = mapOf(
        "completed" to completed,
        "retiredIds" to retiredIds,
        "preservedUnknownIds" to preservedUnknownIds,
        "warning" to warning,
    )

    private fun isPluginOwned(context: Context, notification: Notification, id: Int): Boolean {
        val content = notification.contentIntent ?: return false
        if (content.creatorPackage != context.packageName) return false
        val launcher = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return false
        launcher.action = "SELECT_NOTIFICATION"
        val candidate = PendingIntent.getActivity(
            context, id, launcher, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return false
        return candidate == content
    }

    private fun isNativeOwned(
        context: Context,
        database: ReminderDatabase,
        notification: Notification,
        id: Int,
    ): Boolean = database.eventsForNotification(id).any { event ->
        AssignmentNotificationPublisher.matchesClickIntent(context, notification.contentIntent, event)
    }

    private fun cancelPluginAlarm(context: Context, id: Int) {
        val intent = Intent(context, com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver::class.java)
        val operation = PendingIntent.getBroadcast(
            context, id, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(operation)
        operation.cancel()
    }

    /** Never invoke while holding deliveryLock; plugin RMW stays on main. */
    private fun <T> onMain(action: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return action()
        val done = CountDownLatch(1)
        val expired = AtomicBoolean(false)
        val value = AtomicReference<T>()
        val error = AtomicReference<Throwable>()
        mainHandler.post {
            if (expired.get()) { done.countDown(); return@post }
            try { value.set(action()) } catch (failure: Throwable) { error.set(failure) }
            finally { done.countDown() }
        }
        if (!done.await(5, TimeUnit.SECONDS)) {
            expired.set(true)
            throw IllegalStateException("旧提醒迁移等待主线程超时")
        }
        error.get()?.let { throw IllegalStateException("旧提醒迁移失败", it) }
        return value.get()
    }
}
