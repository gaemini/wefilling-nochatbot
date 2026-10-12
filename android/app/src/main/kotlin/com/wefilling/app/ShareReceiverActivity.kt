package com.wefilling.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        forwardShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        forwardShare(intent)
    }

    private fun forwardShare(sourceIntent: Intent) {
        val requestId = ShareRequestStore.receive(applicationContext, sourceIntent)
        if (requestId != null) {
            startActivity(Intent(this, MainActivity::class.java).apply {
                action = MainActivity.externalShareReadyAction
                putExtra(MainActivity.externalShareIdExtra, requestId)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            })
        }
        finish()
    }
}
