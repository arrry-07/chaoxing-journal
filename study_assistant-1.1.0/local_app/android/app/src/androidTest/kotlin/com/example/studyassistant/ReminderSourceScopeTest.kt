package com.example.studyassistant

import android.content.Context
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.Instant

@RunWith(AndroidJUnit4::class)
class ReminderSourceScopeTest {
    private lateinit var context: Context
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private var epoch = 0L
    private var sequence = 0

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = ReminderDatabase.get(context)
        accountHash = "synthetic-source-scope-${System.nanoTime()}"
        epoch = database.ensureActiveAccount(accountHash).sessionEpoch
    }

    @After
    fun tearDown() {
        AssignmentNotificationPublisher.cancelForAccount(context, database, accountHash)
        database.clearActiveAccount(accountHash)
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .remove("flutter.notification_click_missing_v1")
            .commit()
    }

    @Test
    fun activityScopeStatusAndSourceBaselinesSurviveDatabaseRoundTrip() {
        val snapshot = snapshot()
        val sources = setOf("courseWork", "classroomActivity:35", "classroomActivity:42")
        apply(snapshot, listOf(event(snapshot)), sources)
        assertEquals(snapshot, database.snapshot(accountHash, snapshot.assignmentId))
        assertEquals(sources, database.loadPlanState(accountHash, epoch).baselinedSources)
        val decision = ReminderClickRouter.resolve(context, accountHash, snapshot.assignmentId)
        assertFalse(decision.missing)
        assertEquals(
            "studyassistant://assignments/${Uri.encode(snapshot.assignmentId)}",
            decision.location,
        )
        database.clearActiveAccount(accountHash)
        assertTrue(database.readAccount(accountHash)!!.baselinedSources.isEmpty())
    }

    @Test
    fun examStartKindPersistsAndUnknownStateCancelsItsEvents() {
        val exam = snapshot().copy(eventKind = "examStart")
        val reminder = event(exam)
        val sources = setOf("exam", "examAccount", "examNotice")
        apply(exam, listOf(reminder), sources)
        assertEquals(exam, database.snapshot(accountHash, exam.assignmentId))
        assertEquals("examStart", database.event(reminder.eventId)!!.eventKind)
        assertEquals(sources, database.loadPlanState(accountHash, epoch).baselinedSources)
        assertFalse(database.snapshot(accountHash, exam.assignmentId)!!.matchesEvent(
            reminder.copy(eventKind = "deadline"), System.currentTimeMillis(),
        ))
        apply(exam.copy(status = "unknown"), emptyList(), sources)
        assertEquals(ReminderDatabase.STATUS_CANCELLED, database.event(reminder.eventId)!!.status)
    }

    @Test
    fun versionTwoUpgradeDefaultsOldEventsToDeadlineAndKeepsHistory() {
        val file = File(context.cacheDir, "synthetic-reminder-v2-${System.nanoTime()}.db")
        try {
            SQLiteDatabase.openOrCreateDatabase(file, null).use { old ->
                old.execSQL("CREATE TABLE snapshots (assignment_id TEXT)")
                old.execSQL("INSERT INTO snapshots VALUES ('old-work')")
                old.execSQL("CREATE TABLE events (event_id TEXT, status TEXT)")
                old.execSQL("INSERT INTO events VALUES ('keep-history', 'submitted')")
                old.version = 2
            }
            val helper = object : SQLiteOpenHelper(context, file.absolutePath, null, 3) {
                override fun onCreate(db: SQLiteDatabase) = error("Expected existing v2 database")
                override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    database.onUpgrade(db, oldVersion, newVersion)
                }
            }
            try {
                val upgraded = helper.writableDatabase
                assertEquals(3, upgraded.version)
                upgraded.rawQuery("SELECT event_id, status, event_kind FROM events", null).use { row ->
                    assertTrue(row.moveToFirst())
                    assertEquals("keep-history", row.getString(0))
                    assertEquals("submitted", row.getString(1))
                    assertEquals("deadline", row.getString(2))
                }
                upgraded.rawQuery("SELECT event_kind FROM snapshots", null).use { row ->
                    assertTrue(row.moveToFirst())
                    assertEquals("deadline", row.getString(0))
                }
            } finally {
                helper.close()
            }
        } finally {
            SQLiteDatabase.deleteDatabase(file)
        }
    }

    @Test
    fun versionThreeUpgradeAddsSignalAttemptStateWithoutLosingAccountData() {
        val file = File(context.cacheDir, "synthetic-reminder-v3-${System.nanoTime()}.db")
        try {
            SQLiteDatabase.openOrCreateDatabase(file, null).use { old ->
                old.execSQL(
                    "CREATE TABLE accounts (account_hash TEXT PRIMARY KEY, " +
                        "pending_signal_version INTEGER, consumed_signal_version INTEGER, " +
                        "last_signal_at INTEGER)",
                )
                old.execSQL(
                    "INSERT INTO accounts VALUES " +
                        "('keep-account', 7, 5, 123456789)",
                )
                old.version = 3
            }
            val helper = object : SQLiteOpenHelper(context, file.absolutePath, null, 4) {
                override fun onCreate(db: SQLiteDatabase) = error("Expected existing v3 database")
                override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    database.onUpgrade(db, oldVersion, newVersion)
                }
            }
            try {
                val upgraded = helper.writableDatabase
                assertEquals(4, upgraded.version)
                upgraded.rawQuery(
                    "SELECT pending_signal_version, consumed_signal_version, " +
                        "last_signal_at, attempted_signal_version, last_signal_check_at " +
                        "FROM accounts WHERE account_hash = 'keep-account'",
                    null,
                ).use { row ->
                    assertTrue(row.moveToFirst())
                    assertEquals(7L, row.getLong(0))
                    assertEquals(5L, row.getLong(1))
                    assertEquals(123456789L, row.getLong(2))
                    assertEquals(0L, row.getLong(3))
                    assertTrue(row.isNull(4))
                }
            } finally {
                helper.close()
            }
        } finally {
            SQLiteDatabase.deleteDatabase(file)
        }
    }

    @Test
    fun latestUnknownFailedOrOutOfScopeSnapshotCancelsPendingAndSubmittedEvents() {
        val invalidSnapshots = listOf<(StoredReminderSnapshot) -> StoredReminderSnapshot>(
            { it.copy(status = "unknown") },
            { it.copy(deadlineReadFailed = true) },
            { it.copy(deadlineTrusted = false) },
            { it.copy(inAssignmentScope = false) },
            { it.copy(status = "overdue") },
            { it.copy(completed = true, status = "submitted") },
            { it.copy(deadlineAt = it.deadlineAt!! + 60_000L) },
        )
        for (invalidate in invalidSnapshots) {
            for (submitted in listOf(false, true)) {
                val snapshot = snapshot()
                val events = listOf(event(snapshot), event(snapshot, ReminderDatabase.EVENT_NEW))
                apply(snapshot, events)
                if (submitted) events.forEach {
                    database.markEventSubmitted(
                        it.eventId, it.notificationId, accountHash, it.assignmentId, it.type,
                    )
                }
                val result = apply(invalidate(snapshot), emptyList())
                assertEquals(events.map { it.eventId }.toSet(),
                    result.invalidatedEvents.map { it.eventId }.toSet())
                events.forEach {
                    assertEquals(ReminderDatabase.STATUS_CANCELLED, database.event(it.eventId)!!.status)
                }
            }
        }
    }

    @Test
    fun staleDeadlineCannotBeInsertedOrPublishedAgainstLatestSnapshot() {
        val snapshot = snapshot()
        val event = event(snapshot)
        apply(snapshot, listOf(event))
        val changed = snapshot.copy(deadlineAt = snapshot.deadlineAt!! + 60_000L)
        val result = apply(changed, listOf(event))
        assertTrue(result.desiredDeadlineEvents.isEmpty())
        assertEquals(ReminderDatabase.STATUS_CANCELLED, database.event(event.eventId)!!.status)
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        assertFalse(AssignmentNotificationPublisher.publishDeadline(
            context, database, event, Instant.now(),
        ).submitted)
    }

    @Test
    fun publisherRejectsInvalidSnapshotBeforeCheckingNotificationPermission() {
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        val invalidStates = listOf(
            ContentValues().apply { put("status", "unknown") },
            ContentValues().apply { put("in_assignment_scope", 0) },
            ContentValues().apply { put("deadline_trusted", 0) },
            ContentValues().apply { put("deadline_read_failed", 1) },
        )
        for (values in invalidStates) {
            val snapshot = snapshot()
            val deadline = event(snapshot)
            val newAssignment = event(snapshot, ReminderDatabase.EVENT_NEW)
            apply(snapshot, listOf(deadline, newAssignment))
            // Change the current snapshot without applying another plan: the
            // publisher must validate it even while the old events are pending.
            database.writableDatabase.update(
                "snapshots", values, "account_hash = ? AND assignment_id = ?",
                arrayOf(accountHash, snapshot.assignmentId),
            )
            val deadlineResult = AssignmentNotificationPublisher.publishDeadline(
                context, database, deadline, Instant.now(),
            )
            val newResult = AssignmentNotificationPublisher.publishPendingNewAssignments(
                context, database, accountHash, Instant.now(),
            )
            assertFalse(deadlineResult.submitted)
            assertEquals(null, deadlineResult.warning)
            assertFalse(newResult.submitted)
            assertEquals(null, newResult.warning)
            for (event in listOf(deadline, newAssignment)) {
                assertEquals(ReminderDatabase.STATUS_CANCELLED, database.event(event.eventId)!!.status)
            }
        }
    }

    @Test
    fun staleCallerCannotCancelCurrentValidDeadlineEvent() {
        assertTrue(LegacyAssignmentMigrationState.confirm(context))
        val snapshot = snapshot()
        val current = event(snapshot)
        apply(snapshot, listOf(current))
        val stale = current.copy(deadlineAt = current.deadlineAt!! - 60_000L)
        assertFalse(AssignmentNotificationPublisher.publishDeadline(
            context, database, stale, Instant.now(),
        ).submitted)
        assertEquals(ReminderDatabase.STATUS_PENDING, database.event(current.eventId)!!.status)
    }

    @Test
    fun sourceBaselineAndKnownIdsRollbackWhenSnapshotWriteFails() {
        val snapshot = snapshot()
        val sources = setOf("courseWork", "classroomActivity:35")
        apply(snapshot, listOf(event(snapshot)), sources)
        val before = database.loadPlanState(accountHash, epoch)
        val result = runCatching {
            database.applyPlan(
                accountHash = accountHash,
                sessionEpoch = epoch,
                baselineCompleted = true,
                knownIds = setOf("should-not-save"),
                snapshots = listOf(snapshot, snapshot),
                events = emptyList(),
                completedAt = System.currentTimeMillis(),
                failure = null,
                syncCompleted = true,
                expectedMutationVersion = before.mutationVersion,
                baselinedSources = setOf("courseWork"),
            )
        }
        assertTrue(result.isFailure)
        val after = database.loadPlanState(accountHash, epoch)
        assertEquals(before.baselinedSources, after.baselinedSources)
        assertEquals(before.knownAssignmentIds, after.knownAssignmentIds)
        assertEquals(snapshot, database.snapshot(accountHash, snapshot.assignmentId))
        assertEquals(1, database.eventsForAccount(accountHash).size)
    }

    @Test
    fun sourceBaselinesAreIsolatedByAccount() {
        val snapshot = snapshot()
        apply(snapshot, emptyList(), setOf("classroomActivity:42"))
        val otherHash = "$accountHash-other"
        try {
            val other = database.ensureActiveAccount(otherHash)
            assertTrue(other.baselinedSources.isEmpty())
            assertEquals(setOf("classroomActivity:42"),
                database.readAccount(accountHash)!!.baselinedSources)
        } finally {
            database.clearActiveAccount(otherHash)
            database.ensureActiveAccount(accountHash)
        }
    }

    @Test
    fun pendingUpdateClearsOnlyAfterDartSnapshotIsApplied() {
        database.markPendingUpdate(accountHash, epoch)
        val snapshot = snapshot()
        assertTrue(database.loadPlanState(accountHash, epoch).pendingUpdate)
        apply(snapshot, listOf(event(snapshot)))
        assertFalse(database.loadPlanState(accountHash, epoch).pendingUpdate)
        assertEquals("pending", database.snapshot(accountHash, snapshot.assignmentId)!!.status)
        assertEquals(1, database.pendingDeadlineEvents(accountHash).size)
    }

    @Test
    fun legacyApplyMapsOnlyCourseWorkAndPreservesEstablishedActivitySources() {
        val snapshot = snapshot()
        apply(snapshot, emptyList(), setOf("classroomActivity:35"))
        database.applyPlan(
            accountHash = accountHash,
            sessionEpoch = epoch,
            baselineCompleted = true,
            knownIds = setOf(snapshot.assignmentId),
            snapshots = listOf(snapshot),
            events = emptyList(),
            completedAt = System.currentTimeMillis(),
            failure = null,
            syncCompleted = false,
            expectedMutationVersion = database.loadPlanState(accountHash, epoch).mutationVersion,
        )
        assertEquals(setOf("courseWork", "classroomActivity:35"),
            database.loadPlanState(accountHash, epoch).baselinedSources)
    }

    @Test
    fun outOfScopeActivityClickFallsBackToList() {
        val snapshot = snapshot().copy(inAssignmentScope = false)
        apply(snapshot, emptyList())
        assertTrue(ReminderClickRouter.resolve(context, accountHash, snapshot.assignmentId).missing)
    }

    @Test
    fun jsonSnapshotPreservesFormalMeaningAndScopeDefaultsForOldCalls() {
        val json = JSONObject().put("assignmentId", "synthetic")
            .put("formal", true).put("status", "pending")
        assertTrue(ReminderDatabase.snapshotFromJson(accountHash, epoch, json).inAssignmentScope)
        json.put("formal", false).put("inAssignmentScope", true)
        val activity = ReminderDatabase.snapshotFromJson(accountHash, epoch, json)
        assertTrue(activity.inAssignmentScope)
        assertFalse(activity.formal)
        json.remove("status")
        assertEquals("unknown", ReminderDatabase.snapshotFromJson(accountHash, epoch, json).status)
    }

    @Test
    fun versionOneUpgradePreservesHistoryAndRequiresSnapshotRebuild() {
        val file = File(context.cacheDir, "synthetic-reminder-upgrade-${System.nanoTime()}.db")
        try {
            SQLiteDatabase.openOrCreateDatabase(file, null).use { old ->
                old.execSQL("CREATE TABLE accounts (account_hash TEXT PRIMARY KEY, " +
                    "baseline_completed INTEGER, pending_update INTEGER, mutation_version INTEGER)")
                old.execSQL("INSERT INTO accounts VALUES ('old', 1, 0, 4), ('fresh', 0, 0, 0)")
                old.execSQL("CREATE TABLE snapshots (assignment_id TEXT, formal INTEGER)")
                old.execSQL("INSERT INTO snapshots VALUES ('formal', 1), ('activity', 0)")
                old.execSQL("CREATE TABLE events (event_id TEXT)")
                old.execSQL("INSERT INTO events VALUES ('keep-history')")
                old.version = 1
            }
            val helper = object : SQLiteOpenHelper(context, file.absolutePath, null, 2) {
                override fun onCreate(db: SQLiteDatabase) = error("Expected existing v1 database")
                override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    database.onUpgrade(db, oldVersion, newVersion)
                }
            }
            try {
                val upgraded = helper.writableDatabase
                assertEquals(2, upgraded.version)
                upgraded.rawQuery("SELECT baselined_sources, pending_update, mutation_version " +
                    "FROM accounts WHERE account_hash = 'old'", null).use { row ->
                    assertTrue(row.moveToFirst())
                    assertEquals(setOf("courseWork"), ReminderDatabase.stringSet(row.getString(0)))
                    assertEquals(1, row.getInt(1))
                    assertEquals(5L, row.getLong(2))
                }
                upgraded.rawQuery("SELECT baselined_sources FROM accounts " +
                    "WHERE account_hash = 'fresh'", null).use { row ->
                    assertTrue(row.moveToFirst())
                    assertEquals(emptySet<String>(), ReminderDatabase.stringSet(row.getString(0)))
                }
                upgraded.rawQuery("SELECT formal, in_assignment_scope, status FROM snapshots", null)
                    .use { rows ->
                        while (rows.moveToNext()) {
                            assertEquals(rows.getInt(0), rows.getInt(1))
                            assertEquals("unknown", rows.getString(2))
                        }
                    }
                upgraded.rawQuery("SELECT event_id FROM events", null).use { row ->
                    assertTrue(row.moveToFirst())
                    assertEquals("keep-history", row.getString(0))
                }
            } finally {
                helper.close()
            }
        } finally {
            SQLiteDatabase.deleteDatabase(file)
        }
    }

    private fun snapshot(): StoredReminderSnapshot {
        sequence += 1
        return StoredReminderSnapshot(
            accountHash = accountHash,
            assignmentId = "cx:activity:synthetic:class:$sequence",
            sessionEpoch = epoch,
            courseName = "合成课程",
            title = "合成任务",
            deadlineAt = System.currentTimeMillis() + 3_600_000L,
            deadlineTrusted = true,
            deadlineReadFailed = false,
            status = "pending",
            completed = false,
            hidden = false,
            followed = true,
            formal = false,
            inAssignmentScope = true,
        )
    }

    private fun event(
        snapshot: StoredReminderSnapshot,
        type: String = ReminderDatabase.EVENT_DEADLINE,
    ): StoredReminderEvent {
        val id = "$accountHash|${snapshot.assignmentId}|$type"
        return StoredReminderEvent(
            eventId = id,
            accountHash = accountHash,
            sessionEpoch = epoch,
            type = type,
            assignmentId = snapshot.assignmentId,
            courseName = snapshot.courseName,
            title = snapshot.title,
            notifyAt = System.currentTimeMillis() + 60_000L,
            deadlineAt = snapshot.deadlineAt,
            offsets = listOf(1),
            batchId = null,
            status = ReminderDatabase.STATUS_PENDING,
            notificationId = ReminderDatabase.stableNotificationId(id),
            eventKind = snapshot.eventKind,
        )
    }

    private fun apply(
        snapshot: StoredReminderSnapshot,
        events: List<StoredReminderEvent>,
        sources: Set<String> = setOf("courseWork"),
    ) = database.applyPlan(
        accountHash = accountHash,
        sessionEpoch = epoch,
        baselineCompleted = sources.contains("courseWork"),
        knownIds = setOf(snapshot.assignmentId),
        snapshots = listOf(snapshot),
        events = events,
        completedAt = System.currentTimeMillis(),
        failure = null,
        syncCompleted = true,
        expectedMutationVersion = database.loadPlanState(accountHash, epoch).mutationVersion,
        baselinedSources = sources,
    )
}
