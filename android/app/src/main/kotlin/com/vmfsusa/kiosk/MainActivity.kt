package com.vmfsusa.kiosk

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import androidx.activity.OnBackPressedCallback
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * VMFS USA — Kiosk activity.
 *
 * Layered lockdown (best effort without Device Owner provisioning):
 *
 *   1. HOME launcher category in the manifest — home button stays in the app.
 *   2. Aggressive immersive mode — the status bar and navigation bar are
 *      never rendered. Back / Home / Recents buttons are physically hidden;
 *      transient swipe-to-reveal is suppressed.
 *   3. Lock Task Mode (screen pinning) on every resume.
 *   4. Re-arm immersive + pinning on every focus change. If anything in
 *      Android tries to show the system UI (a permission dialog, an A11y
 *      toast, etc.) we yank it back down the instant focus returns.
 *   5. Back button intercepted at the activity level — never closes the app.
 *   6. SHOW_WHEN_LOCKED + KEEP_SCREEN_ON flags — the kiosk wakes itself even
 *      from the lock screen and stays awake.
 *
 * For TRUE unbreakable lockdown (no escape with hold Back+Recents), the
 * tablet must be provisioned as Device Owner. See docs/DEVICE_OWNER.md.
 */
class MainActivity : FlutterActivity() {

    private val kioskChannel = "vmfs.kiosk/lockdown"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Bypass the lock screen and keep the screen on indefinitely.
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
        )

        // Let our content draw under the system bars (so hiding them doesn't
        // leave black space at the top/bottom).
        WindowCompat.setDecorFitsSystemWindows(window, false)

        applyImmersive()
        blockBackButton()
    }

    override fun onResume() {
        super.onResume()
        applyImmersive()
        enableKioskMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // Anything that took focus away (dialog, A11y, peek-down) is gone —
            // immediately re-hide the bars and re-pin if pinning was broken.
            applyImmersive()
            enableKioskMode()
        }
    }

    /**
     * Permanently hide the status + navigation bars. The
     * `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE` flag suppresses the
     * temporary peek-down when the user swipes — they stay hidden until
     * we explicitly show them.
     */
    private fun applyImmersive() {
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

        // Legacy flag set for older Android — overlaps with the controller
        // above but causes no harm and covers edge cases on some OEM ROMs.
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )

        // Re-listen for any unexpected visibility change and immediately
        // re-hide. This catches programmatic shows we didn't initiate.
        @Suppress("DEPRECATION")
        window.decorView.setOnSystemUiVisibilityChangeListener { visibility ->
            if (visibility and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION == 0) {
                applyImmersive()
            }
        }
    }

    /**
     * Pin the activity to the screen. First call shows a system consent
     * dialog; subsequent calls (after the admin allows once) pin silently.
     */
    private fun enableKioskMode() {
        if (isInLockTaskMode()) return
        try {
            startLockTask()
        } catch (_: Throwable) {
            // Falls back to HOME-launcher + immersive lockdown.
        }
    }

    private fun isInLockTaskMode(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
    }

    /**
     * Intercept the system Back button at the activity level. The Flutter
     * navigator can still pop screens within the app, but Back will never
     * exit the app.
     */
    private fun blockBackButton() {
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    // No-op. Customer cannot back out of the app.
                }
            },
        )
    }

    /**
     * Also block the hardware Back key if some custom ROM bypasses the
     * standard onBackPressed dispatcher (some tablets do).
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        return when (event.keyCode) {
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_HOME,
            KeyEvent.KEYCODE_APP_SWITCH,
            KeyEvent.KEYCODE_MENU,
            -> true // consume — don't let Android handle these
            else -> super.dispatchKeyEvent(event)
        }
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
                    "applyImmersive" -> {
                        applyImmersive()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
