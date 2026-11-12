package com.example.studyassistant

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.util.concurrent.Executors

/**
 * One-time retirement of assignment notifications scheduled by the legacy
 * `flutter_local_notifications` path. Native deadline notifications share the
 * same channels and can collide with legacy ids, so ownership is proven from
 * the delivered notification itself rather than from an id range or channel.
 *
 * Only notifications whose click operation was created by the plugin
 * (`MainActivity` launch intent + `notificationId` extra) or ids that are backed
 * by the plugin's own schedule cache are touched. Anything else is preserved
 * and reported, and the caller must not record the migration as complete.
 */
object LegacyAssignmentNotificationMigrator {
    const val CHANNEL = "study_assistant/legacy_assignment_migration"

    /** Serializes notification posting/cancelling with legacy retirement. */
    val deliveryLock = Any()

    private const val PLUGIN_PREFS = "scheduled_notifications"
    private const val PLUGIN_CACHE_KEY = "scheduled_notifications"
    private const val PLUGIN_NOTIFICATION_ID_EXTRA = "notificationId"
    private const val CHANNEL_DEADLINES = "assignment_deadlines"
    private const val CHANNEL_UPDATES = "assignment_updates"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val barrierExecutor = Executors.newSingleThreadExecutor()

    data class Outcome(
        val completed: Boolean,
        val retiredIds: List<Int>,
        val preservedUnknownIds: List<Int>,
        val cacheChanged: Boolean,
        val warning: String?,
    )

    fun attach(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        val database = ReminderDatabase.get(appContext)
        val channel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method != "retireLegacyAssignments") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val ownedIds = (call.argument<List<*>>("ownedIds") ?: emptyList<Any>())
                .mapNotNull { (it as? Number)?.toInt() }
                .toSet()
            val excludeIds = (call.argument<List<*>>("excludeIds") ?: emptyList<Any>())
                .mapNotNull { (it as? Number)?.toInt() }
                .toSet()
            mainHandler.post {
                val outcome = try {
                    synchronized(deliveryLock) {
                        retireNow(appContext, database, ownedIds, excludeIds)
                    }
                } catch (error: Exception) {
                    result.error(
                        "legacy_migration_error",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                    return@post
                }
                // apply() is asynchronous. commit() on the same SharedPreferences
                // instance writes the current map (including this retirement) and
                // reports whether the whole map reached disk.
                val cachePrefs = appContext.getSharedPreferences(
                    PLUGIN_PREFS,
                    Context.MODE_PRIVATE,
                )
                if (!outcome.cacheChanged) {
                    result.success(outcome.toMap())
                    return@post
                }
                barrierExecutor.execute {
                    val committed = try {
                        cachePrefs.edit().commit()
                    } catch (_: Exception) {
                        false
                    }
                    mainHandler.post {
                        if (!committed) {
                            result.success(
                                outcome.copy(
                                    completed = false,
                                    warning = "旧提醒调度缓存未能写入磁盘",
                                ).toMap(),
                            )
                        } else {
                            result.success(outcome.toMap())
                        }
                    }
                }
            }
        }
    }

    /** Runs on the main thread; callers hold [deliveryLock]. */
    internal fun retireNow(
        context: Context,
        database: ReminderDatabase,
        ownedIds: Set<Int>,
        excludeIds: Set<Int> = emptySet(),
    ): Outcome {
        val manager = NotificationManagerCompat.from(context)
        val active = manager.activeNotifications
        val nativeIds = database.notificationIds()
        val pluginPrefs = context.getSharedPreferences(PLUGIN_PREFS, Context.MODE_PRIVATE)
        val cacheRawPresent = pluginPrefs.contains(PLUGIN_CACHE_KEY)
        val cacheIds = readPluginCacheIds(pluginPrefs)
        val retire = linkedSetOf<Int>()
        val retireCacheOnly = linkedSetOf<Int>()
        val unknown = linkedSetOf<Int>()
        val failures = mutableListOf<String>()
        val cache = readPluginCache(pluginPrefs)

        for (entry in active) {
            val id = entry.id
            val notification = entry.notification
            if (id in excludeIds || entry.tag != null) continue
            if (notification.channelId != CHANNEL_DEADLINES &&
                notification.channelId != CHANNEL_UPDATES
            ) {
                continue
            }
            val nativeOwned = id in nativeIds
            val pluginOwned = isPluginOwned(context, notification, id)
            when {
                nativeOwned -> {
                    // The visible notification belongs to the native publisher.
                    // A colliding legacy schedule must still be retired so it
                    // cannot repost over the native notification later.
                    if (id in cacheIds || id in ownedIds) retireCacheOnly.add(id)
                }
                pluginOwned -> retire.add(id)
                id in ownedIds -> unknown.add(id)
                else -> unknown.add(id)
            }
        }
        for (id in ownedIds) {
            if (id in retire || id in retireCacheOnly || id in unknown) continue
            if (id in nativeIds) {
                if (id in cacheIds) retireCacheOnly.add(id)
            } else if (id in cacheIds) {
                // Pending plugin alarms from the legacy schedule cache.
                retireCacheOnly.add(id)
            }
            // Ids that are neither visible nor cached already delivered their
            // notification and the user dismissed it: nothing left to retire.
        }

        for (id in retire) {
            try {
                manager.cancel(id)
            } catch (error: Exception) {
                failures.add("取消通知 $id 失败：${error.message ?: error.javaClass.simpleName}")
            }
        }
        for (id in retire + retireCacheOnly) {
            try {
                cancelPluginAlarm(context, id)
            } catch (error: Exception) {
                failures.add("取消旧闹钟 $id 失败：${error.message ?: error.javaClass.simpleName}")
            }
        }

        val removed = retire + retireCacheOnly
        var cacheChanged = false
        if (cacheRawPresent && cache == null) {
            failures.add("旧提醒调度缓存无法解析")
        }
        if (cache != null && removed.isNotEmpty()) {
            val kept = JSONArray()
            var dropped = false
            for (index in 0 until cache.length()) {
                val item = cache.optJSONObject(index) ?: continue
                val id = item.optInt(PLUGIN_NOTIFICATION_ID_EXTRA, Int.MIN_VALUE)
                if (id in removed) {
                    dropped = true
                } else {
                    kept.put(item)
                }
            }
            if (dropped) {
                try {
                    // apply() updates the in-memory map; the channel handler
                    // confirms durability with commit() on a worker thread.
                    pluginPrefs.edit().putString(PLUGIN_CACHE_KEY, kept.toString()).apply()
                    cacheChanged = true
                } catch (error: Exception) {
                    failures.add("旧提醒调度缓存写入失败：${error.message ?: error.javaClass.simpleName}")
                }
            }
        }

        val warning = failures.takeIf { it.isNotEmpty() }?.joinToString("；")
        return Outcome(
            completed = unknown.isEmpty() && failures.isEmpty(),
            retiredIds = removed.sorted(),
            preservedUnknownIds = unknown.sorted(),
            cacheChanged = cacheChanged,
            warning = warning,
        )
    }

    private fun Outcome.toMap(): Map<String, Any?> = mapOf(
        "completed" to completed,
        "retiredIds" to retiredIds,
        "preservedUnknownIds" to preservedUnknownIds,
        "warning" to warning,
    )

    /**
     * The plugin builds the click operation from the app's launcher intent with
     * requestCode = notification id. Native reminders use ReminderClickActivity
     * and a different action/data, so a matching component plus the plugin's
     * id extra proves plugin ownership without triggering the PendingIntent.
     */
    @Suppress("DEPRECATION")
    private fun isPluginOwned(
        context: Context,
        notification: Notification,
        id: Int,
    ): Boolean {
        val content = notification.contentIntent ?: return false
        if (content.creatorPackage != context.packageName) return false
        val launcher = context.packageManager
            .getLaunchIntentForPackage(context.packageName) ?: return false
        launcher.action = "SELECT_NOTIFICATION"
        var flags = PendingIntent.FLAG_NO_CREATE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        // Same operation identity (launcher component, SELECT_NOTIFICATION
        // action, requestCode = id) as FlutterLocalNotificationsPlugin creates.
        val candidate = PendingIntent.getActivity(context, id, launcher, flags)
            ?: return false
        return candidate == content
    }

    private fun cancelPluginAlarm(context: Context, id: Int) {
        val intent = Intent(
            context,
            com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver::class.java,
        )
        var flags = PendingIntent.FLAG_NO_CREATE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        PendingIntent.getBroadcast(context, id, intent, flags)?.cancel()
    }

    private fun readPluginCacheIds(
        prefs: android.content.SharedPreferences,
    ): Set<Int> {
        val cache = readPluginCache(prefs) ?: return emptySet()
        val ids = mutableSetOf<Int>()
        for (index in 0 until cache.length()) {
            val item = cache.optJSONObject(index) ?: continue
            ids.add(item.optInt(PLUGIN_NOTIFICATION_ID_EXTRA, Int.MIN_VALUE))
        }
        return ids
    }

    private fun readPluginCache(
        prefs: android.content.SharedPreferences,
    ): JSONArray? {
        val raw = prefs.getString(PLUGIN_CACHE_KEY, null) ?: return null
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            null
        }
    }
}
