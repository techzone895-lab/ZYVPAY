package com.zyvpay.zyv_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONArray
import org.json.JSONObject

/** Picks up ZP1 messages only; every other SMS is left alone for the user's SMS app. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        // A long SMS arrives as several parts in one intent; join them per sender.
        parts.groupBy { it.originatingAddress ?: "" }.forEach { (from, msgs) ->
            val body = msgs.joinToString("") { it.messageBody ?: "" }
            if (!body.contains("ZP1")) return@forEach
            val msg = mapOf("from" to from, "body" to body, "ts" to System.currentTimeMillis())
            val l = listener
            if (l != null) l(msg) else SmsStore.add(context, msg)
        }
    }

    companion object {
        @Volatile
        var listener: ((Map<String, Any>) -> Unit)? = null
    }
}

internal object SmsStore {
    private const val PREFS = "zyv_sms"
    private const val KEY = "pending"
    private const val MAX = 200

    @Synchronized
    fun add(context: Context, msg: Map<String, Any>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        arr.put(JSONObject(msg))
        while (arr.length() > MAX) arr.remove(0)
        prefs.edit().putString(KEY, arr.toString()).apply()
    }

    @Synchronized
    fun drain(context: Context): List<Map<String, Any>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        prefs.edit().remove(KEY).apply()
        return (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            mapOf("from" to o.getString("from"), "body" to o.getString("body"), "ts" to o.getLong("ts"))
        }
    }
}
