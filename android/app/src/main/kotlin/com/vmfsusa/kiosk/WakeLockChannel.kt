package com.vmfsusa.kiosk

import android.content.Context
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * PARTIAL_WAKE_LOCK manager.
 *
 * Used during dispense + OTA install so Android can't suspend the CPU
 * mid-motor-turn or mid-byte-transfer. Mirrors what factory.apk does
 * around its dispense flow.
 *
 * Method channel: vmfs.kiosk/wake_lock
 *   acquire(tag, timeoutMs)  -> bool   acquire (or refresh) a wake lock
 *   release(tag)             -> bool   release a previously-held lock
 *
 * The screen-on side is already covered by FLAG_KEEP_SCREEN_ON in
 * MainActivity — this channel is specifically for CPU wake locks.
 */
class WakeLockChannel(context: Context, engine: FlutterEngine) {

    companion object {
        private const val TAG = "WakeLockChannel"
        private const val PREFIX = "vmfs:"
    }

    private val channel = MethodChannel(
        engine.dartExecutor.binaryMessenger,
        "vmfs.kiosk/wake_lock",
    )

    private val powerManager = context
        .applicationContext
        .getSystemService(Context.POWER_SERVICE) as PowerManager

    private val held = mutableMapOf<String, PowerManager.WakeLock>()

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "acquire" -> {
                        val tag = call.argument<String>("tag") ?: "default"
                        val timeoutMs = (call.argument<Int>("timeoutMs") ?: 30_000).toLong()
                        result.success(acquire(tag, timeoutMs))
                    }
                    "release" -> {
                        val tag = call.argument<String>("tag") ?: "default"
                        result.success(release(tag))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                Log.e(TAG, "channel error: ${e.message}")
                result.error("WAKE_LOCK_ERROR", e.message, null)
            }
        }
    }

    @Synchronized
    private fun acquire(tag: String, timeoutMs: Long): Boolean {
        val key = "$PREFIX$tag"
        return try {
            val existing = held[key]
            if (existing != null && existing.isHeld) {
                // Refresh: release + re-acquire (PowerManager.WakeLock has no
                // built-in "extend timeout" API).
                try { existing.release() } catch (_: Throwable) {}
            }
            val wl = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, key)
            wl.setReferenceCounted(false)
            wl.acquire(timeoutMs)
            held[key] = wl
            true
        } catch (e: Throwable) {
            Log.e(TAG, "acquire($tag) failed: ${e.message}")
            false
        }
    }

    @Synchronized
    private fun release(tag: String): Boolean {
        val key = "$PREFIX$tag"
        val wl = held.remove(key) ?: return true
        return try {
            if (wl.isHeld) wl.release()
            true
        } catch (e: Throwable) {
            Log.e(TAG, "release($tag) failed: ${e.message}")
            false
        }
    }
}
