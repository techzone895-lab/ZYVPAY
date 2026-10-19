package com.zyvpay.zyv_sms

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/**
 * Sends SMS directly through SmsManager (no compose screen) and streams incoming
 * ZP1 messages to Dart. Messages that arrive while Dart is not listening are kept in
 * [SmsStore] and handed over by `drain`.
 */
class ZyvSmsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "zyv_sms")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "zyv_sms/incoming")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        SmsReceiver.listener = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "send" -> send(call.argument<String>("to")!!, call.argument<String>("body")!!, call.argument<Int>("subscriptionId"), result)
            "drain" -> result.success(SmsStore.drain(context))
            else -> result.notImplemented()
        }
    }

    private fun smsManager(subscriptionId: Int?): SmsManager {
        val base = if (Build.VERSION.SDK_INT >= 31) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION") SmsManager.getDefault()
        }
        if (subscriptionId == null || subscriptionId < 0) return base
        return if (Build.VERSION.SDK_INT >= 31) base.createForSubscriptionId(subscriptionId)
        else @Suppress("DEPRECATION") SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
    }

    // Completes with null on success or an error string once the radio reports the send result.
    private fun send(to: String, body: String, subscriptionId: Int?, result: MethodChannel.Result) {
        val action = "com.zyvpay.zyv_sms.SENT.${counter.incrementAndGet()}"
        var done = false
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                if (done) return
                done = true
                c.unregisterReceiver(this)
                if (resultCode == Activity.RESULT_OK) result.success(null) else result.success("SEND_FAILED_$resultCode")
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        val sent = PendingIntent.getBroadcast(
            context, 0, Intent(action).setPackage(context.packageName),
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            val sms = smsManager(subscriptionId)
            val parts = sms.divideMessage(body)
            if (parts.size == 1) {
                sms.sendTextMessage(to, null, body, sent, null)
            } else {
                val intents = ArrayList<PendingIntent?>(parts.map { null })
                intents[parts.size - 1] = sent
                sms.sendMultipartTextMessage(to, null, parts, intents, null)
            }
        } catch (e: Exception) {
            done = true
            context.unregisterReceiver(receiver)
            result.success("SEND_ERROR_${e.javaClass.simpleName}")
            return
        }
        // No radio callback (airplane mode on some devices): give up after 60s.
        main.postDelayed({
            if (!done) {
                done = true
                runCatching { context.unregisterReceiver(receiver) }
                result.success("SEND_TIMEOUT")
            }
        }, 60_000)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        SmsReceiver.listener = { msg -> main.post { sink.success(msg) } }
    }

    override fun onCancel(arguments: Any?) {
        SmsReceiver.listener = null
    }

    companion object {
        private val counter = AtomicInteger()
    }
}
