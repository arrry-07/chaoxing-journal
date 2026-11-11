package com.example.studyassistant

import android.content.Context
import android.content.Intent
import android.net.Uri

data class ReminderClickDecision(
    val location: String,
    val missing: Boolean,
)

object ReminderClickRouter {
    const val MISSING_MESSAGE =
        "该作业已不存在、已隐藏或不属于当前账号，已返回作业列表"

    fun resolve(
        context: Context,
        requestedAccount: String?,
        requestedAssignment: String?,
    ): ReminderClickDecision {
        val database = ReminderDatabase.get(context)
        val current = database.activeAccount()
        val account = requestedAccount
        val assignment = requestedAssignment
        val accountMatches = current != null &&
            account != null &&
            current.accountHash == account
        if (accountMatches && assignment == null) {
            return ReminderClickDecision(
                location = "studyassistant://assignments",
                missing = false,
            )
        }
        val validAssignment = accountMatches &&
            assignment != null &&
            database.snapshot(account, assignment)?.let {
                it.formal && !it.hidden && it.followed
            } == true
        if (validAssignment) {
            return ReminderClickDecision(
                location = "studyassistant://assignments/${Uri.encode(assignment!!)}",
                missing = false,
            )
        }
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString(
                "flutter.notification_click_missing_v1",
                MISSING_MESSAGE,
            )
            .apply()
        return ReminderClickDecision(
            location = "studyassistant://assignments",
            missing = true,
        )
    }

    fun launch(context: Context, decision: ReminderClickDecision) {
        context.startActivity(
            Intent(
                Intent.ACTION_VIEW,
                Uri.parse(decision.location),
                context,
                MainActivity::class.java,
            ).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TASK,
            ),
        )
    }
}
