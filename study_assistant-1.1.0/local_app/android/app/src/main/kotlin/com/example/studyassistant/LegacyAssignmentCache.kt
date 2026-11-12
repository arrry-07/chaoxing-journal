package com.example.studyassistant

import org.json.JSONArray
import org.json.JSONObject

/** V18 Gson cache ownership fields; click's notificationId is NOT the cache id. */
internal class LegacyAssignmentCache private constructor(
    private val items: JSONArray,
    val assignmentIds: Set<Int>,
    val foreignIds: Set<Int>,
    val hasUnknown: Boolean,
) {
    fun without(retired: Set<Int>, excluded: Set<Int> = emptySet()): String {
        val kept = JSONArray()
        for (index in 0 until items.length()) {
            val item = items.opt(index)
            val objectItem = item as? JSONObject
            val id = objectItem?.let(::id)
            val drop = objectItem != null && id != null &&
                id in retired && id !in excluded && id !in foreignIds &&
                isAssignment(objectItem)
            if (!drop) kept.put(item)
        }
        return kept.toString()
    }

    companion object {
        fun parse(raw: String?): LegacyAssignmentCache {
            val items = if (raw == null) JSONArray() else JSONArray(raw)
            val assignments = linkedSetOf<Int>()
            val foreign = linkedSetOf<Int>()
            var unknown = false
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index)
                val id = item?.let(::id)
                if (item == null || id == null) {
                    unknown = true
                    continue
                }
                if (isAssignment(item)) {
                    assignments.add(id)
                } else {
                    // Any conflicting/invalid category blocks cancellation for
                    // this id, not merely deletion of this one cache record.
                    foreign.add(id)
                    if (!validOwnershipFields(item)) unknown = true
                }
            }
            return LegacyAssignmentCache(items, assignments, foreign, unknown)
        }

        private fun id(item: JSONObject): Int? {
            val value = item.opt("id") as? Number ?: return null
            val long = value.toLong()
            return long.takeIf {
                it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() && value.toDouble() == it.toDouble()
            }?.toInt()
        }

        private fun validOwnershipFields(item: JSONObject): Boolean =
            id(item) != null && item.opt("payload") is String &&
                item.opt("channelId") is String &&
                (!item.has("tag") || item.isNull("tag") || item.opt("tag") is String)

        private fun isAssignment(item: JSONObject): Boolean =
            validOwnershipFields(item) && item.getString("payload").let {
                it.startsWith("a:") && it.length > 2
            } && item.getString("channelId") in setOf("assignment_deadlines", "assignment_updates") &&
                (!item.has("tag") || item.isNull("tag"))
    }
}
