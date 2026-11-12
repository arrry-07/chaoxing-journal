package com.example.studyassistant

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class LegacyAssignmentCacheTest {
    @Test
    fun v18IdAndAssignmentPayloadAreRequiredAndEveryNonTargetElementSurvives() {
        val raw = """[{"id":41,"payload":"a:studyassistant:///assignments/one","channelId":"assignment_deadlines"},{"id":42,"payload":"p:one","channelId":"personal_reminders"},null,17,{"notificationId":43,"payload":"a:old-extra-is-not-cache-id","channelId":"assignment_deadlines"}]"""
        val cache = LegacyAssignmentCache.parse(raw)
        assertEquals(setOf(41), cache.assignmentIds)
        assertTrue(cache.hasUnknown)
        val kept = JSONArray(cache.without(setOf(41)))
        assertEquals(4, kept.length())
        assertEquals("p:one", kept.getJSONObject(0).getString("payload"))
        assertTrue(kept.isNull(1))
        assertEquals(17, kept.getInt(2))
        assertEquals(43, kept.getJSONObject(3).getInt("notificationId"))
    }

    @Test
    fun foreignDuplicateAndExclusionProtectAllRecordsForThatId() {
        val cache = LegacyAssignmentCache.parse("""[{"id":1,"payload":"a:one","channelId":"assignment_updates"},{"id":1,"payload":"p:one","channelId":"assignment_updates"},{"id":2,"payload":"a:two","channelId":"assignment_deadlines"}]""")
        assertEquals(setOf(1), cache.foreignIds)
        assertEquals(3, JSONArray(cache.without(setOf(1, 2), setOf(2))).length())
    }
}
