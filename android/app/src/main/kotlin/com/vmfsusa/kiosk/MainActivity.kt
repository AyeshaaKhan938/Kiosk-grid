package com.vmfsusa.kiosk

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val kioskChannel = "vmfs.kiosk/lockdown"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hardenWindowFlags()
    }

    override fun onResume() {
        super.onResume()
        enableKioskMode()
        hideSystemUi()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // If the system UI ever sneaks back (e.g. a notification briefly
        // overlays us), re-hide as soon as we regain focus.
        if (hasFocus) hideSystemUi()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // /dev/ttyS* serial bridge — talks to the Reyeah Control Board directly.
        TtySerialChannel(flutterEngine)

        // Remote APK self-update — installs an APK downloaded from vms-cloud.
        ApkInstallerChannel(applicationContext, flutterEngine)

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
     * Apply window flags that keep the activity above the lock screen, awake,
     * and behind a fullscreen viewport. Belt-and-suspenders on top of the
     * Flutter immersiveSticky mode from main.dart.
     */
    private fun hardenWindowFlags() {
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    /**
     * Aggressively hide status bar + nav bar. Called from onResume() and
     * every time the window regains focus, so even if Android temporarily
     * reveals the bars (e.g. a system swipe attempt), we re-hide them.
     */
    @Suppress("DEPRECATION")
    private fun hideSystemUi() {
        val decor = window.decorView
        decor.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
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
