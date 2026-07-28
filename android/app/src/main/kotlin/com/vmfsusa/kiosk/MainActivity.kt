package com.vmfsusa.kiosk

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
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
 *      never rendered. Back / Home / Recents buttons are physically hidden.
 *      We also tell Android (10+) that the app owns every screen edge via
 *      `systemGestureExclusionRects`, which suppresses the OS's
 *      swipe-from-edge gesture detection inside the rect. If a swipe
 *      still leaks through (corners are always reserved by the OS), a
 *      visibility-change listener re-hides the bars on the next frame.
 *   3. Lock Task Mode (screen pinning) on every resume.
 *   4. Re-arm immersive + pinning on every focus change. If anything in
 *      Android tries to show the system UI (a permission dialog, an A11y
 *      toast, etc.) we yank it back down the instant focus returns.
 *   5. Back / Home / Recents / Menu key events consumed in dispatchKeyEvent
 *      so neither Android nor Flutter ever sees them — the app can't be
 *      backed out of.
 *   6. SHOW_WHEN_LOCKED + KEEP_SCREEN_ON flags — the kiosk wakes itself even
 *      from the lock screen and stays awake.
 *
 * For TRUE unbreakable lockdown (no escape with hold Back+Recents), the
 * tablet must be provisioned as Device Owner. See docs/DEVICE_OWNER.md.
 */
class MainActivity : FlutterActivity() {

    private val kioskChannel = "vmfs.kiosk/lockdown"

    /**
     * When false, onResume / onWindowFocusChanged do NOT call
     * `startLockTask`, immersive system-bar hiding is skipped, and the
     * hardware Back / Home / Recents keys pass through to Android
     * normally. Setup wizard's initial Wi-Fi step flips this off so the
     * admin can drop into Android Settings, configure the network, and
     * come back; the wizard turns it on again on completion. Defaults to
     * true so subsequent boots (after isConfigured = true) come up
     * locked down without any handshake.
     */
    private var kioskModeAllowed = true

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

        if (kioskModeAllowed) applyImmersive()
    }

    override fun onResume() {
        super.onResume()
        if (kioskModeAllowed) {
            applyImmersive()
            enableKioskMode()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && kioskModeAllowed) {
            // Anything that took focus away (dialog, A11y, peek-down) is gone —
            // immediately re-hide the bars and re-pin if pinning was broken.
            applyImmersive()
            enableKioskMode()
        }
    }

    /**
     * Aggressively hide the status + navigation bars and tell Android we
     * own every screen edge so the system gesture handles don't react to
     * bottom / side swipes. On non-Device-Owner installs Android still
     * reserves the swipe-from-bottom gesture as a safety mechanism, so
     * the bars may flash briefly — the re-hide listener below kills the
     * flash within ~50 ms of it appearing.
     */
    private fun applyImmersive() {
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

        // Legacy flag set for older Android — overlaps with the controller
        // above but covers edge cases on some OEM ROMs.
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )

        // Tell Android 10+ that our app owns every pixel of every screen
        // edge. The OS will suppress its own swipe-from-edge gesture
        // detection inside these rects — so swiping up from the bottom no
        // longer pops the nav bar on gesture-nav devices. (Note: the OS
        // still keeps a tiny mandatory exclusion at the very corners for
        // accessibility; full edge-to-edge blocking needs Device Owner.)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.decorView.post {
                val w = window.decorView.width
                val h = window.decorView.height
                if (w > 0 && h > 0) {
                    window.decorView.systemGestureExclusionRects =
                        listOf(Rect(0, 0, w, h))
                }
            }
        }

        // Aggressive re-hide listener: the instant the OS reveals the
        // bars (transient swipe-from-bottom on 3-button or gesture nav),
        // we immediately request hide again. This kills the brief flash
        // visually — there will be at most a single-frame appearance.
        @Suppress("DEPRECATION")
        window.decorView.setOnSystemUiVisibilityChangeListener { visibility ->
            if (visibility and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION == 0) {
                // Hide again on the next frame to dodge OS re-show races.
                window.decorView.post {
                    WindowInsetsControllerCompat(window, window.decorView)
                        .hide(WindowInsetsCompat.Type.systemBars())
                }
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
     * Block the hardware Back / Home / Recents / Menu keys at the lowest
     * level. Consuming them here means Android never dispatches them to
     * the rest of the activity, so the Flutter side never sees them and
     * the customer can't back out of the app. Setup wizard (with
     * [kioskModeAllowed] = false) bypasses this so the admin can
     * actually reach Android Settings during initial Wi-Fi config.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!kioskModeAllowed) return super.dispatchKeyEvent(event)
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

        // SMG-S400 / BKX16 AI cooler — electromagnetic lock + dual cameras.
        BketCoolerChannel(applicationContext, flutterEngine)

        // Remote APK self-update — installs an APK downloaded from vms-cloud.
        ApkInstallerChannel(applicationContext, flutterEngine)

        // Persistent log file (factory-parity LogFileUtil port). Writes
        // date-rotated text files under the app's external-files dir so
        // field debugging captures every send/receive, dispense, OTA
        // attempt, etc. — invaluable when the client reports an issue
        // we can't reproduce locally.
        LogFileChannel(applicationContext, flutterEngine)

        // PARTIAL_WAKE_LOCK manager for the dispense / OTA windows so
        // the CPU isn't suspended mid-motor-turn or mid-download.
        WakeLockChannel(applicationContext, flutterEngine)

        // Foreground priority anchor. Keeps the process alive even when
        // Android's low-memory killer would normally reap a background
        // app. The notification is hidden under our immersive bar so
        // customers never see it.
        SerialMonitorService.start(applicationContext)

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
                    "setKioskModeAllowed" -> {
                        val allowed =
                            call.argument<Boolean>("allowed") ?: true
                        kioskModeAllowed = allowed
                        if (allowed) {
                            // Switched ON — re-apply lockdown immediately so
                            // the admin doesn't have to background+foreground
                            // the app to see the bars disappear.
                            applyImmersive()
                            enableKioskMode()
                        } else {
                            // Switched OFF — drop out of Lock Task Mode so
                            // intents to Android Settings (Wi-Fi config) work,
                            // and let the system bars reappear so the admin
                            // can actually navigate.
                            try { stopLockTask() } catch (_: Throwable) {}
                            showSystemBars()
                        }
                        result.success(true)
                    }
                    "openWifiSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (t: Throwable) {
                            result.error("INTENT_FAILED", t.message, null)
                        }
                    }
                    "openSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (t: Throwable) {
                            result.error("INTENT_FAILED", t.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Re-show the status bar and navigation bar. Mirror-image of
     * [applyImmersive] for the unpinned setup-mode case. Without this,
     * flipping [kioskModeAllowed] off but the immersive listener still
     * hiding bars on every redraw would leave the admin staring at a
     * fullscreen app with no way to navigate.
     */
    private fun showSystemBars() {
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.show(WindowInsetsCompat.Type.systemBars())

        // Drop the legacy fullscreen flag set so the OS goes back to
        // rendering its own decor.
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE

        // Disarm the re-hide listener and clear the gesture-exclusion
        // rects so the OS reacts to swipes again.
        @Suppress("DEPRECATION")
        window.decorView.setOnSystemUiVisibilityChangeListener(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.decorView.systemGestureExclusionRects = emptyList()
        }
    }
}
