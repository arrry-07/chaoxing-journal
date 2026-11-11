package com.example.studyassistant

import android.app.Activity
import android.os.Bundle
import android.widget.Toast

class ReminderClickActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.action != ReminderClickReceiver.ACTION_CLICK) {
            finish()
            return
        }
        val decision = ReminderClickRouter.resolve(
            this,
            intent.getStringExtra(ReminderClickReceiver.EXTRA_ACCOUNT_HASH),
            intent.getStringExtra(ReminderClickReceiver.EXTRA_ASSIGNMENT_ID),
        )
        if (decision.missing) {
            Toast.makeText(this, ReminderClickRouter.MISSING_MESSAGE, Toast.LENGTH_LONG).show()
        }
        ReminderClickRouter.launch(this, decision)
        finish()
    }
}
