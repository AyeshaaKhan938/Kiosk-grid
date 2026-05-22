package com.vmfsusa.kiosk

import android.util.Log
import io.flutter.app.FlutterApplication

/**
 * Custom Flutter Application class.
 *
 * Mirrors factory.apk's `MyApplication` slot — gives us a place to hook
 * process-wide initialization that needs to run BEFORE any activity
 * starts. Right now we just emit a startup log line so crash reports /
 * field log files have a clear "process started" marker; future
 * additions (crashlytics init, global exception handler, network
 * security hooks) belong here too.
 *
 * Wired in AndroidManifest.xml via `android:name=".VmfsApplication"`.
 */
class VmfsApplication : FlutterApplication() {

    companion object {
        private const val TAG = "VmfsApplication"
    }

    override fun onCreate() {
        super.onCreate()
        // Install a default uncaught exception handler that funnels any
        // background-thread crash to logcat with a recognizable tag so
        // the on-tablet debug log captures it before the JVM dies.
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                Log.e(TAG, "uncaught on ${thread.name}", throwable)
            } catch (_: Throwable) { /* ignore */ }
            previous?.uncaughtException(thread, throwable)
        }
        Log.i(TAG, "VMFS Application onCreate — process started")
    }
}
