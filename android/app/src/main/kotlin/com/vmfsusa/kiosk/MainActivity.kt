package com.vmfsusa.kiosk

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val kioskChannel = "vmfs.kiosk/lockdown"

    override fun onResume() {
        super.onResume()
        enableKioskMode()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // /dev/ttyS* serial bridge — talks to the Reyeah Control Board directly.
        TtySerialChannel(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, kioskChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exitKioskMode" -> {
                        try {
                            stopLockTask()
                            result.success(true)
                        } catch (t: Throwable) {
                            result.error("UNLOCK_FAILED", t.message, null)
                        }
                    }
                    "enterKioskMode" -> {
                        enableKioskMode()
                        result.success(isInLockTaskMode())
                    }
                    "isInKioskMode" -> {
                        result.success(isInLockTaskMode())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Pin the activity to the screen so customers can't swipe to Recents
     * or pull up another app. First call shows a system dialog asking the
     * admin to confirm — after that the device remembers consent and pins
     * silently every time the activity resumes.
     *
     * If the device blocks startLockTask() (rare without Device Owner
     * provisioning), we fail silently — the Level-1 HOME launcher in the
     * manifest still keeps the customer out of the rest of Android.
     */
    private fun enableKioskMode() {
        if (isInLockTaskMode()) return
        try {
            startLockTask()
        } catch (_: Throwable) {
            // Best-effort — manifest HOME category still active.
        }
    }

    private fun isInLockTaskMode(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
    }
}
