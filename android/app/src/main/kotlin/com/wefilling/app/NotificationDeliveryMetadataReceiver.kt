package com.wefilling.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.os.Build
import org.json.JSONObject

/** Metadata only. Firebase/Flutter remain the sole notification renderers. */
class NotificationDeliveryMetadataReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "com.google.android.c2dm.intent.RECEIVE") return
        try {
            val extras = intent.extras ?: return
            if (extras.getString("notificationMetadataVersion") != "2") return
            val tag = extras.getString("gcm.n.tag") ?: return
            if (!tag.startsWith("snack_") && !tag.startsWith("dm_") &&
                !tag.startsWith("notification_")) return
            val millis = extras.getString("notificationCommitMillis")?.toLongOrNull() ?: return
            if (millis <= 0) return
            val data = JSONObject()
            for (key in listOf("type", "recipientUserId", "snackChatId", "conversationId",
                "messageSequence", "sentAtMillis", "sentAtSeconds", "sentAtNanos", "messageId",
                "notificationId")) {
                extras.getString(key)?.let { data.put(key, it) }
            }
            if (data.optString("recipientUserId").isEmpty()) return
            val type = data.optString("type")
            if (type != "snack_chat_message" && type != "dm_received" &&
                data.optString("notificationId").isEmpty()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.activeNotifications.filter { active ->
                    active.tag == tag && active.id != 0 &&
                        read(context, tag, active.notification.`when`)?.let {
                            JSONObject(it).optBoolean("_localRendered")
                        } == true
                }
                    .forEach { manager.cancel(it.tag, it.id) }
            }
            synchronized(lock) {
                val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                val buckets = JSONObject(prefs.getString(tag, "{}") ?: "{}")
                val bucket = millis.toString()
                val previous = buckets.optJSONObject(bucket)
                // A single OS millisecond can contain multiple pushes. Store
                // the maximum receipt, never infer which tied card is visible.
                val newer = previous == null || if (type == "snack_chat_message") {
                    data.optLong("messageSequence") > previous.optLong("messageSequence")
                } else {
                    val seconds = data.optLong("sentAtSeconds")
                    val oldSeconds = previous.optLong("sentAtSeconds")
                    seconds > oldSeconds || (seconds == oldSeconds &&
                        data.optLong("sentAtNanos") > previous.optLong("sentAtNanos"))
                }
                if (newer) buckets.put(bucket, data)
                val keys = buckets.keys().asSequence().toList().sortedByDescending { it.toLongOrNull() ?: 0 }
                keys.drop(8).forEach { buckets.remove(it) }
                prefs.edit().putString(tag, buckets.toString()).apply()
            }
        } catch (_: Exception) {
            // Metadata failure must never interrupt FCM delivery.
        }
    }

    companion object {
        private const val PREFERENCES = "delivered_push_receipt_metadata_v2"
        private val lock = Any()

        fun recordLocal(context: Context, tag: String, millis: Long, data: JSONObject) {
            if (tag.isEmpty() || millis <= 0 || data.optString("recipientUserId").isEmpty()) return
            synchronized(lock) {
                data.put("_localRendered", true)
                val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                val buckets = JSONObject(prefs.getString(tag, "{}") ?: "{}")
                buckets.put(millis.toString(), data)
                val keys = buckets.keys().asSequence().toList()
                    .sortedByDescending { it.toLongOrNull() ?: 0 }
                keys.drop(8).forEach { buckets.remove(it) }
                prefs.edit().putString(tag, buckets.toString()).apply()
            }
        }

        fun read(context: Context, tag: String?, millis: Long): String? {
            if (tag == null || millis <= 0) return null
            return synchronized(lock) {
                try {
                    val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                    JSONObject(prefs.getString(tag, "{}") ?: "{}")
                        .optJSONObject(millis.toString())?.toString()
                } catch (_: Exception) { null }
            }
        }
    }
}
