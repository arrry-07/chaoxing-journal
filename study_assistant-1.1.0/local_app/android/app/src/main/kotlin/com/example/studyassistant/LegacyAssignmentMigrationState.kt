package com.example.studyassistant

import android.content.Context
import android.util.Log

/** Native-only revision: old Flutter v2 booleans/native_active are not evidence. */
internal object LegacyAssignmentMigrationState {
    private const val TAG = "LegacyMigrationState"
    private const val PREFS = "native_assignment_migration"
    private const val REVISION_KEY = "verified_revision"
    private const val REVISION = 3
    @Volatile private var blockedInProcess = false

    fun isComplete(context: Context): Boolean = !blockedInProcess && try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(REVISION_KEY, 0) == REVISION
    } catch (error: Exception) {
        Log.w(TAG, "read_revision_failed ${error.javaClass.simpleName}")
        false
    }

    /** Called on the ordered worker, never main. Commit failure must fail closed
     * even though SharedPreferences has already updated its in-memory map. */
    fun begin(context: Context): Boolean {
        blockedInProcess = true
        return try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().remove(REVISION_KEY).commit()
        } catch (error: Exception) {
            Log.w(TAG, "begin_commit_failed ${error.javaClass.simpleName}")
            false
        }
    }

    fun confirm(context: Context): Boolean {
        val saved = try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit().putInt(REVISION_KEY, REVISION).commit() &&
                prefs.getInt(REVISION_KEY, 0) == REVISION
        } catch (error: Exception) {
            Log.w(TAG, "confirm_commit_failed ${error.javaClass.simpleName}")
            false
        }
        if (!saved) {
            // Do not let a later instance read a failed commit's in-memory value.
            runCatching {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit().remove(REVISION_KEY).commit()
            }.onFailure { Log.w(TAG, "clear_revision_failed ${it.javaClass.simpleName}") }
        }
        blockedInProcess = !saved
        return saved
    }
}
