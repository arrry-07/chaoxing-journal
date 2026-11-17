package com.example.studyassistant

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReminderHistoryDatabaseTest {
    private lateinit var context: Context
    private lateinit var databaseName: String
    private lateinit var database: ReminderDatabase
    private lateinit var accountHash: String
    private var watermark = 0L

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        databaseName = "history-${System.nanoTime()}.db"
        database = ReminderDatabase.openForTest(context, databaseName)
        accountHash = "history-account"
        val epoch = database.ensureActiveAccount(accountHash).sessionEpoch
        database.updateSettings(
            accountHash = accountHash,
            sessionEpoch = epoch,
            backgroundEnabled = false,
            intervalMinutes = 240,
            listenerEnabled = true,
            newAssignmentEnabled = true,
            showDetails = false,
        )
    }

    @After
    fun tearDown() {
        runCatching { database.close() }
        context.deleteDatabase(databaseName)
    }

    @Test
    fun retentionKeepsLatestFiveHundredAndPersistsWatermarkBeforeDelete() {
        val now = System.currentTimeMillis()
        var persistedBeforeDelete = true
        for (index in 1..501) {
            val removedAtCall = watermark
            val result = insert(
                operationSequence = index.toLong(),
                observationId = "obs-$index",
                observedAt = now,
                currentPrunedThrough = { watermark },
                persist = {
                    watermark = it
                    if (removedAtCall != watermark) persistedBeforeDelete = true
                },
            )
            assertEquals(ReminderHistoryInsertResult.INSERTED, result)
        }
        val count = database.readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM reminder_history WHERE account_hash = ?",
            arrayOf(accountHash),
        ).use { it.moveToFirst(); it.getLong(0) }
        assertEquals(500L, count)
        assertEquals(1L, watermark)
        assertTrue(persistedBeforeDelete)
        assertEquals(
            0L,
            database.readableDatabase.rawQuery(
                "SELECT COUNT(*) FROM reminder_history WHERE observation_id = 'obs-1'",
                null,
            ).use { it.moveToFirst(); it.getLong(0) },
        )
    }

    @Test
    fun duplicateObservationWinsBeforePrunedWatermark() {
        val now = System.currentTimeMillis()
        assertEquals(
            ReminderHistoryInsertResult.INSERTED,
            insert(1, "same-id", now),
        )
        assertEquals(
            ReminderHistoryInsertResult.DUPLICATE,
            insert(1, "same-id", now),
        )
        watermark = 9
        assertEquals(
            ReminderHistoryInsertResult.EXPIRED,
            insert(9, "old-operation", now),
        )
    }

    @Test
    fun thirtyDayBoundaryPrunesAndKeepsNewerRows() {
        val now = System.currentTimeMillis()
        val old = now - 31L * 24L * 60L * 60L * 1000L
        assertEquals(ReminderHistoryInsertResult.INSERTED, insert(1, "old", old))
        assertEquals(ReminderHistoryInsertResult.INSERTED, insert(2, "new", now))
        val ids = database.listReminderHistory(
            accountHash = accountHash,
            historyGeneration = 3,
            snapshotMaxId = null,
            beforeId = null,
            category = null,
            subjectRefs = emptyList(),
        )
        assertEquals(listOf("new"), ids.map { it.observationId })
        assertEquals(1L, watermark)
    }

    @Test
    fun evidenceUsesNewestOperationAndCanBeRemoved() {
        val base = ReminderScheduleEvidenceRow(
            accountHash = accountHash,
            historyGeneration = 3,
            logicalKey = "manual:key",
            sessionEpoch = 1,
            operationSequence = 4,
            subjectKind = "manual",
            subjectId = "entry",
            category = "personal",
            scheduledAt = 1000,
            notificationId = 8,
            expectedPayload = "p:entry",
            state = "confirmedScheduled",
            confirmedAt = 1000,
        )
        assertTrue(database.recordReminderScheduleEvidence(base))
        assertTrue(
            !database.recordReminderScheduleEvidence(
                base.copy(operationSequence = 3, state = "retainedOld"),
            ),
        )
        assertEquals(
            "confirmedScheduled",
            database.scheduleEvidenceForSubject(
                accountHash,
                3,
                "manual",
                "entry",
            ).single().state,
        )
        assertTrue(
            !database.removeReminderScheduleEvidence(
                accountHash,
                3,
                "manual:key",
                3,
            ),
        )
        assertTrue(
            database.removeReminderScheduleEvidence(
                accountHash,
                3,
                "manual:key",
                5,
            ),
        )
        assertTrue(
            database.scheduleEvidenceForSubject(
                accountHash,
                3,
                "manual",
                "entry",
            ).isEmpty(),
        )
    }

    private fun insert(
        operationSequence: Long,
        observationId: String,
        observedAt: Long,
        currentPrunedThrough: () -> Long = { watermark },
        persist: (Long) -> Unit = { watermark = it },
    ): ReminderHistoryInsertResult = database.insertReminderHistory(
        accountHash = accountHash,
        sessionEpoch = 1,
        historyGeneration = 3,
        observationId = observationId,
        operationSequence = operationSequence,
        subjectKind = "assignment",
        subjectId = "cx:work:1:2:3",
        logicalKey = "event-$observationId",
        category = "deadline",
        stage = "scheduled",
        reasonCode = null,
        observedAt = observedAt,
        scheduledAt = observedAt + 1000,
        notificationId = 1,
        batchKey = null,
        retentionCutoff = System.currentTimeMillis() -
            30L * 24L * 60L * 60L * 1000L,
        maxRows = 500,
        currentPrunedThrough = currentPrunedThrough,
        persistPrunedThrough = persist,
    )
}
