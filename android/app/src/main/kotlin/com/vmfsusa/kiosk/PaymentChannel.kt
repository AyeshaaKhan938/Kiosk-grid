package com.vmfsusa.kiosk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge for Contaloupe / Nayax card readers and bill/coin acceptors.
 *
 * OEM SDKs should call [emit] with type=success / credit / declined.
 * Field integrations can also broadcast:
 *   action [ACTION_PAYMENT_RESULT] extras: type, reference, provider, amount_cents
 *   action [ACTION_CASH_CREDIT] extras: amount_cents
 */
class PaymentChannel(
    private val appContext: Context,
    flutterEngine: FlutterEngine,
) : EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "vmfs.kiosk/payment"
        const val EVENT_CHANNEL = "vmfs.kiosk/payment_events"
        const val ACTION_PAYMENT_RESULT = "com.vmfsusa.kiosk.PAYMENT_RESULT"
        const val ACTION_CASH_CREDIT = "com.vmfsusa.kiosk.CASH_CREDIT"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var sessionActive = false
    private var targetCents = 0
    private var provider = "simulate"

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null || !sessionActive) return
            when (intent.action) {
                ACTION_PAYMENT_RESULT -> {
                    val type = intent.getStringExtra("type") ?: "success"
                    emit(
                        mapOf(
                            "type" to type,
                            "reference" to (intent.getStringExtra("reference") ?: ""),
                            "provider" to (intent.getStringExtra("provider") ?: provider),
                            "message" to (intent.getStringExtra("message") ?: ""),
                            "amount_cents" to intent.getIntExtra("amount_cents", targetCents),
                        ),
                    )
                }
                ACTION_CASH_CREDIT -> {
                    val cents = intent.getIntExtra("amount_cents", 0)
                    if (cents > 0) {
                        emit(
                            mapOf(
                                "type" to "credit",
                                "amount_cents" to cents,
                            ),
                        )
                    }
                }
            }
        }
    }

    init {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCardPayment" -> {
                    targetCents = call.argument<Number>("amount_cents")?.toInt() ?: 0
                    provider = call.argument<String>("provider") ?: "nayax"
                    sessionActive = true
                    emit(
                        mapOf(
                            "type" to "status",
                            "message" to "Card reader armed ($provider)",
                            "provider" to provider,
                        ),
                    )
                    // OEM SDK hook point — until linked, wait for broadcast.
                    result.success(true)
                }
                "startCashPayment" -> {
                    targetCents = call.argument<Number>("amount_cents")?.toInt() ?: 0
                    provider = "cash"
                    sessionActive = true
                    emit(
                        mapOf(
                            "type" to "status",
                            "message" to "Bill/coin acceptor armed",
                        ),
                    )
                    result.success(true)
                }
                "cancelPayment" -> {
                    sessionActive = false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(this)

        val filter = IntentFilter().apply {
            addAction(ACTION_PAYMENT_RESULT)
            addAction(ACTION_CASH_CREDIT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(receiver, filter)
        }
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
